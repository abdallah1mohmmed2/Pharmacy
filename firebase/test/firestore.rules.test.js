const fs = require('node:fs');
const path = require('node:path');
const { after, before, beforeEach, test } = require('node:test');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { doc, setDoc, getDoc } = require('firebase/firestore');

const projectId = 'pharmacy-dafb6';
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

test('manager writes batch only to claimed branch', async () => {
  const db = branchUser('branch-A');
  await assertSucceeds(setDoc(doc(db, 'pharmacy_sync_batches/branch-A/batches/batch-1'), {
    branch_id: 'branch-A', source_device_id: '11111111-1111-4111-8111-111111111111', batch_uuid: 'batch-1', events: [{ uuid: 'x' }],
  }));
});
test('cross-branch writes are denied', async () => {
  const db = branchUser('branch-A');
  await assertFails(setDoc(doc(db, 'pharmacy_sync_batches/branch-B/batches/batch-2'), {
    branch_id: 'branch-B', source_device_id: '11111111-1111-4111-8111-111111111111', batch_uuid: 'batch-2', events: [],
  }));
});
test('sync batches are append-only', async () => {
  const db = branchUser('branch-A');
  const ref = doc(db, 'pharmacy_sync_batches/branch-A/batches/batch-3');
  await assertSucceeds(setDoc(ref, { branch_id: 'branch-A', source_device_id: '11111111-1111-4111-8111-111111111111', batch_uuid: 'batch-3', events: [] }));
  await assertFails(setDoc(ref, { branch_id: 'branch-A', source_device_id: '11111111-1111-4111-8111-111111111111', batch_uuid: 'batch-3', events: [] }));
});
test('sync batches require a valid source device UUID', async () => {
  const db = branchUser('branch-A');
  await assertFails(setDoc(doc(db, 'pharmacy_sync_batches/branch-A/batches/no-device'), {
    branch_id: 'branch-A', batch_uuid: 'no-device', events: [],
  }));
  await assertFails(setDoc(doc(db, 'pharmacy_sync_batches/branch-A/batches/bad-device'), {
    branch_id: 'branch-A', source_device_id: 'device-1', batch_uuid: 'bad-device', events: [],
  }));
  await assertSucceeds(setDoc(doc(db, 'pharmacy_sync_batches/branch-A/batches/valid-device'), {
    branch_id: 'branch-A', source_device_id: '11111111-1111-4111-8111-111111111111', batch_uuid: 'valid-device', events: [],
  }));
});
test('ordinary staff cannot read manager dashboards', async () => {
  await assertFails(getDoc(doc(branchUser('branch-A', 'staff'), 'pharmacy_daily_dashboards/daily-A')));
});
test('unauthenticated clients cannot read branch documents', async () => {
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'pharmacy_branches/branch-A')));
});
