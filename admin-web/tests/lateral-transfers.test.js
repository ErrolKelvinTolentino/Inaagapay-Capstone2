// Lateral Transfers & Endpoint Routing — regression tests.
//
//   node admin-web/tests/lateral-transfers.test.js
//
// Verifies:
// 1. PortalScope peer_facilities discovery & resolution
// 2. transferDirection() classification for:
//    - RHU to RHU (peer lateral)
//    - BHC to BHC (sibling lateral)
//    - RHU to BHC (allocation downward)
//    - BHC to RHU (return upward)
//    - RHU to MHO (return upward)
//    - MHO to RHU (allocation downward)
// 3. transferEndpoints() destination dropdown includes peer RHUs
// 4. transferEndpointName() names peer RHUs with real names (not "Facility #X")
const fs = require('fs');
const vm = require('vm');

let pass = 0, fail = 0;
function check(name, cond, detail) {
  if (cond) { pass++; console.log('  ok   ' + name); }
  else { fail++; console.log('  FAIL ' + name + (detail !== undefined ? '  -> ' + JSON.stringify(detail) : '')); }
}

// -----------------------------------------------------------------------------
// 1. PortalScope Tests
// -----------------------------------------------------------------------------
console.log('\n--- PortalScope (portal-scope.js) ---');

const portalScopeCode = fs.readFileSync('admin-web/pages/portal-scope.js', 'utf8');

// Mock browser environment for portal-scope.js
const mockLocalStorage = {
  store: {},
  getItem(k) { return this.store[k] || null; },
  setItem(k, v) { this.store[k] = String(v); },
  removeItem(k) { delete this.store[k]; }
};

// Seed an RHU session: RHU I (facility_id: 2, parent: 1)
mockLocalStorage.setItem('inaagapay_admin_session', JSON.stringify({
  account_id: 10,
  account_type: 'admin',
  facility_id: 2
}));

// Seed cached scope with child BHCs and peer RHUs
mockLocalStorage.setItem('inaagapay_portal_scope', JSON.stringify({
  ready: true,
  role: 'rhu',
  account_type: 'admin',
  facility_id: 2,
  facility_name: 'Rural Health Unit I',
  depot_facility_id: 2,
  depot_name: 'RHU I Depot',
  child_facility_type: 'BHC',
  child_facilities: [
    { facility_id: 10, name: 'Sto. Nino BHC' },
    { facility_id: 11, name: 'San Isidro BHC' }
  ],
  bhc_facilities: [
    { facility_id: 10, name: 'Sto. Nino BHC', parent_facility_id: 2 },
    { facility_id: 11, name: 'San Isidro BHC', parent_facility_id: 2 }
  ],
  peer_facilities: [
    { facility_id: 3, name: 'Rural Health Unit II', facility_type: 'RHU' },
    { facility_id: 4, name: 'Rural Health Unit III', facility_type: 'RHU' }
  ],
  parent_facility_id: 1,
  parent_facility_name: 'Municipal Health Office',
  scope_facility_ids: [2, 10, 11]
}));

const mockWindow = {};
const mockDoc = {
  querySelectorAll: () => [],
  getElementById: () => null,
  body: null,
  addEventListener: () => {}
};

const scopeCtx = {
  window: mockWindow,
  document: mockDoc,
  localStorage: mockLocalStorage,
  console
};

vm.createContext(scopeCtx);
vm.runInContext(portalScopeCode, scopeCtx);

const PortalScope = mockWindow.PortalScope;

check('PortalScope exists', !!PortalScope);
check('PortalScope is RHU', PortalScope.isRhu === true);
check('PortalScope has peerFacilities', Array.isArray(PortalScope.peerFacilities) && PortalScope.peerFacilities.length === 2);
check('PortalScope peerFacilities names RHU II', PortalScope.peerFacilities.some(p => p.name === 'Rural Health Unit II'));
check('PortalScope.facilityLabel resolves peer RHU name', PortalScope.facilityLabel(3) === 'Rural Health Unit II');
check('PortalScope.facilityLabel resolves child BHC name', PortalScope.facilityLabel(10) === 'Sto. Nino BHC');
check('PortalScope.facilityLabel resolves own depot name', PortalScope.facilityLabel(2) === 'RHU I Depot');
check('PortalScope.facilityLabel resolves parent MHO name', PortalScope.facilityLabel(1) === 'Municipal Health Office');


