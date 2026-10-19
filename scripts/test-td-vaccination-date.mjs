// Run the real Td RPC and migration in isolated PostgreSQL; no live patients,
// doses, stock deductions or notifications. Freeze the clock only in the test
// copy to reproduce the midnight Philippine / previous-day UTC boundary.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import { PGlite } from './validation/node_modules/@electric-sql/pglite/dist/index.js';

const db = new PGlite();
const baseline = fs.readFileSync('database/migrations/20260821_inventory_and_td_fixes.sql', 'utf8');
const migration = fs.readFileSync('database/migrations/20261008_td_vaccination_philippine_date.sql', 'utf8');
const signature = 'administer_maternal_td_dose(bigint,text,date,bigint,bigint,text,text,text,text)';
const oldGuard = 'p_vaccination_date > CURRENT_DATE';
const newGuard = "p_vaccination_date > (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Manila')::date";
function definition(name) {
  const start = baseline.indexOf(`CREATE OR REPLACE FUNCTION public.${name}(`);
  const end = baseline.indexOf('$fn$;', start);
  assert(start >= 0 && end > start);
  return baseline.slice(start, end + 6);
}
async function metadata() {
  return (await db.query(`SELECT prosrc,proacl::text,proconfig,prosecdef,proowner
    FROM pg_proc WHERE oid=$1::regprocedure`, [signature])).rows[0];
}
async function rpc(mother, date, dose = 'Td1', source = 'external') {
  return (await db.query(`SELECT public.administer_maternal_td_dose($1,$2,$3,2,1,$4) AS result`,
    [mother, dose, date, source])).rows[0].result;
}
async function freeze(source, instant) {
  await db.query("SELECT set_config('test.td_now',$1,false)", [instant]);
  const testDefinition = source
    .replace(/\bCURRENT_DATE\b/g, '(public.td_test_clock())::date')
    .replace(/\bCURRENT_TIMESTAMP\b/g, 'public.td_test_clock()')
    .replace(/\bNOW\(\)/gi, 'public.td_test_clock()');
  await db.exec(testDefinition);
}
try {
  await db.exec(`
    SET TIME ZONE 'UTC';
    CREATE ROLE authenticated;
    CREATE TABLE accounts(account_id bigint PRIMARY KEY);
    CREATE TABLE midwives(midwife_id bigint PRIMARY KEY,account_id bigint REFERENCES accounts);
    INSERT INTO accounts VALUES(10); INSERT INTO midwives VALUES(1,10);
    CREATE TABLE maternal_td_records(td_record_id bigserial PRIMARY KEY,mother_id bigint,
      dose_number text,vaccination_date date,facility_id bigint,facility_name text,source text,
      administered_by bigint REFERENCES midwives,inventory_deducted boolean,
      protection_until date,next_due_date date,remarks text,evidence text,inventory_batch_id bigint,
      UNIQUE(mother_id,dose_number));
    CREATE TABLE inventory_items(item_id bigint PRIMARY KEY,name text,generic_name text,
      doses_per_unit int,open_vial_shelf_hours int,is_archived boolean,item_type text);
    CREATE TABLE inventory_batches(batch_id bigint PRIMARY KEY,item_id bigint,facility_id bigint,
      batch_number text,quantity_remaining int,status text,expiration_date date,vial_opened_at timestamptz,
      doses_remaining_in_open_vial int,open_vials_count int);
    CREATE TABLE inventory_transactions(transaction_id bigserial PRIMARY KEY,batch_id bigint,
      facility_id bigint,transaction_type text,quantity int,reference_type text,reference_id bigint,
      notes text,performed_by bigint REFERENCES accounts,logged_at timestamp);
    INSERT INTO inventory_items VALUES(1,'Td vaccine','Tetanus',10,672,false,'vaccine');
    INSERT INTO inventory_batches VALUES(1,1,2,'TD-TEST',10,'active','2027-01-01',NULL,0,0);
    CREATE FUNCTION public.td_test_clock() RETURNS timestamptz LANGUAGE sql VOLATILE
      AS 'SELECT current_setting(''test.td_now'')::timestamptz';
  `);
  for (const name of ['resolve_actor_account_id','normalize_td_dose','td_dose_schedule','administer_maternal_td_dose']) {
    await db.exec(definition(name));
  }
  await db.exec(`REVOKE ALL ON FUNCTION ${signature} FROM PUBLIC;
    GRANT EXECUTE ON FUNCTION ${signature} TO authenticated`);
  const before = await metadata();
  await db.exec(migration);
  await db.exec(migration);
  const after = await metadata();
  assert.deepEqual({ ...after, prosrc: before.prosrc }, before, 'Owner, grants, security and timezone settings stay intact');
  assert.equal(after.prosrc, before.prosrc.replace(oldGuard, newGuard), 'Only the future-date comparison changes');
  assert.equal((await db.query('SELECT count(*)::int AS n FROM maternal_td_records')).rows[0].n, 0, 'Installing the migration cannot record vaccinations');
  const patchedDefinition = (await db.query('SELECT pg_get_functiondef($1::regprocedure) AS definition', [signature])).rows[0].definition;

  await freeze(definition('administer_maternal_td_dose'), '2026-10-07T16:30:00Z');
  assert.equal((await rpc(1,'2026-10-08')).success, false, 'Reproduce today falsely rejected after Philippine midnight');
  let mother = 2;
  for (const zone of ['UTC', 'America/Los_Angeles', 'Asia/Manila']) {
    await db.query("SELECT set_config('TimeZone',$1,false)", [zone]);
    for (const [instant, today, tomorrow] of [
      ['2026-10-07T15:59:59Z','2026-10-07','2026-10-08'],
      ['2026-10-07T16:00:00Z','2026-10-08','2026-10-09'],
      ['2026-10-07T23:59:59Z','2026-10-08','2026-10-09'],
      ['2026-10-08T00:00:00Z','2026-10-08','2026-10-09'],
    ]) {
      await freeze(patchedDefinition, instant);
      assert.equal((await rpc(mother++,today)).success, true, `${zone}: local today allowed at ${instant}`);
      assert.equal((await rpc(mother++,tomorrow)).success, false, `${zone}: future day still rejected at ${instant}`);
      assert.equal((await db.query('SHOW TimeZone')).rows[0].TimeZone, zone);
    }
  }
  await db.exec("SET TIME ZONE 'UTC'");
  await freeze(patchedDefinition, '2026-10-07T16:30:00Z');
  assert.equal((await rpc(100,null)).success, false);
  assert.equal((await rpc(100,'2026-10-08','Td9')).success, false);
  assert.equal((await rpc(100,'2026-10-06')).success, true, 'Past vaccination dates remain valid');
  await rpc(101,'2026-09-11');
  assert.match((await rpc(101,'2026-10-08','Td2')).error, /DOH interval not met/);
  await rpc(102,'2026-09-10');
  assert.equal((await rpc(102,'2026-10-08','Td2')).success, true, 'The 28-day minimum remains valid');
  assert.equal((await db.query('SELECT count(*)::int AS n FROM inventory_transactions')).rows[0].n, 0);
  const given = await rpc(103,'2026-10-08','Td1','bhc');
  assert.equal(given.mode,'new_vial_opened');
  assert.equal((await rpc(103,'2026-10-08','Td1','bhc')).mode,'already_deducted');
  assert.equal((await rpc(104,'2026-10-08','Td1','bhc')).mode,'open_vial_dose');
  const batches = (await db.query('SELECT quantity_remaining,doses_remaining_in_open_vial FROM inventory_batches')).rows;
  assert.deepEqual(batches,[{ quantity_remaining: 9, doses_remaining_in_open_vial: 8 }]);
  const ledger = (await db.query('SELECT quantity,performed_by,logged_at::text AS logged_at FROM inventory_transactions ORDER BY transaction_id')).rows;
  assert.equal(ledger.length,2);
  assert.equal(ledger[0].quantity,-1);
  assert.equal(ledger[1].quantity,0);
  assert(ledger.every(row => row.performed_by === 10 && row.logged_at === '2026-10-07 16:30:00'), 'Ledger timestamps stay UTC and the administering actor stays correct');
  console.log('Td date validation: midnight regression, three session timezones, future/null dates, past history, dose intervals, stock deductions, repeat safety, UTC timestamps and permissions passed.');
} finally {
  await db.close();
}
