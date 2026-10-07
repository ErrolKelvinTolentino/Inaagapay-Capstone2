const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const test = require('node:test');

const source = fs.readFileSync('admin-web/pages/inventory.html', 'utf8');
const now = Date.parse('2026-10-07T12:00:00+08:00');
class Clock extends Date {
  constructor(...args) { super(...(args.length ? args : [now])); }
  static now() { return now; }
}
function section(start, end) {
  const offset = source.indexOf(start);
  assert.ok(offset >= 0, `Missing source section: ${start}`);
  const stop = source.indexOf(end, offset);
  assert.ok(stop > offset, `Missing end of source section: ${end}`);
  return source.slice(offset, stop);
}
function batch(id, overrides = {}) {
  return { batch_id: id, item_id: 1, facility_id: 2, batch_number: `LOT-${id}`,
    status: 'active', quantity_received: 5, quantity_remaining: 4,
    expiration_date: '2027-10-01', received_date: '2026-09-01',
    doses_remaining_in_open_vial: 0, vial_opened_at: null, ...overrides };
}
function opened(hoursAgo) { return new Date(now - hoursAgo * 3600000).toISOString(); }
function harness(batches) {
  const nodes = {
    'global-bhc-filter': { value: 'all' }, 'batches-search': { value: '' },
    'batches-filter-status': { value: '' }, 'batches-filter-expiry': { value: '' },
    'batches-tbody': { innerHTML: '' }, 'open-vials-tbody': { innerHTML: '' },
    'tx-search': { value: '' }, 'tx-filter-type': { value: '' },
    'tx-filter-direction': { value: '' }, 'tx-tbody': { innerHTML: '' },
  };
  const ctx = {
    batches, items: [{ item_id: 1, name: 'BCG', doses_per_unit: 10, open_vial_shelf_hours: 6 }],
    transactions: [], window: {}, Date: Clock, console,
    document: { getElementById: id => nodes[id] || null },
    ctlVal: id => nodes[id]?.value || '', dateWindow: () => null, inDateWindow: () => true,
    facilityMatches: (id, filter) => filter === 'all' || String(id) === filter,
    batchLocationName: b => `Facility ${b.facility_id}`, getNearestUsableBatch: () => null,
    isOwnDepot: () => false, isColdChainItem: () => true, isBatchColdChainCompromised: () => false,
    esc: value => String(value), formatShortDate: value => value,
    syncSortIndicators() {}, renderTableMeta() {}, renderPaginationControls() {},
    renderDoseConfigWarning() {}, emptyStateRow: () => '<tr><td>No batches</td></tr>',
    accountMap: {}, inventoryTransfers: [], doseLedgerViewAvailable: true,
    formatDateTimeStacked: value => value, transferEndpointName: id => `Facility ${id}`,
    paginationState: { batches: { currentPage: 1, pageSize: 2 }, tx: { currentPage: 1, pageSize: 10 } },
  };
  vm.createContext(ctx);
  for (const [start, end] of [
    ['        const tableViews =', '        function ctl('],
    ['        function cmpValues(', '        window.toggleSort ='],
    ['        function isBatchExpired(', '        function daysUntil('],
    ['        function storedOpenDoses(', '        /** "8 vials'],
    ['        function openVialAgeHours(', '        function describeShelfLimit('],
    ['        function getExpiryCountdownBadge(', '        // Render Subview A:'],
    ['        function batchExpiryState(', '        function renderBatches('],
    ['        function renderBatches(', '        // Render Barangay Stock Allocation'],
    ['        function renderTransactions(', '        window.openMovementNarrative ='],
    ['        function renderOpenVialsTracker(', '        window.renderOpenVialsTracker ='],
  ]) vm.runInContext(section(start, end), ctx);
  return { ctx, nodes, view: vm.runInContext('tableViews.batches', ctx) };
}
function ids(rows) { return Array.from(rows, row => row.batch_id); }
function renderedIds(html) {
  return [...html.matchAll(/<tr data-batch-id="(\d+)"/g)].map(match => Number(match[1]));
}

test('expiry priority surfaces spoiled pools before expired sealed stock and near-expiry usable stock', () => {
  const rows = [
    batch(1),
    batch(2, { expiration_date: '2026-10-08' }),
    batch(3, { doses_remaining_in_open_vial: 3, vial_opened_at: opened(5.5) }),
    batch(4, { expiration_date: '2026-09-01' }),
    batch(5, { doses_remaining_in_open_vial: 3, vial_opened_at: opened(6) }),
    batch(6, { doses_remaining_in_open_vial: 3 }),
    batch(7, { status: 'discarded', quantity_remaining: 0, expiration_date: '2025-01-01' }),
  ];
  const before = JSON.stringify(rows);
  const { ctx } = harness(rows);
  assert.deepEqual(ids(ctx.sortByExpiryPriority(rows)), [5, 6, 4, 3, 2, 1, 7]);
  assert.equal(JSON.stringify(rows), before, 'Sorting must not change stock or source order');
  assert.deepEqual(ids(ctx.sortByExpiryPriority(rows, false)), [7, 1, 2, 3, 4, 5, 6]);
  rows[4].doses_remaining_in_open_vial = 0;
  rows[4].vial_opened_at = null;
  assert.deepEqual(ids(ctx.sortByExpiryPriority(rows)).slice(0, 3), [6, 4, 3],
    'Confirmed discard releases the batch from the first disposal group');
});

