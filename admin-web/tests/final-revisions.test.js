const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const test = require('node:test');

const read = name => fs.readFileSync(`admin-web/pages/${name}`, 'utf8');

test('coverage query includes the classification used by the immunization chart', () => {
  const ctx = { window: {}, console };
  vm.runInNewContext(read('data-cache.js'), ctx);
  const columns = ctx.window.AdminData.columns('child_immunization_coverage').split(/,\s*/);
  assert.ok(columns.includes('coverage_status'));
  assert.ok(columns.includes('birthdate'));
  assert.ok(ctx.window.AdminData.columns('inventory_batches').includes('vial_opened_at'));
});

test('an overdue open vial holds its batch until disposal without changing sealed quantities', async () => {
  const now = Date.parse('2026-10-07T12:00:00+08:00');
  class Clock extends Date {
    constructor(...args) { super(...(args.length ? args : [now])); }
    static now() { return now; }
  }
  const items = [{ item_id: 1, name: 'Td', doses_per_unit: 10, open_vial_shelf_hours: 672 }];
  const batches = [{ item_id: 1, facility_id: 2, status: 'active', expiration_date: '2027-01-01',
    quantity_remaining: 4, doses_remaining_in_open_vial: 3,
    vial_opened_at: new Date(now - 672 * 3600000).toISOString() }];
  const AdminData = { rows: async (_, table) => table === 'inventory_items' ? items : batches };
  const ctx = { window: { AdminData }, AdminData, Date: Clock, console };
  vm.runInNewContext(read('inventory-stock.js'), ctx);
  const stock = ctx.window.InventoryStock;
  stock.setFacilities([{ facility_id: 2, name: 'Tarcan' }]);
  await stock.load({});
  assert.equal(stock.metricsFor(1, '2').available, 0);
  assert.equal(stock.metricsFor(1, '2').availableDoses, 0);
  assert.equal(batches[0].quantity_remaining, 4);
  assert.equal(stock.usableOpenDoses(batches[0], items[0]), 0);
  batches[0].vial_opened_at = new Date(now - 671 * 3600000).toISOString();
  assert.equal(stock.metricsFor(1, '2').availableDoses, 43);
  batches[0].vial_opened_at = null;
  assert.equal(stock.usableOpenDoses(batches[0], items[0]), 0);
  assert.equal(stock.metricsFor(1, '2').availableDoses, 0);
  batches[0].doses_remaining_in_open_vial = 0;
  assert.equal(stock.metricsFor(1, '2').availableDoses, 40, 'Confirmed discard releases the sealed stock');
});

test('all spreadsheet table cells have borders and preserve wrapped prose and numeric values', async () => {
  let captured;
  const addr = ({ r, c }) => String.fromCharCode(65 + c) + (r + 1);
  const XLSX = {
    utils: {
      book_new: () => ({ Sheets: {} }), encode_cell: addr,
      aoa_to_sheet: rows => {
        const ws = {};
        rows.forEach((row, r) => row.forEach((v, c) => { ws[addr({ r, c })] = { v, t: typeof v === 'number' ? 'n' : 's' }; }));
        return ws;
      },
      book_append_sheet: (wb, ws, name) => { wb.Sheets[name] = ws; },
    },
    writeFile: wb => { captured = wb; },
  };
  const document = {
    querySelector: () => null,
    createElement: () => ({ dataset: {}, events: {}, addEventListener(k, fn) { this.events[k] = fn; } }),
    head: { appendChild: script => script.events.load() },
  };
  const ctx = { window: { XLSX }, document, localStorage: { getItem: () => null }, console };
  vm.runInNewContext(read('export-kit.js'), ctx);
  const narrative = 'Issued stock to Tarcan.\nReceipt remains pending.';
  await ctx.window.ExportKit.xlsx('test.xlsx', [{ name: 'Log', blocks: [{
    columns: ['Quantity', 'Account', 'Optional'], rows: [['1,200', narrative, '']],
  }] }]);
  const ws = captured.Sheets.Log;
  assert.equal(ws.A8.v, 1200);
  assert.equal(ws.B8.v, narrative);
  for (const address of ['A7', 'B7', 'C7', 'A8', 'B8', 'C8']) {
    assert.equal(ws[address].s.border.bottom.style, 'thin');
    assert.equal(ws[address].s.alignment.wrapText, true);
  }
  assert.ok(ws['!rows'][7].hpt > 28);
});

test('overdue doses remain visible for disposal and alerts while dispensing excludes them', () => {
  const source=read('inventory.html');
  const now=Date.parse('2026-10-07T12:00:00+08:00');
  const item={item_id:1,doses_per_unit:10,open_vial_shelf_hours:672};
  const batch={batch_id:3,item_id:1,facility_id:2,quantity_remaining:4,doses_remaining_in_open_vial:3,
    vial_opened_at:new Date(now-673*3600000).toISOString()};
  const extract=(startMarker,endMarker)=>source.slice(source.indexOf(startMarker),source.indexOf(endMarker,source.indexOf(startMarker)));
  const ctx={items:[item],batches:[batch],isBatchExpired:()=>false,window:{},Date:{now:()=>now},
    itemDosesPerUnit:()=>10,facilityMatches:()=>true};
  ctx.Date=class extends Date { static now(){return now;} };
  vm.createContext(ctx);
  vm.runInContext(extract('        function storedOpenDoses(','        /** "8 vials'),ctx);
  vm.runInContext(extract('        function planDoseDispense(','        function updateDispensePlan('),ctx);
  assert.equal(ctx.storedOpenDoses(batch),3);
  assert.equal(ctx.batchOpenDoses(batch),0);
  assert.equal(ctx.expiredOpenVials('2').length,1);
  assert.equal(ctx.planDoseDispense(batch,item,2).vialsOpened,1);
  assert.equal(ctx.planDoseDispense(batch,item,2).fromOpen,0);
  const discard=extract('        window.openDiscardVialModal =','        // Backwards-compatible alias');
  assert.ok(discard.includes('const openDoses = storedOpenDoses(batch)'));

  const actions=[];
  ctx.document={getElementById:()=>({value:'',dispatchEvent(){}})};
  ctx.Event=class {};
  ctx.showToast=()=>{};
  ctx.window.openDiscardVialModal=id=>actions.push(['discard',id]);
  ctx.openModal=id=>actions.push(['modal',id]);
  ctx.updateDispensePlan=()=>{};
  vm.runInContext(extract('        window.quickDispense =','        // Form Submit: Add Item'),ctx);
  ctx.window.quickDispense(3);
  assert.deepEqual(actions,[['discard',3]],'A stale direct Use action routes to acknowledged disposal');
  batch.doses_remaining_in_open_vial=0;
  ctx.window.quickDispense(3);
  assert.deepEqual(actions[1],['modal','modal-dispense'],'A confirmed discard permits the batch again');
});

