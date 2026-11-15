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

## Acceptance handoff: engineering versus owner action (2026-11-11)

Latest verified feature-branch CI: [43025538752](https://github.com/abdallah1mohmmed2/Pharmacy/actions/runs/43025538752), completed **success** at `713a76cd98ab5f5f1718d3e013fabf214a60c368`. This includes the branch-isolated voucher cursor regression test. Do not rerun or recreate successful tests solely because older handoff sections describe them as pending.

### Engineering verification without owner intervention

- Inventory existing financial voucher capture, apply/replay, independent-database tests, failure rollback, and financial-sale replay before identifying missing **operation-specific** coverage. Existing evidence is not equivalent to acceptance of every purchase, return, payroll or partner operation.
- Review trusted financial relay implementation and automated authorization contract, and distinguish test/mock verification from actual deployed backend identity, claims and reference provisioning.
- Keep production financial transport disabled, financial Firestore allowlists unchanged, and the draft PR unmerged. Do not modify `main`.

### Explicit owner-controlled production gates

1. Approve the intended real Firebase project and any deployment or real-data integration. No production deployment without explicit approval.
2. In a secure administrative environment, generate and safeguard the Ed25519 signing key and signed *single* tenant/branch manifest for `pharmacy/PHARMACY` and `ph1/PH1`. Do not commit the private key, identity registry or operational manifest. The owner must confirm the final tenant and branch identities before issuance.
3. Install the trusted public key in the approved build configuration and provision the *same* signed branch manifest to the intended devices; record actual UUID/device identity checks.
4. Approve Firebase Auth accounts, UID-to-branch role mapping and Custom Claims through trusted administration, and verify actual token/branch authorization and backend domain checks.
5. Authorize a staged end-to-end acceptance run against the approved backend and two separately provisioned devices/databases; only then consider a controlled production rollout.

**Status:** CI and client-side regression coverage are verified. Administrative provisioning, live trusted backend checks, and full production acceptance are **not verified**. Do not count pre-existing independent-database tests as missing work, and do not claim production readiness from CI alone.
