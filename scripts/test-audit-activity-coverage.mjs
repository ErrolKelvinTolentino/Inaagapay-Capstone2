// Isolated PostgreSQL tests; no network, live accounts or patient records.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import { PGlite } from './validation/node_modules/@electric-sql/pglite/dist/index.js';

const db = new PGlite();
const base = fs.readFileSync('database/migrations/20260826_audit_trail_completeness.sql', 'utf8');
const actor = fs.readFileSync('database/migrations/20260930_portal_admin_scope_and_audit_actor.sql', 'utf8');
const clinical = fs.readFileSync('database/migrations/20260922_audit_clinical_encounter_tables.sql', 'utf8');
const migration = fs.readFileSync('database/migrations/20261008_audit_vaccinations_and_drives.sql', 'utf8');
function definition(source, name) {
  const start = source.indexOf(`CREATE OR REPLACE FUNCTION public.${name}(`);
  assert.ok(start >= 0, name);
  const end = source.indexOf('$fn$;', start);
  assert.ok(end > start, name);
  return source.slice(start, end + 6);
}
async function logs(table) {
  return (await db.query('SELECT * FROM audit_trail WHERE table_name=$1 ORDER BY audit_id', [table])).rows;
}

try {
  await db.exec(`
    CREATE TABLE accounts (
      account_id bigint PRIMARY KEY, account_type text DEFAULT 'midwife', first_name text,
      last_name text, middle_name text, extension_name text, email_address text, phone_number text,
      password_hash text, status text DEFAULT 'active', is_verified boolean DEFAULT true,
      created_at timestamp DEFAULT now(), updated_at timestamp, last_login_at timestamp,
      last_login_token text, verification_code text, reset_code text,
      is_temporary_password boolean DEFAULT false, created_by text, status_changed_by bigint
    );
    CREATE TABLE midwives (midwife_id bigint PRIMARY KEY, account_id bigint REFERENCES accounts);
    CREATE TABLE health_facilities (facility_id bigint PRIMARY KEY, name text);
    CREATE TABLE facility_assignments (facility_assignment_id bigint, account_id bigint,
      facility_id bigint, is_active boolean, assigned_at timestamp);
    CREATE TABLE maternal_td_records (td_record_id bigint PRIMARY KEY, mother_id bigint,
      dose_number text, vaccination_date date, facility_id bigint, source text,
      administered_by bigint REFERENCES midwives, inventory_deducted boolean DEFAULT false,
      inventory_batch_id bigint, remarks text, immunization_schedule_id bigint);
    CREATE TABLE immunization_schedule (immunization_schedule_id bigint PRIMARY KEY,
      facility_id bigint, bhc_id bigint, vaccine_id bigint, schedule_date date, notes text);
    CREATE TABLE clinical_encounters (encounter_id bigint PRIMARY KEY, recorded_by bigint);
    CREATE TABLE prenatal_checkups (encounter_id bigint PRIMARY KEY REFERENCES clinical_encounters,
      pregnancy_id bigint, checkup_weight numeric);
    CREATE TABLE lab_tests (encounter_id bigint PRIMARY KEY REFERENCES clinical_encounters);
    CREATE TABLE ultrasounds (encounter_id bigint PRIMARY KEY REFERENCES clinical_encounters);
    CREATE TABLE immunization_records (immunization_record_id bigint PRIMARY KEY, administered_by bigint);
    CREATE TABLE ai_responses (ai_response_id bigint PRIMARY KEY, reference_table text,
      reference_id bigint, approved_by bigint, generated_by_ai boolean, status text);
    CREATE TABLE pregnancy_risk_assessments (pregnancy_risk_id bigint PRIMARY KEY,
      pregnancy_id bigint, ai_response_id bigint REFERENCES ai_responses,
      risk_level text, assessed_by_ai boolean, updated_at timestamp);
    CREATE TABLE audit_trail (audit_id bigserial PRIMARY KEY, action_timestamp timestamp DEFAULT now(),
      account_id bigint REFERENCES accounts, action text, table_name text, row_id text,
      old_data jsonb, new_data jsonb, description text, actor_name text, actor_role text,
      actor_facility_id bigint, actor_facility_name text, module text, severity text,
      entity_label text, narrative text, details jsonb, related_ids jsonb, source text,
      event_key text, event_txid bigint);
    INSERT INTO accounts(account_id,first_name,last_name) VALUES (1,'Test','Scheduler'),(10,'Test','Nurse');
    INSERT INTO midwives VALUES (1,10);
    INSERT INTO maternal_td_records(td_record_id,dose_number) VALUES (90,'Td1');
    INSERT INTO immunization_schedule VALUES (90,1,1,1,'2026-10-08',NULL);
    -- Deliberately model the legacy ambiguous resolver: numeric actor 1 is
    -- midwife 1/account 10, whereas the scheduler's account is actually 1.
    CREATE FUNCTION audit_actor(p_actor bigint) RETURNS jsonb LANGUAGE sql AS $$
      SELECT jsonb_build_object('account_id',CASE WHEN p_actor=1 THEN 10 ELSE p_actor END,
        'name',CASE WHEN p_actor IS NULL THEN 'System' ELSE 'Test Nurse' END,
        'role',CASE WHEN p_actor IS NULL THEN 'system' ELSE 'midwife' END);
    $$;
  `);
  for (const name of ['audit_kv','audit_section','audit_bigint','audit_redact','audit_ts',
    'audit_utc','audit_module_for','audit_severity_for','audit_write']) await db.exec(definition(base, name));
  await db.exec(definition(actor, 'audit_account_actor'));
  await db.exec(definition(actor, 'audit_account_change'));
  await db.exec(definition(clinical, 'audit_clinical_change'));
  await db.exec(`
    CREATE TRIGGER account_audit AFTER INSERT OR UPDATE OR DELETE ON accounts
      FOR EACH ROW EXECUTE FUNCTION audit_account_change();
    CREATE TRIGGER prenatal_audit AFTER INSERT OR UPDATE OR DELETE ON prenatal_checkups
      FOR EACH ROW EXECUTE FUNCTION audit_clinical_change('encounter_id','prenatal_checkup');
    CREATE TRIGGER lab_audit AFTER INSERT OR UPDATE OR DELETE ON lab_tests
      FOR EACH ROW EXECUTE FUNCTION audit_clinical_change('encounter_id','lab_test');
    CREATE TRIGGER ultrasound_audit AFTER INSERT OR UPDATE OR DELETE ON ultrasounds
      FOR EACH ROW EXECUTE FUNCTION audit_clinical_change('encounter_id','ultrasound');
    CREATE TRIGGER immunization_audit AFTER INSERT OR UPDATE OR DELETE ON immunization_records
      FOR EACH ROW EXECUTE FUNCTION audit_clinical_change('immunization_record_id','immunization');
  `);

  await db.exec(migration);
  await db.exec(migration);
  assert.equal((await logs('maternal_td_records')).length, 0, 'no invented historical audits');
  assert.equal((await logs('immunization_schedule')).length, 0);
  assert.equal((await db.query('SELECT count(*)::int AS n FROM maternal_td_records')).rows[0].n, 1);

  await db.exec(`INSERT INTO maternal_td_records(td_record_id,mother_id,dose_number,administered_by)
    VALUES (1,50,'Td2',1); UPDATE maternal_td_records SET inventory_deducted=true WHERE td_record_id=1;`);
  let td = await logs('maternal_td_records');
  assert.equal(td.length, 1, 'stock bookkeeping must not duplicate clinical events');
  assert.equal(td[0].action, 'create_maternal_td');
  assert.equal(td[0].account_id, 10, 'administered_by is a midwife_id');
  assert.equal(td[0].module, 'Clinical');
  assert.equal(td[0].related_ids.mother_id, '50');
  await db.exec("UPDATE maternal_td_records SET dose_number='Td3' WHERE td_record_id=1");
  td = await logs('maternal_td_records');
  assert.equal(td[1].action, 'update_maternal_td');
  assert.match(td[1].narrative, /dose number/);
  await db.exec('DELETE FROM maternal_td_records WHERE td_record_id=1');
  assert.equal((await logs('maternal_td_records'))[2].action, 'delete_maternal_td');

  await db.exec(`INSERT INTO immunization_schedule(immunization_schedule_id,facility_id,vaccine_id,schedule_date,scheduled_by)
    VALUES (1,1,1,'2026-10-09',1);`);
  let drives = await logs('immunization_schedule');
  assert.equal(drives[0].action, 'schedule_vaccination_drive');
  assert.equal(drives[0].account_id, 1, 'scheduled_by is an account_id despite a midwife-id collision');
  assert.equal(drives[0].actor_name, 'Test Scheduler');
  assert.equal(drives[0].module, 'Vaccination Drives');
  await db.exec("UPDATE immunization_schedule SET schedule_date='2026-10-10' WHERE immunization_schedule_id=1");
  assert.equal((await logs('immunization_schedule'))[1].action, 'update_vaccination_drive');
  await db.exec('DELETE FROM immunization_schedule WHERE immunization_schedule_id=1');
  assert.equal((await logs('immunization_schedule'))[2].action, 'delete_vaccination_drive');
  await db.exec('INSERT INTO immunization_schedule(immunization_schedule_id) VALUES (2)');
  drives = await logs('immunization_schedule');
  assert.equal(drives[3].actor_name, 'System', 'older callers must not receive an invented actor');
  assert.equal(drives[3].account_id, null);
  const count = drives.length;
  await db.exec('UPDATE immunization_schedule SET vaccine_id=vaccine_id WHERE immunization_schedule_id=2');
  assert.equal((await logs('immunization_schedule')).length, count, 'no-op edit is not an event');

  // Existing clinical and account/password auditing survives the extension.
  await db.exec(`INSERT INTO clinical_encounters VALUES (1,1),(2,1),(3,1);
    INSERT INTO prenatal_checkups VALUES (1,8,60); INSERT INTO lab_tests VALUES (2);
    INSERT INTO ultrasounds VALUES (3); INSERT INTO immunization_records VALUES (1,1);
    UPDATE accounts SET phone_number='09123456789' WHERE account_id=1;
    UPDATE accounts SET password_hash='test-hash-not-a-real-password' WHERE account_id=1;`);
  for (const [table, action] of [['prenatal_checkups','create_prenatal_checkup'], ['lab_tests','create_lab_test'],
    ['ultrasounds','create_ultrasound'], ['immunization_records','create_immunization']]) {
    assert.equal((await logs(table))[0].action, action);
  }
  const accountLogs = await logs('accounts');
  assert.equal(accountLogs[0].action, 'update_account');
  assert.equal(accountLogs[1].action, 'change_password');
  assert.equal(accountLogs[1].new_data.password_hash, '[redacted]');
  assert.ok(!JSON.stringify(accountLogs).includes('test-hash-not-a-real-password'));
  await db.exec(`INSERT INTO ai_responses VALUES
    (1,'prenatal_checkups',1,1,true,'approved'), (2,'prenatal_checkups',1,1,true,'edited'),
    (3,'ultrasounds',1,1,true,'approved'), (4,'prenatal_checkups',1,1,true,'skipped');
    INSERT INTO pregnancy_risk_assessments VALUES
    (1,8,1,'Low',true,NULL), (2,8,1,'High',false,NULL),
    (3,8,2,'High',false,NULL), (4,8,NULL,'High',false,NULL),
    (5,8,3,'High',false,NULL), (6,8,4,'High',false,NULL);`);
  let reviews = await logs('pregnancy_risk_assessments');
  assert.equal(reviews.length, 1, 'only an actual override of used prenatal AI insights is audited');
  assert.equal(reviews[0].action, 'ai_prenatal_insight_edited');
  assert.equal(reviews[0].account_id, 1);
  assert.equal(reviews[0].related_ids.encounter_id, 1);
  assert.equal(reviews[0].module, 'AI');
  assert.ok(!reviews[0].narrative.includes('High'), 'no clinical values in the narrative');
  await db.exec('UPDATE pregnancy_risk_assessments SET updated_at=now() WHERE pregnancy_risk_id=2');
  assert.equal((await logs('pregnancy_risk_assessments')).length, 1);
  await db.exec("UPDATE pregnancy_risk_assessments SET risk_level='Moderate' WHERE pregnancy_risk_id=2");
  assert.equal((await logs('pregnancy_risk_assessments')).length, 1,
    'a later unattributed database correction is not a new midwife AI review');
  // The phone writes with the API role. Restricting direct execution of the
  // trigger function must not prevent an otherwise permitted clinical save.
  await db.exec(`CREATE ROLE test_api_writer;
    GRANT INSERT ON maternal_td_records, immunization_schedule TO test_api_writer;
    SET ROLE test_api_writer;
    INSERT INTO maternal_td_records(td_record_id,dose_number,administered_by) VALUES (2,'Td1',1);
    INSERT INTO immunization_schedule(immunization_schedule_id,scheduled_by) VALUES (3,1);
    RESET ROLE;`);
  assert.equal((await logs('maternal_td_records')).at(-1).account_id, 10);
  assert.equal((await logs('immunization_schedule')).at(-1).account_id, 1);
  console.log('PASS: idempotence, no backfill, Td recording/edit/deletion, drive scheduling/rescheduling/deletion, actor-id collisions, no-op suppression, existing clinical/profile/password audits, credential redaction.');
} finally {
  await db.close();
}
