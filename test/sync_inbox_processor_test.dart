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
    processor = FirestoreInboxProcessor(
      database: db,
      allowedTablesForTesting: {'sync_items', 'sync_parents', 'sync_children'},
      payloadFieldsForTesting: {
        'sync_items': {'title'},
        'sync_parents': {'name'},
        'sync_children': {'parent_id', 'title'},
      },
    );
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

  Future<InboxBatchResult> receive(Map<String, Object?> incoming,
          {FirestoreInboxProcessor? using, String batch = 'policy-batch'}) =>
      (using ?? processor).processBatch(
          branchId: 7,
          batchUuid: batch,
          payloadHash: batchFingerprint([incoming]),
          events: [incoming]);

  test(
      'production policy rejects an existing unlisted table before storing payload',
      () async {
    final incoming = event(
        table: 'sync_items',
        uuid: 'blocked',
        version: 1,
        payload: {'title': 'PRIVATE_SENTINEL'});
    final result =
        await receive(incoming, using: FirestoreInboxProcessor(database: db));
    expect(result.rejected, 1);
    expect(await db.query('sync_items'), isEmpty);
    expect(await db.query('sync_inbox'), isEmpty);
  });

  test(
      'unknown and sensitive fields reject entire event without retaining values',
      () async {
    await db.execute('ALTER TABLE sync_items ADD COLUMN password_hash TEXT');
    for (final field in ['password_hash', 'future_field', 'id']) {
      final incoming = event(
          table: 'sync_items',
          uuid: field,
          version: 1,
          payload: {'title': 'valid', field: 'PRIVATE_SENTINEL'});
      expect((await receive(incoming, batch: field)).rejected, 1);
    }
    expect(await db.query('sync_items'), isEmpty);
    expect(await db.query('sync_inbox'), isEmpty);
  });

  test('approved field rejects nested payloads and mismatched identity',
      () async {
    final payloads = <Map<String, Object?>>[
      {
        'title': {'token': 'PRIVATE_SENTINEL'}
      },
      {'title': '{"patient":"PRIVATE_SENTINEL"}'},
      {'title': 'ok', 'uuid': 'wrong'},
      {'title': 'ok', 'sync_version': 99},
    ];
    for (var i = 0; i < payloads.length; i++) {
      final incoming = event(
          table: 'sync_items',
          uuid: 'item-$i',
          version: 1,
          payload: payloads[i]);
      expect((await receive(incoming, batch: 'invalid-$i')).rejected, 1);
    }
    expect(await db.query('sync_items'), isEmpty);
    expect(await db.query('sync_inbox'), isEmpty);
  });

  test('relation metadata cannot inject unapproved columns or parent tables',
      () async {
    await db.execute(
        'ALTER TABLE sync_children ADD COLUMN private_owner_id INTEGER REFERENCES sync_parents(id)');
    final relations = <Map<String, Object?>>[
      {
        'private_owner_id': {'table': 'sync_parents', 'uuid': 'p'}
      },
      {
        'title': {'table': 'sync_parents', 'uuid': 'p'}
      },
      {
        'branch_id': {'table': 'sync_parents', 'uuid': 'p'}
      },
      {
        'parent_id': {'table': 'users', 'uuid': 'p'}
      },
      {
        'parent_id': {
          'table': 'sync_parents',
          'uuid': 'p',
          'secret': 'PRIVATE_SENTINEL'
        }
      },
      {
        'parent_id': {'table': 'sync_parents', 'uuid': 123}
      },
    ];
    for (var i = 0; i < relations.length; i++) {
      final incoming = event(
          table: 'sync_children',
          uuid: 'c-$i',
          version: 1,
          payload: {'title': 'child', 'parent_id': 42},
          relations: relations[i]);
      expect((await receive(incoming, batch: 'relations-$i')).rejected, 1);
    }
    expect(await db.query('sync_children'), isEmpty);
    expect(await db.query('sync_inbox'), isEmpty);
  });

  test(
      'embedded relations must match envelope and valid replays stay idempotent',
      () async {
    final invalid =
        event(table: 'sync_items', uuid: 'invalid', version: 1, payload: {
      'title': 'bad',
      '__relations': {'secret': 'PRIVATE_SENTINEL'}
    });
    expect((await receive(invalid)).rejected, 1);
    final valid = event(
        table: 'sync_items',
        uuid: 'valid',
        version: 1,
        payload: {'title': 'ok', '__relations': {}});
    expect((await receive(valid, batch: 'valid-batch')).applied, 1);
    expect((await receive(valid, batch: 'valid-batch')).duplicates, 1);
  });

  test('update and soft delete keep excluded local fields unchanged', () async {
    await db.execute('ALTER TABLE sync_items ADD COLUMN private_note TEXT');
    await db.insert('sync_items', {
      'uuid': 'local',
      'branch_id': 7,
      'sync_version': 1,
      'sync_status': 'SYNCED',
      'title': 'old',
      'private_note': 'LOCAL_ONLY'
    });
    final update = event(
        table: 'sync_items',
        uuid: 'local',
        version: 2,
        operation: 'UPDATE',
        payload: {'title': 'new'});
    expect((await receive(update)).applied, 1);
    final deletion = event(
        table: 'sync_items',
        uuid: 'local',
        version: 3,
        operation: 'SOFT_DELETE',
        payload: {});
    expect((await receive(deletion, batch: 'delete')).applied, 1);
    final row = (await db.query('sync_items')).single;
    expect(row['private_note'], 'LOCAL_ONLY');
    expect(row['title'], 'new');
    expect(row['is_deleted'], 1);
  });

  test('deferred events are revalidated when policy changes', () async {
    final incoming =
        event(table: 'sync_children', uuid: 'child', version: 1, payload: {
      'title': 'child',
      'parent_id': 3
    }, relations: {
      'parent_id': {'table': 'sync_parents', 'uuid': 'missing'}
    });
    expect((await receive(incoming)).deferred, 1);
    expect(await FirestoreInboxProcessor(database: db).retryDeferred(7), 0);
    expect((await db.query('sync_inbox')).single['status'], 'FAILED');
    expect((await db.query('sync_inbox')).single['error_text'],
        'SYNC_PAYLOAD_POLICY_REJECTED');
  });

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

  test('rejects an event whose payload belongs to another branch', () async {
    final incoming = event(
      table: 'sync_items',
      uuid: 'foreign-item',
      version: 1,
      payload: {
        'uuid': 'foreign-item',
        'branch_id': 'branch-b-uuid',
        'sync_version': 1,
        'sync_status': 'SYNCED',
        'is_deleted': 0,
        'title': 'must not cross branches',
      },
    );

    final result = await processor.processBatch(
      branchId: 7,
      batchUuid: 'foreign-branch-batch',
      payloadHash: batchFingerprint([incoming]),
      expectedBranchUuid: 'branch-a-uuid',
      events: [incoming],
    );

    expect(result.rejected, 1);
    expect(await db.query('sync_items'), isEmpty);
    expect((await db.query('sync_inbox')).single['status'], 'FAILED');
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
