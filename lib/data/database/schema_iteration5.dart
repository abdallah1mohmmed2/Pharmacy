// lib/data/database/schema_iteration5.dart
import 'package:sqflite/sqflite.dart';

abstract final class SchemaIteration5 {
  static Future<void> upgrade(DatabaseExecutor db) async {
    await _ensureColumn(db, 'sales_invoice_items', 'is_substitute', 'INTEGER NOT NULL DEFAULT 0');
    await _ensureColumn(db, 'sales_invoice_items', 'substitute_for_drug_id', 'INTEGER');
    await _ensureColumn(db, 'sales_invoice_items', 'substitution_reason', 'TEXT');
    await _ensureColumn(db, 'sales_invoice_items', 'substituted_by_user_id', 'INTEGER');
    await db.execute('CREATE TABLE IF NOT EXISTS audit_logs(id INTEGER PRIMARY KEY AUTOINCREMENT, branch_id INTEGER NOT NULL DEFAULT 1, user_id INTEGER, action_code TEXT NOT NULL, entity_type TEXT NOT NULL, entity_id INTEGER, reference_no TEXT, old_value TEXT, new_value TEXT, reason TEXT, severity TEXT NOT NULL DEFAULT \'INFO\', occurred_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_audit_logs_branch_time ON audit_logs(branch_id,occurred_at)');
    await db.execute('CREATE TABLE IF NOT EXISTS user_permissions(id INTEGER PRIMARY KEY AUTOINCREMENT,user_id INTEGER NOT NULL,permission_code TEXT NOT NULL,is_allowed INTEGER NOT NULL DEFAULT 0,UNIQUE(user_id,permission_code))');
    await db.execute('CREATE TABLE IF NOT EXISTS report_favorites(id INTEGER PRIMARY KEY AUTOINCREMENT,user_id INTEGER NOT NULL,report_number INTEGER NOT NULL CHECK(report_number BETWEEN 1 AND 55),created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,UNIQUE(user_id,report_number))');
  }

  static Future<void> _ensureColumn(DatabaseExecutor db, String table, String column, String declaration) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    if (!columns.any((row) => row['name'] == column)) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $declaration');
    }
  }
}
