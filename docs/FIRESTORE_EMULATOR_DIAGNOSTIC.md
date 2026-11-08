# Firestore Emulator diagnostic — 2026-11-08

## Scope

Branch: `feature/central-medicine-catalog`

This note records the CI failure where the REST `:commit` endpoint returned HTTP 200 but the Admin SDK did not find the written sync batch.

## Diagnosis and test hardening

The integration test writes through Firestore REST and verifies persistence through Firebase Admin SDK. Those checks must use the exact same emulator endpoint and project/database.

The test previously relied on implicit Admin SDK emulator discovery. It now:

1. Requires `FIRESTORE_EMULATOR_HOST`; if it is absent, the test fails before any Admin Firestore access rather than risking a live-project request.
2. Explicitly configures Admin SDK Firestore with that host and `ssl: false`.
3. Requires `FIREBASE_AUTH_EMULATOR_HOST` for the Auth Emulator sign-in step.
4. Parses the REST commit response and asserts that exactly one write result was acknowledged.
5. Includes the full document resource name, emulator host, and project ID in the missing-document assertion.
6. Keeps the authenticated REST read and cross-branch write denial checks.

No Firestore Security Rules were changed. No production Firebase resources, users, claims, or data were modified.

## Verification status

- The previous Emulator run had 6 passing tests and 1 failing integration test.
- The previous failure showed HTTP 200 from REST `:commit`, followed by `adminSnapshot.exists == false`.
- This change is committed to the feature branch; a new GitHub Actions run must pass before the issue can be considered resolved.
- Flutter Analyze, Flutter tests, Android APK, and Windows Release must also pass in the same CI run before the broader phase is marked complete.

## Safety constraints

- Do not relax branch isolation rules to make this test pass.
- Do not issue production Custom Claims or deploy Firebase.
- Do not merge into `main` without explicit authorization.
