import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/global_uuid.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration12.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  Future<Database> openDatabaseWithSyncTables() async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE branches (id INTEGER PRIMARY KEY, uuid TEXT NOT NULL UNIQUE, updated_at TEXT)',
    );
    await db.execute(
      'CREATE TABLE sync_queue (id INTEGER PRIMARY KEY, status TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE sync_inbox_batches (id INTEGER PRIMARY KEY)',
    );
    await db.execute(
      'CREATE TABLE sync_inbox_cursors (branch_id INTEGER PRIMARY KEY)',
    );
    return db;
  }

  test('migrates legacy branch-main to a unique RFC UUID before sync', () async {
    final db = await openDatabaseWithSyncTables();
    try {
      await db.insert('branches', {
        'id': 1,
        'uuid': 'branch-main',
        'updated_at': '2026-11-01',
      });
      await db.insert('branches', {
        'id': 2,
        'uuid': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'updated_at': '2026-11-01',
      });

      await SchemaIteration12.upgrade(db);
      final rows = await db.query('branches', orderBy: 'id');
      final migrated = rows.first['uuid'].toString();
      expect(GlobalUuid.isValid(migrated), isTrue);
      expect(migrated, isNot('branch-main'));
      expect(rows.last['uuid'], 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
      expect(await db.query('branches'), hasLength(2));
    } finally {
      await db.close();
    }
  });

  test('refuses to rotate branch identity after cloud history exists', () async {
    final db = await openDatabaseWithSyncTables();
    try {
      await db.insert('branches', {
        'id': 1,
        'uuid': 'branch-main',
        'updated_at': '2026-11-01',
      });
      await db.insert('sync_queue', {'id': 1, 'status': 'DONE'});

      await expectLater(
        SchemaIteration12.upgrade(db),
        throwsA(isA<StateError>()),
      );
      final branch = (await db.query('branches')).single;
      expect(branch['uuid'], 'branch-main');
    } finally {
      await db.close();
    }
  });

  test('UUID v4 generator creates unique valid identifiers', () {
    final values = List.generate(100, (_) => GlobalUuid.generateV4());
    expect(values.every(GlobalUuid.isValid), isTrue);
    expect(values.toSet(), hasLength(values.length));
  });
}
