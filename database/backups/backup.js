/* =====================================================
   InaAgapay — pre-seed data backup

   clean_and_seed_vaccines_supplements.sql deletes every inventory item, batch
   and ledger row, and clears the inventory foreign keys on the clinical
   tables. This project has PITR disabled and no physical backups, so there is
   nothing to restore from if that goes wrong.

   This pulls the affected tables out over PostgREST and writes, per table:

     <table>.json   the rows exactly as returned
     restore.sql    INSERT statements that put them back

   It is a DATA backup of the tables the seed touches — not a database backup.
   Schema, functions, RLS policies and every other table are not covered.

   Usage:  node database/backups/backup.js
   ===================================================== */

const fs = require("fs");
const path = require("path");

const SUPABASE_URL = "https://krooorixhjwygcsdoomg.supabase.co/rest/v1";
const ANON_KEY =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imtyb29vcml4aGp3eWdjc2Rvb21nIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ0NjI5NDIsImV4cCI6MjEwMDAzODk0Mn0.iVIxsgZhd_k0c-rDOjRK5J9xBiL0z-bH2l1LXH9IksU";
const HEADERS = { apikey: ANON_KEY, Authorization: "Bearer " + ANON_KEY };

// Wiped outright by the seed — every column is needed to restore them.
const FULL_TABLES = [
  "inventory_items",
  "inventory_batches",
  "inventory_transactions",
  "inventory_transfers",
  "inventory_stock_requests",
];

// Survive the seed, but have their inventory foreign key set to NULL by it.
// Only the key pair is taken: enough to relink, and no clinical detail leaves
// the database.
const LINK_TABLES = [
  { table: "immunization_records", pk: "immunization_record_id", cols: ["inventory_batch_id", "inventory_deducted"] },
  { table: "maternal_td_records", pk: "td_record_id", cols: ["inventory_batch_id", "inventory_deducted"] },
  { table: "vaccines", pk: "vaccine_id", cols: ["inventory_item_id"] },
];

const PAGE = 1000;

async function fetchAll(table, select) {
  const rows = [];
  for (let offset = 0; ; offset += PAGE) {
    const url = `${SUPABASE_URL}/${table}?select=${encodeURIComponent(select)}&limit=${PAGE}&offset=${offset}`;
    const res = await fetch(url, { headers: HEADERS });
    const body = await res.json();
    if (!res.ok || !Array.isArray(body)) {
      const err = new Error(body && body.message ? body.message : `HTTP ${res.status}`);
      err.detail = body;
      throw err;
    }
    rows.push(...body);
    if (body.length < PAGE) break;
  }
  return rows;
}

/** A Postgres literal for one JSON value. */
function lit(v) {
  if (v === null || v === undefined) return "NULL";
  if (typeof v === "number") return String(v);
  if (typeof v === "boolean") return v ? "true" : "false";
  if (typeof v === "object") return `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb`;
  return `'${String(v).replace(/'/g, "''")}'`;
}

function insertStatements(table, rows) {
  if (rows.length === 0) return `-- ${table}: no rows\n`;
  const cols = Object.keys(rows[0]);
  const head = `INSERT INTO public.${table} (${cols.map((c) => `"${c}"`).join(", ")}) VALUES\n`;
  const values = rows
    .map((r) => "  (" + cols.map((c) => lit(r[c])).join(", ") + ")")
    .join(",\n");
  return `${head}${values}\nON CONFLICT DO NOTHING;\n`;
}

function relinkStatements(spec, rows) {
  const live = rows.filter((r) => spec.cols.some((c) => r[c] !== null && r[c] !== false));
  if (live.length === 0) return `-- ${spec.table}: nothing was linked\n`;
  return live
    .map((r) => {
      const sets = spec.cols.map((c) => `"${c}" = ${lit(r[c])}`).join(", ");
      return `UPDATE public.${spec.table} SET ${sets} WHERE "${spec.pk}" = ${lit(r[spec.pk])};`;
    })
    .join("\n") + "\n";
}

(async () => {
  const stamp = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
  const dir = path.join(__dirname, stamp);
  fs.mkdirSync(dir, { recursive: true });

  const report = [];
  let restore = `-- InaAgapay data restore — captured ${new Date().toISOString()}\n`;
  restore += `-- Rebuilds the tables clean_and_seed_vaccines_supplements.sql wipes.\n`;
  restore += `-- Run inside a transaction, against an empty set of inventory tables.\n\nBEGIN;\n\n`;

  for (const table of FULL_TABLES) {
    try {
      const rows = await fetchAll(table, "*");
      fs.writeFileSync(path.join(dir, `${table}.json`), JSON.stringify(rows, null, 2));
      restore += `-- ${table} (${rows.length} rows)\n${insertStatements(table, rows)}\n`;
      report.push({ table, rows: rows.length, status: "ok" });
    } catch (e) {
      report.push({ table, rows: 0, status: "FAILED: " + e.message });
      restore += `-- ${table}: NOT CAPTURED (${e.message})\n\n`;
    }
  }

  restore += `-- Re-link the clinical records the seed unlinks\n`;
  for (const spec of LINK_TABLES) {
    try {
      const rows = await fetchAll(spec.table, [spec.pk, ...spec.cols].join(","));
      fs.writeFileSync(path.join(dir, `${spec.table}.links.json`), JSON.stringify(rows, null, 2));
      const linked = rows.filter((r) => spec.cols.some((c) => r[c] !== null && r[c] !== false)).length;
      restore += relinkStatements(spec, rows) + "\n";
      report.push({ table: spec.table + " (links)", rows: `${linked} linked of ${rows.length}`, status: "ok" });
    } catch (e) {
      report.push({ table: spec.table + " (links)", rows: 0, status: "FAILED: " + e.message });
      restore += `-- ${spec.table}: NOT CAPTURED (${e.message})\n\n`;
    }
  }

  restore += `\n-- Sequences must be moved past the restored ids, or the next insert collides.\n`;
  for (const t of FULL_TABLES) {
    const pk = { inventory_items: "item_id", inventory_batches: "batch_id", inventory_transactions: "transaction_id", inventory_transfers: "transfer_id", inventory_stock_requests: "request_id" }[t];
    restore += `SELECT setval(pg_get_serial_sequence('public.${t}', '${pk}'), COALESCE((SELECT MAX(${pk}) FROM public.${t}), 1), true);\n`;
  }
  restore += `\nCOMMIT;\n`;

  fs.writeFileSync(path.join(dir, "restore.sql"), restore);
  fs.writeFileSync(path.join(dir, "manifest.json"), JSON.stringify({ captured_at: new Date().toISOString(), project: "krooorixhjwygcsdoomg", report }, null, 2));

  console.log(`backup written to database/backups/${stamp}\n`);
  const pad = (s, n) => String(s).padEnd(n);
  console.log("  " + pad("table", 34) + pad("rows", 22) + "status");
  console.log("  " + "-".repeat(70));
  report.forEach((r) => console.log("  " + pad(r.table, 34) + pad(r.rows, 22) + r.status));
  const failed = report.filter((r) => r.status !== "ok");
  console.log(`\n  ${report.length - failed.length} of ${report.length} captured` + (failed.length ? ` — ${failed.length} FAILED` : ""));
})();
