const { after, before, test } = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');

const projectId = 'pharmacy-dafb6';
const branchId = '2d91c5e0-8a42-4c10-9b33-5f4a7c8d9012';
const email = 'sync-branch@example.test';
const password = 'EmulatorSync-Passw0rd!';
let uid;
let idToken;

before(async () => {
  admin.initializeApp({ projectId });
  const user = await admin.auth().createUser({ email, password });
  uid = user.uid;
  await admin.auth().setCustomUserClaims(uid, {
    branch_id: branchId,
    branch_role: 'manager',
  });
  const host = process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9099';
  const response = await fetch(
    'http://' + host + '/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=emulator-api-key',
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password, returnSecureToken: true }),
    },
  );
  const raw = await response.text();
  assert.equal(response.status, 200, raw);
  idToken = JSON.parse(raw).idToken;
  const decodedToken = await admin.auth().verifyIdToken(idToken);
  assert.equal(decodedToken.branch_id, branchId,
    'signed-in ID token must contain the trusted branch claim');
  assert.equal(decodedToken.branch_role, 'manager',
    'signed-in ID token must contain the manager role claim');
});

after(async () => {
  if (uid) await admin.auth().deleteUser(uid);
  await admin.app().delete();
});

test('authenticated branch sync commits and reads its Firestore batch; cross-branch write is denied', async () => {
  const host = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
  const base = 'http://' + host + '/v1/projects/' + projectId +
    '/databases/(default)/documents';
  const batchId = 'batch-emulator-001';
  const documentName = 'projects/' + projectId +
    '/databases/(default)/documents/pharmacy_sync_batches/' +
    branchId + '/batches/' + batchId;

  const commit = await fetch(base + ':commit', {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + idToken, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      writes: [{
        update: {
          name: documentName,
          fields: {
            branch_id: { stringValue: branchId },
            batch_uuid: { stringValue: batchId },
            events: { arrayValue: { values: [] } },
          },
        },
        currentDocument: { exists: false },
      }],
    }),
  });
  const commitBody = await commit.text();
  assert.equal(commit.status, 200, commitBody);

  // Verify the commit reached the emulator database independently of the
  // authenticated REST read. This distinguishes a missing document from a
  // Security Rules/custom-claims rejection.
  const adminSnapshot = await admin.firestore()
    .doc('pharmacy_sync_batches/' + branchId + '/batches/' + batchId)
    .get();
  assert.equal(adminSnapshot.exists, true,
    'Firestore commit returned 200 but the batch document is missing');
  assert.equal(adminSnapshot.get('branch_id'), branchId);

  const read = await fetch(base + '/pharmacy_sync_batches/' + branchId +
    '/batches/' + batchId, {
      headers: { Authorization: 'Bearer ' + idToken },
    });
  assert.equal(read.status, 200, await read.text());

  const foreignPath = 'projects/' + projectId +
    '/databases/(default)/documents/pharmacy_sync_batches/other-branch/batches/foreign-batch';
  const foreign = await fetch(base + ':commit', {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + idToken, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      writes: [{
        update: {
          name: foreignPath,
          fields: {
            branch_id: { stringValue: 'other-branch' },
            batch_uuid: { stringValue: 'foreign-batch' },
            events: { arrayValue: { values: [] } },
          },
        },
        currentDocument: { exists: false },
      }],
    }),
  });
  assert.ok([400, 403].includes(foreign.status),
    'expected cross-branch write to be denied, got ' + foreign.status +
    ': ' + await foreign.text());
});
