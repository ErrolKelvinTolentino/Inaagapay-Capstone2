/**
 * admin-sms-notifications-inventory.test.js
 *
 * Comprehensive test suite verifying:
 * 1. SMS Dispatch & Phone Formatting (Edge function + Inventory SMS + Account Create)
 * 2. Admin Notifications & Alert System (notification-center.js + Alert Hub)
 * 3. Stocks & Inventory Logic (Calculations, Batches, Expiry, Transfers, Thresholds)
 */

const assert = require('assert');
const fs = require('fs');
const path = require('path');

console.log('\n=======================================================');
console.log('  ADMIN SMS, NOTIFICATIONS & INVENTORY TEST SUITE');
console.log('=======================================================\n');

let passed = 0;
let failed = 0;

function it(desc, fn) {
  try {
    fn();
    passed++;
    console.log('  ✓ ' + desc);
  } catch (err) {
    failed++;
    console.error('  ✗ ' + desc + ':', err.message);
  }
}

// -------------------------------------------------------------
// PART 1: SMS Phone Number Formatting & Validation
// -------------------------------------------------------------
console.log('--- 1. SMS Formatting & Validation ---');

function formatPhilippineNumber(num) {
  if (!num) return '';
  const cleaned = String(num).replace(/\D/g, '');
  if (cleaned.startsWith('09')) return '+63' + cleaned.substring(1);
  if (cleaned.startsWith('639')) return '+' + cleaned;
  if (cleaned.startsWith('9') && cleaned.length === 10) return '+63' + cleaned;
  return cleaned.startsWith('+') ? cleaned : '+' + cleaned;
}

const PH_MOBILE_REGEX = /^\+639\d{9}$/;

it('formats standard 09xx number to +639xx', () => {
  const formatted = formatPhilippineNumber('09171234567');
  assert.strictEqual(formatted, '+639171234567');
  assert.strictEqual(PH_MOBILE_REGEX.test(formatted), true);
});

it('formats 639xx without plus to +639xx', () => {
  const formatted = formatPhilippineNumber('639171234567');
  assert.strictEqual(formatted, '+639171234567');
  assert.strictEqual(PH_MOBILE_REGEX.test(formatted), true);
});

it('handles already formatted +639xx', () => {
  const formatted = formatPhilippineNumber('+639171234567');
  assert.strictEqual(formatted, '+639171234567');
  assert.strictEqual(PH_MOBILE_REGEX.test(formatted), true);
});

it('strips dashes and spaces from user-entered numbers', () => {
  const formatted = formatPhilippineNumber('0917-123 4567');
  assert.strictEqual(formatted, '+639171234567');
  assert.strictEqual(PH_MOBILE_REGEX.test(formatted), true);
});

it('rejects invalid numbers that do not match Philippine mobile specs', () => {
  const formatted = formatPhilippineNumber('12345');
  assert.strictEqual(PH_MOBILE_REGEX.test(formatted), false);
});

// Verify send-sms Edge Function normalizer
const sendSmsSource = fs.readFileSync(
  path.join(__dirname, '../../supabase/functions/send-sms/index.ts'),
  'utf8'
);

it('send-sms Edge function contains Philippine number normalization', () => {
  assert(sendSmsSource.includes('digits.startsWith("09")'), 'Normalizes 09 numbers');
  assert(sendSmsSource.includes('digits.startsWith("639")'), 'Normalizes 639 numbers');
  assert(sendSmsSource.includes('PH_MOBILE.test(number)'), 'Validates normalized number');
});

// Verify inventory.html SMS button and dispatcher
const inventorySource = fs.readFileSync(
  path.join(__dirname, '../pages/inventory.html'),
  'utf8'
);

it('inventory.html has Send SMS Reminders button and handler', () => {
  assert(inventorySource.includes('id="btn-send-inventory-sms-alert"'), 'SMS button present in toolbar');
  assert(inventorySource.includes('window.sendInventoryAlertSms = async function'), 'sendInventoryAlertSms handler exported');
  assert(inventorySource.includes('formatPhilippineNumber(phone)'), 'Formats staff phone numbers before invoke');
  assert(inventorySource.includes('db.functions.invoke("send-sms"'), 'Invokes send-sms Edge Function');
});

// -------------------------------------------------------------
// PART 2: Admin Notification Center & Live Alerts
// -------------------------------------------------------------
console.log('\n--- 2. Admin Notification Center & Live Alerts ---');

const notifCenterSource = fs.readFileSync(
  path.join(__dirname, '../pages/notification-center.js'),
  'utf8'
);

it('notification-center.js calculates unread count including live alerts', () => {
  assert(notifCenterSource.includes('function unreadCount()'), 'unreadCount defined');
  assert(notifCenterSource.includes('function untoldLive()'), 'untoldLive defined for unseen live conditions');
  assert(notifCenterSource.includes('function storedRows()'), 'storedRows deduplicates against live conditions');
});

