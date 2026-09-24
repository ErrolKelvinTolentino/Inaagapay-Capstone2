// Portal exports — regression tests.
//
//   node admin-web/tests/export-kit.test.js
//
// Runs the real export-kit.js in a sandbox and checks the parts that do not
// need a browser: text that jsPDF's built-in fonts cannot draw is replaced
// rather than printed as a stray symbol, file names are safe, and the pages
// that offer PDF / Excel actually load the kit and wire their buttons.
const fs = require('fs');
const vm = require('vm');

const kit = fs.readFileSync('admin-web/pages/export-kit.js', 'utf8');
const ctx = { window: {}, document: {}, localStorage: { getItem: () => null }, console };
vm.createContext(ctx);
vm.runInContext(kit, ctx);
const ExportKit = ctx.window.ExportKit;

let pass = 0, fail = 0;
function check(name, cond, detail) {
  if (cond) { pass++; console.log('  ok   ' + name); }
  else { fail++; console.log('  FAIL ' + name + (detail !== undefined ? '  -> ' + JSON.stringify(detail) : '')); }
}

console.log('\npdfSafe');
check('keeps Latin-1 names', ExportKit.pdfSafe('Peñaflor, Añonuevo') === 'Peñaflor, Añonuevo');
check('en and em dashes become hyphens', ExportKit.pdfSafe('Sep 1 – Sep 30 — RHU') === 'Sep 1 - Sep 30 - RHU');
check('arrows become ->', ExportKit.pdfSafe('BHC → RHU') === 'BHC -> RHU');
check('curly quotes become straight', ExportKit.pdfSafe('“Td2” ‘ok’') === '"Td2" \'ok\'');
check('null prints as nothing', ExportKit.pdfSafe(null) === '');
check('anything else outside Latin-1 is dropped, not garbled', ExportKit.pdfSafe('done ✓') === 'done ');

console.log('\nfileName');
const name = ExportKit.fileName('Inventory Report: Pinagbarilan BHC!', 'pdf');
check('slugged and dated', /^inventory-report-pinagbarilan-bhc_\d{4}-\d{2}-\d{2}\.pdf$/.test(name), name);

console.log('\npages load the kit and wire their buttons');
const pages = {
  'reports.html': ['export-pdf-btn', 'export-xlsx-btn', 'drive-export-pdf-btn', 'drive-export-xlsx-btn'],
  'inventory.html': ['downloadInventoryReportPdf', 'downloadInventoryReportXlsx'],
  'audit-trail.html': ['export-xlsx-btn'],
};
for (const [page, hooks] of Object.entries(pages)) {
  const html = fs.readFileSync('admin-web/pages/' + page, 'utf8');
  check(`${page} includes export-kit.js`, html.includes('<script src="export-kit.js"></script>'));
  hooks.forEach((hook) => check(`${page} wires ${hook}`, (html.match(new RegExp(hook, 'g')) || []).length >= 2));
}

const reports = fs.readFileSync('admin-web/pages/reports.html', 'utf8');
check('Reports PDF button no longer just calls window.print()',
  !/export-pdf-btn"\)\?\.addEventListener\("click", \(\) => \{\s*window\.print\(\);/.test(reports));
const inventory = fs.readFileSync('admin-web/pages/inventory.html', 'utf8');
check('batches export is a real .xlsx, not HTML renamed .xls',
  !inventory.includes('application/vnd.ms-excel') && inventory.includes('inventory_batches_${localDateKey()}.xlsx'));

console.log(`\nResults: ${pass} passed, ${fail} failed.`);
process.exit(fail ? 1 : 0);
