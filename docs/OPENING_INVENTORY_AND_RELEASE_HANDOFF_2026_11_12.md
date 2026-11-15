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


## Existing clinical-details screen: strict separation from stock balances
- The existing clinical-details screen already shows medicine price, package size/count and type/form. When opening inventory captures **medicine-level price or package metadata**, update the **existing corresponding fields** in the current medicine model so that this screen displays the latest values. Do not add a duplicate panel or independent source of truth.
- **Never display available stock quantity, remaining cartons/packets/units, warehouse balances, stock movements or inventory entry totals in clinical details.** These belong exclusively to inventory screens. Distinguish fixed package composition (e.g. units per carton) from current quantity on hand.
- Batch-specific expiry date, lot number and receipt date remain in inventory/batch screens, not clinical details. Keep clinical medical content unchanged; do not overwrite drug indications, interactions, contraindications or other medical attributes with stock-entry values.
- Preserve existing system settings and data path. Add tests ensuring price/package changes are reflected in existing clinical-details fields while stock-count changes do not add or alter clinical detail fields.


## Excel (.xlsx) bulk opening-stock import — requested, not yet implemented
- Add **استيراد من Excel** to the **existing** `المخزون ← إدخال البضاعة / الرصيد الافتتاحي` screen, alongside manual entry. Do not change system settings, data routing or existing database ownership.
- Provide a downloadable, documented XLSX template with columns: existing drug identifier or name, medicine type/form, carton quantity, additional packet quantity, additional loose-unit quantity, packets per carton, units per packet, independent carton/packet/unit selling prices, per-batch expiry date, lot/batch number, effective stock-entry date, **optional existing shelf code/number (رقم الرف — اختياري)**, warehouse reference and optional purchase cost/source. Explicitly document the unit meanings and currency; require positive conversion factors. Dates use unambiguous YYYY-MM-DD.
- **Shelf number is optional** in both manual entry and Excel import. An empty shelf cell must be accepted and must not block opening stock posting; retain an unset/null shelf reference. If supplied, resolve the shelf code against the **existing** `shelf_locations` records for the selected warehouse/branch; do not create duplicate shelf records or reinterpret the code as a new storage path. Show row-level error for unknown shelf or wrong-warehouse shelf. Allow assigning a shelf later through existing inventory location workflow without altering stock quantities or prices.
- Parse and validate **all rows before posting**: medicine matching (ambiguous names require manual resolution), branch and warehouse authorization, numeric constraints, pricing precision, dates and batch expiry. Preview totals and row-level errors; allow correction and explicit approval. Never silently invent clinical attributes or drug identifiers.
- Post approved rows using the **same existing branch-scoped inventory transaction, FEFO batches and stock movements** as manual opening stock. Use stable import/job ID and per-row idempotency keys, detect repeated uploads and partial retries; avoid stock duplication. On failure do not leave partially posted untraceable balances; define atomic import/rollback policy and audit imported file hash, operator, actual posting timestamp and effective date.
- Update only the **existing medicine price/package fields** consumed by clinical details; do **not** expose stock-on-hand or expiry batches inside clinical details. All quantities, batch expiry dates and warehouse balances remain in inventory.
- Tests: correct conversion for mixed units, multiple batches of one medicine, price propagation, invalid/ambiguous rows, duplicate file/retry, transaction rollback, no settings/data-route changes, no regression in purchases/sales/FEFO, and authorized two-device sync only when separately approved.
- Status: source implementation added; CI and live acceptance still pending.

## Implementation status
- The original handoff documented an unimplemented request. Implementation progress is recorded below; release gates remain pending.
- Next engineering action: inspect schema/migrations, drug model, inventory posting service and existing screens; implement minimal missing opening-balance transaction and UI, then tests. Do not alter `main`.


## Automatic selling-price suggestions from any entered unit price — requested, not implemented
- In opening-stock manual entry, once valid `packets_per_carton` and `units_per_packet` are supplied, entering **one** of carton, packet or loose-unit selling prices automatically calculates **suggested** prices for the other two: carton = packet × packets_per_carton = unit × packets_per_carton × units_per_packet; packet = carton / packets_per_carton = unit × units_per_packet; unit = packet / units_per_packet = carton / (packets_per_carton × units_per_packet).
- User-entered prices always take precedence: do not overwrite a manually edited field when another field changes. Provide clear calculated-versus-manual state, and allow explicitly recalculating or resetting suggested prices. Define currency rounding/precision and avoid silently changing values on save.
- Excel template/import applies the same rule **only to blank price fields** when exactly one source price is supplied; preserve any other explicitly entered prices. Flag conflicting explicit prices for review, not silent replacement. Validate conversion factors > 0 and all monetary values >= 0.
- Save the resulting independent selling prices through the existing medicine price fields/data path so the existing clinical-details screen reflects price/package metadata. Inventory balances remain exclusively in inventory screens. No system-setting changes.
- Tests: all three source-price directions, manual override precedence, precision/rounding, Excel blanks versus explicit values, invalid pack ratios, and no regression in existing medicine pricing modes.
- Status: source implementation added; CI and live acceptance still pending.

