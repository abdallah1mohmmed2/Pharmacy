#!/usr/bin/env node
'use strict';

// Offline, one-time issuer for a pharmacy's shared Tenant/Branch identity.
// Keep the private key and registry outside the repository and distribute
// only the signed manifest to devices. This tool never contacts Firebase.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

function args(argv) {
  const out = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const item = argv[i];
    if (!item.startsWith('--')) out._.push(item);
    else {
      const key = item.slice(2);
      if (!argv[i + 1] || argv[i + 1].startsWith('--')) throw new Error('Missing value for --' + key);
      out[key] = argv[++i];
    }
  }
  return out;
}
function required(options, key) {
  if (!options[key] || !options[key].trim()) throw new Error('Required option: --' + key);
  return options[key].trim();
}
function assertOutsideRepository(target, label) {
  const repositoryRoot = path.resolve(__dirname, '../..');
  const relative = path.relative(repositoryRoot, path.resolve(target));
  if (relative === '' || (!relative.startsWith('..' + path.sep) && relative !== '..' && !path.isAbsolute(relative))) {
    throw new Error(label + ' must be stored outside the Git repository');
  }
}
function atomicWrite(file, data, mode = 0o600) {
  fs.mkdirSync(path.dirname(file), { recursive: true, mode: 0o700 });
  const temp = file + '.tmp-' + process.pid;
  fs.writeFileSync(temp, data, { flag: 'wx', mode });
  fs.renameSync(temp, file);
  try { fs.chmodSync(file, mode); } catch (_) {}
}
function canonicalPayload(payload) {
  // Fixed field order is part of the v1 signing contract.
  return JSON.stringify({
    schema_version: payload.schema_version,
    tenant_uuid: payload.tenant_uuid,
    tenant_code: payload.tenant_code,
    tenant_name_ar: payload.tenant_name_ar,
    branch_uuid: payload.branch_uuid,
    branch_code: payload.branch_code,
    branch_name_ar: payload.branch_name_ar,
    issued_at: payload.issued_at,
    issuance_id: payload.issuance_id,
  });
}
function initKeys(keyDir) {
  fs.mkdirSync(keyDir, { recursive: true, mode: 0o700 });
  const privatePath = path.join(keyDir, 'provisioning-ed25519-private.pem');
  const publicPath = path.join(keyDir, 'provisioning-ed25519-public.pem');
  if (fs.existsSync(privatePath) || fs.existsSync(publicPath)) {
    throw new Error('Key files already exist; refusing to overwrite or rotate them implicitly');
  }
  const pair = crypto.generateKeyPairSync('ed25519');
  atomicWrite(privatePath, pair.privateKey.export({ type: 'pkcs8', format: 'pem' }), 0o600);
  atomicWrite(publicPath, pair.publicKey.export({ type: 'spki', format: 'pem' }), 0o644);
  console.log('Created an Ed25519 keypair. Keep the private key offline; embed/distribute only the public key.');
}
function issue(options) {
  const keyDir = path.resolve(required(options, 'key-dir'));
  const output = path.resolve(required(options, 'output'));
  const registryPath = path.join(keyDir, 'identity-registry.json');
  const privatePath = path.join(keyDir, 'provisioning-ed25519-private.pem');
  const publicPath = path.join(keyDir, 'provisioning-ed25519-public.pem');
  if (!fs.existsSync(privatePath) || !fs.existsSync(publicPath)) throw new Error('Issuer keypair is missing; run init-keys first');
  if (fs.existsSync(registryPath)) throw new Error('An identity has already been issued from this registry; refusing to generate a second identity');
  if (fs.existsSync(output)) throw new Error('Output file already exists; refusing to overwrite it');

  const payload = {
    schema_version: 1,
    tenant_uuid: crypto.randomUUID(),
    tenant_code: 'MAIN',
    tenant_name_ar: required(options, 'tenant-name-ar'),
    branch_uuid: crypto.randomUUID(),
    branch_code: 'MAIN',
    branch_name_ar: required(options, 'branch-name-ar'),
    issued_at: new Date().toISOString(),
    issuance_id: crypto.randomUUID(),
  };
  const privateKey = crypto.createPrivateKey(fs.readFileSync(privatePath));
  const publicKey = crypto.createPublicKey(fs.readFileSync(publicPath));
  const signature = crypto.sign(null, Buffer.from(canonicalPayload(payload), 'utf8'), privateKey);
  if (!crypto.verify(null, Buffer.from(canonicalPayload(payload), 'utf8'), publicKey, signature)) {
    throw new Error('Internal signature self-check failed');
  }
  const bundle = {
    payload,
    signature: signature.toString('base64'),
    signature_algorithm: 'Ed25519',
  };
  // Persist the registry first. If writing the output fails, the same IDs are
  // recoverable from the registry; a new issuance remains blocked.
  atomicWrite(registryPath, JSON.stringify({ ...payload, manifest_path: output }, null, 2) + '\n', 0o600);
  atomicWrite(output, JSON.stringify(bundle, null, 2) + '\n', 0o644);
  console.log(JSON.stringify({
    manifest: output,
    tenant_uuid: payload.tenant_uuid,
    branch_uuid: payload.branch_uuid,
    issuance_id: payload.issuance_id,
    note: 'Copy this exact signed manifest to every device in this branch. Never run issue again for the same organization/branch.'
  }, null, 2));
}
function verify(options) {
  const manifestPath = path.resolve(required(options, 'manifest'));
  const publicPath = path.resolve(required(options, 'public-key'));
  const bundle = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  if (!bundle.payload || bundle.signature_algorithm !== 'Ed25519' || !bundle.signature) throw new Error('Unsupported or malformed provisioning manifest');
  const payload = bundle.payload;
  for (const field of ['tenant_uuid', 'branch_uuid', 'issuance_id']) {
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(String(payload[field] || ''))) {
      throw new Error('Invalid UUID field: ' + field);
    }
  }
  if (payload.schema_version !== 1) throw new Error('Unsupported schema_version');
  const key = crypto.createPublicKey(fs.readFileSync(publicPath));
  const ok = crypto.verify(null, Buffer.from(canonicalPayload(payload), 'utf8'), key, Buffer.from(bundle.signature, 'base64'));
  if (!ok) throw new Error('Provisioning manifest signature is invalid');
  console.log('Valid Ed25519 provisioning manifest: ' + payload.tenant_uuid + ' / ' + payload.branch_uuid);
}
function main() {
  const options = args(process.argv.slice(2));
  const command = options._[0];
  if (command === 'init-keys') initKeys(path.resolve(required(options, 'key-dir')));
  else if (command === 'issue') issue(options);
  else if (command === 'verify') verify(options);
  else throw new Error([
    'Usage:',
    '  node tools/provisioning/issuer.js init-keys --key-dir /secure/offline/issuer',
    '  node tools/provisioning/issuer.js issue --key-dir /secure/offline/issuer --output /secure/distribution/pharmacy.json --tenant-name-ar "..." --branch-name-ar "..."',
    '  node tools/provisioning/issuer.js verify --manifest /path/pharmacy.json --public-key /path/provisioning-ed25519-public.pem',
  ].join('\n'));
}
try { main(); } catch (error) { console.error(error.message); process.exitCode = 1; }