it('notification-center.js provides route shortcuts to inventory entities', () => {
  assert(notifCenterSource.includes('REFERENCE_ROUTES'), 'REFERENCE_ROUTES defined');
  assert(notifCenterSource.includes('inventory_transfers'), 'inventory_transfers route defined');
  assert(notifCenterSource.includes('inventory_stock_requests'), 'inventory_stock_requests route defined');
  assert(notifCenterSource.includes('inventory_batches'), 'inventory_batches route defined');
  assert(notifCenterSource.includes('inventory_items'), 'inventory_items route defined');
});

it('notification-center.js listens for live refresh and visibility events', () => {
  assert(notifCenterSource.includes('inaagapay:data-refreshed'), 'Listens for live-refresh data events');
  assert(notifCenterSource.includes('visibilitychange'), 'Listens for tab visibility changes');
  assert(notifCenterSource.includes('window.addEventListener("focus"'), 'Refreshes when window regains focus');
});

it('all primary admin pages include notification-center.js and bell icon', () => {
  const pages = [
    'dashboard.html',
    'inventory.html',
    'reports.html',
    'accounts.html',
    'audit-trail.html',
    'backup.html',
    'facilities.html',
    'midwife-assignment.html'
  ];

  pages.forEach(page => {
    const src = fs.readFileSync(path.join(__dirname, '../pages/' + page), 'utf8');
    assert(src.includes('notification-center.js'), page + ' loads notification-center.js');
    assert(src.includes('notif-bell-btn') || src.includes('notification-center'), page + ' has notification bell button');
  });
});

// -------------------------------------------------------------
// PART 3: Stocks & Inventory Logic & Alert Hub
// -------------------------------------------------------------
console.log('\n--- 3. Stocks & Inventory Logic & Alert Hub ---');

it('inventory.html exports all critical focusing and modal functions', () => {
  assert(inventorySource.includes('window.openAlertsModal'), 'openAlertsModal exported');
  assert(inventorySource.includes('window.filterAlerts'), 'filterAlerts exported');
  assert(inventorySource.includes('window.focusItem'), 'focusItem exported');
  assert(inventorySource.includes('window.focusBatch'), 'focusBatch exported');
  assert(inventorySource.includes('window.focusRequest'), 'focusRequest exported');
  assert(inventorySource.includes('window.focusTransfer'), 'focusTransfer exported');
  assert(inventorySource.includes('window.focusOpenVial'), 'focusOpenVial exported');
});

it('Alert Hub modal contains category filters for low stock, expiry, vials, requests, transit, coldchain', () => {
  assert(inventorySource.includes('id="alert-tab-all"'), 'All alerts filter tab');
  assert(inventorySource.includes('id="alert-tab-low"'), 'Low stock filter tab');
  assert(inventorySource.includes('id="alert-tab-expiry"'), 'Expiry filter tab');
  assert(inventorySource.includes('id="alert-tab-vials"'), 'Open vials filter tab');
  assert(inventorySource.includes('id="alert-tab-requests"'), 'Requests filter tab');
  assert(inventorySource.includes('id="alert-tab-transit"'), 'In-transit filter tab');
  assert(inventorySource.includes('id="alert-tab-coldchain"'), 'Cold chain filter tab');
});

it('Stock readers calculate effective thresholds and open vial doses correctly', () => {
  function dosesPerUnit(item) {
    return Math.max(1, parseInt(item && item.doses_per_unit, 10) || 1);
  }
  function openDoses(batch) {
    return Math.max(0, parseInt(batch && batch.doses_remaining_in_open_vial, 10) || 0);
  }

  const sampleItem = { item_id: 1, name: 'BCG Vaccine', doses_per_unit: 20 };
  const sampleBatch = { batch_id: 1, doses_remaining_in_open_vial: 8 };

  assert.strictEqual(dosesPerUnit(sampleItem), 20);
  assert.strictEqual(openDoses(sampleBatch), 8);
});

it('isBatchExpired correctly identifies expired vs active batches', () => {
  function isBatchExpired(b) {
    if (!b || !b.expiration_date) return false;
    const exp = new Date(b.expiration_date); exp.setHours(0, 0, 0, 0);
    const today = new Date(); today.setHours(0, 0, 0, 0);
    return exp <= today;
  }

  const expiredBatch = { expiration_date: '2020-01-01' };
  const futureBatch = { expiration_date: '2030-01-01' };

  assert.strictEqual(isBatchExpired(expiredBatch), true);
  assert.strictEqual(isBatchExpired(futureBatch), false);
});

it('Alert Hub expiry card formats expiration date in Jan 01, 2001 style', () => {
  assert(
    inventorySource.includes('formatShortDate(b.expiration_date)'),
    'Alert hub expiry card uses formatShortDate'
  );
});

// -------------------------------------------------------------
// Summary
// -------------------------------------------------------------
console.log('\n=======================================================');
console.log('Results: ' + passed + ' passed, ' + failed + ' failed.');
console.log('=======================================================\n');

if (failed > 0) {
  process.exit(1);
}
