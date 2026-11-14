# Pharmacy — audit and fixes for oversized JSON editors (2026-11-14)

Branch: feature/central-medicine-catalog. Scope: display/editor only; no database migration.

## Audit scope
Reviewed the Flutter screen implementations under lib/screens, including drug details,
import/export, settings, audit, clinical, finance, inventory, sales and report screens.
Differentiated required raw-source inputs from accidental raw JSON presentation.

## Confirmed and addressed
1. **Drug composition and clinical JSON fields**: already fixed in
   lib/screens/drugs/drug_json_editor_field.dart and covered by
   test/drug_json_editor_field_test.dart. Original fields and structure unchanged.
2. **Drug CSV/JSON import column mapping**: formerly displayed a JSON string
   as a 2–5 line textbox, with a preview that rendered every mapped column
   inline. Replaced with lib/screens/drugs/drug_import_mapping_field.dart.
   This presents a compact summary, opens a bounded scrollable form with
   explicit source and target column names, supports add/edit/remove, and
   validates duplicate or incomplete column mappings before updating the
   controller. Unknown legacy formats remain accessible in a bounded
   advanced editor, and closing an untouched editor preserves original bytes.
   The mapping contract stays Map<String,String>, so dry-run and import code
   are unchanged. Preview is collapsed initially and scrollable when expanded.
3. **Audit log raw JSON in system settings**: the advanced technical section
   could grow arbitrarily when historical before/after payloads were large.
   Both immutable payloads now display in separately scrollable, height-limited
   regions. The original JSON and its hash are not edited or truncated in data.

## Intentionally unchanged
- CSV/JSON source textarea in the drug import tab: this is explicitly the
  user's original source input; it was already capped at 14 visual lines and
  has a file picker for large files.
- The friendly JSON settings editor: it already uses switches, bounded
  choices and structured fields while retaining unknown setting keys.
- Existing small enum dropdowns (drug status, form, route, permissions):
  there is no evidence in the audit that these produce the reported JSON
  display defect. Avoid unnecessary behavior changes.
- Stored drug JSON, schema, imported data, audit events, theme, branch data
  and prior financial/clinical behavior.

## Regression tests
test/drug_import_mapping_field_test.dart verifies that mapping JSON is not
shown raw by default, cancel/no-op preserves original bytes, add retains
existing columns, duplicate source columns are rejected, and unknown legacy
structures remain accessible without automatic rewrite.

## Release gate
Run the existing full Flutter analyzer, Flutter tests, Android APK and Windows
build using .github/workflows/flutter-ci.yml. Do not claim CI success before
the branch's newest run completes.
