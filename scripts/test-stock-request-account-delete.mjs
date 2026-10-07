// Runs the migration in isolated PostgreSQL; never connects to Supabase.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import { PGlite } from './validation/node_modules/@electric-sql/pglite/dist/index.js';

const db = new PGlite();
const migration = fs.readFileSync('database/migrations/20261007_stock_request_requester_delete_cascade.sql', 'utf8');
try {
  await db.exec(`
    CREATE TABLE accounts (account_id bigint PRIMARY KEY);
    CREATE TABLE inventory_stock_requests (
      request_id bigint PRIMARY KEY,
      requested_by bigint NOT NULL,
      CONSTRAINT inventory_stock_requests_requested_by_fkey
        FOREIGN KEY (requested_by) REFERENCES accounts ON DELETE RESTRICT
    );
    CREATE TABLE inventory_transfers (
      transfer_id bigint PRIMARY KEY,
      request_id bigint REFERENCES inventory_stock_requests ON DELETE SET NULL,
      issued_by bigint NOT NULL REFERENCES accounts ON DELETE RESTRICT
    );
    INSERT INTO accounts VALUES (100), (200);
    INSERT INTO inventory_stock_requests VALUES (20,100), (21,100), (30,200);
    INSERT INTO inventory_transfers VALUES (23,20,200);
  `);

  await db.exec(migration);
  await db.exec(migration);
  assert.equal((await db.query('SELECT count(*)::int AS n FROM inventory_stock_requests')).rows[0].n, 3);
  assert.equal((await db.query("SELECT confdeltype FROM pg_constraint WHERE conname = 'inventory_stock_requests_requested_by_fkey'")).rows[0].confdeltype, 'c');
  await assert.rejects(db.query('INSERT INTO inventory_stock_requests VALUES (40,999)'), /foreign key constraint/);

  // Cascade affects only the deleted requester's rows. Received transfers
  // survive with their request link cleared and their issuer unchanged.
  await db.exec('DELETE FROM accounts WHERE account_id=100');
  assert.deepEqual((await db.query('SELECT * FROM inventory_stock_requests')).rows, [{request_id: 30, requested_by: 200}]);
  assert.deepEqual((await db.query('SELECT * FROM inventory_transfers')).rows, [{transfer_id: 23, request_id: null, issued_by: 200}]);
  assert.deepEqual((await db.query('SELECT * FROM accounts')).rows, [{account_id: 200}]);

  // Separate issuer restrictions still block the delete atomically: stock
  // requests must not disappear when another FK rejects the account delete.
  await db.exec(`
    INSERT INTO accounts VALUES (100);
    INSERT INTO inventory_stock_requests VALUES (20,100);
    INSERT INTO inventory_transfers VALUES (24,20,100);
  `);
  await assert.rejects(db.query('DELETE FROM accounts WHERE account_id=100'), /foreign key constraint/);
  assert.equal((await db.query('SELECT count(*)::int AS n FROM inventory_stock_requests WHERE requested_by=100')).rows[0].n, 1);
  assert.equal((await db.query('SELECT count(*)::int AS n FROM accounts WHERE account_id=100')).rows[0].n, 1);
  console.log('PASS: migration rerun, FK enforcement, scoped cascade, retained transfers, and rollback on issuer restriction.');
} finally {
  await db.close();
}
