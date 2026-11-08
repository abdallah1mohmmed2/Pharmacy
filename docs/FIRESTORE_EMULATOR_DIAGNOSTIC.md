# Firestore Emulator diagnostic — 2026-11-08

## Scope

Branch: `feature/central-medicine-catalog`

This note records the CI failure where the REST `:commit` endpoint returned HTTP 200 but the Admin SDK did not find the written sync batch.

## Changes made

The integration test writes through Firestore REST and verifies persistence through Firebase Admin SDK. Both checks must use the same emulator endpoint, project, and database.

The test already:
1. Requires `FIRESTORE_EMULATOR_HOST`; if absent, it fails before Admin Firestore access rather than risking a live-project request.
2. Explicitly configures Admin SDK Firestore with that host and `ssl: false`.
3. Requires `FIREBASE_AUTH_EMULATOR_HOST` for Auth Emulator sign-in.
4. Parses the REST commit response and asserts exactly one write result was acknowledged.
5. Includes the full document resource name, emulator host, and project ID in the missing-document assertion.
6. Keeps authenticated REST read and cross-branch write-denial checks.

This follow-up sets Node's test-file concurrency explicitly to one in both `test` and `test:rules` scripts. The rules test suite calls `env.clearFirestore()`; serial execution prevents test files sharing the same emulator project from overlapping and clearing each other's data. This is a test-isolation safeguard, not yet proof that concurrency was the sole cause of the missing document.

No Firestore Security Rules were changed. No production Firebase resources, users, claims, or data were modified.

## Verification status

- Previous Emulator run: 6 passing tests and 1 failing integration test.
- Failure: REST `:commit` acknowledged one write, then the Admin SDK reported the document missing.
- The next CI run must confirm whether serial test-file execution resolves the failure.
- If it persists, inspect REST GET immediately after commit and compare it with Admin SDK using the same host, project, database, and full resource path. Do not remove either read assertion.
- Flutter Analyze, Flutter tests, Android APK, and Windows Release must all pass in the same CI run before the broader phase is marked complete.

## Safety constraints

- Do not relax branch-isolation rules to make tests pass.
- Do not issue production Custom Claims or deploy Firebase.
- Do not merge into `main` without explicit authorization.