test('expired filters catch overdue and unverified open doses, including the exact shelf boundary', () => {
  const { ctx } = harness([]);
  const stale = batch(1, { doses_remaining_in_open_vial: 3, vial_opened_at: opened(6) });
  const unverified = batch(2, { doses_remaining_in_open_vial: 3, vial_opened_at: 'invalid-time' });
  const expiringToday = batch(3, { expiration_date: '2026-10-07' });
  for (const row of [stale, unverified, expiringToday]) {
    assert.equal(ctx.matchesBatchExpiryFilters(row, 'expired', ''), true);
    assert.equal(ctx.matchesBatchExpiryFilters(row, '', 'expired'), true);
    assert.equal(ctx.matchesBatchExpiryFilters(row, 'active', ''), false);
    assert.equal(ctx.matchesBatchExpiryFilters(row, '', 'safe'), false);
    assert.equal(ctx.matchesBatchExpiryFilters(row, '', '30'), false);
  }
  const healthy = batch(4, { doses_remaining_in_open_vial: 3, vial_opened_at: opened(5) });
  assert.equal(ctx.matchesBatchExpiryFilters(healthy, 'active', '30'), true);
  assert.equal(ctx.matchesBatchExpiryFilters(healthy, '', 'safe'), false,
    'The open-vial deadline takes precedence over a distant sealed expiry');
  assert.equal(ctx.matchesBatchExpiryFilters(batch(5), 'active', 'safe'), true);
  assert.equal(ctx.matchesBatchExpiryFilters(batch(6, { status: 'discarded' }), 'discarded', ''), true);
  ctx.items[0].open_vial_shelf_hours = 0;
  assert.equal(ctx.matchesBatchExpiryFilters(unverified, 'active', 'safe'), true,
    'An explicit zero shelf limit is preserved');
});

test('batch renderer applies urgency before pagination while retaining facility filters and date-column sorting', () => {
  const overdue = batch(30, { doses_remaining_in_open_vial: 3, vial_opened_at: opened(7) });
  const rows = [batch(1, { expiration_date: '2026-10-08' }), batch(2), overdue,
    batch(31, { facility_id: 9, doses_remaining_in_open_vial: 3, vial_opened_at: opened(8) })];
  const { ctx, nodes, view } = harness(rows);
  nodes['global-bhc-filter'].value = '2';
  assert.equal(view.sortField, 'expiry_priority');
  ctx.renderBatches();
  assert.deepEqual(renderedIds(nodes['batches-tbody'].innerHTML), [30, 1]);
  assert.ok(nodes['batches-tbody'].innerHTML.includes('Open doses expired'));
  assert.ok(nodes['batches-tbody'].innerHTML.includes('discard required'));
  assert.ok(!nodes['batches-tbody'].innerHTML.includes('quickDispense(30)'));
  assert.ok(nodes['batches-tbody'].innerHTML.includes('openDiscardVialModal(30)'));
  nodes['batches-filter-expiry'].value = 'expired';
  ctx.renderBatches();
  assert.deepEqual(renderedIds(nodes['batches-tbody'].innerHTML), [30]);
  nodes['batches-filter-expiry'].value = '';
  view.sortField = 'expiration';
  ctx.renderBatches();
  assert.deepEqual(renderedIds(nodes['batches-tbody'].innerHTML), [1, 2],
    'Explicit sealed-expiry column sorting still uses the printed batch expiry');
  assert.ok(source.includes('data-sort="batches:expiry_priority"'));
});

test('open-vial monitor orders spoiled doses first and never labels a calendar-expired batch as active', () => {
  const { ctx, nodes } = harness([
    batch(1, { doses_remaining_in_open_vial: 3, vial_opened_at: opened(1) }),
    batch(2, { doses_remaining_in_open_vial: 3, vial_opened_at: opened(5.5) }),
    batch(3, { doses_remaining_in_open_vial: 3, vial_opened_at: opened(7) }),
    batch(4, { doses_remaining_in_open_vial: 3, vial_opened_at: 'invalid-time' }),
    batch(5, { doses_remaining_in_open_vial: 3, vial_opened_at: opened(1), expiration_date: '2026-10-07' }),
    batch(6, { facility_id: 9, doses_remaining_in_open_vial: 3, vial_opened_at: opened(8) }),
  ]);
  nodes['global-bhc-filter'].value = '2';
  ctx.renderOpenVialsTracker();
  const html = nodes['open-vials-tbody'].innerHTML;
  assert.deepEqual([...html.matchAll(/<code>LOT-(\d+)<\/code>/g)].map(match => Number(match[1])), [3, 4, 5, 2, 1]);
  assert.ok(html.includes('Time unverified'));
  assert.ok(html.includes('Batch expired — unusable'));
  assert.ok(!html.includes('NaN'));
});

