#!/usr/bin/env node
'use strict';

// Trusted administrative environment only. Never commit service-account keys.
const admin = require('firebase-admin');

async function main() {
  const [uid, branchId, role] = process.argv.slice(2);
  if (!uid || !branchId || !['owner', 'manager', 'staff'].includes(role)) {
    throw new Error('Usage: node scripts/set-branch-claims.js <AUTH_UID> <BRANCH_UUID> <owner|manager|staff>');
  }
  if (!/^[A-Za-z0-9_-]{8,128}$/.test(branchId)) throw new Error('Invalid branch UUID');
  admin.initializeApp({ credential: admin.credential.applicationDefault() });
  const user = await admin.auth().getUser(uid);
  await admin.auth().setCustomUserClaims(uid, {
    ...(user.customClaims || {}),
    branch_id: branchId,
    branch_role: role,
  });
  console.log(JSON.stringify({ uid, branch_id: branchId, branch_role: role }));
}
main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
