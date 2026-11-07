import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/data/database/schema_iteration7.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => sqfliteFfiInit());

  test('iteration 7 adds report cost permissions idempotently for existing roles', () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1,
      onCreate: (database, version) async {
        await database.execute(
          'CREATE TABLE roles(role_code TEXT PRIMARY KEY)',
        );
        await database.execute(
          'CREATE TABLE role_permissions('
          'id INTEGER PRIMARY KEY AUTOINCREMENT,'
          'role_code TEXT NOT NULL,'
          'permission_code TEXT NOT NULL,'
          'is_allowed INTEGER NOT NULL,'
          'UNIQUE(role_code,permission_code))',
        );
        for (final role in [
          'OWNER',
          'MANAGER',
          'PHARMACIST',
          'CASHIER',
          'STOREKEEPER',
          'ACCOUNTANT',
          'AUDITOR',
        ]) {
          await database.insert('roles', {'role_code': role});
        }
      }),
    );

    await SchemaIteration7.upgrade(db);
    await SchemaIteration7.upgrade(db);

    final rows = await db.query(
      'role_permissions',
      where: 'permission_code=?',
      whereArgs: ['reports.cost.view'],
    );
    expect(rows, hasLength(7));
    final allowed = rows
        .where((row) => row['is_allowed'] == 1)
        .map((row) => row['role_code'])
        .toSet();
    expect(allowed, {'OWNER', 'MANAGER', 'ACCOUNTANT'});

    await db.close();
  });
}
