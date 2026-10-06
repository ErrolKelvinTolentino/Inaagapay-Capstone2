// Additive, repeatable supply seed requested for the revision demonstration.
// node scripts/replenish-inventory.mjs [--apply]
// Uses the configured project. Never resets existing batches or movements.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const env = Object.fromEntries(fs.readFileSync(path.join(root, 'inaagapay_flutter_v2/.env'), 'utf8')
  .split(/\r?\n/).filter(l => l.includes('=') && !l.trim().startsWith('#'))
  .map(l => { const i = l.indexOf('='); return [l.slice(0, i).trim(), l.slice(i + 1).trim().replace(/^['"]|['"]$/g, '')]; }));
const run = 'REV-20261007';
const date = '2026-10-07';
async function api(table, query, method = 'GET', body) {
  const response = await fetch(`${env.SUPABASE_URL}/rest/v1/${table}?${query}`, {
    method, headers: { apikey: env.SUPABASE_ANON_KEY, 'Content-Type': 'application/json', Prefer: 'return=representation' },
    ...(body ? { body: JSON.stringify(body) } : {}), signal: AbortSignal.timeout(30000),
  });
  const result = await response.json();
  if (!response.ok) throw new Error(`${table}: HTTP ${response.status} (${result.code ?? 'request failed'})`);
  return result;
}
try {
  const [items, facilities, batches] = await Promise.all([
    api('inventory_items', 'select=item_id,name,item_type,minimum_stock_threshold,is_archived&is_archived=eq.false'),
    api('health_facilities', 'select=facility_id,name,facility_type,is_active&is_active=eq.true'),
    api('inventory_batches', 'select=batch_id,item_id,facility_id,batch_number,quantity_received,quantity_remaining,status,expiration_date'),
  ]);
  const shelves = [...facilities.filter(f => ['BHC', 'RHU', 'MHO'].includes(f.facility_type))];
  // Older portals use a null facility ID for their municipal warehouse.
  if (batches.some(b => b.facility_id === null)) shelves.push({ facility_id: null, name: 'Municipal Warehouse', facility_type: 'MHO' });
  const additions = [];
  for (const facility of shelves) for (const item of items) {
    const number = `${run}-F${facility.facility_id ?? 'MW'}-I${item.item_id}`;
    if (batches.some(b => b.batch_number === number)) continue;
    const tier = facility.facility_type === 'MHO' ? 5 : facility.facility_type === 'RHU' ? 2 : 1;
    const target = Math.max(item.item_type === 'supplement' ? 5000 : 1000, (item.minimum_stock_threshold ?? 0) * 10) * tier;
    const available = batches.filter(b => b.item_id === item.item_id && b.facility_id === facility.facility_id && b.status === 'active' && b.expiration_date >= date)
      .reduce((sum, b) => sum + b.quantity_remaining, 0);
    const quantity = Math.max(0, target - available);
    if (!quantity) continue;
    additions.push({ item_id: item.item_id, facility_id: facility.facility_id, batch_number: number,
      quantity_received: quantity, quantity_remaining: quantity, received_date: date,
      expiration_date: item.item_type === 'vaccine' ? '2028-04-07' : '2029-04-07',
      manufacturer: null, status: 'active', created_by: null });
  }
  console.log(JSON.stringify({ mode: process.argv.includes('--apply') ? 'apply' : 'preview', activeItems: items.length,
    facilities: shelves.length, barangayCenters: shelves.filter(f => f.facility_type === 'BHC').length,
    newBatches: additions.length, unitsToAdd: additions.reduce((n, b) => n + b.quantity_received, 0) }));
  if (!process.argv.includes('--apply')) process.exit(0);
  const added = additions.length ? await api('inventory_batches', 'select=batch_id,facility_id,batch_number,quantity_received', 'POST', additions) : [];
  const runBatches = [...batches.filter(b => b.batch_number.startsWith(run + '-')), ...added];
  const existing = await api('inventory_transactions', `select=batch_id&reference_type=eq.Revision%20supply%20seed%202026-10-07`);
  const recorded = new Set(existing.map(t => t.batch_id));
  const receipts = runBatches.filter(b => !recorded.has(b.batch_id)).map(b => ({
    batch_id: b.batch_id, facility_id: b.facility_id, transaction_type: 'receipt', quantity: b.quantity_received,
    reference_type: 'Revision supply seed 2026-10-07', performed_by: null,
    notes: 'Supply seed requested for the revision demonstration. No physical delivery or transfer is asserted.',
    resulting_quantity_remaining: b.quantity_received,
    client_operation_key: `${run}:receipt:${b.batch_id}`,
  }));
  if (receipts.length) await api('inventory_transactions', 'select=transaction_id', 'POST', receipts);
  const after = await api('inventory_batches', 'select=item_id,facility_id,quantity_remaining,status,expiration_date');
  const shortages = [];
  for (const f of shelves) for (const i of items) {
    const available = after.filter(b => b.item_id === i.item_id && b.facility_id === f.facility_id && b.status === 'active' && b.expiration_date >= date)
      .reduce((sum, b) => sum + b.quantity_remaining, 0);
    const target = Math.max(i.item_type === 'supplement' ? 5000 : 1000, (i.minimum_stock_threshold ?? 0) * 10)
      * (f.facility_type === 'MHO' ? 5 : f.facility_type === 'RHU' ? 2 : 1);
    if (available < target) shortages.push({ facility: f.name, item: i.name, available, target });
  }
  console.log(JSON.stringify({ createdBatches: added.length, receiptEntries: receipts.length, shortages }));
  if (shortages.length) process.exitCode = 1;
} catch (error) { console.error(error.message); process.exitCode = 1; }
