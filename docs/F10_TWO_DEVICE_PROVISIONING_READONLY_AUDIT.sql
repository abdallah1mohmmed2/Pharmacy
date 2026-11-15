-- F10 read-only preflight for EACH device's SQLite backup (v17+).
-- Run on copies, separately. Never execute UPDATE/INSERT/ALTER on source data.
-- UUIDs are identities, not values to infer from local integer IDs.
-- Compare exported results offline; do not share patient or customer records.
PRAGMA query_only = ON;
PRAGMA user_version;
PRAGMA integrity_check;
PRAGMA foreign_key_check;

-- Rows missing trusted cross-device identities.
SELECT 'warehouses_missing_uuid' AS check_name, COUNT(*) AS row_count
FROM warehouses WHERE uuid IS NULL OR TRIM(uuid) = '';
SELECT 'batches_missing_uuid' AS check_name, COUNT(*) AS row_count
FROM batches_fefo WHERE uuid IS NULL OR TRIM(uuid) = '';

-- Duplicate populated UUIDs (should be zero; v17 has partial unique indexes).
SELECT uuid, COUNT(*) AS occurrences FROM warehouses
WHERE uuid IS NOT NULL AND TRIM(uuid) <> ''
GROUP BY uuid HAVING COUNT(*) > 1;
SELECT uuid, COUNT(*) AS occurrences FROM batches_fefo
WHERE uuid IS NOT NULL AND TRIM(uuid) <> ''
GROUP BY uuid HAVING COUNT(*) > 1;

-- Cross-device comparison candidates. These are NOT safe automatic matches.
-- Local drug_id / warehouse_id are for inspection within each DB only.
SELECT id, uuid, code, name_ar FROM warehouses ORDER BY code, id;
SELECT id, uuid, drug_id, warehouse_id, batch_no, expiry_date
FROM batches_fefo ORDER BY warehouse_id, drug_id, batch_no, expiry_date, id;

-- Potential ambiguous warehouse codes within one device.
SELECT code, COUNT(*) AS occurrences FROM warehouses
WHERE code IS NOT NULL AND TRIM(code) <> ''
GROUP BY code HAVING COUNT(*) > 1;

-- Potential ambiguous batch descriptors within one device.
SELECT warehouse_id, drug_id, batch_no, expiry_date, COUNT(*) AS occurrences
FROM batches_fefo
GROUP BY warehouse_id, drug_id, batch_no, expiry_date
HAVING COUNT(*) > 1;
