# Pharmacy handoff — remaining release gates and opening inventory entry (2026-11-12)

Branch: `feature/central-medicine-catalog`. Never change `main` for this task. This document is a specification and status handoff, **not** evidence the requested inventory feature is implemented.

## Verified CI status
- Workflow run [43107259394](https://github.com/abdallah1mohmmed2/Pharmacy/actions/runs/43107259394) at commit `3b8f41768d597c55e27565b32f0df01a51cdc2aa`: Android, Windows, and finance-relay-contract jobs succeeded. `pharmacy-android` artifact exists.
- Android Gradle compatibility was repaired by pinning Gradle 9.5.1 in the workflow. A green build does not verify actual two-device sync.
- Operator reports issuer key and signed manifest were generated and public key configured in GitHub variables; verify exact public/private key pairing and successful identity import on each device, not just CI.
- Existing Firebase project: `pharmacy-dafb6`; rules require Firebase Auth custom claims `branch_id` (issued UUID) and `branch_role` (owner/manager where required).

## Remaining deployment tasks — do in order, without duplicating successful work
1. Confirm Android APK installation and **backups** on both devices; verify one signed branch manifest imported on both, same tenant/branch UUID and distinct device UUIDs. Never copy the SQLite database between devices or issue separate branch identities.
2. Grant approved Firebase Auth account(s) trusted Admin custom claims `branch_id=<issued branch_uuid>`, `branch_role=owner` (or least-privileged appropriate role). Use an authorized admin environment, keep service-account credentials and signing private key out of Git, devices, and chat. Refresh Firebase ID tokens/re-login.
3. Obtain the Firebase Web API key (not FCM VAPID key), configure runtime cloud setting 35 on each device (`project_id=pharmacy-dafb6`, `database_id=(default)`, appropriate API key). Verify Firestore access and explicit unauthorized denial before enabling any supported non-financial synchronization.
4. Perform real two-independent-device A→B and B→A tests with a harmless record; verify idempotent repeat, reconnect, branch isolation, no duplicate stock or entries; log evidence and actual supported entity types.
5. Keep production financial synchronization disabled pending approved HTTPS trusted relay, full transaction-bound Outbox capture, authorization/validation, second-database atomic idempotent replay and acceptance tests per `docs/CI_VERIFICATION_AND_REMAINING_GATES_2026_11_11.md` and `docs/FINANCIAL_SYNC_CONTRACT.md`. Do not equate passing CI contract tests with a deployed server.
6. Change demo/default credentials and PINs before production; perform backup/restore, permissions, release-signing, install/upgrade and operational handover checks. Do not claim ready for delivery until acceptance is documented.

## New requirement: pharmacy-specific opening inventory with dated entry
**Goal:** On first use, the pharmacy operator adds the medicines **actually owned/in stock** to their own branch inventory. This is distinct from the central drug catalog; no auto-creation of stock from merely selecting a catalog medicine.

### Operator workflow
1. Open `المخزون ← إدخال البضاعة / الرصيد الافتتاحي`. Choose a medicine from existing branch/central catalog or add a branch medicine if missing, without overwriting shared catalog records.
2. Select warehouse and optionally shelf, batch/lot, **mandatory expiry date (تاريخ الانتهاء) for each batch**, supplier/source and notes. Display a date picker and clear day/month/year. Reject invalid dates; warn/block expired stock according to approved policy, and flag near-expiry stock. Preserve traceability of stock by FEFO batch and stock movement. Allow several batches for the same medicine, each with its own expiry date.
3. Specify package hierarchy: **carton (كرتون) → packet/strip (باكت/شريط) → single unit (حبة)**. Explicitly enter `packets_per_carton` and `units_per_packet` as positive integers; names may vary by product. Do not assume one carton or packet has a universal size.
4. Enter initial quantities as cartons, packets and loose units. Compute normalized units exactly: `total_units = cartons * packets_per_carton * units_per_packet + packets * units_per_packet + loose_units`. Prevent negative counts and integer overflow; support 0 in individual quantity fields but require positive total for posting.
5. Enter **selling prices** for carton, packet and unit independently (currency and rounding per branch). Do not silently infer one from another when operator provided a different price; if optional derived defaults are shown, make them editable. Separate purchase cost from selling price. Show a preview of the normalized quantity and prices.
6. Choose **stock-entry effective date** (today by default, or a permitted previous day) and record a separate immutable `created_at` actual timestamp. Validate date policy (future dates blocked unless explicitly approved); preserve both dates for historical reports and audit. The user's phrase “put it on one of the days” is interpreted as choosing the entry day; confirm if they instead mean a dated calendar/schedule.
7. Post once, in a **single SQLite transaction**: branch medicine reference, batch with expiry, opening stock movement and any required valuation/accounting linkage. Use a stable operation UUID/idempotency key. Never write stock_total_units directly from the catalog form, never double-post on retries, and never overwrite existing stock when adding a new opening batch.
8. Show list/search of entered medicines with per-warehouse stock, unit breakdown, three prices, entry date, expiry and source. Corrections must be explicit auditable adjustments/reversals, not silent edits to posted quantities.

### Repository findings to reuse, not duplicate
- `lib/providers/pos_and_drugs_provider.dart` already has `saveDrug`, `loadDrugs`, and existing `sell_price_pack`, `sell_price_strip`, `sell_price_unit` behavior. `saveDrug` explicitly sets new catalog stock to zero and warns that stock must come from FEFO batches/movements. Existing strip/unit prices are currently derived from pack price; three independently editable prices need a compatible design and migration.
- `lib/providers/inventory_and_purchase_provider.dart` already manages warehouses, shelves, FEFO batches, stock movements, stocktaking and purchase invoice posting. Reuse existing inventory operations, database tables, providers and UI navigation. Audit purchase/stocktaking pathways before creating an opening-stock posting service.
- The requested **carton** level may not match current `pack/strip/unit` naming and conversion. Audit `DrugModel`, migrations, POS price selection and reports; add only missing conversion and price fields, with backwards-compatible migration. Avoid breaking existing sales, expiry/FEFO and accounting.
- Do not invent fake medicine details or silently alter central catalog. Keep the new workflow branch-specific.

### Acceptance tests
- Enter a medicine with 2 cartons × 10 packets/carton × 12 units/packet + 3 packets + 4 loose units → **280 units**. Verify prices for all three units persist independently and POS uses the selected unit's correct price.
- Enter stock for a chosen previous day; report shows effective date while audit retains actual posting time.
- Same medicine with two lots/expiry dates retains separate FEFO balances; no cross-branch leakage. Expiry date persists per batch, appears on inventory entry and stock lists, and is used by FEFO allocation; invalid/missing dates are rejected, expired stock is not silently offered for sale.
- Repeated submission with the same operation UUID does not duplicate quantity or ledger rows; failed transaction leaves no partial stock.
- Existing purchases/sales/returns/stocktaking and migration tests remain green; two-device inventory sync is separately verified **only after** authorized, validated sync support is established.


## Non-negotiable compatibility: existing settings and data path
- **Do not modify system settings, existing setting keys/defaults, Firebase project configuration, cloud setting 35, authentication, branch identity, sync endpoint, or data-routing logic** to implement opening inventory. No new independent database, server, collection, alternate storage path or separate inventory source of truth.
- Follow the **same established application data flow**: existing branch-scoped medicine catalog reference → existing inventory/FEFO batch and stock-movement services → current SQLite database and transaction conventions → existing approved Outbox/sync path **only for supported and authorized event types**. Do not bypass validation or activate financial sync.
- Reuse existing providers, services, tables, migrations and navigation. Any essential schema extension must be backward-compatible and additive, preserve historical records/UUIDs, and must not reset or silently migrate settings. Avoid changing existing purchase, sale, stocktaking, return and valuation semantics.
- Before implementation, write regression tests asserting unchanged system settings and storage/sync routing, plus no stock mutation from catalog-only edits; verify existing records remain readable and current business workflows still pass.
- If a requested feature cannot fit the current schema/data path safely, document the gap and seek approval before any architectural or settings change; do not silently introduce a new route.

## Implementation status
- **Documentation/specification added**; opening-inventory feature is **NOT YET IMPLEMENTED** by this handoff commit.
- Next engineering action: inspect schema/migrations, drug model, inventory posting service and existing screens; implement minimal missing opening-balance transaction and UI, then tests. Do not alter `main`.
