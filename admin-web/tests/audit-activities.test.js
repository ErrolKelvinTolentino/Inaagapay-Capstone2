const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const test = require('node:test');

const html = fs.readFileSync('admin-web/pages/audit-trail.html', 'utf8');
const vocabulary = html.slice(html.indexOf('const ACTION_LABELS'), html.indexOf('/* ── Data'));
const context = { titleCase: s => String(s).replaceAll('_', ' '), selections: {} };
vm.createContext(context);
vm.runInContext(vocabulary + '\nglobalThis.api = { activityOf, actionLabel, actorOf, moduleOf, REQUESTED_ACTIVITIES };', context);
const { activityOf, actionLabel, actorOf, moduleOf, REQUESTED_ACTIVITIES } = context.api;

test('all requested activities have clear labels and are available before the first event', () => {
  assert.equal(REQUESTED_ACTIVITIES.length, 9);
  for (const action of REQUESTED_ACTIVITIES) assert.ok(!actionLabel(action).includes('_'), action);
  vm.runInContext('let allLogs = []; function fillSelect(id, values){ selections[id] = values; }', context);
  const start = html.indexOf('function buildFilterOptions()');
  const end = html.indexOf('function fillSelect(', start);
  vm.runInContext(html.slice(start, end) + '\nbuildFilterOptions();', context);
  assert.deepEqual(Array.from(context.selections['filter-action']).sort(), Array.from(REQUESTED_ACTIVITIES).sort());
});

test('older prenatal AI edit events share the explicit edit filter without changing the stored event', () => {
  const log = { action: 'UPDATE', table_name: 'ai_edit_history', description: 'Midwife edited AI checkup remarks content before submission.' };
  assert.equal(activityOf(log), 'ai_prenatal_insight_edited');
  assert.equal(actionLabel(activityOf(log)), 'Prenatal Checkup AI Insights Edited');
  assert.equal(log.action, 'UPDATE');
  assert.equal(activityOf({ ...log, description: 'AI ultrasound analysis edited' }), 'ai_insight_edited');
  assert.equal(activityOf({ ...log, description: '', new_data: { reference_table: 'prenatal_checkups' } }), 'ai_prenatal_insight_edited');
  assert.equal(activityOf({ ...log, action: 'DELETE' }), 'DELETE');
});

test('generic AI saves do not turn unrelated record updates into AI edits', () => {
  assert.equal(activityOf({ table_name: 'ai_responses', action: 'INSERT', new_data: { status: 'generated' } }), 'ai_insight_generated');
  assert.equal(activityOf({ table_name: 'ai_responses', action: 'UPDATE', new_data: { status: 'edited' } }), 'ai_insight_saved');
  assert.equal(activityOf({ table_name: 'prenatal_checkups', action: 'update_prenatal_checkup' }), 'update_prenatal_checkup');
  assert.equal(activityOf({ table_name: 'ai_responses', action: 'AI_APPROVAL' }), 'AI_APPROVAL');
});

test('profile changes are distinct from password, status, and bookkeeping changes', () => {
  const log = { table_name: 'accounts', action: 'update_account', old_data: { phone_number: '09111111111' }, new_data: { phone_number: '09222222222' } };
  assert.equal(activityOf(log), 'update_profile_information');
  assert.equal(activityOf({ ...log, action: 'change_password' }), 'change_password');
  assert.equal(activityOf({ ...log, action: 'change_account_status' }), 'change_account_status');
  assert.equal(activityOf({ ...log, old_data: {}, new_data: { updated_at: '2026-10-08' } }), 'update_account');
  assert.equal(activityOf({ ...log, old_data: {}, new_data: {} }), 'update_account');
});

test('Td and drives have proper modules even when older rows say Activity', () => {
  assert.equal(moduleOf({ table_name: 'maternal_td_records', module: 'Activity' }), 'Clinical');
  assert.equal(moduleOf({ table_name: 'immunization_schedule', module: 'Activity' }), 'Vaccination Drives');
  assert.equal(moduleOf({ table_name: 'inventory_batches', module: 'Inventory' }), 'Inventory');
});

test('a midwife editing a mother record keeps their staff identity', () => {
  assert.equal(actorOf({ table_name: 'mothers', actor_role: 'midwife', actor_name: 'Test Midwife', account_id: 7 }), 'Test Midwife');
  assert.equal(actorOf({ table_name: 'mothers', actor_role: 'mother', actor_name: 'Private Name', account_id: 40 }), 'Patient #40');
});