test('Discarded includes open-dose loss history while keeping remaining sealed stock usable', () => {
  const active = batch(1);
  const fullyDiscarded = batch(2, { status: 'discarded', quantity_remaining: 0 });
  const healthy = batch(3);
  const { ctx, nodes } = harness([active, fullyDiscarded, healthy]);
  ctx.transactions = [
    { transaction_id: 91, batch_id: '1', facility_id: 2, transaction_type: 'discard',
      quantity: 0, dose_quantity: -3, reference_type: 'Open Vial Discard', logged_at: '2026-10-07T02:00:00Z' },
    { transaction_id: 92, batch_id: 3, facility_id: 2, transaction_type: 'dispense',
      quantity: 0, dose_quantity: -2, reference_type: 'Child Immunization' },
  ];
  const before = JSON.stringify(active);
  nodes['batches-filter-status'].value = 'discarded';
  ctx.renderBatches();
  const html = nodes['batches-tbody'].innerHTML;
  assert.deepEqual(renderedIds(html), [1, 2]);
  assert.ok(html.includes('3 open dose(s) discarded'));
  assert.ok(html.includes('Batch discarded'));
  assert.ok(html.includes('openMovementNarrative(91)'), 'Details point to the actual discard record');
  assert.ok(html.includes('quickDispense(1)'), 'Remaining healthy sealed stock still permits Use');
  assert.equal(ctx.matchesBatchExpiryFilters(active, 'active', ''), true);
  assert.equal(JSON.stringify(active), before, 'Filtering history must not change remaining stock or batch status');
});

test('discard history distinguishes legacy dose quantities from sealed losses and opens the newest record', () => {
  const row = batch(1);
  const { ctx } = harness([row]);
  ctx.transactions = [
    { transaction_id: 81, batch_id: 1, transaction_type: 'discard', quantity: -2,
      reference_type: 'Open Vial Discard', logged_at: '2026-09-01T00:00:00Z' },
    { transaction_id: 82, batch_id: 1, transaction_type: 'expiry_disposal', quantity: 0, dose_quantity: -3,
      reference_type: 'Open Vial Expiry', logged_at: '2026-10-01T00:00:00Z' },
    { transaction_id: 83, batch_id: 1, transaction_type: 'expiry_disposal', quantity: -1, dose_quantity: -10,
      reference_type: 'Damaged sealed vial', logged_at: '2026-09-15T00:00:00Z' },
    { transaction_id: 84, batch_id: 1, transaction_type: 'discard', quantity: 0, dose_quantity: 0 },
    { transaction_id: 85, batch_id: 1, transaction_type: 'adjustment', quantity: -5 },
    { transaction_id: 86, batch_id: 9, transaction_type: 'discard', quantity: 0, dose_quantity: -20 },
  ];
  const before = JSON.stringify(ctx.transactions);
  const history = ctx.batchDiscardHistory(row);
  assert.equal(history.openDoses, 5);
  assert.equal(history.units, 1);
  assert.deepEqual(Array.from(history.records, tx => tx.transaction_id), [82, 83, 81]);
  assert.equal(JSON.stringify(ctx.transactions), before);
});

test('the discard ledger filter and Stock Out retain dose-only discards with zero sealed-unit movement', () => {
  const { ctx, nodes } = harness([batch(1), batch(2)]);
  ctx.transactions = [
    { transaction_id: 91, batch_id: 1, facility_id: 2, transaction_type: 'discard',
      quantity: 0, dose_quantity: -3, reference_type: 'Open Vial Discard' },
    { transaction_id: 92, batch_id: 1, facility_id: 2, transaction_type: 'expiry_disposal',
      quantity: -1, dose_quantity: -10, reference_type: 'Damaged sealed vial' },
    { transaction_id: 93, batch_id: 1, facility_id: 2, transaction_type: 'dispense',
      quantity: 0, dose_quantity: -2, reference_type: 'Child Immunization' },
    { transaction_id: 94, batch_id: 2, facility_id: 9, transaction_type: 'discard',
      quantity: 0, dose_quantity: -3, reference_type: 'Open Vial Discard' },
  ];
  nodes['global-bhc-filter'].value = '2';
  nodes['tx-filter-type'].value = 'discards';
  nodes['tx-filter-direction'].value = 'out';
  ctx.renderTransactions();
  const html = nodes['tx-tbody'].innerHTML;
  const details = [...html.matchAll(/onclick="openMovementNarrative\((\d+)\)"/g)].map(match => Number(match[1]));
  assert.deepEqual(details, [91, 92]);
  assert.ok(html.includes('Discarded'));
  assert.ok(html.includes('-3 dose(s)'));
  nodes['tx-filter-direction'].value = 'in';
  ctx.renderTransactions();
  assert.ok(!nodes['tx-tbody'].innerHTML.includes('openMovementNarrative'));
});
