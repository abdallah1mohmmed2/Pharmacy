// lib/data/database/schema_iteration4.dart
import 'package:sqflite/sqflite.dart';

/// Additive migration for clinical patient-state fields.
abstract final class SchemaIteration4 {
  static Future<void> upgrade(DatabaseExecutor db) async {
    final columns = await db.rawQuery('PRAGMA table_info(patients)');
    if (!columns.any((row) => row['name'] == 'pregnancy_status_known')) {
      await db.execute(
        'ALTER TABLE patients ADD COLUMN pregnancy_status_known '
        'INTEGER NOT NULL DEFAULT 0 CHECK(pregnancy_status_known IN(0,1))',
      );
    }
  }
}
