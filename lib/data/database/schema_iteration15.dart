import 'package:sqflite/sqflite.dart';

/// Additive, local audit/idempotency ledger for opening inventory postings.
/// Never changes existing warehouse, FEFO or stock movement schema.
abstract final class SchemaIteration15 {
  static Future<void> upgrade(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS opening_inventory_posts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      operation_uuid TEXT NOT NULL UNIQUE,
      branch_id INTEGER NOT NULL,
      source_hash TEXT,
      source_name TEXT,
      effective_date TEXT NOT NULL,
      posted_at TEXT NOT NULL,
      line_count INTEGER NOT NULL CHECK(line_count>0),
      total_units INTEGER NOT NULL CHECK(total_units>0),
      FOREIGN KEY(branch_id) REFERENCES branches(id)
    )''');
    await db.execute('''CREATE UNIQUE INDEX IF NOT EXISTS
        idx_opening_import_hash ON opening_inventory_posts(branch_id, source_hash)
        WHERE source_hash IS NOT NULL''');
  }
}
