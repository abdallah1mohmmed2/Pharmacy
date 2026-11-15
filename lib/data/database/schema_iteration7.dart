// lib/data/database/schema_iteration7.dart
import 'package:sqflite/sqflite.dart';

/// Adds report cost visibility to the role-based permission matrix.
///
/// This migration is intentionally separate from Iteration 6 because users
/// may already have a version-9 database where that iteration has run.
abstract final class SchemaIteration7 {
  static const Map<String, bool> _defaults = {
    'OWNER': true,
    'MANAGER': true,
    'PHARMACIST': false,
    'CASHIER': false,
    'STOREKEEPER': false,
    'ACCOUNTANT': true,
    'AUDITOR': false,
  };

  static Future<void> upgrade(DatabaseExecutor db) async {
    for (final entry in _defaults.entries) {
      final role = await db.query(
        'roles',
        columns: ['role_code'],
        where: 'role_code=?',
        whereArgs: [entry.key],
        limit: 1,
      );
      if (role.isEmpty) continue;
      await db.insert(
        'role_permissions',
        {
          'role_code': entry.key,
          'permission_code': 'reports.cost.view',
          'is_allowed': entry.value ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }
}