## Implementation progress (2026-11-12; feature branch only)
- **Implemented in source, pending CI and live acceptance:** new opening-stock form `lib/screens/inventory/opening_inventory_screen.dart`, reusable atomic/idempotent FEFO posting `lib/data/services/opening_inventory_service.dart`, XLSX template/import preview `lib/data/services/opening_inventory_excel.dart`, permission-gated inventory-screen entry, preservation of manual prices and explicit separation of clinical details from stock balances.
- SQLite database migrates **additively from v17 to v18**, retaining the same database file/path and system settings. The new local-only `opening_inventory_posts` ledger records operation UUID/file hash to prevent repeat posts; it is not added to the synchronization allowlist.
- Automated integration coverage: mixed-unit quantity (280), multiple batches, optional shelf, price conflicts/overrides, duplicate import prevention, rollback, unchanged settings and v17→v18 preservation. Release still requires CI, real POS/FEFO and two-device tests; do not claim synchronization of stock or production readiness.
- Opening stock optionally accepts unit cost and stores it in FEFO/movement data, **but does not yet generate a balanced opening valuation journal**. Financial opening valuation must be separately implemented and tested before relying on opening stock financial reports.

## Dosage-form import from Excel (2026-11-13, feature branch)
- Reuse **existing** `drugs.dosage_form` field, not a new table/column. Accepted enum codes are TABLET, CAPSULE, SYRUP, SUSPENSION, DROPS, INJECTION, CREAM, OINTMENT, INHALER, SUPPOSITORY, SACHET, OTHER.
- Opening balance XLSX now accepts optional column **نوع الدواء** (Arabic labels mapped to the enum, or existing English enum codes). The application's generated template also includes this optional column; existing 17-column spreadsheets still import unchanged.
- The opening-stock service validates that an explicitly supplied form does **not** conflict with a preclassified medicine, and rejects inconsistent forms across multiple lots of the same medicine before posting any stock. It fills `OTHER` only when a valid form has been explicitly provided; it never overwrites known dosage-form values. This is transactional and does not create new medicines.
- Arabic workbook `pharmacy_opening_inventory_with_drug_types.xlsx` keeps existing drug-name lists, auto-priced selling-price formulas and a dosage-form dropdown in column U with an enum-reference worksheet. Note this downloadable Excel is a user-side artifact, **not** a tracked file in the repository or a live catalog sync.
- The prior automatic selling-price rounding rule (derived prices up to the next multiple of 10, explicit prices preserved) remains unchanged. Type mapping tests were added to the integration suite; GitHub Actions must pass before claiming the new release is verified. Device acceptance and cross-device stock sync remain separate gates.

## Excel purchase-cost inputs (2026-11-13)
- Optional headers: `إدخال تكلفة الكرتون`, `إدخال تكلفة الباكت`, `إدخال تكلفة الحبة`. Exactly one nonblank cost source is accepted per stock row; multiple cost-source inputs are an import error instead of a silent override.
- Acquisition cost is computed to the existing `OpeningStockLine.unitCost` (carton ÷ packets per carton ÷ units per packet; packet ÷ units per packet; unit unchanged) and is stored through existing FEFO batch `unit_cost` and `pack_cost`. **Do not round acquisition cost to the next 10**; the upward multiple-of-10 rounding rule applies only to derived selling prices.
- Legacy XLSX files containing just the original `تكلفة الحبة` remain supported. New exported workbook `pharmacy_opening_inventory_types_and_purchase_costs.xlsx` uses independent raw cost-source columns with display-only formulas for per-unit, packet and carton costs. The parser ignores displayed formula cells rather than trusting spreadsheet formula caches.
- This does **not** automatically create a general-ledger opening valuation journal or change `drugs.cost_price_pack`, which may have distinct purchasing semantics. Financial valuation and multi-device synchronization remain separate acceptance items.
