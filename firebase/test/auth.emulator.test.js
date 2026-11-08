const { after, before, test } = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');

const projectId = 'demo-pharmacy-erp';
const email = 'branch-manager@example.test';
const password = 'EmulatorOnly-Passw0rd!';

before(() => {
  admin.initializeApp({ projectId });
});
after(async () => {
  try {
    const user = await admin.auth().getUserByEmail(email);
    await admin.auth().deleteUser(user.uid);
  } catch (_) {}
  await admin.app().delete();
});

test('Firebase Auth Emulator signs in user and returns branch custom claims', async () => {
  const user = await admin.auth().createUser({ email, password });
  await admin.auth().setCustomUserClaims(user.uid, {
    branch_id: 'branch-uuid-0001',
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
  assert.equal(response.status, 200, await response.text());
  const payload = await response.json();
  assert.ok(payload.idToken);
  const decoded = await admin.auth().verifyIdToken(payload.idToken);
  assert.equal(decoded.uid, user.uid);
  assert.equal(decoded.branch_id, 'branch-uuid-0001');
  assert.equal(decoded.branch_role, 'manager');
});
