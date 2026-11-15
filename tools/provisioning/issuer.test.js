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
test('issuer refuses key and manifest paths inside the repository', () => {
  const inside = path.resolve(__dirname, '../../.identity-test-must-not-exist');
  const keyResult = run(['init-keys', '--key-dir', inside]);
  assert.notEqual(keyResult.status, 0);
  assert.equal(fs.existsSync(inside), false);

  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'pharmacy-provision-path-'));
  const keys = path.join(root, 'issuer');
  try {
    assert.equal(run(['init-keys', '--key-dir', keys]).status, 0);
    const outputInside = path.resolve(__dirname, '../../.identity-manifest-must-not-exist.json');
    const result = run(['issue', '--key-dir', keys, '--output', outputInside,
      '--tenant-name-ar', 'مؤسسة اختبار', '--branch-name-ar', 'فرع اختبار']);
    assert.notEqual(result.status, 0);
    assert.equal(fs.existsSync(outputInside), false);
    assert.equal(fs.existsSync(path.join(keys, 'identity-registry.json')), false);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('issuer creates one signed Tenant/Branch identity and refuses re-issuance', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'pharmacy-provision-'));
  const keys = path.join(root, 'issuer');
  const manifest = path.join(root, 'distribution', 'branch.json');
  try {
    assert.equal(run(['init-keys', '--key-dir', keys]).status, 0);
    assert.equal(run(['issue', '--key-dir', keys, '--output', manifest,
      '--tenant-code', 'pharmacy', '--tenant-name-ar', 'pharmacy',
      '--branch-code', 'ph1', '--branch-name-ar', 'ph1']).status, 0);
    const bundle = JSON.parse(fs.readFileSync(manifest, 'utf8'));
    assert.match(bundle.payload.tenant_uuid, /^[0-9a-f-]{36}$/i);
    assert.match(bundle.payload.branch_uuid, /^[0-9a-f-]{36}$/i);
    assert.notEqual(bundle.payload.tenant_uuid, bundle.payload.branch_uuid);
    assert.equal(bundle.payload.tenant_code, 'PHARMACY');
    assert.equal(bundle.payload.tenant_name_ar, 'pharmacy');
    assert.equal(bundle.payload.branch_code, 'PH1');
    assert.equal(bundle.payload.branch_name_ar, 'ph1');
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
