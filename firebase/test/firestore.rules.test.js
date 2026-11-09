const fs = require('node:fs');
const path = require('node:path');
const { after, before, beforeEach, test } = require('node:test');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { doc, setDoc, getDoc, serverTimestamp } = require('firebase/firestore');

const projectId = 'pharmacy-dafb6';
const deviceId = '11111111-1111-4111-8111-111111111111';
let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId,
    firestore: { rules: fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8') },
  });
});
beforeEach(async () => env.clearFirestore());
after(async () => env.cleanup());

function branchUser(branchId, branchRole = 'manager') {
  return env.authenticatedContext('user-' + branchId, {
    branch_id: branchId, branch_role: branchRole,
  }).firestore();
}

function batch(id = 'a'.repeat(64), branchId = 'branch-A', overrides = {}) {
  return {
    branch_id: branchId,
    source_device_id: deviceId,
    batch_uuid: id,
    payload_hash: 'b'.repeat(64),
    schema_version: 1,
    events: [{ event_uuid: 'event-1', table: 'drug_categories', uuid: 'row-1' }],
    created_at: serverTimestamp(),
    ...overrides,
  };
}

function batchRef(db, branchId = 'branch-A', id = 'a'.repeat(64)) {
  return doc(db, 'pharmacy_sync_batches/' + branchId + '/batches/' + id);
}

test('authenticated branch user creates an immutable batch with approved envelope', async () => {
  const db = branchUser('branch-A');
  await assertSucceeds(setDoc(batchRef(db), batch()));
  await assertFails(setDoc(batchRef(db), batch()));
  await assertSucceeds(getDoc(batchRef(db)));
});

test('server timestamp transform is accepted, but client-provided time is denied', async () => {
  const db = branchUser('branch-A');
  const accepted = 'c'.repeat(64);
  await assertSucceeds(setDoc(batchRef(db, 'branch-A', accepted),
    batch(accepted, 'branch-A', { created_at: serverTimestamp() })));
  const forged = 'd'.repeat(64);
  await assertFails(setDoc(batchRef(db, 'branch-A', forged),
    batch(forged, 'branch-A', { created_at: new Date('2020-01-01T00:00:00Z') })));
});

test('cross-branch writes and reads are denied', async () => {
  const dbA = branchUser('branch-A');
  const dbB = branchUser('branch-B');
  const id = 'e'.repeat(64);
  await assertFails(setDoc(batchRef(dbA, 'branch-B', id), batch(id, 'branch-B')));
  await assertSucceeds(setDoc(batchRef(dbA), batch()));
  await assertFails(getDoc(batchRef(dbB)));
});

test('unknown fields and unexpected schema versions are rejected', async () => {
  const db = branchUser('branch-A');
  await assertFails(setDoc(batchRef(db), batch(undefined, undefined,
    { password_hash: 'SECRET_SENTINEL' })));
  await assertFails(setDoc(batchRef(db), batch(undefined, undefined,
    { schema_version: 2 })));
  await assertFails(setDoc(batchRef(db), batch(undefined, undefined,
    { payload_hash: 'not-a-hash' })));
  await assertFails(setDoc(batchRef(db), batch(undefined, undefined,
    { payload_hash: null })));
});

test('required fields and event-count bounds are enforced', async () => {
  const db = branchUser('branch-A');
  const missingHash = batch();
  delete missingHash.payload_hash;
  await assertFails(setDoc(batchRef(db), missingHash));
  const missingSchema = batch();
  delete missingSchema.schema_version;
  await assertFails(setDoc(batchRef(db), missingSchema));
  const missingTimestamp = batch();
  delete missingTimestamp.created_at;
  await assertFails(setDoc(batchRef(db), missingTimestamp));
  await assertFails(setDoc(batchRef(db), batch(undefined, undefined, { events: [] })));
  await assertFails(setDoc(batchRef(db), batch(undefined, undefined,
    { events: Array.from({ length: 101 }, (_, i) => ({ uuid: String(i) })) })));
  await assertFails(setDoc(batchRef(db), batch(undefined, undefined, { events: 'wrong-type' })));
});

test('batch path and source device must use approved identifiers', async () => {
  const db = branchUser('branch-A');
  await assertFails(setDoc(batchRef(db, 'branch-A', 'not-a-sha256'),
    batch('not-a-sha256')));
  await assertFails(setDoc(batchRef(db), batch(undefined, undefined,
    { source_device_id: 'device-1' })));
  await assertFails(setDoc(batchRef(db), batch(undefined, undefined,
    { source_device_id: null })));
  await assertFails(setDoc(batchRef(db), batch(undefined, undefined,
    { batch_uuid: 'f'.repeat(64) })));
});

test('valid document cannot be deleted or overwritten', async () => {
  const db = branchUser('branch-A');
  await assertSucceeds(setDoc(batchRef(db), batch()));
  await assertFails(setDoc(batchRef(db), batch(undefined, undefined,
    { events: [{ uuid: 'another' }] })));
});

test('unreviewed branch, dashboard and financial snapshot writes are closed', async () => {
  const db = branchUser('branch-A');
  await assertFails(setDoc(doc(db, 'pharmacy_branches/branch-A'), { branch_id: 'branch-A' }));
  await assertFails(setDoc(doc(db, 'pharmacy_daily_dashboards/daily-A'),
    { branch_id: 'branch-A', secret: 'PRIVATE_SENTINEL' }));
  await assertFails(setDoc(doc(db, 'pharmacy_parties_snapshot/branch-A'),
    { branch_id: 'branch-A', partner_mode: 'shares', secret: 'PRIVATE_SENTINEL' }));
});

test('staff cannot read financial snapshots but its own manager can', async () => {
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'pharmacy_parties_snapshot/branch-A'),
      { branch_id: 'branch-A', partner_mode: 'shares' });
  });
  await assertFails(getDoc(doc(branchUser('branch-A', 'staff'), 'pharmacy_parties_snapshot/branch-A')));
  await assertSucceeds(getDoc(doc(branchUser('branch-A'), 'pharmacy_parties_snapshot/branch-A')));
});

test('ordinary staff cannot read manager dashboards', async () => {
  await assertFails(getDoc(doc(branchUser('branch-A', 'staff'), 'pharmacy_daily_dashboards/daily-A')));
});
test('unauthenticated clients cannot read branch documents', async () => {
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'pharmacy_branches/branch-A')));
});
