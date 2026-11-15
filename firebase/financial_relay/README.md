# Financial voucher relay — server-side boundary

This module complements the existing `FinancialVoucherOperation` source transaction/outbox, SQLite replay, and HTTP client. It does **not** alter those already implemented and tested components.

## Implemented (code only)

- `POST /v1/operations`: checks a Firebase ID token with `verifyIdToken(token, true)`, requires a matching `branch_id` UUID claim and an `owner`, `manager`, or `accountant` `branch_role`, validates a strict v1 CASH receipt/payment envelope, canonical SHA-256, exact debit/credit balance and membership.
- The Firestore Admin adapter atomically allocates a monotonically increasing branch sequence and creates an immutable operation record. Replays with the same UUID/hash return the same ACK without applying the operation again; conflicting hashes fail.
- `GET /v1/operations?branch_uuid=...&after=...&limit=...`: authorized branch-only ordered paging; cursor is a server sequence, not a local SQLite ID.
- Before accepting an operation, a trusted administrator must explicitly provision `financial_operation_registries/{branch_uuid}`. Required data: `enabled: true`, `fraction_digits` (0–3), `party_uuids` (array), `cash_accounts` (UUID-to-GL-UUID map), and `party_gl` (`RECEIPT`/`PAYMENT` to GL UUID map). The registry must be populated by a trusted backend administrator from verified master records, **never client supplied**. Missing or mismatched identity, currency precision, cash GL or party GL blocks all writes.
- Server starts **disabled** unless `PHARMACY_FINANCIAL_RELAY_ENABLED=true` is set. Its service account must use Application Default Credentials outside this repository. Use an HTTPS gateway with operational authorization controls; do not serve it publicly over plain HTTP.
- Firestore Security Rules do not grant clients access to these new collections. The Admin SDK performs privileged writes only after validation.

## Verification

`node --test firebase/financial_relay/*.test.js` runs fast in-process handler and transaction tests. `firebase/npm test` (the existing Firebase Emulator suite) also runs `firebase/test/finance_relay_emulator.test.js` against an actual local Firestore Emulator. Check the exact CI run and outcome recorded in `docs/SYNC_IMPLEMENTATION_HANDOFF.md`, not a previous passing build.

## Release gates — not done

**This module has not been deployed. It is not enabled in production and is not yet automatically connected to the app's financial sync schedule.** Master-data registry registration and real Firebase Custom Claims provisioning, actual HTTPS endpoint/credential deployment, authenticated two-device acceptance, independent server operation-audit review, load testing and privacy review all remain prerequisites. The voucher contract covers only `RECEIPT/PAYMENT + CASH`; all other financial operations (sales, purchases, returns, payroll, partners, wallet, bank, settlement) remain unapproved.

Do not expand `SyncTablePolicy` or allow generic Firestore row events for financial documents. Use the dedicated immutable envelope and trusted relay only. No deployment or modification of `main` is authorized by these tests.

## Contract compatibility — CASH v2 / YER

The relay validator now accepts only the Dart financial CASH voucher schema version `2`, with `currency_code: YER` and `fraction_digits: 0`. Legacy v1 and non-YER envelopes fail closed. Provisioned branch registries must use `fraction_digits: 0`. This does not authorize other financial domains or enable production relay deployment.
