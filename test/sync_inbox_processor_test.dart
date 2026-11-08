import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/sync_inbox_processor.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration11.dart';

void main() {
  late Database db;
  late FirestoreInboxProcessor processor;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await SchemaIteration11.upgrade(db);
    await db.execute('''CREATE TABLE sync_items(
      id INTEGER PRIMARY KEY AUTOINCREMENT, uuid TEXT NOT NULL UNIQUE,
      branch_id INTEGER NOT NULL, sync_version INTEGER NOT NULL DEFAULT 1,
      sync_status TEXT NOT NULL DEFAULT 'LOCAL', is_deleted INTEGER NOT NULL DEFAULT 0,
      title TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE sync_parents(
      id INTEGER PRIMARY KEY AUTOINCREMENT, uuid TEXT NOT NULL UNIQUE,
      branch_id INTEGER NOT NULL, sync_version INTEGER NOT NULL DEFAULT 1,
      sync_status TEXT NOT NULL DEFAULT 'LOCAL', name TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE sync_children(
      id INTEGER PRIMARY KEY AUTOINCREMENT, uuid TEXT NOT NULL UNIQUE,
      branch_id INTEGER NOT NULL, sync_version INTEGER NOT NULL DEFAULT 1,
      sync_status TEXT NOT NULL DEFAULT 'LOCAL', parent_id INTEGER NOT NULL,
      title TEXT NOT NULL, FOREIGN KEY(parent_id) REFERENCES sync_parents(id))''');
    processor = FirestoreInboxProcessor(database: db);
  });

  tearDown(() async {
    await db.close();
  });

  Map<String, Object?> event({
    required String table,
    required String uuid,
    required int version,
    required Map<String, Object?> payload,
    Map<String, Object?> relations = const {},
    String operation = 'INSERT',
  }) {
    final eventUuid = sha256
        .convert(utf8.encode('$table|$uuid|$version|$operation'))
        .toString();
    return {
      'event_uuid': eventUuid,
      'table': table,
      'uuid': uuid,
      'operation': operation,
      'version': version,
      'payload': payload,
      'relations': relations,
    };
  }

  String canonicalJson(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return jsonEncode(
          {for (final key in keys) key: jsonDecode(canonicalJson(value[key]))});
    }
    if (value is List) {
      return jsonEncode(
          value.map((item) => jsonDecode(canonicalJson(item))).toList());
    }
    return jsonEncode(value);
  }

  String batchFingerprint(List<Map<String, Object?>> events) =>
      sha256.convert(utf8.encode(canonicalJson(events))).toString();

  test('applies an event once and treats a replay as a duplicate', () async {
    final incoming = event(
      table: 'sync_items',
      uuid: 'item-1',
      version: 1,
      payload: {
        'uuid': 'item-1',
        'branch_id': 7,
        'sync_version': 1,
        'sync_status': 'SYNCED',
        'is_deleted': 0,
        'title': 'دواء تجريبي',
      },
    );

    final first = await processor.processBatch(
      branchId: 7,
      batchUuid: 'batch-1',
      payloadHash: batchFingerprint([incoming]),
      events: [incoming],
    );
    final replay = await processor.processBatch(
      branchId: 7,
      batchUuid: 'batch-1',
      payloadHash: batchFingerprint([incoming]),
      events: [incoming],
    );

    expect(first.applied, 1);
    expect(replay.duplicates, 1);
    expect(await db.rawQuery('SELECT * FROM sync_items'), hasLength(1));
    final inbox = await db.query('sync_inbox');
    expect(inbox.single['status'], 'APPLIED');
  });

  test('resolves foreign keys by parent UUID rather than remote integer ID',
      () async {
    final parent = event(
      table: 'sync_parents',
      uuid: 'parent-global-1',
      version: 1,
      payload: {
        'uuid': 'parent-global-1',
        'branch_id': 7,
        'sync_version': 1,
        'sync_status': 'SYNCED',
        'name': 'parent',
      },
    );
    final child = event(
      table: 'sync_children',
      uuid: 'child-global-1',
      version: 1,
      payload: {
        'uuid': 'child-global-1',
        'branch_id': 7,
        'sync_version': 1,
        'sync_status': 'SYNCED',
        'parent_id': 99999,
        'title': 'child',
      },
      relations: {
        'parent_id': {'table': 'sync_parents', 'uuid': 'parent-global-1'},
      },
    );

    await processor.processBatch(
      branchId: 7,
      batchUuid: 'batch-parent',
      payloadHash: batchFingerprint([parent]),
      events: [parent],
    );
    final result = await processor.processBatch(
      branchId: 7,
      batchUuid: 'batch-child',
      payloadHash: batchFingerprint([child]),
      events: [child],
    );

    expect(result.applied, 1);
    final parentId = (await db.query('sync_parents')).single['id'];
    final childRow = (await db.query('sync_children')).single;
    expect(childRow['parent_id'], parentId);
  });

  test('retries a deferred child after its parent arrives', () async {
    final child = event(
      table: 'sync_children',
      uuid: 'child-waiting',
      version: 1,
      payload: {
        'uuid': 'child-waiting',
        'branch_id': 7,
        'sync_version': 1,
        'sync_status': 'SYNCED',
        'parent_id': 555,
        'title': 'waiting child',
      },
      relations: {
        'parent_id': {'table': 'sync_parents', 'uuid': 'parent-late'},
      },
    );
    final firstPass = await processor.processBatch(
      branchId: 7,
      batchUuid: 'batch-waiting-child',
      payloadHash: batchFingerprint([child]),
      events: [child],
    );
    expect(firstPass.deferred, 1);

    final parent = event(
      table: 'sync_parents',
      uuid: 'parent-late',
      version: 1,
      payload: {
        'uuid': 'parent-late',
        'branch_id': 7,
        'sync_version': 1,
        'sync_status': 'SYNCED',
        'name': 'late parent',
      },
    );
    await processor.processBatch(
      branchId: 7,
      batchUuid: 'batch-late-parent',
      payloadHash: batchFingerprint([parent]),
      events: [parent],
    );
    expect(await processor.retryDeferred(7), 1);
    final parentId = (await db.query('sync_parents')).single['id'];
    final childRow = (await db.query('sync_children')).single;
    expect(childRow['parent_id'], parentId);
    expect(
      (await db.query('sync_inbox',
              where: 'event_uuid=?', whereArgs: [child['event_uuid']]))
          .single['status'],
      'APPLIED',
    );
  });

  test('does not overwrite a newer unsynchronized local edit', () async {
    await db.insert('sync_items', {
      'uuid': 'item-local',
      'branch_id': 7,
      'sync_version': 2,
      'sync_status': 'LOCAL',
      'title': 'local-newer',
    });
    final incoming = event(
      table: 'sync_items',
      uuid: 'item-local',
      version: 1,
      payload: {
        'uuid': 'item-local',
        'branch_id': 7,
        'sync_version': 1,
        'sync_status': 'SYNCED',
        'is_deleted': 0,
        'title': 'remote-older',
      },
      operation: 'UPDATE',
    );

    final result = await processor.processBatch(
      branchId: 7,
      batchUuid: 'batch-stale',
      payloadHash: batchFingerprint([incoming]),
      events: [incoming],
    );

    expect(result.rejected, 1);
    final row = (await db.query('sync_items')).single;
    expect(row['title'], 'local-newer');
    expect(row['sync_version'], 2);
    expect((await db.query('sync_inbox')).single['status'], 'IGNORED');
  });

  test('rejects reuse of a batch UUID with a different fingerprint', () async {
    final original = event(
      table: 'sync_items',
      uuid: 'item-2',
      version: 1,
      payload: {
        'uuid': 'item-2',
        'branch_id': 7,
        'sync_version': 1,
        'sync_status': 'SYNCED',
        'is_deleted': 0,
        'title': 'one',
      },
    );
    final tampered = event(
      table: 'sync_items',
      uuid: 'item-3',
      version: 1,
      payload: {
        'uuid': 'item-3',
        'branch_id': 7,
        'sync_version': 1,
        'sync_status': 'SYNCED',
        'is_deleted': 0,
        'title': 'two',
      },
    );
    await processor.processBatch(
      branchId: 7,
      batchUuid: 'batch-fixed',
      payloadHash: batchFingerprint([original]),
      events: [original],
    );

    expect(
      () => processor.processBatch(
        branchId: 7,
        batchUuid: 'batch-fixed',
        payloadHash: batchFingerprint([tampered]),
        events: [tampered],
      ),
      throwsStateError,
    );
  });
}