// -----------------------------------------------------------------------------
// 2. inventory.html transfer direction & endpoint tests
// -----------------------------------------------------------------------------
console.log('\n--- Inventory Transfer Logic (inventory.html) ---');

const invHtml = fs.readFileSync('admin-web/pages/inventory.html', 'utf8');

// Extract transferDirection, transferEndpoints, transferEndpointName, placeKey
// Let's create an environment matching inventory.html's scope
const invCtx = {
  PortalScope,
  bhcs: [
    { bhc_id: 10, bhc_name: 'Sto. Nino BHC' },
    { bhc_id: 11, bhc_name: 'San Isidro BHC' }
  ],
  municipalFacilityId: () => 1,
  unknownFacilityLabel: id => `Facility #${id}`,
  console
};

vm.createContext(invCtx);

// Extract helper functions from inventory.html
function extractFunction(src, name) {
  const marker = `function ${name}(`;
  const idx = src.indexOf(marker);
  if (idx < 0) throw new Error(`Could not find ${name} in source`);
  // Find matching braces
  let braceCount = 0;
  let started = false;
  let end = idx;
  for (let i = idx; i < src.length; i++) {
    if (src[i] === '{') {
      braceCount++;
      started = true;
    } else if (src[i] === '}') {
      braceCount--;
      if (started && braceCount === 0) {
        end = i + 1;
        break;
      }
    }
  }
  return src.slice(idx, end);
}

const fnPlaceKey = extractFunction(invHtml, 'placeKey');
const fnIsOwnDepot = extractFunction(invHtml, 'isOwnDepot');
const fnSamePlace = extractFunction(invHtml, 'samePlace');
const fnTransferDirection = extractFunction(invHtml, 'transferDirection');
const fnTransferEndpointName = extractFunction(invHtml, 'transferEndpointName');
const fnTransferEndpoints = extractFunction(invHtml, 'transferEndpoints');
const fnTransferSourceFacilityId = extractFunction(invHtml, 'transferSourceFacilityId');
const fnTransferDirectionOf = extractFunction(invHtml, 'transferDirectionOf');

const dirMetaIdx = invHtml.indexOf('const DIRECTION_META = {');
const dirMetaEnd = invHtml.indexOf('};', dirMetaIdx) + 2;
const dirMetaCode = invHtml.slice(dirMetaIdx, dirMetaEnd);

vm.runInContext(
  [fnPlaceKey, fnIsOwnDepot, fnSamePlace, dirMetaCode, fnTransferDirection, fnTransferEndpointName, fnTransferEndpoints, fnTransferSourceFacilityId, fnTransferDirectionOf].join('\n\n') +
  '\nglobalThis.__inv = { placeKey, isOwnDepot, samePlace, DIRECTION_META, transferDirection, transferEndpointName, transferEndpoints, transferSourceFacilityId, transferDirectionOf };',
  invCtx
);

const { transferDirection, transferEndpointName, transferEndpoints, transferSourceFacilityId, transferDirectionOf, DIRECTION_META } = invCtx.__inv;
invCtx.DIRECTION_META = DIRECTION_META;

// A. Test transferDirection
check('RHU 1 (depot: "central") -> RHU 2 (3): lateral', transferDirection('central', 3) === 'lateral', transferDirection('central', 3));
check('RHU 1 (depot: 2) -> RHU 2 (3): lateral', transferDirection(2, 3) === 'lateral', transferDirection(2, 3));
check('RHU 2 (3) -> RHU 1 (depot: 2): lateral', transferDirection(3, 2) === 'lateral', transferDirection(3, 2));

check('RHU 1 (depot: "central") -> BHC 10: allocation', transferDirection('central', 10) === 'allocation', transferDirection('central', 10));
check('RHU 1 (depot: 2) -> BHC 10: allocation', transferDirection(2, 10) === 'allocation', transferDirection(2, 10));

