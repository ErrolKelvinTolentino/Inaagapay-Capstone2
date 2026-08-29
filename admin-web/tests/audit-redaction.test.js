// Audit trail redaction policy — regression tests.
//
//   node admin-web/tests/audit-redaction.test.js
//
// Pulls the real functions out of audit-trail.html and exercises them against
// row shapes taken from active-draftschema.sql. It re-implements nothing: if
// the policy in the page changes, this runs the changed policy.
//
// Why it exists: audit_clinical_change() snapshots whole patient rows into
// old_data / new_data, and this page is what prints them. Widening the policy
// by accident — adding a key to STRUCTURAL_KEY, dropping one from
// PERSONAL_KEYS, adding a table that is not in PATIENT_TABLES — puts a
// patient's address or readings on screen for every portal account. These
// tests are what should fail first when that happens.
//
// The fail-closed case is the important one: a column added to `mothers`
// tomorrow must be withheld without anyone remembering to list it here.
const fs = require('fs');
const vm = require('vm');

const html = fs.readFileSync('admin-web/pages/audit-trail.html', 'utf8');
const script = /<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/i.exec(html)[1];

const start = script.indexOf('const REDACTED_KEYS');
const end = script.indexOf('function buildRecordHTML');
if (start < 0 || end < 0) throw new Error('could not locate the redaction block');

const src = script.slice(start, end);
// Approximates the page's own titleCase closely enough for these assertions.
const ctx = {
  titleCase: s => String(s).replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase()),
  console,
};
vm.createContext(ctx);
vm.runInContext(
  src + '\nglobalThis.__api = { redactionPolicy, redactSnapshot, changedFields, isSensitiveKey };',
  ctx
);
const { redactionPolicy, redactSnapshot, changedFields } = ctx.__api;

let pass = 0, fail = 0;
function check(name, cond, detail) {
  if (cond) { pass++; console.log('  ok   ' + name); }
  else { fail++; console.log('  FAIL ' + name + (detail ? '  -> ' + JSON.stringify(detail) : '')); }
}

// ---- a mother's row, as audit_clinical_change snapshots it -----------------
const motherRow = {
  mother_id: 12, account_id: 40, birthdate: '1996-04-02',
  house_number: '14', street: 'Rizal St', barangay: 'Pinagbarilan',
  city_municipality: 'Baliwag', province: 'Bulacan',
  height: 155, weight: 58, blood_type: 'O+', status: 'active',
  gravida: 2, para: 1, abortus: 0, living_children: 1,
};
const motherLog = {
  table_name: 'mothers',
  old_data: motherRow,
  new_data: Object.assign({}, motherRow, { weight: 61, blood_type: 'O-' }),
};

console.log('\nmothers row');
const mp = redactionPolicy(motherLog);
check('policy names the subject', mp.withheldFor === 'patient record', mp.withheldFor);

const mSnap = redactSnapshot(motherLog.new_data, mp);
for (const k of ['birthdate','house_number','street','barangay','city_municipality',
                 'province','height','weight','blood_type','gravida','para',
                 'abortus','living_children']) {
  check('withheld: ' + k, String(mSnap[k]).startsWith('[withheld'), mSnap[k]);
}
for (const k of ['mother_id','account_id','status']) {
  check('kept: ' + k, mSnap[k] === motherRow[k], mSnap[k]);
}

const mDiff = changedFields(motherLog);
check('both changed fields still listed', mDiff.length === 2, mDiff.map(d => d.key));
check('field names survive', mDiff.every(d => d.key), mDiff);
check('no value leaks into the diff',
  mDiff.every(d => d.was === '(recorded)' && d.now === '(changed)'), mDiff);
check('nothing anywhere prints 61 or O-',
  !JSON.stringify(mDiff).includes('61') && !JSON.stringify(mDiff).includes('O-'), mDiff);

