# Fix: compact JSON editor in drug editing — 2026-11-14

## Reported issue
The drug editing form displayed raw JSON, notably `ingredients_json` (compound medicine composition), as long dark text controls that were difficult for nontechnical users to review.

## Changes
- Introduced `lib/screens/drugs/drug_json_editor_field.dart` and wired it into the existing drug editor for fields whose keys end in `_json`.
- A JSON field now appears as one compact, bounded summary instead of displaying the raw payload in the main form.
- Recognizable `ingredients_json` arrays (strings and objects with `name`, `ingredient`, `name_ar`, `active`, `inn_name`, or `ingredient_name`) open as a simple list of named components. Add, rename, and remove actions operate on the existing list; when renaming, unknown metadata such as quantity, code and dosage remains unchanged.
- JSON with unknown/legacy structure uses the original content in a bounded advanced editor. No automatic migration or reformat is performed upon merely opening and closing the dialog.
- Editing requires valid JSON in advanced mode; invalid modifications cannot overwrite the original controller.
- Controllers in nested dialog are disposed only after the closing route animation finishes, avoiding a Flutter disposed-controller assertion.
- Existing theme, database schema, column names, serialization and saved values are not changed.

## Regression coverage
`test/drug_json_editor_field_test.dart` checks compact preview, preservation of nested/legacy fields, add and rename, cancel and no-op byte preservation, malformed input rejection, and unchanged clinical map JSON.

## Data safety and rollout
No database migration, bulk update, deletion or historical rewrite. This change only modifies local UI presentation and saves a JSON field when the user explicitly changes it. The parent drug editor still controls the final persistence.
