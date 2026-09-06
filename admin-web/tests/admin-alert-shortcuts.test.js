/**
 * admin-alert-shortcuts.test.js
 *
 * Verification suite for Admin Alert Shortcuts and Navigation.
 */

const assert = require("assert");
const fs = require("fs");
const path = require("path");

const notifCenterSource = fs.readFileSync(
  path.join(__dirname, "../pages/notification-center.js"),
  "utf8"
);
const inventorySource = fs.readFileSync(
  path.join(__dirname, "../pages/inventory.html"),
  "utf8"
);
const dashboardSource = fs.readFileSync(
  path.join(__dirname, "../pages/dashboard.html"),
  "utf8"
);
const reportsSource = fs.readFileSync(
  path.join(__dirname, "../pages/reports.html"),
  "utf8"
);

console.log("\n--- Admin Alert Shortcuts & Navigation Test Suite ---");

// 1. Notification Center Routing
{
  const routeForMatch = notifCenterSource.match(/function routeFor\(row\)\s*\{([\s\S]*?)\n  \}/);
  const liveRouteMatch = notifCenterSource.match(/function liveRoute\(alert\)\s*\{([\s\S]*?)\n  \}/);
  const refRoutesMatch = notifCenterSource.match(/const REFERENCE_ROUTES = (\{[\s\S]*?\n  \});/);
  const typeFallbackMatch = notifCenterSource.match(/const TYPE_FALLBACK = (\{[\s\S]*?\n  \});/);

  assert(routeForMatch, "routeFor function found in notification-center.js");
  assert(liveRouteMatch, "liveRoute function found in notification-center.js");
  assert(refRoutesMatch, "REFERENCE_ROUTES found in notification-center.js");
  assert(typeFallbackMatch, "TYPE_FALLBACK found in notification-center.js");

  const evalContext = new Function(
    `${refRoutesMatch[0]}
     ${typeFallbackMatch[0]}
     function routeFor(row) { ${routeForMatch[1]} }
     function liveRoute(alert) { ${liveRouteMatch[1]} }
     return { REFERENCE_ROUTES, TYPE_FALLBACK, routeFor, liveRoute };`
  )();

  const { routeFor, liveRoute } = evalContext;

  // Test explicit reference_type
  const transferRoute = routeFor({ reference_type: "inventory_transfers", reference_id: 123 });
  assert.strictEqual(transferRoute.href, "inventory.html?tab=requests&subview=transfers&transfer_id=123");
  assert.strictEqual(transferRoute.actionHint, "Open transfer");
  console.log("  ok   routeFor(inventory_transfers) links directly to transfer_id with actionHint");

  const reqRoute = routeFor({ reference_type: "inventory_stock_requests", reference_id: 456 });
  assert.strictEqual(reqRoute.href, "inventory.html?tab=requests&subview=requests&request_id=456");
  assert.strictEqual(reqRoute.actionHint, "Review request");
  console.log("  ok   routeFor(inventory_stock_requests) links directly to request_id with actionHint");

  const batchRoute = routeFor({ reference_type: "inventory_batches", reference_id: 789 });
  assert.strictEqual(batchRoute.href, "inventory.html?tab=catalog&subview=batches&batch_id=789");
  assert.strictEqual(batchRoute.actionHint, "View batch");
  console.log("  ok   routeFor(inventory_batches) links directly to batch_id with actionHint");

  const itemRoute = routeFor({ reference_type: "inventory_items", reference_id: 10 });
  assert.strictEqual(itemRoute.href, "inventory.html?tab=catalog&subview=summary&item_id=10");
  assert.strictEqual(itemRoute.actionHint, "View item");
  console.log("  ok   routeFor(inventory_items) links directly to item_id with actionHint");

  // Test legacy fallback matching
  const legacyTransfer = routeFor({
    reference_type: null,
    title: "Transfer #88 Dispatched",
    message: "Transfer #88 has been issued to Sto. Nino BHC"
  });
  assert.strictEqual(legacyTransfer.href, "inventory.html?tab=requests&subview=transfers&transfer_id=88");
  console.log("  ok   routeFor(legacy transfer) parses #id and routes to transfer_id");

  const legacyReq = routeFor({
    reference_type: null,
    title: "Requisition Received",
    message: "Stock request #52 is awaiting approval"
  });
  assert.strictEqual(legacyReq.href, "inventory.html?tab=requests&subview=requests&request_id=52");
  console.log("  ok   routeFor(legacy request) parses #id and routes to request_id");

  const legacyBatch = routeFor({
    reference_type: null,
    title: "Batch Expiring",
    message: "Stock in batch BATCH-2026-X expires soon"
  });
  assert.strictEqual(legacyBatch.href, "inventory.html?tab=catalog&subview=batches&batch_id=BATCH-2026-X");
  console.log("  ok   routeFor(legacy batch) parses batch number and routes to batch_id");

  // Test clinical reminders
  const checkup = routeFor({ type: "checkup_reminder", title: "Upcoming checkup", message: "Checkup due" });
  assert.strictEqual(checkup.href, "reports.html");
  console.log("  ok   routeFor(checkup_reminder) routes to reports.html");

  const vaccine = routeFor({ type: "vaccine_reminder", title: "Vaccine due", message: "Vaccine reminder" });
  assert.strictEqual(vaccine.href, "reports.html");
  console.log("  ok   routeFor(vaccine_reminder) routes to reports.html");

  // Test liveRoute
  const liveItem = liveRoute({ item_id: 15, batch_id: null, facility_id: 2, severity: "low" });
  assert.strictEqual(liveItem.href, "inventory.html?tab=catalog&subview=summary&item_id=15&facility_id=2");
  assert.strictEqual(liveItem.actionHint, "View item");
  console.log("  ok   liveRoute(item) points to summary with item_id & facility_id");

  const liveBatch = liveRoute({ item_id: 15, batch_id: 99, facility_id: null, severity: "urgent" });
  assert.strictEqual(liveBatch.href, "inventory.html?tab=catalog&subview=batches&batch_id=99");
  assert.strictEqual(liveBatch.actionHint, "View batch");
  console.log("  ok   liveRoute(batch) points to batches with batch_id");

  const liveOpenVial = liveRoute({ item_id: 15, batch_id: 99, alert_kind: "open_vial", facility_id: 3 });
  assert.strictEqual(liveOpenVial.href, "inventory.html?tab=catalog&subview=batches&batch_id=99&open_vial=1&facility_id=3");
  assert.strictEqual(liveOpenVial.actionHint, "Discard vial");
  console.log("  ok   liveRoute(open_vial) appends &open_vial=1 and Discard vial hint");
}

