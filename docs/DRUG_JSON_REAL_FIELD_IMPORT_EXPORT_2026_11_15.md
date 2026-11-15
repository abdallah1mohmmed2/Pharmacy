# Pharmacy — real drug-field JSON/CSV import/export (2026-11-15)

Branch: feature/central-medicine-catalog. No database migration. Do not change main.

## Previous problems

1. The JSON export included all SQLite drug columns, while the manually
   curated import allowlist excluded real model fields (strip_price_mode).
2. Pasted JSON and picked JSON files had different execution paths. Pasted
   imports could apply model default values during an overwrite, even when
   those fields were absent from the source.
3. Export was not restricted to the selected active branch.
4. The column mapping form allowed strings not backed by real model fields,
   and the preview did not show actual source values.

## Complete model field contract

DrugImportFieldCatalog derives all 98 drug fields directly from the
DrugModel.toMap() contract. Every field has an Arabic display label (96 model fields plus 2 catalog-link
columns added by a schema migration).
85 are writable through catalog import; 13 are read-only references:
- id, uuid, branch_id, created_at, updated_at
- is_deleted, sync_status, sync_version
- completeness_pct, units_per_pack, stock_total_units
- catalog_uuid, catalog_version

All persisted columns are included in exports (subject to the explicit
hide-cost option). The 11 above are exported for reference but are never
written back by a drug-catalog import. Real inventory is reconstructed from
warehouse FEFO batches and stock movement records — catalog import cannot
set it. Calculated fields, branch IDs, local UUIDs and sync metadata are
not transferable by copying a drug JSON record.

Writable fields include strip_price_mode, ped_doses_per_day, ingredients_json,
clinical JSON fields and all other persisted editable model columns.
An exact source key maps to the same real model column; custom source keys
must be mapped explicitly. The target field picker searches the live
85-field catalog and disallows nonexistent, read-only and duplicated targets.
Unknown fields are reported, not silently converted to arbitrary columns.

## Actual file values on screen

The preview reads up to the first three real rows of the chosen file.
For each source column it displays its original name, true target model key,
Arabic label, real sample value and writable/protected/unmapped status.
The preview truncates long text for display only; the original source is not
rewritten. The full dry-run still validates all rows before imports are enabled.

## Consistent execution

The pasted-text path stages the source temporarily and delegates to the
same streaming file-import implementation, transaction batching, branch
isolation and explicit-field updates. Missing fields no longer acquire
default values during an overwrite.

Exports now include only the current branch. The default screen toggle
includes cost values for full fidelity; users can explicitly hide costs.

## Important scope limit

This feature imports and exports the DRUG CATALOG, not a full database backup.
It does not reconstruct historical opening stock, warehouses, purchase
invoices, stock movement records, cash, or patient information. Foreign
keys (manufacturer, active ingredient and category) are local references
and must already exist in the destination database; IDs cannot be assumed
portable across different installations. It does not infer clinical truth.

## Regression coverage

SQLite integration tests in test/drug_file_import_streaming_test.dart check:
- every actual DrugModel field has an explicit import policy and Arabic label
- real JSON export to file, and re-import of all editable fields
- clinical JSON, dosage counts, boolean flags, manual strip prices persisted
- protected stock, UUID and other local metadata cannot be overwritten
- pasted JSON does not change unmentioned fields
- actual value preview and source/target mapping
- nonexistent fields require explicit validated mapping
- export is branch-scoped

Release requires analyzer, flutter test, Windows and Android CI to pass.