// ---- a prenatal checkup ---------------------------------------------------
console.log('\nprenatal_checkups row');
const ckLog = {
  table_name: 'prenatal_checkups',
  old_data: { encounter_id: 9, pregnancy_id: 3, checkup_weight: 60,
              blood_pressure_systolic: 118, fetal_heart_beat: 140,
              fundal_height_cm: 24, edema: 'none', midwife_notes: 'well' },
  new_data: { encounter_id: 9, pregnancy_id: 3, checkup_weight: 62,
              blood_pressure_systolic: 150, fetal_heart_beat: 138,
              fundal_height_cm: 26, edema: 'moderate', midwife_notes: 'BP up, review' },
};
const cp = redactionPolicy(ckLog);
const cSnap = redactSnapshot(ckLog.new_data, cp);
for (const k of ['checkup_weight','blood_pressure_systolic','fetal_heart_beat',
                 'fundal_height_cm','edema','midwife_notes']) {
  check('withheld: ' + k, String(cSnap[k]).startsWith('[withheld'), cSnap[k]);
}
check('kept: encounter_id', cSnap.encounter_id === 9);
check('kept: pregnancy_id', cSnap.pregnancy_id === 3);
const cDiff = changedFields(ckLog);
check('all 6 clinical changes still counted', cDiff.length === 6, cDiff.length);
check('no reading leaks', !JSON.stringify(cDiff).match(/150|moderate|BP up/), cDiff);

// ---- a column nobody thought about (fail-closed) ---------------------------
console.log('\nfail-closed on an unknown column');
const futureLog = {
  table_name: 'mothers',
  old_data: { mother_id: 12, hiv_status: 'negative' },
  new_data: { mother_id: 12, hiv_status: 'positive' },
};
const fSnap = redactSnapshot(futureLog.new_data, redactionPolicy(futureLog));
check('a column added later does not leak by default',
  String(fSnap.hiv_status).startsWith('[withheld'), fSnap.hiv_status);

// ---- a patient's account row ----------------------------------------------
console.log('\naccounts row — patient');
const patAcct = {
  table_name: 'accounts',
  old_data: { account_id: 40, account_type: 'mother', first_name: 'Rosa',
              last_name: 'Cruz', email_address: 'r@x.com', phone_number: '0917',
              status: 'active', password_hash: 'abc' },
  new_data: { account_id: 40, account_type: 'mother', first_name: 'Rosa',
              last_name: 'Cruz-Santos', email_address: 'r2@x.com',
              phone_number: '0918', status: 'inactive', password_hash: 'def' },
};
const pp = redactionPolicy(patAcct);
check('policy names the subject', pp.withheldFor === 'patient account', pp.withheldFor);
const pSnap = redactSnapshot(patAcct.new_data, pp);
for (const k of ['first_name','last_name','email_address','phone_number']) {
  check('withheld: ' + k, String(pSnap[k]).startsWith('[withheld'), pSnap[k]);
}
check('credentials still hard-redacted', pSnap.password_hash === '[redacted]', pSnap.password_hash);
check('kept: status', pSnap.status === 'inactive');
check('kept: account_type', pSnap.account_type === 'mother');
const pDiff = changedFields(patAcct);
check('surname change is still auditable as an event',
  pDiff.some(d => /Last Name/i.test(d.key)), pDiff.map(d => d.key));
check('the new surname is not printed',
  !JSON.stringify(pDiff).includes('Cruz-Santos'), pDiff);

// ---- a STAFF account row: accountability must survive ----------------------
console.log('\naccounts row — staff');
const staffAcct = {
  table_name: 'accounts',
  old_data: { account_id: 7, account_type: 'midwife', first_name: 'Ana',
              last_name: 'Reyes', status: 'active', password_hash: 'abc' },
  new_data: { account_id: 7, account_type: 'midwife', first_name: 'Ana',
              last_name: 'Reyes', status: 'suspended', password_hash: 'abc' },
};
const sp = redactionPolicy(staffAcct);
check('no withholding banner for staff', sp.withheldFor === null, sp.withheldFor);
const sSnap = redactSnapshot(staffAcct.new_data, sp);
check('staff name still shown', sSnap.first_name === 'Ana' && sSnap.last_name === 'Reyes', sSnap);
check('staff credentials still redacted', sSnap.password_hash === '[redacted]');
const sDiff = changedFields(staffAcct);
check('the suspension is fully legible', sDiff.some(d => d.now === 'suspended'), sDiff);

// ---- inventory rows must be completely unaffected --------------------------
console.log('\ninventory row');
const invLog = {
  table_name: 'inventory_batches',
  old_data: { batch_id: 12, batch_number: 'BCG-2026A', quantity_remaining: 5,
              manufacturer: 'Serum Institute', status: 'active' },
  new_data: { batch_id: 12, batch_number: 'BCG-2026A', quantity_remaining: 4,
              manufacturer: 'Serum Institute', status: 'active' },
};
const ip = redactionPolicy(invLog);
check('no withholding on inventory', ip.withheldFor === null);
const iDiff = changedFields(invLog);
check('quantities still fully legible',
  iDiff.length === 1 && iDiff[0].was === '5' && iDiff[0].now === '4', iDiff);

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