check('BHC 10 -> RHU 1 (depot: "central"): return', transferDirection(10, 'central') === 'return', transferDirection(10, 'central'));
check('BHC 10 -> RHU 1 (depot: 2): return', transferDirection(10, 2) === 'return', transferDirection(10, 2));

check('BHC 10 -> BHC 11: lateral (sister BHCs)', transferDirection(10, 11) === 'lateral', transferDirection(10, 11));
check('BHC 11 -> BHC 10: lateral (sister BHCs)', transferDirection(11, 10) === 'lateral', transferDirection(11, 10));

check('RHU 1 (depot: 2) -> MHO (warehouse: 1): return', transferDirection(2, 1) === 'return', transferDirection(2, 1));
check('MHO (warehouse: 1) -> RHU 1 (depot: 2): allocation', transferDirection(1, 2) === 'allocation', transferDirection(1, 2));

check('Self-transfer (2 -> 2): internal', transferDirection(2, 2) === 'internal', transferDirection(2, 2));
check('Self-transfer (10 -> 10): internal', transferDirection(10, 10) === 'internal', transferDirection(10, 10));

// B. Test transferEndpoints
const destEndpoints = transferEndpoints('destination');
const srcEndpoints = transferEndpoints('source');

check('Destination options include Peer Rural Health Units group',
  destEndpoints.some(e => e.group === 'Peer Rural Health Units (Lateral)'));
check('Destination options include RHU II',
  destEndpoints.some(e => e.value === '3' && e.label === 'Rural Health Unit II' && e.group === 'Peer Rural Health Units (Lateral)'));
check('Destination options include RHU III',
  destEndpoints.some(e => e.value === '4' && e.label === 'Rural Health Unit III' && e.group === 'Peer Rural Health Units (Lateral)'));
check('Destination options include Return upward to MHO',
  destEndpoints.some(e => e.value === '1' && e.group === 'Return upward'));
check('Destination options include child BHCs',
  destEndpoints.some(e => e.value === '10' && e.label === 'Sto. Nino BHC'));

check('Source options DO NOT include peer RHUs (RHU cannot issue from peer depot)',
  !srcEndpoints.some(e => e.group === 'Peer Rural Health Units (Lateral)'));
check('Source options DO NOT include return upward',
  !srcEndpoints.some(e => e.group === 'Return upward'));
check('Source options include own depot',
  srcEndpoints.some(e => e.value === 'central'));
check('Source options include child BHCs (for BHC-to-BHC or BHC return)',
  srcEndpoints.some(e => e.value === '10'));

// C. Test transferEndpointName
check('transferEndpointName(3) resolves to "Rural Health Unit II" (not "Facility #3")',
  transferEndpointName(3) === 'Rural Health Unit II', transferEndpointName(3));
check('transferEndpointName(4) resolves to "Rural Health Unit III"',
  transferEndpointName(4) === 'Rural Health Unit III', transferEndpointName(4));
check('transferEndpointName(2) resolves to "RHU I Depot"',
  transferEndpointName(2) === 'RHU I Depot', transferEndpointName(2));
check('transferEndpointName(10) resolves to "Sto. Nino BHC"',
  transferEndpointName(10) === 'Sto. Nino BHC', transferEndpointName(10));
check('transferEndpointName(1) resolves to "Municipal Health Office"',
  transferEndpointName(1) === 'Municipal Health Office', transferEndpointName(1));

// -----------------------------------------------------------------------------
// 3. Inventory Movement Transfer Audit Note & Details Resolution
// -----------------------------------------------------------------------------
console.log('\n--- Inventory Movement Transfer Audit Note Resolution ---');

// Mock inventory data matching inventory.html globals
const mockTransfers = [
  {
    transfer_id: 101,
    source_facility_id: 10,
    destination_facility_id: 11,
    source_batch_id: 55,
    quantity_issued: 25,
    status: 'pending_receipt',
    remarks: 'Expected delivery: 2026-09-06. Reason for move: Emergency shortage at recipient BHC. Urgent resupply.',
    voucher_no: 'STV-2026-00101',
    created_at: '2026-09-05T08:30:00Z'
  }
];