test('the local expiry clock blocks an already-open form without database polling', () => {
  const source=read('inventory.html');
  let now=Date.parse('2026-10-07T12:00:00+08:00');
  const item={item_id:1,doses_per_unit:10,open_vial_shelf_hours:6};
  const batch={batch_id:3,item_id:1,quantity_remaining:4,doses_remaining_in_open_vial:3,
    vial_opened_at:new Date(now-5*3600000).toISOString()};
  let timer;
  const host={style:{}};const button={dataset:{}};const rendered=[];
  const ctx={items:[item],batches:[batch],window:{},console,
    setTimeout:(fn,delay)=>{timer={fn,delay};return 1;},clearTimeout(){},
    selectedDispenseBatch:()=>batch,
    document:{getElementById:id=>id==='dispense-plan'?host:id==='save-dispense-btn'?button:null},
    renderKPIs:()=>rendered.push('kpis'),renderCatalog:()=>rendered.push('catalog'),renderBatches:()=>rendered.push('batches'),
    renderOpenVialsTracker:()=>rendered.push('vials'),renderSubviewCounts:()=>rendered.push('counts'),populateDropdowns:()=>rendered.push('picker'),
    Date:class extends Date {static now(){return now;}}
  };
  vm.createContext(ctx);
  const slice=(start,end)=>source.slice(source.indexOf(start),source.indexOf(end,source.indexOf(start)));
  vm.runInContext(slice('        function storedOpenDoses(','        /** "8 vials'),ctx);
  vm.runInContext(slice('        function openVialAgeHours(','        function describeShelfLimit('),ctx);
  vm.runInContext(slice('        let openVialExpiryTimer =','        function updateDispensePlan('),ctx);
  ctx.scheduleOpenVialExpiryRefresh();
  assert.equal(timer.delay,3600001);
  now+=timer.delay;
  timer.fn();
  assert.equal(button.disabled,true);
  assert.ok(host.innerHTML.includes('Disposal required before use'));
  assert.equal(rendered.length,6);
  assert.equal(batch.quantity_remaining,4);
  assert.equal(batch.doses_remaining_in_open_vial,3,'A clock refresh must not write off any doses');
});

test('turnout uses short unique labels and limits visible ticks without dropping drive values', () => {
  const source = read('reports.html');
  const start = source.indexOf('        function renderDriveTurnoutChart(');
  const end = source.indexOf('        function renderDriveTrendChart(', start);
  let chart;
  const ctx = {
    document: { getElementById: () => ({}) }, chartDriveTurnout: null,
    resetChartCanvas() {}, showEmptyChart() {}, onlyUpcoming: () => false,
    formatDriveDate: value => value, Date,
    Chart: class { constructor(_, opts) { chart = opts; } },
  };
  const held = Array.from({ length: 12 }, (_, i) => ({ schedule_date: '2026-09-15',
    facility_name: `Long health center ${i}`, vaccine_name: 'Pentavalent', invited_count: 10, attended_count: 8 }));
  vm.runInNewContext(source.slice(start, end) + '\nrenderDriveTurnoutChart(held, []);', { ...ctx, held });
  assert.equal(new Set(chart.data.labels).size, 12);
  assert.equal(chart.data.datasets[0].data.length, 12);
  assert.equal(chart.options.scales.x.ticks.maxTicksLimit, 6);
  assert.ok(chart.options.plugins.tooltip.callbacks.title([{ dataIndex: 0 }]).includes('Long health center 0'));
});

test('dashboard PDF exports all four indicator datasets and never exports audit entries', async () => {
  const source = read('dashboard.html');
  const start = source.indexOf('        // The summary is a scoped health/operations report');
  const end = source.indexOf('        // Initialize All Dashboard Operations.', start);
  let handler;
  const calls = [];
  const document = { getElementById: () => ({ textContent: '12', addEventListener: (_, fn) => { handler = fn; } }) };
  const chart = { data: { labels: ['Example'], datasets: [{ data: [3] }] }, canvas: { style: {} } };
  const report = { heading: x => calls.push(x), table: x => calls.push(x), chart() {}, paragraph() {}, save() {} };
  vm.runInNewContext(source.slice(start, end), {
    document, ExportKit: { pdf: async () => report, scopeLabel: () => 'RHU 1', fileName: () => 'summary.pdf' },
    chartRiskInstance: chart, chartBhcInstance: chart, chartMonthlyInstance: chart, chartInventoryInstance: chart,
    showToast() {}, console,
  });
  await handler();
  assert.equal(calls.filter(x => typeof x === 'object').length, 5);
  assert.ok(!JSON.stringify(calls).toLowerCase().includes('audit'));
});
