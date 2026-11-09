const { after, before, test } = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');

const projectId = 'pharmacy-dafb6';
const branchId = '2d91c5e0-8a42-4c10-9b33-5f4a7c8d9012';
const email = 'sync-branch@example.test';
const password = 'EmulatorSync-Passw0rd!';
let uid;
let idToken;
let firestore;

before(async () => {
  const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST;
  assert.ok(
    firestoreHost,
    'FIRESTORE_EMULATOR_HOST must be set; refusing to run Admin SDK checks against a live Firestore project',
  );

  admin.initializeApp({ projectId });
  firestore = admin.firestore();
  // Bind the Admin SDK explicitly to the same local emulator used by REST.
  // This prevents an Admin SDK read from silently targeting another endpoint.
  firestore.settings({ host: firestoreHost, ssl: false });

  const user = await admin.auth().createUser({ email, password });
  uid = user.uid;
  await admin.auth().setCustomUserClaims(uid, {
    branch_id: branchId,
    branch_role: 'manager',
  });
  const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
  assert.ok(authHost, 'FIREBASE_AUTH_EMULATOR_HOST must be set for Auth Emulator tests');
  const response = await fetch(
    'http://' + authHost + '/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=emulator-api-key',
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
  if (admin.apps.length) await admin.app().delete();
});

test('authenticated branch sync commits and reads its Firestore batch; cross-branch write is denied', async () => {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  const base = 'http://' + host + '/v1/projects/' + projectId +
    '/databases/(default)/documents';
  const batchId = 'a'.repeat(64);
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
            source_device_id: { stringValue: '11111111-1111-4111-8111-111111111111' },
            batch_uuid: { stringValue: batchId },
            payload_hash: { stringValue: 'b'.repeat(64) },
            schema_version: { integerValue: '1' },
            events: { arrayValue: { values: [{ mapValue: { fields: {
              uuid: { stringValue: 'test-event-uuid' },
            } } }] } },
          },
        },
        updateTransforms: [{ fieldPath: 'created_at', setToServerValue: 'REQUEST_TIME' }],
        currentDocument: { exists: false },
      }],
    }),
  });
  const commitBody = await commit.text();
  assert.equal(commit.status, 200, commitBody);
  const commitResult = JSON.parse(commitBody);
  assert.equal(
    commitResult.writeResults?.length,
    1,
    'Firestore commit must acknowledge exactly one write: ' + commitBody,
  );

  // Verify the commit reached the exact same emulator endpoint used by REST.
  // The Admin SDK bypasses Security Rules, so this isolates persistence/path
  // problems from authenticated client authorization problems.
  const adminSnapshot = await firestore
    .doc('pharmacy_sync_batches/' + branchId + '/batches/' + batchId)
    .get();
  assert.equal(
    adminSnapshot.exists,
    true,
    'Firestore commit acknowledged one write but Admin SDK found no document at ' +
      documentName + ' (emulator=' + host + ', project=' + projectId + ')',
  );
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
            source_device_id: { stringValue: '11111111-1111-4111-8111-111111111111' },
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