const mockItems = [
  { item_id: 1, name: 'Amoxicillin 500mg', generic_name: 'Amoxicillin', unit_of_measure: 'capsule', item_type: 'medicine' }
];

const mockBatches = [
  { batch_id: 55, item_id: 1, batch_number: 'AMX-2026A', expiration_date: '2027-03-31' }
];

const mockTx = {
  transaction_id: 888,
  batch_id: 55,
  facility_id: 10,
  transaction_type: 'transfer',
  quantity: -25,
  reference_type: 'Lateral transfer: Sto. Nino BHC to San Isidro BHC - pending receipt',
  reference_id: 101,
  performed_by: 10,
  activity_reason: 'Emergency shortage at recipient BHC',
  activity_notes: 'Urgent resupply',
  logged_at: '2026-09-05T08:30:00Z'
};

// Simulate the transfer resolution logic in openMovementNarrative
const refId = mockTx.reference_id || (mockTx.reference_type && (String(mockTx.reference_type).match(/#(\d+)/) || [])[1]);
const resolvedTransferId = mockTx.transfer_id || (mockTx.transaction_type === 'transfer' ? mockTx.reference_id : refId);
const resolvedTransfer = (mockTransfers || []).find(x => String(x.transfer_id) === String(resolvedTransferId));

check('Movement transfer resolves transfer ID from reference_id', resolvedTransferId === 101, resolvedTransferId);
check('Movement transfer finds transfer record in mockTransfers', !!resolvedTransfer && resolvedTransfer.transfer_id === 101);

if (resolvedTransfer) {
  const srcName = transferEndpointName(transferSourceFacilityId(resolvedTransfer));
  const dstName = transferEndpointName(resolvedTransfer.destination_facility_id);
  const dirKey = transferDirectionOf(resolvedTransfer);
  const dirMeta = invCtx.DIRECTION_META[dirKey] || { label: 'Transfer' };
  const reasonMatch = String(resolvedTransfer.remarks || '').match(/Reason for move:\s*([^.]+)\./i);
  const moveReason = reasonMatch ? reasonMatch[1].trim() : resolvedTransfer.remarks;

  check('Transfer origin resolves to Sto. Nino BHC', srcName === 'Sto. Nino BHC', srcName);
  check('Transfer destination resolves to San Isidro BHC', dstName === 'San Isidro BHC', dstName);
  check('Transfer direction resolves to Lateral', dirKey === 'lateral' && dirMeta.label === 'Lateral', dirKey);
  check('Transfer reason parsed correctly', moveReason === 'Emergency shortage at recipient BHC', moveReason);

  const transferSection = {
    title: 'Stock Transfer Route & Movement Tracking',
    rows: [
      { label: 'Transfer ID', value: `#${resolvedTransfer.transfer_id}` },
      { label: 'Movement Direction', value: dirMeta.label },
      { label: 'Originating Facility', value: srcName },
      { label: 'Destination Facility', value: dstName },
      { label: 'Transfer Status', value: (resolvedTransfer.status || 'pending').replace(/_/g, ' ').toUpperCase() },
      { label: 'Quantity Dispatched', value: `${resolvedTransfer.quantity_issued} capsules` },
      { label: 'Movement Purpose / Reason', value: moveReason },
      { label: 'Voucher Number', value: resolvedTransfer.voucher_no }
    ]
  };

  check('Audit note transferSection contains Transfer ID', transferSection.rows.some(r => r.label === 'Transfer ID' && r.value === '#101'));
  check('Audit note transferSection contains Direction', transferSection.rows.some(r => r.label === 'Movement Direction' && r.value === 'Lateral'));
  check('Audit note transferSection contains Origin & Destination',
    transferSection.rows.some(r => r.label === 'Originating Facility' && r.value === 'Sto. Nino BHC') &&
    transferSection.rows.some(r => r.label === 'Destination Facility' && r.value === 'San Isidro BHC'));
  check('Audit note transferSection contains Reason', transferSection.rows.some(r => r.label === 'Movement Purpose / Reason' && r.value === 'Emergency shortage at recipient BHC'));
}

console.log(`\nResults: ${pass} passed, ${fail} failed.\n`);
if (fail > 0) process.exit(1);
