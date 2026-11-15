#!/usr/bin/env node
'use strict';

// Trusted administrative environment only. Never commit service-account keys.
// The UID-to-branch assignment must come from an operator-managed file outside
// the repository; the CLI cannot choose or override a branch or role.
const fs = require('node:fs');
const path = require('node:path');
const admin = require('firebase-admin');

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ALLOWED_ROLES = new Set(['owner', 'manager', 'staff']);

function loadTrustedAssignment(uid) {
  const mappingPath = process.env.BRANCH_UID_MAP_FILE;
  if (!mappingPath || !path.isAbsolute(mappingPath)) {
    throw new Error('BRANCH_UID_MAP_FILE must point to an absolute path outside the repository');
  }
  const repositoryRoot = path.resolve(__dirname, '../..');
  const relative = path.relative(repositoryRoot, path.resolve(mappingPath));
  if (!relative.startsWith('..' + path.sep) && relative !== '..' && !path.isAbsolute(relative)) {
    throw new Error('The UID mapping file must be stored outside the Git repository');
  }
  const mapping = JSON.parse(fs.readFileSync(mappingPath, 'utf8'));
  const assignment = mapping[uid];
  if (!assignment || typeof assignment !== 'object') {
    throw new Error('No trusted branch assignment exists for this Firebase UID');
  }
  const branchId = String(assignment.branch_id || '');
  const role = String(assignment.branch_role || '');
  if (!UUID_PATTERN.test(branchId)) throw new Error('Trusted mapping contains an invalid branch UUID');
  if (!ALLOWED_ROLES.has(role)) throw new Error('Trusted mapping contains an unsupported branch role');
  return { branchId, role };
}

async function main() {
  const [uid] = process.argv.slice(2);
  if (!uid || process.argv.length !== 3) {
    throw new Error('Usage: BRANCH_UID_MAP_FILE=/secure/path/branch-uid-map.json node scripts/set-branch-claims.js <AUTH_UID>');
  }
  const { branchId, role } = loadTrustedAssignment(uid);
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
