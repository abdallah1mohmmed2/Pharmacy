import 'package:sqflite/sqflite.dart';

/// Introduces the organization (tenant) boundary while keeping the current
/// rollout limited to one tenant and one pharmacy branch.
abstract final class SchemaIteration12 {
  static Future<void> upgrade(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tenants (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        code TEXT NOT NULL UNIQUE,
        name_ar TEXT NOT NULL,
        name_en TEXT,
        is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0,1)),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    final branchColumns = await db.rawQuery('PRAGMA table_info(branches)');
    final names = branchColumns.map((row) => row['name'] as String).toSet();
    if (!names.contains('tenant_uuid')) {
      await db.execute(
        'ALTER TABLE branches ADD COLUMN tenant_uuid TEXT '
        'REFERENCES tenants(uuid)',
      );
    }

    // Existing installs are linked to the single seeded tenant. This legacy
    // placeholder is deliberately NOT a cloud identity; secure provisioning
    // must replace it with an operator-issued UUID before cloud sync is enabled.
    await db.insert(
      'tenants',
      {
        'uuid': 'tenant-main',
        'code': 'MAIN',
        'name_ar': 'المؤسسة الرئيسية',
        'name_en': 'Main Organization',
        'is_active': 1,
        'created_at': '2026-11-08T00:00:00.000',
        'updated_at': '2026-11-08T00:00:00.000',
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await db.execute(
      "UPDATE branches SET tenant_uuid='tenant-main' "
      "WHERE tenant_uuid IS NULL",
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_branches_tenant_uuid '
      'ON branches(tenant_uuid)',
    );
  }
}
