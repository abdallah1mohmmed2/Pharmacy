'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const crypto = require('node:crypto');

const script = path.resolve(__dirname, 'issuer.js');
function run(args) {
  return spawnSync(process.execPath, [script, ...args], { encoding: 'utf8' });
}
test('issuer creates one signed Tenant/Branch identity and refuses re-issuance', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'pharmacy-provision-'));
  const keys = path.join(root, 'issuer');
  const manifest = path.join(root, 'distribution', 'branch.json');
  try {
    assert.equal(run(['init-keys', '--key-dir', keys]).status, 0);
    assert.equal(run(['issue', '--key-dir', keys, '--output', manifest,
      '--tenant-name-ar', 'المؤسسة التجريبية', '--branch-name-ar', 'الصيدلية الرئيسية']).status, 0);
    const bundle = JSON.parse(fs.readFileSync(manifest, 'utf8'));
    assert.match(bundle.payload.tenant_uuid, /^[0-9a-f-]{36}$/i);
    assert.match(bundle.payload.branch_uuid, /^[0-9a-f-]{36}$/i);
    assert.notEqual(bundle.payload.tenant_uuid, bundle.payload.branch_uuid);
    const pub = crypto.createPublicKey(fs.readFileSync(path.join(keys, 'provisioning-ed25519-public.pem')));
    const canonical = JSON.stringify({
      schema_version: bundle.payload.schema_version,
      tenant_uuid: bundle.payload.tenant_uuid,
      tenant_code: bundle.payload.tenant_code,
      tenant_name_ar: bundle.payload.tenant_name_ar,
      branch_uuid: bundle.payload.branch_uuid,
      branch_code: bundle.payload.branch_code,
      branch_name_ar: bundle.payload.branch_name_ar,
      issued_at: bundle.payload.issued_at,
      issuance_id: bundle.payload.issuance_id,
    });
    assert.equal(crypto.verify(null, Buffer.from(canonical), pub, Buffer.from(bundle.signature, 'base64')), true);
    assert.equal(run(['verify', '--manifest', manifest, '--public-key',
      path.join(keys, 'provisioning-ed25519-public.pem')]).status, 0);
    assert.notEqual(run(['issue', '--key-dir', keys, '--output', path.join(root, 'second.json'),
      '--tenant-name-ar', 'مؤسسة ثانية', '--branch-name-ar', 'فرع ثان']).status, 0);
    bundle.payload.branch_uuid = crypto.randomUUID();
    fs.writeFileSync(manifest, JSON.stringify(bundle));
    assert.notEqual(run(['verify', '--manifest', manifest, '--public-key',
      path.join(keys, 'provisioning-ed25519-public.pem')]).status, 0);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});
