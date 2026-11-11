# Pharmacy CI verification and remaining gates — 2026-11-11

Branch: `feature/central-medicine-catalog`. This is a verification note, not a production release authorization.

## Verified after UUID fixture repair

GitHub Actions run [42862912446](https://github.com/abdallah1mohmmed2/Pharmacy/actions/runs/42862912446) completed with **success** on the branch's pull request. All three jobs passed:
- `android`: SQLite sync inventory check, Dart formatting, branch identity provisioning test, Firestore Emulator security tests, Firebase JSON validation, Flutter analysis, sync integration against Firestore Emulator, full Flutter tests, Android APK build, ZIP packaging and artifact upload.
- `windows`: Flutter analysis, Windows release build, ZIP packaging and artifact upload.
- `finance-relay-contract`: trusted financial relay contract/authorization verification.

This supersedes the *pending CI* statement in `CI_UUID_FIX_2026_11_10.md` for that repair. It does **not** prove financial replication is production-ready.

## Unclosed acceptance gates (do not repeat completed groundwork)

As specified by `FINANCIAL_SYNC_CONTRACT.md`, P0-05 remains open. Before any financial allowlist expansion or production enablement, demonstrate:
1. Stable globally unique identities and mappings for historical and new cash movements, ledger rows and polymorphic `doc_id/source_id` references, preserving historical UUIDs.
2. An immutable, complete operation envelope captured into Outbox in the *same SQLite transaction* as the source business posting (P0-06).
3. Trusted server-side validation of financial operation membership, currency precision, debit/credit balance, relationships and authorization.
4. Atomic apply and durable idempotent replay on an independent second database, including rollback on partial failure and missing dependencies, for each approved operation type.
5. Separate privacy/field contracts and acceptance gates for sensitive clinical, payroll and partner data; no implicit permission from a financial operation.
6. Deployment configuration and identity provisioning acceptance checks before production sync or sale activation.

The existing `processAtomicBatch` and cash voucher validator are groundwork, **not** end-to-end financial transport. Keep financial transport blocked, retain the draft PR, and do not merge to `main`.

## Next engineering step

Audit the existing source posting/Outbox integration for a single cash voucher operation; implement only the missing transaction-bound capture and identity mapping after tests confirm the gap. Follow with two-database replay tests. Do not rebuild working sync infrastructure or weaken UUID validation.

## 2026-11-11 follow-up: voucher cursor persistence

Commit `dbde1e6fb9a59c47e38f945f456f286a1e9701c1` adds `FinancialRelayClient.syncVouchersOnce` using the existing voucher `sendPending` and `receivePage` functions. It stores a branch-UUID-scoped cursor in `app_settings` after each successfully processed page. It is explicitly caller-invoked, not scheduled, and does not activate production transport. The existing voucher capture/replay implementation was **not** duplicated.

**Verification pending:** this commit has not yet been shown to pass CI or targeted restart/interrupted-page tests. Do not treat the feature as accepted until those checks pass. The cursor and applied operations are not committed in one SQLite transaction; a crash between them intentionally causes idempotent replay rather than lost events. Financial deployment gates above remain in force.

## 2026-11-11 follow-up: verified voucher cursor hardening

GitHub Actions run [42990882379](https://github.com/abdallah1mohmmed2/Pharmacy/actions/runs/42990882379) completed **success** at commit `bdab0a9240dc766788e41251a36f73313facfd35`; Android, Windows and finance-relay-contract jobs all succeeded.

- The voucher receive path now rejects a non-empty page whose cursor does not advance, matching the pre-existing sale receive guard.
- `test/financial_relay_client_test.dart` covers restart cursor persistence, no cursor advancement on relay HTTP failure, and rejection of a non-advancing voucher page.
- These are client-side cursor/transport tests, **not** proof of a complete end-to-end financial transfer across two independently provisioned databases and an authorized server.
- Existing voucher capture/replay, branch identity groundwork, and security contract tests must be inventoried before adding any redundant implementation.
- The server's production token/role/branch membership validation, financial domain authorization, currency/reference validation, and operational provisioning remain acceptance gates until verified against a deployed trusted backend. Do not enable production finance sync or merge `main` on the strength of CI alone.
