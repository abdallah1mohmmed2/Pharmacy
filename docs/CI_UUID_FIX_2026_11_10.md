# CI UUID fixture repair — 2026-11-10

Baseline: `61d2cf40dd9d0c334a5b1239c2b79779b847bf25` on
`feature/central-medicine-catalog` (verified remotely before editing).

Run [42857837708](https://github.com/abdallah1mohmmed2/Pharmacy/actions/runs/42857837708),
Android job `129975607088`, failed in Flutter tests: 18 failures in
`sync_inbox_processor_test.dart`. The fixtures supplied non-UUID row and parent
identities (`one`, `parent`, etc.) after production UUID validation became strict.
Windows, analysis, Firestore integration, and finance-relay-contract succeeded
in that run; Android packaging was skipped after the test failure.

Repair: deterministic UUID-shaped test fixtures, including inserted parents and
SQL lookup predicates. No change to production validation. Added a separate
negative test proving malformed row/parent UUIDs cannot store sensitive payloads.

Local verification: Flutter 3.47.9 / Dart 3.13.7, Linux system SQLite,
`flutter test --no-pub test/sync_inbox_processor_test.dart`: **28 passed**.
Dependencies satisfy the repository pubspec; no dependency constraints changed.
CI was neither dispatched nor awaited. A new green CI result is not claimed.

Status: fixture repair tested locally; production financial transport remains
blocked. F11 capture/wire/replay and F17–F20 retain their separate acceptance gates.