// 2. In-Page Navigation in notification-center.js
{
  assert(notifCenterSource.includes("function executeNavigation(targetHref)"), "executeNavigation function defined");
  assert(notifCenterSource.includes("window.applyHubQueryParam()"), "Calls applyHubQueryParam for in-page switching on inventory.html");
  assert(notifCenterSource.includes("window.history.pushState"), "Uses history.pushState to update URL on in-page navigation");
  console.log("  ok   notification-center.js supports smooth in-page navigation on inventory.html without reload");
}

// 3. Table Rows Data Attributes in inventory.html
{
  assert(inventorySource.includes('data-item-id="${item.item_id}"'), "Catalog rows include data-item-id");
  assert(inventorySource.includes('data-batch-id="${b.batch_id}"'), "Batches rows include data-batch-id");
  assert(inventorySource.includes('data-request-id="${request.request_id}"'), "Stock requests rows include data-request-id");
  assert(inventorySource.includes('data-transfer-id="${transfer.transfer_id}"'), "Transfers rows include data-transfer-id");
  console.log("  ok   All inventory table rows emit data-* attributes for exact target element selection");
}

// 4. Focusing Helpers in inventory.html
{
  assert(inventorySource.includes("window.focusTransfer = function"), "window.focusTransfer exported");
  assert(inventorySource.includes("window.focusRequest = function"), "window.focusRequest exported");
  assert(inventorySource.includes("window.focusItem = function"), "window.focusItem exported");
  assert(inventorySource.includes("window.focusBatch = function"), "window.focusBatch exported");
  assert(inventorySource.includes("window.focusOpenVial = function"), "window.focusOpenVial exported");
  assert(inventorySource.includes("row-highlight-pulse"), "row-highlight-pulse animation used");
  console.log("  ok   All focusing helpers (transfer, request, item, batch, open vial) defined with highlight pulse");
}

// 5. Query Param and Hash Support in inventory.html
{
  assert(inventorySource.includes("window.applyHubQueryParam = applyHubQueryParam"), "window.applyHubQueryParam exported");
  assert(inventorySource.includes('window.addEventListener("popstate", applyHubQueryParam)'), "popstate event listener attached");
  assert(inventorySource.includes('rawHash.startsWith("tab-")'), "Hash anchors (#tab-requests, #tab-transactions) handled");
  assert(inventorySource.includes('params.get("transfer_id")'), "transfer_id parameter handled");
  assert(inventorySource.includes('params.get("request_id")'), "request_id parameter handled");
  assert(inventorySource.includes('params.get("batch_id")'), "batch_id parameter handled");
  assert(inventorySource.includes('params.get("item_id")'), "item_id parameter handled");
  assert(inventorySource.includes('params.get("open_vial")'), "open_vial parameter handled");
  assert(inventorySource.includes('params.get("modal")'), "modal=alerts parameter handled");
  console.log("  ok   applyHubQueryParam supports all query params and legacy hash anchors");
}

// 6. Alert Hub Modal Cards in inventory.html
{
  assert(inventorySource.includes('View Item'), "Low stock cards have View Item button");
  assert(inventorySource.includes('View Batch'), "Expiry and coldchain cards have View Batch button");
  assert(inventorySource.includes('View Request'), "Request cards have View Request button");
  assert(inventorySource.includes('a.shortcut ?'), "Alert cards have clickable titles linking to a.shortcut");
  console.log("  ok   Alert Hub modal cards have direct View buttons and clickable shortcut titles");
}

// 7. Dashboard and Reports links
{
  assert(dashboardSource.includes('href="inventory.html?tab=requests&subview=requests"'), "dashboard.html links to requests tab via query param");
  assert(!dashboardSource.includes('href="inventory.html#tab-requests"'), "dashboard.html legacy hash link removed");
  assert(reportsSource.includes('href="inventory.html?tab=transactions&subview=ledger"'), "reports.html links to ledger via query param");
  assert(!reportsSource.includes('href="inventory.html#tab-transactions"'), "reports.html legacy hash link removed");
  console.log("  ok   dashboard.html and reports.html use direct query param links");
}

console.log("\nAll Admin Alert Shortcut tests passed successfully!\n");
