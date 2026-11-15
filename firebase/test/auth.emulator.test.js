const { after, before, test } = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');

const projectId = 'pharmacy-dafb6';
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
    branch_id: '2d91c5e0-8a42-4c10-9b33-5f4a7c8d9012',
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
  const rawResponse = await response.text();
  assert.equal(response.status, 200, rawResponse);
  const payload = JSON.parse(rawResponse);
  assert.ok(payload.idToken);
  const decoded = await admin.auth().verifyIdToken(payload.idToken);
  assert.equal(decoded.uid, user.uid);
  assert.equal(decoded.branch_id, '2d91c5e0-8a42-4c10-9b33-5f4a7c8d9012');
  assert.equal(decoded.branch_role, 'manager');

  // A refresh-token exchange must issue a fresh ID token carrying the same
  // trusted branch claims, matching the Flutter client's renewal flow.
  const refreshResponse = await fetch(
    'http://' + host + '/securetoken.googleapis.com/v1/token?key=emulator-api-key',
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'refresh_token',
        refresh_token: payload.refreshToken,
      }),
    },
  );
  const refreshBody = await refreshResponse.text();
  assert.equal(refreshResponse.status, 200, refreshBody);
  const refreshed = JSON.parse(refreshBody);
  assert.ok(refreshed.id_token);
  const refreshedClaims = await admin.auth().verifyIdToken(refreshed.id_token);
  assert.equal(refreshedClaims.uid, user.uid);
  assert.equal(refreshedClaims.branch_id, '2d91c5e0-8a42-4c10-9b33-5f4a7c8d9012');
  assert.equal(refreshedClaims.branch_role, 'manager');

  // Updating claims does not mutate an already-issued ID token. A subsequent
  // refresh-token exchange must expose the newly assigned role.
  await admin.auth().setCustomUserClaims(user.uid, {
    branch_id: '2d91c5e0-8a42-4c10-9b33-5f4a7c8d9012',
    branch_role: 'staff',
  });
  const claimsRefreshResponse = await fetch(
    'http://' + host + '/securetoken.googleapis.com/v1/token?key=emulator-api-key',
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'refresh_token',
        refresh_token: refreshed.refresh_token,
      }),
    },
  );
  const claimsRefreshBody = await claimsRefreshResponse.text();
  assert.equal(claimsRefreshResponse.status, 200, claimsRefreshBody);
  const claimsRefreshed = JSON.parse(claimsRefreshBody);
  const updatedClaims = await admin.auth().verifyIdToken(claimsRefreshed.id_token);
  assert.equal(updatedClaims.branch_id, '2d91c5e0-8a42-4c10-9b33-5f4a7c8d9012');
  assert.equal(updatedClaims.branch_role, 'staff');
});
