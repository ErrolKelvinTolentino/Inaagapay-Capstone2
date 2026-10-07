// Executes the real accounting functions and manual-disposal migration in
// isolated PostgreSQL. It never connects to Supabase.
// npm install --prefix scripts/validation --ignore-scripts
// node scripts/test-manual-vial-disposal.mjs
import fs from 'node:fs';
import assert from 'node:assert/strict';
import { PGlite } from './validation/node_modules/@electric-sql/pglite/dist/index.js';

const db=new PGlite();
try {
  await db.exec(`
    CREATE ROLE anon; CREATE ROLE authenticated;
    CREATE TABLE accounts(account_id bigint PRIMARY KEY);
    INSERT INTO accounts VALUES(1);
    CREATE FUNCTION resolve_actor_account_id(bigint) RETURNS bigint LANGUAGE sql AS 'SELECT account_id FROM accounts WHERE account_id=$1';
    CREATE TABLE inventory_items(item_id bigint PRIMARY KEY,name text,generic_name text,doses_per_unit int,open_vial_shelf_hours int);
    CREATE TABLE vaccines(vaccine_name text,inventory_item_id bigint);
    CREATE TABLE inventory_batches(batch_id bigint PRIMARY KEY,item_id bigint,facility_id bigint,batch_number text,
      quantity_remaining int,status text,doses_remaining_in_open_vial int,open_vials_count int,vial_opened_at timestamptz,expiration_date date);
    CREATE TABLE inventory_transactions(transaction_id bigserial PRIMARY KEY,batch_id bigint,facility_id bigint,transaction_type text,
      quantity int,dose_quantity int,reference_type text,reference_id bigint,notes text,performed_by bigint REFERENCES accounts,
      resulting_quantity_remaining int,resulting_open_vial_doses int,logged_at timestamptz);
    INSERT INTO inventory_items VALUES(1,'Td','',10,672),(2,'BCG','',20,6),(3,'Calcium Carbonate','',1,0);
    INSERT INTO inventory_batches VALUES
      (1,1,2,'TD-OVERDUE',4,'active',3,1,now()-interval '29 days',current_date+100),
      (2,2,2,'BCG-BOUNDARY',1,'active',19,1,now()-interval '6 hours',current_date+100),
      (3,1,2,'TD-RECENT',2,'active',4,1,now()-interval '1 day',current_date+100),
      (4,1,2,'TD-UNDATED',2,'active',3,1,NULL,current_date+100),
      (5,2,2,'BCG-EMPTY-SEALED',0,'active',5,1,now()-interval '7 hours',current_date+100),
      (6,1,2,'SEALED-DATE-EXPIRED',2,'active',4,1,now(),current_date-1),
      (7,3,2,'CALCIUM',20,'active',0,0,NULL,current_date+100);
  `);
  const loadFunction=async(file,name)=>{
    const s=fs.readFileSync(file,'utf8');const start=s.indexOf(`CREATE OR REPLACE FUNCTION public.${name}(`);
    assert.ok(start>=0);const end=s.indexOf('$fn$;',start)+'$fn$;'.length;await db.exec(s.slice(start,end));
  };
  for(const name of ['item_dose_presentation','dispense_stock_doses'])
    await loadFunction('database/migrations/20260831_dose_presentation_single_source.sql',name);
  await loadFunction('database/migrations/20260821_inventory_and_td_fixes.sql','discard_open_vial_doses');
  await db.exec(`REVOKE ALL ON FUNCTION dispense_stock_doses(bigint,integer,bigint,text) FROM PUBLIC;
    GRANT EXECUTE ON FUNCTION dispense_stock_doses(bigint,integer,bigint,text) TO anon,authenticated;
    REVOKE ALL ON FUNCTION discard_open_vial_doses(bigint,bigint,text) FROM PUBLIC;
    GRANT EXECUTE ON FUNCTION discard_open_vial_doses(bigint,bigint,text) TO authenticated;`);
  const privileges=async()=>JSON.stringify((await db.query(`SELECT proname,proacl::text FROM pg_proc
    WHERE proname IN('dispense_stock_doses','discard_open_vial_doses') ORDER BY proname`)).rows);
  const before=await privileges();
  const migration=fs.readFileSync('database/migrations/20261007_require_open_vial_disposal.sql','utf8');
  await db.exec(migration);await db.exec(migration);
  assert.equal(await privileges(),before,'Existing function permissions are preserved');
  assert.equal((await db.query('SELECT count(*)::int AS n FROM inventory_transactions')).rows[0].n,0,'Installation cannot discard doses');
  const dispense=async id=>(await db.query('SELECT dispense_stock_doses($1,1,1,NULL) AS result',[id])).rows[0].result;
  for(const id of [1,2,4,5,6]) {
    const result=await dispense(id);
    assert.equal(result.success,false);assert.equal(result.code,'OPEN_VIAL_DISPOSAL_REQUIRED');
  }
  assert.equal((await db.query('SELECT count(*)::int AS n FROM inventory_transactions')).rows[0].n,0,'Rejected use cannot silently dispose or dispense');
  assert.equal((await dispense(3)).doses_from_open,1,'Unexpired open doses remain usable');
  assert.equal((await dispense(7)).units_remaining,19,'Single-dose dispensing is preserved');
  const discard=async(id,actor,reason)=>(await db.query('SELECT discard_open_vial_doses($1,$2,$3) AS result',[id,actor,reason])).rows[0].result;
  assert.equal((await discard(1,null,'expired')).success,false);
  assert.equal((await discard(1,1,' ')).success,false);
  assert.equal((await discard(1,999,'expired')).success,false);
  const note='[DOH MDVP] 28-day limit (Witness: Midwife Santos | Notes: verified at clinic)';
  assert.equal((await discard(1,1,note)).doses_discarded,3);
  const batch=(await db.query('SELECT * FROM inventory_batches WHERE batch_id=1')).rows[0];
  assert.equal(batch.quantity_remaining,4);assert.equal(batch.doses_remaining_in_open_vial,0);
  assert.equal(batch.open_vials_count,0);assert.equal(batch.vial_opened_at,null);
  const ledger=(await db.query("SELECT * FROM inventory_transactions WHERE reference_type='Open Vial Discard'")).rows;
  assert.equal(ledger.length,1);assert.equal(ledger[0].quantity,0);assert.equal(ledger[0].dose_quantity,-3);
  assert.equal(ledger[0].performed_by,1);assert.ok(ledger[0].notes.includes(note));
  assert.equal((await discard(1,1,note)).success,false,'Repeated acknowledgement cannot double-discard');
  const restored=await dispense(1);
  assert.equal(restored.success,true);assert.equal(restored.units_remaining,3);assert.equal(restored.doses_left_open,9);
  await discard(5,1,'Six-hour limit; Witness: Midwife Santos');
  assert.equal((await db.query('SELECT status FROM inventory_batches WHERE batch_id=5')).rows[0].status,'depleted');
  await db.exec(`ALTER TABLE inventory_transactions ADD CONSTRAINT test_ledger CHECK(dose_quantity>-100);
    INSERT INTO inventory_batches VALUES(8,1,2,'ROLLBACK',15,'active',101,1,now()-interval '29 days',current_date+100);`);
  await assert.rejects(discard(8,1,note));
  assert.equal((await db.query('SELECT doses_remaining_in_open_vial FROM inventory_batches WHERE batch_id=8')).rows[0].doses_remaining_in_open_vial,101);
  console.log('Manual vial disposal: permissions, held batches, valid dispensing, acknowledgement, sealed/dose conservation, repeat safety and rollback passed.');
} finally {await db.close();}
