const assert = require('node:assert/strict');
const { createHash } = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const test = require('node:test');

// A small ZIP with the two Android entries required by the preparation script.
function apkFixture() {
  const entries = ['AndroidManifest.xml', 'classes.dex'];
  const locals = [], directory = [];
  let position = 0;
  for (const name of entries) {
    const filename = Buffer.from(name), contents = Buffer.alloc(1024, 65);
    let crc = 0xffffffff;
    for (const byte of contents) {
      crc ^= byte;
      for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
    }
    crc = (crc ^ 0xffffffff) >>> 0;
    const local = Buffer.alloc(30), central = Buffer.alloc(46);
    local.writeUInt32LE(0x04034b50); local.writeUInt16LE(20, 4);
    local.writeUInt32LE(crc, 14);
    local.writeUInt32LE(contents.length, 18); local.writeUInt32LE(contents.length, 22);
    local.writeUInt16LE(filename.length, 26);
    central.writeUInt32LE(0x02014b50); central.writeUInt16LE(20, 4); central.writeUInt16LE(20, 6);
    central.writeUInt32LE(crc, 16);
    central.writeUInt32LE(contents.length, 20); central.writeUInt32LE(contents.length, 24);
    central.writeUInt16LE(filename.length, 28); central.writeUInt32LE(position, 42);
    locals.push(local, filename, contents); directory.push(central, filename);
    position += local.length + filename.length + contents.length;
  }
  const central = Buffer.concat(directory), end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50); end.writeUInt16LE(entries.length, 8); end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(central.length, 12); end.writeUInt32LE(position, 16);
  return Buffer.concat([...locals, central, end]);
}

function setup(t) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'inaagapay-download-test-'));
  assert.equal(path.dirname(path.resolve(directory)), path.resolve(os.tmpdir()));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  fs.mkdirSync(path.join(directory, 'downloads'));
  fs.copyFileSync(path.join(__dirname, '../prepare-download.mjs'), path.join(directory, 'prepare-download.mjs'));
  const apk = apkFixture(), sha256 = createHash('sha256').update(apk).digest('hex');
  fs.writeFileSync(path.join(directory, 'fixture.apk'), apk);
  fs.writeFileSync(path.join(directory, 'mock-fetch.mjs'), `
    import { readFile, appendFile } from 'node:fs/promises';
    globalThis.fetch = async url => {
      await appendFile(new URL('./requested-url.txt', import.meta.url), String(url));
      return new Response(await readFile(new URL('./fixture.apk', import.meta.url)), {
        headers: { 'content-type': 'application/vnd.android.package-archive' }
      });
    };
  `);
  const env = { ...process.env };
  delete env.APK_ARTIFACT_URL; delete env.APK_ARTIFACT_SHA256;
  return {
    directory, apk, sha256,
    manifest(value = { url: 'https://example.com/release.apk', sha256 }) {
      fs.writeFileSync(path.join(directory, 'downloads/release.json'), JSON.stringify(value));
    },
    run(overrides = {}) {
      return spawnSync(process.execPath, ['--import', './mock-fetch.mjs', './prepare-download.mjs'], {
        cwd: directory, env: { ...env, ...overrides }, encoding: 'utf8', timeout: 15000,
      });
    },
  };
}

test('a clean Git deployment fetches and validates the pinned release', t => {
  const fixture = setup(t); fixture.manifest();
  const result = fixture.run();
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(fs.readFileSync(path.join(fixture.directory, 'downloads/inaagapay.apk')), fixture.apk);
  assert.match(result.stdout, /APK prepared and verified/);
});

test('a valid local APK remains usable without release configuration or network', t => {
  const fixture = setup(t);
  fs.writeFileSync(path.join(fixture.directory, 'downloads/inaagapay.apk'), fixture.apk);
  const result = fixture.run();
  assert.equal(result.status, 0, result.stderr);
  assert.equal(fs.existsSync(path.join(fixture.directory, 'requested-url.txt')), false);
});

test('explicit hosting environment overrides the pinned release', t => {
  const fixture = setup(t);
  fixture.manifest({ url: 'https://example.com/old.apk', sha256: '0'.repeat(64) });
  const result = fixture.run({ APK_ARTIFACT_URL: 'https://example.com/override.apk', APK_ARTIFACT_SHA256: fixture.sha256 });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(fs.readFileSync(path.join(fixture.directory, 'requested-url.txt'), 'utf8'), 'https://example.com/override.apk');
});

test('hash mismatch preserves an existing APK and removes the partial download', t => {
  const fixture = setup(t);
  fs.writeFileSync(path.join(fixture.directory, 'downloads/inaagapay.apk'), fixture.apk);
  const result = fixture.run({ APK_ARTIFACT_URL: 'https://example.com/bad.apk', APK_ARTIFACT_SHA256: '0'.repeat(64) });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /SHA-256 does not match/);
  assert.deepEqual(fs.readFileSync(path.join(fixture.directory, 'downloads/inaagapay.apk')), fixture.apk);
  assert.equal(fs.readdirSync(path.join(fixture.directory, 'downloads')).some(name => name.endsWith('.partial')), false);
});

test('a pinned non-APK response cannot produce a successful build', t => {
  const fixture = setup(t), html = Buffer.from('<html>download unavailable</html>');
  fs.writeFileSync(path.join(fixture.directory, 'fixture.apk'), html);
  fixture.manifest({ url: 'https://example.com/error.apk', sha256: createHash('sha256').update(html).digest('hex') });
  const result = fixture.run();
  assert.equal(result.status, 1);
  assert.equal(fs.existsSync(path.join(fixture.directory, 'downloads/inaagapay.apk')), false);
});

test('missing release configuration reports an actionable error', t => {
  const fixture = setup(t), result = fixture.run();
  assert.equal(result.status, 1);
  assert.match(result.stderr, /APK is missing.*release.json/);
});
