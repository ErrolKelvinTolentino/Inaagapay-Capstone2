import fs from 'node:fs';
import assert from 'node:assert/strict';
import { PGlite } from './validation/node_modules/@electric-sql/pglite/dist/index.js';

const cleanup = fs.readFileSync('database/seed/23_remove_qa_history.sql', 'utf8');
const db = new PGlite();
try {
  await db.exec(`
    CREATE TABLE accounts(account_id bigint PRIMARY KEY, name text);
    CREATE TABLE lab_tests(lab_test_id bigint PRIMARY KEY, image text);
    CREATE TABLE audit_trail(audit_id bigint PRIMARY KEY, description text, old_data jsonb);
    CREATE TABLE email_queue(email_id bigint PRIMARY KEY, recipient text, body text);
    CREATE TABLE admin_change_events(event_id bigserial PRIMARY KEY, operation text);
    CREATE FUNCTION notify_audit_delete() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN INSERT INTO admin_change_events(operation) VALUES(TG_OP); RETURN NULL; END; $$;
    CREATE TRIGGER audit_delete AFTER DELETE ON audit_trail FOR EACH STATEMENT EXECUTE FUNCTION notify_audit_delete();
    INSERT INTO accounts VALUES(48,'Preserved mother');
    INSERT INTO lab_tests VALUES(1,'data:image/png;base64,random QA bytes');
    INSERT INTO audit_trail VALUES
      (1,'Codex fixture',NULL),
      (2,'Login','{"email_address":"user@qa.test"}'),
      (3,'QA simulated record',NULL),
      (4,'Ordinary history',NULL),
      (5,'Saved image','{"image":"data:image/png;base64, QA "}'),
      (6,'Credential change','{"password_hash":"codex", "nested":{"access_token":"QA"}}');
    INSERT INTO email_queue VALUES(1,'user@qa.test','QA email'),(2,'qa@example.com','Ordinary email');
  `);
  const result = await db.exec(cleanup);
  assert.deepEqual(result.flatMap(r => r.rows ?? []).filter(r => 'removed_qa_audits' in r),
    [{ removed_qa_audits: 3, removed_qa_emails: 1 }]);
  assert.deepEqual((await db.query('SELECT audit_id FROM audit_trail ORDER BY audit_id')).rows,
    [{ audit_id: 4 }, { audit_id: 5 }, { audit_id: 6 }]);
  assert.equal((await db.query('SELECT count(*)::int AS n FROM accounts')).rows[0].n, 1);
  assert.equal((await db.query('SELECT image FROM lab_tests')).rows[0].image, 'data:image/png;base64,random QA bytes');
  assert.equal((await db.query('SELECT recipient FROM email_queue')).rows[0].recipient, 'qa@example.com');
  const second = await db.exec(cleanup);
  assert.deepEqual(second.flatMap(r => r.rows ?? []).filter(r => 'removed_qa_audits' in r),
    [{ removed_qa_audits: 0, removed_qa_emails: 0 }]);

  // A new downstream FK must block deletion, including cascading references.
  await db.exec(`CREATE TABLE audit_dependents(id bigint PRIMARY KEY, audit_id bigint REFERENCES audit_trail ON DELETE CASCADE);
    INSERT INTO audit_trail VALUES(7,'Codex fixture',NULL); INSERT INTO audit_dependents VALUES(1,7);`);
  await assert.rejects(db.exec(cleanup), /referencing foreign keys/);
  await db.exec('ROLLBACK');
  assert.equal((await db.query('SELECT count(*)::int AS n FROM audit_dependents')).rows[0].n, 1);
  console.log('QA history cleanup: reviewed markers, image/credential exclusions, preservation, idempotency and FK guard passed.');
} finally {
  await db.close();
}
