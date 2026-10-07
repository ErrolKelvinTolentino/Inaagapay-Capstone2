// Isolated PostgreSQL execution of the actual seed SQL. No remote connections.
// npm install --prefix scripts/validation --ignore-scripts
// node scripts/test-revision-seeds.mjs
import fs from 'node:fs';
import assert from 'node:assert/strict';
import { PGlite } from './validation/node_modules/@electric-sql/pglite/dist/index.js';

const db = new PGlite();
const cleanup = fs.readFileSync('database/seed/20_remove_qa_fixtures.sql','utf8');
const activity = fs.readFileSync('database/seed/21_admin_consumption_activity.sql','utf8');
const count = async table => (await db.query(`SELECT count(*)::int AS n FROM ${table}`)).rows[0].n;
try {
  await db.exec(`
    CREATE TABLE accounts (account_id bigint PRIMARY KEY,email_address text,status text,account_type text);
    CREATE TABLE mothers (mother_id bigint PRIMARY KEY,account_id bigint REFERENCES accounts ON DELETE CASCADE);
    CREATE TABLE children (child_id bigint PRIMARY KEY,mother_id bigint REFERENCES mothers ON DELETE SET NULL,first_name text,last_name text);
    CREATE TABLE health_facilities (facility_id bigint PRIMARY KEY,name text,barangay text,facility_type text,parent_facility_id bigint,is_active boolean);
    CREATE TABLE inventory_items (item_id bigint PRIMARY KEY,name text,generic_name text,doses_per_unit int,open_vial_shelf_hours int,is_archived boolean);
    CREATE TABLE inventory_batches (batch_id bigserial PRIMARY KEY,item_id bigint REFERENCES inventory_items ON DELETE CASCADE,
      facility_id bigint REFERENCES health_facilities,batch_number text,quantity_received int,quantity_remaining int,
      received_date date,expiration_date date,manufacturer text,status text,doses_remaining_in_open_vial int DEFAULT 0,
      open_vials_count int DEFAULT 0,vial_opened_at timestamptz,
      CHECK (quantity_remaining>=0 AND quantity_remaining<=quantity_received));
    CREATE TABLE inventory_transactions (transaction_id bigserial PRIMARY KEY,batch_id bigint REFERENCES inventory_batches ON DELETE CASCADE,
      facility_id bigint,transaction_type text,quantity int,dose_quantity int,reference_type text,reference_id bigint,
      notes text,performed_by bigint REFERENCES accounts ON DELETE SET NULL,resulting_quantity_remaining int,resulting_open_vial_doses int,logged_at timestamptz);
    CREATE TABLE vaccines (vaccine_id bigint PRIMARY KEY,vaccine_name text,inventory_item_id bigint REFERENCES inventory_items ON DELETE SET NULL);
    CREATE TABLE given_medications (id bigint PRIMARY KEY,mother_id bigint REFERENCES mothers ON DELETE CASCADE,inventory_batch_id bigint REFERENCES inventory_batches ON DELETE RESTRICT);
    CREATE TABLE maternal_td_records (id bigint PRIMARY KEY,mother_id bigint REFERENCES mothers ON DELETE CASCADE,inventory_batch_id bigint REFERENCES inventory_batches);
    CREATE TABLE immunization_records (id bigint PRIMARY KEY,child_id bigint REFERENCES children ON DELETE CASCADE,vaccine_id bigint REFERENCES vaccines,inventory_batch_id bigint REFERENCES inventory_batches);
    CREATE TABLE immunization_schedule (schedule_id bigint PRIMARY KEY,vaccine_id bigint REFERENCES vaccines,notes text);
    CREATE TABLE inventory_stock_requests (request_id bigint PRIMARY KEY,item_id bigint REFERENCES inventory_items,requested_by bigint REFERENCES accounts ON DELETE RESTRICT);
    CREATE TABLE inventory_transfers (transfer_id bigint PRIMARY KEY,source_batch_id bigint REFERENCES inventory_batches,
      destination_batch_id bigint REFERENCES inventory_batches,issued_by bigint REFERENCES accounts ON DELETE RESTRICT,
      request_id bigint REFERENCES inventory_stock_requests ON DELETE SET NULL);
    CREATE TABLE inventory_count_sessions (count_id bigint PRIMARY KEY);
    CREATE TABLE inventory_count_lines (line_id bigint PRIMARY KEY,count_id bigint REFERENCES inventory_count_sessions ON DELETE CASCADE,batch_id bigint REFERENCES inventory_batches);
    CREATE TABLE inventory_disposals (id bigint PRIMARY KEY,batch_id bigint REFERENCES inventory_batches);
    CREATE TABLE inventory_unusable_stock_reports (id bigint PRIMARY KEY,batch_id bigint REFERENCES inventory_batches);
    CREATE TABLE audit_trail (audit_id bigserial PRIMARY KEY,table_name text,row_id text,old_data jsonb,new_data jsonb);
    CREATE VIEW child_immunization_coverage AS SELECT child_id,current_date AS birthdate FROM children;
    CREATE FUNCTION resolve_actor_account_id(bigint) RETURNS bigint LANGUAGE sql AS 'SELECT $1';
    INSERT INTO accounts VALUES (1,'mho@example.internal','active','mho'),(2,'codex.qa@qa.test','active','mother'),(3,'contest@example.internal','active','mother');
    INSERT INTO mothers VALUES (10,1),(20,2),(30,3);
    INSERT INTO children VALUES (100,10,'Diwata','Bituin'),(200,20,'QA Baby','Workbook'),(201,NULL,'Test','Child'),(300,30,'Testament','Rivera');
    INSERT INTO health_facilities VALUES (1,'RHU I','','RHU',NULL,true),(2,'Tarcan BHC','Tarcan','BHC',1,true),
      (3,'San Jose BHC','San Jose','BHC',1,true),(4,'Concepcion BHC','Concepcion','BHC',1,true),(5,'Other RHU BHC','Other','BHC',9,true);
    INSERT INTO inventory_items VALUES (1,'Ferrous Sulfate + Folic Acid','',1,0,false),(2,'Calcium Carbonate','',1,0,false),
      (58,'Codex QA Count Item 20260929','',1,0,false),(59,'Latest test-approved supply','',1,0,false);
    INSERT INTO inventory_batches (item_id,facility_id,batch_number,quantity_received,quantity_remaining,received_date,expiration_date,status)
      VALUES (58,2,'QA-CODEX',100,95,current_date-30,current_date+100,'active'),
        (1,2,'REAL-CONSUMED',100,37,current_date-30,current_date+100,'active'),
        (2,2,'CODEX-MW-QA-ORDINARY-ITEM',10,10,current_date-30,current_date+100,'active');
    INSERT INTO inventory_transactions (batch_id,quantity,transaction_type) VALUES (1,100,'receipt'),(1,-5,'dispense'),(2,100,'receipt'),(2,-63,'dispense'),(3,10,'receipt');
    INSERT INTO vaccines VALUES (1,'Iron programme',1),(58,'QA vaccine',58);
    INSERT INTO given_medications VALUES (1,20,1);
    INSERT INTO maternal_td_records VALUES (1,20,1);
    INSERT INTO immunization_records VALUES (1,200,58,1);
    INSERT INTO immunization_schedule VALUES (1,1,'Tarcan drive'),(58,58,'Codex QA drive');
    INSERT INTO inventory_stock_requests VALUES (1,58,2),(2,1,2),(3,1,1);
    INSERT INTO inventory_transfers (transfer_id,source_batch_id,destination_batch_id,issued_by) VALUES (1,1,NULL,2);
    INSERT INTO inventory_count_sessions VALUES (1),(2);
    INSERT INTO inventory_count_lines VALUES (1,1,1),(2,2,1),(3,2,2);
    INSERT INTO inventory_disposals VALUES (1,1);
    INSERT INTO inventory_unusable_stock_reports VALUES (1,1);
    INSERT INTO audit_trail (table_name,row_id,old_data) VALUES ('inventory_items','58','{"name":"Codex QA"}'),
      ('inventory_transactions','1','{}'),('given_medications','1','{"mother_id":20}'),('inventory_transactions','3','{}');
  `);

  // A real family's use of QA stock aborts and rolls back the whole cleanup.
  await db.exec('INSERT INTO given_medications VALUES (2,10,1)');
  await assert.rejects(db.exec(cleanup), /non-QA clinical record/);
  await db.exec('ROLLBACK');
  assert.equal(await count('inventory_items'),4);
  assert.equal(await count('children'),4);
  await db.exec('DELETE FROM given_medications WHERE id=2');
  await db.exec('INSERT INTO given_medications VALUES (3,NULL,1)');
  await assert.rejects(db.exec(cleanup), /non-QA clinical record/);
  await db.exec('ROLLBACK');
  await db.exec('DELETE FROM given_medications WHERE id=3');
  await db.exec('INSERT INTO inventory_transfers (transfer_id,source_batch_id,issued_by) VALUES (2,2,2)');
  await assert.rejects(db.exec(cleanup), /non-QA clinical record/);
  await db.exec('ROLLBACK');
  await db.exec('DELETE FROM inventory_transfers WHERE transfer_id=2');
  await db.exec(cleanup);
  assert.equal(await count('accounts'),2);
  assert.equal(await count('mothers'),2);
  assert.equal(await count('children'),3);
  assert.equal((await db.query('SELECT count(*)::int AS n FROM children WHERE child_id=201')).rows[0].n,1,'An orphan child is not a QA fixture solely because its name contains Test');
  assert.deepEqual((await db.query('SELECT request_id FROM inventory_stock_requests')).rows,[{request_id:3}],'Remove QA requesters\' requests even for ordinary catalogue items');
  assert.equal(await count('inventory_items'),3);
  assert.equal(await count('inventory_transactions'),2);
  assert.equal(await count('inventory_batches'),1,'Codex-marked batches on ordinary items are removed too');
  assert.equal(await count('immunization_schedule'),1);
  assert.equal(await count('inventory_count_sessions'),1);
  assert.equal(await count('inventory_count_lines'),1);
  assert.equal(await count('audit_trail'),1);
  assert.equal((await db.query('SELECT quantity_remaining FROM inventory_batches WHERE batch_id=2')).rows[0].quantity_remaining,37);
  await db.exec(cleanup);
  assert.equal(await count('audit_trail'),1,'Repeat cleanup preserves the remaining movement audit');

  // Execute the actual production presentation and dispensing functions.
  const source=fs.readFileSync('database/migrations/20260831_dose_presentation_single_source.sql','utf8');
  for (const name of ['item_dose_presentation','dispense_stock_doses']) {
    const start=source.indexOf(`CREATE OR REPLACE FUNCTION public.${name}(`);
    const end=source.indexOf('$fn$;',start)+'$fn$;'.length;
    await db.exec(source.slice(start,end));
  }
  await db.exec(fs.readFileSync('database/migrations/20261007_require_open_vial_disposal.sql','utf8'));
  await db.exec(activity);
  const batches=(await db.query(`SELECT b.*,sum(t.quantity)::int AS ledger_balance FROM inventory_batches b
    JOIN inventory_transactions t USING(batch_id) WHERE batch_number LIKE 'DEFENSE-%' GROUP BY b.batch_id`)).rows;
  assert.equal(batches.length,6);
  assert.ok(batches.every(b=>b.quantity_remaining===b.ledger_balance));
  assert.equal((await db.query('SELECT quantity_remaining FROM inventory_batches WHERE batch_id=2')).rows[0].quantity_remaining,37);
  const tarcanIron=batches.find(b=>b.facility_id===2 && b.item_id===1);
  const previous=(await db.query(`SELECT sum(-quantity)::int AS units,count(*)::int AS events
    FROM inventory_transactions WHERE batch_id=$1 AND reference_type LIKE '% previous-%'`,[tarcanIron.batch_id])).rows[0];
  assert.deepEqual(previous,{units:1800,events:30});
  assert.equal((await db.query(`SELECT max(day_units)::int AS peak FROM
    (SELECT sum(-quantity) AS day_units FROM inventory_transactions WHERE batch_id=$1 AND transaction_type='dispense'
      AND reference_type LIKE '% previous-%' GROUP BY (logged_at AT TIME ZONE 'Asia/Manila')::date) x`,[tarcanIron.batch_id])).rows[0].peak,360);
  assert.equal((await db.query(`SELECT count(*)::int AS n FROM inventory_transactions
    WHERE reference_type LIKE 'Defense demo %' AND logged_at>now()`)).rows[0].n,0);
  const txCount=await count('inventory_transactions');
  await db.exec(activity);
  assert.equal(await count('inventory_transactions'),txCount,'Seed rerun cannot dispense twice');
  console.log('Revision seeds: guarded cleanup, fixture audit removal, preserved stock, actual RPC deductions, peak usage and idempotency passed.');
} finally { await db.close(); }
