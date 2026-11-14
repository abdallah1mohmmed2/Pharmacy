import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/sync_inbox_processor.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration11.dart';

// Deterministic UUID-shaped fixtures; production validation remains strict.
String testUuid(String label) {
  final hash = sha256.convert(utf8.encode(label)).toString();
  return '${hash.substring(0, 8)}-${hash.substring(8, 12)}-4${hash.substring(13, 16)}-8${hash.substring(17, 20)}-${hash.substring(20, 32)}';
}

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

  const operationUuid = 'a1234567-1234-4123-8123-123456789abc';
  const branchUuid = 'b1234567-1234-4123-8123-123456789abc';
  Map<String, Object?> atomicEvent(String uuid,
          {String table = 'sync_items',
          int version = 1,
          String operation = 'INSERT',
          Map<String, Object?> fields = const {},
          Map<String, Object?> relations = const {}}) =>
      event(
          table: table,
          uuid: testUuid(uuid),
          version: version,
          operation: operation,
          payload: {'branch_id': branchUuid, ...fields},
          relations: relations);

  Future<InboxBatchResult> receiveAtomic(List<Map<String, Object?>> events,
          {FirestoreInboxProcessor? using,
          String operationId = operationUuid}) =>
      (using ?? processor).processAtomicBatch(
          branchId: 7,
          operationUuid: operationId,
          expectedBranchUuid: branchUuid,
          payloadHash: batchFingerprint(events),
          events: events);

  Future<void> expectAtomicRollback() async {
    expect(await db.query('sync_items'), isEmpty);
    expect(await db.query('sync_children'), isEmpty);
    expect(await db.query('sync_inbox'), isEmpty);
    expect(await db.query('sync_inbox_batches'), isEmpty);
  }

  test('malformed row and parent UUIDs are rejected without storing payload',
      () async {
    final invalidRow = event(
        table: 'sync_items',
        uuid: 'legacy-local-1',
        version: 1,
        payload: {'title': 'PRIVATE_SENTINEL'});
    expect((await receive(invalidRow, batch: 'invalid-row')).rejected, 1);
    final invalidParent = event(
        table: 'sync_children',
        uuid: testUuid('child'),
        version: 1,
        payload: {
          'title': 'PRIVATE_SENTINEL',
          'parent_id': 1
        },
        relations: {
          'parent_id': {'table': 'sync_parents', 'uuid': 'legacy-parent'}
        });
    expect((await receive(invalidParent, batch: 'invalid-parent')).rejected, 1);
    expect(await db.query('sync_inbox'), isEmpty);
    expect(await db.query('sync_items'), isEmpty);
    expect(await db.query('sync_children'), isEmpty);
  });

  test(
      'ordinary batch can apply one member while rejecting another; atomic batch rolls back both',
      () async {
    final ordinary = [
      event(
          table: 'sync_items',
          uuid: testUuid('ordinary-valid'),
          version: 1,
          payload: {'title': 'inventory-effect'}),
      event(
          table: 'sync_items',
          uuid: testUuid('ordinary-invalid'),
          version: 1,
          payload: {'title': 'financial-effect', 'private_field': 'blocked'}),
    ];
    final ordinaryResult = await processor.processBatch(
        branchId: 7,
        batchUuid: 'ordinary-partial',
        payloadHash: batchFingerprint(ordinary),
        events: ordinary);
    expect(ordinaryResult.applied, 1);
    expect(ordinaryResult.rejected, 1);
    expect(await db.query('sync_items'), hasLength(1));

    final atomic = [
      atomicEvent('atomic-valid', fields: {'title': 'inventory-effect'}),
      atomicEvent('atomic-invalid',
          fields: {'title': 'financial-effect', 'private_field': 'blocked'}),
    ];
    await expectLater(
        receiveAtomic(atomic), throwsA(isA<AtomicInboxBatchException>()));
    expect(await db.query('sync_items'), hasLength(1));
    expect(
        await db.query('sync_items',
            where: 'uuid=?', whereArgs: [testUuid('atomic-valid')]),
        isEmpty);
    expect(
        await db.query('sync_inbox_batches',
            where: 'batch_uuid=?', whereArgs: ['atomic-v1:$operationUuid']),
        isEmpty);
  });

  test('atomic operation rejects invalid identity and mismatched branch',
      () async {
    final events = [
      atomicEvent('one', fields: {'title': 'one'})
    ];
    expect(() => receiveAtomic(events, operationId: 'local-1'),
        throwsA(isA<AtomicInboxBatchException>()));
    await receiveAtomic(events);
    await expectLater(
        processor.processAtomicBatch(
            branchId: 7,
            operationUuid: operationUuid,
            expectedBranchUuid: 'c1234567-1234-4123-8123-123456789abc',
            payloadHash: batchFingerprint(events),
            events: events),
        throwsA(isA<AtomicInboxBatchException>()));
    expect(await db.query('sync_items'), hasLength(1));
  });

  test('atomic replay rejects a receipt whose member is no longer APPLIED',
      () async {
    final events = [
      atomicEvent('one', fields: {'title': 'one'})
    ];
    await receiveAtomic(events);
    await db.update('sync_inbox', {'status': 'IGNORED'});
    await expectLater(
        receiveAtomic(events), throwsA(isA<AtomicInboxBatchException>()));
    expect(await db.query('sync_items'), hasLength(1));
  });

  test('atomic operation commits once and replay does not repeat inserts',
      () async {
    final events = [
      atomicEvent('one', fields: {'title': 'one'}),
      atomicEvent('two', fields: {'title': 'two'})
    ];
    expect((await receiveAtomic(events)).applied, 2);
    expect((await receiveAtomic(events)).duplicates, 2);
    expect(await db.query('sync_items'), hasLength(2));
    expect(await db.query('sync_inbox'), hasLength(2));
    expect(await db.query('sync_inbox_batches'), hasLength(1));
  });

  test(
      'atomic operation rolls back earlier valid members when a field is rejected',
      () async {
    final events = [
      atomicEvent('one', fields: {'title': 'one'}),
      atomicEvent('two', fields: {'title': 'two', 'password_hash': 'secret'})
    ];
    await expectLater(
        receiveAtomic(events), throwsA(isA<AtomicInboxBatchException>()));
    await expectAtomicRollback();
  });

  test(
      'atomic SQLite failure rolls back data and receipts then retries as a whole',
      () async {
    await db.execute(
        "CREATE TRIGGER fail_second BEFORE INSERT ON sync_items WHEN NEW.title='two' BEGIN SELECT RAISE(ABORT, 'test failure'); END");
    final events = [
      atomicEvent('one', fields: {'title': 'one'}),
      atomicEvent('two', fields: {'title': 'two'})
    ];
    await expectLater(
        receiveAtomic(events), throwsA(isA<AtomicInboxBatchException>()));
    await expectAtomicRollback();
    await db.execute('DROP TRIGGER fail_second');
    expect((await receiveAtomic(events)).applied, 2);
  });

  test(
      'missing dependency leaves no partial operation or deferred single member',
      () async {
    final events = [
      atomicEvent('one', fields: {'title': 'one'}),
      atomicEvent('child', table: 'sync_children', fields: {
        'title': 'child',
        'parent_id': 99
      }, relations: {
        'parent_id': {'table': 'sync_parents', 'uuid': testUuid('parent')}
      })
    ];
    await expectLater(
        receiveAtomic(events), throwsA(isA<AtomicInboxBatchException>()));
    await expectAtomicRollback();
    expect(await processor.retryDeferred(7), 0);
    await db.insert('sync_parents',
        {'uuid': testUuid('parent'), 'branch_id': 7, 'name': 'parent'});
    expect((await receiveAtomic(events)).applied, 2);
  });

  test('atomic conflict keeps local edit and rolls back other members',
      () async {
    await db.insert('sync_items', {
      'uuid': testUuid('local'),
      'branch_id': 7,
      'title': 'newer local',
      'sync_version': 2,
      'sync_status': 'LOCAL'
    });
    final events = [
      atomicEvent('one', fields: {'title': 'one'}),
      atomicEvent('local', fields: {'title': 'remote'})
    ];
    await expectLater(
        receiveAtomic(events), throwsA(isA<AtomicInboxBatchException>()));
    expect((await db.query('sync_items')).single['title'], 'newer local');
    expect(await db.query('sync_inbox'), isEmpty);
    expect(await db.query('sync_inbox_batches'), isEmpty);
  });

  test('operation identity cannot be reused with changed content', () async {
    final original = [
      atomicEvent('one', fields: {'title': 'one'})
    ];
    await receiveAtomic(original);
    final modified = [
      atomicEvent('one', fields: {'title': 'changed'})
    ];
    await expectLater(receiveAtomic(modified), throwsStateError);
    expect((await db.query('sync_items')).single['title'], 'one');
  });

  test('atomic group cannot adopt members previously applied independently',
      () async {
    final first = atomicEvent('one', fields: {'title': 'one'});
    await receive(first);
    final events = [
      first,
      atomicEvent('two', fields: {'title': 'two'})
    ];
    await expectLater(
        receiveAtomic(events), throwsA(isA<AtomicInboxBatchException>()));
    expect(await db.query('sync_items'), hasLength(1));
    expect(await db.query('sync_inbox_batches'), hasLength(1));
  });

  test('duplicate members and reserved namespace are rejected', () async {
    final first = atomicEvent('one', fields: {'title': 'one'});
    expect(() => receiveAtomic([first, first]),
        throwsA(isA<AtomicInboxBatchException>()));
    expect(
        () => processor.processBatch(
            branchId: 7,
            batchUuid: 'atomic-v1:$operationUuid',
            payloadHash: batchFingerprint([first]),
            events: [first]),
        throwsA(isA<AtomicInboxBatchException>()));
    await expectAtomicRollback();
  });

  test('atomic mode does not enable production financial tables', () async {
    final events = [
      atomicEvent('journal', table: 'journal_entries', fields: {})
    ];
    await expectLater(
        receiveAtomic(events, using: FirestoreInboxProcessor(database: db)),
        throwsA(isA<AtomicInboxBatchException>()));
    await expectAtomicRollback();
  });

  test('missing receipt member is not reinserted during atomic replay',
      () async {
    final events = [
      atomicEvent('one', fields: {'title': 'one'}),
      atomicEvent('two', fields: {'title': 'two'})
    ];
    await receiveAtomic(events);
    await db.delete('sync_inbox',
        where: 'row_uuid=?', whereArgs: [testUuid('two')]);
    await db
        .delete('sync_items', where: 'uuid=?', whereArgs: [testUuid('two')]);
    await expectLater(
        receiveAtomic(events), throwsA(isA<AtomicInboxBatchException>()));
    expect(await db.query('sync_items'), hasLength(1));
    expect(await db.query('sync_inbox'), hasLength(1));
  });

  test(
      'production policy rejects an existing unlisted table before storing payload',
      () async {
    final incoming = event(
        table: 'sync_items',
        uuid: testUuid('blocked'),
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
          uuid: testUuid(field),
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
      {'title': 'ok', 'uuid': testUuid('wrong')},
      {'title': 'ok', 'sync_version': 99},
    ];
    for (var i = 0; i < payloads.length; i++) {
      final incoming = event(
          table: 'sync_items',
          uuid: testUuid('item-$i'),
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
        'private_owner_id': {'table': 'sync_parents', 'uuid': testUuid('p')}
      },
      {
        'title': {'table': 'sync_parents', 'uuid': testUuid('p')}
      },
      {
        'branch_id': {'table': 'sync_parents', 'uuid': testUuid('p')}
      },
      {
        'parent_id': {'table': 'users', 'uuid': testUuid('p')}
      },
      {
        'parent_id': {
          'table': 'sync_parents',
          'uuid': testUuid('p'),
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
          uuid: testUuid('c-$i'),
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
    final invalid = event(
        table: 'sync_items',
        uuid: testUuid('invalid'),
        version: 1,
        payload: {
          'title': 'bad',
          '__relations': {'secret': 'PRIVATE_SENTINEL'}
        });
    expect((await receive(invalid)).rejected, 1);
    final valid = event(
        table: 'sync_items',
        uuid: testUuid('valid'),
        version: 1,
        payload: {'title': 'ok', '__relations': {}});
    expect((await receive(valid, batch: 'valid-batch')).applied, 1);
    expect((await receive(valid, batch: 'valid-batch')).duplicates, 1);
  });

  test('invalid replay cannot change an already applied inbox record',
      () async {
    final valid = event(
        table: 'sync_items',
        uuid: testUuid('same'),
        version: 1,
        payload: {'title': 'valid'});
    expect((await receive(valid, batch: 'original')).applied, 1);
    final forged = event(
        table: 'sync_items',
        uuid: testUuid('same'),
        version: 1,
        payload: {'title': 'forged', 'password_hash': 'PRIVATE_SENTINEL'});
    expect((await receive(forged, batch: 'forged')).rejected, 1);
    expect((await db.query('sync_inbox')).single['status'], 'APPLIED');
    expect((await db.query('sync_items')).single['title'], 'valid');
  });

  test('update and soft delete keep excluded local fields unchanged', () async {
    await db.execute('ALTER TABLE sync_items ADD COLUMN private_note TEXT');
    await db.insert('sync_items', {
      'uuid': testUuid('local'),
      'branch_id': 7,
      'sync_version': 1,
      'sync_status': 'SYNCED',
      'title': 'old',
      'private_note': 'LOCAL_ONLY'
    });
    final update = event(
        table: 'sync_items',
        uuid: testUuid('local'),
        version: 2,
        operation: 'UPDATE',
        payload: {'title': 'new'});
    expect((await receive(update)).applied, 1);
    final deletion = event(
        table: 'sync_items',
        uuid: testUuid('local'),
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
    final incoming = event(
        table: 'sync_children',
        uuid: testUuid('child'),
        version: 1,
        payload: {
          'title': 'child',
          'parent_id': 3
        },
        relations: {
          'parent_id': {'table': 'sync_parents', 'uuid': testUuid('missing')}
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
      uuid: testUuid('item-1'),
      version: 1,
      payload: {
        'uuid': testUuid('item-1'),
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
      uuid: testUuid('parent-global-1'),
      version: 1,
      payload: {
        'uuid': testUuid('parent-global-1'),
        'branch_id': 7,
        'sync_version': 1,
        'sync_status': 'SYNCED',
        'name': 'parent',
      },
    );
    final child = event(
      table: 'sync_children',
      uuid: testUuid('child-global-1'),
      version: 1,
      payload: {
        'uuid': testUuid('child-global-1'),
        'branch_id': 7,
        'sync_version': 1,
        'sync_status': 'SYNCED',
        'parent_id': 99999,
        'title': 'child',
      },
      relations: {
        'parent_id': {
          'table': 'sync_parents',
          'uuid': testUuid('parent-global-1')
        },
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
      uuid: testUuid('child-waiting'),
      version: 1,
      payload: {
        'uuid': testUuid('child-waiting'),
        'branch_id': 7,
        'sync_version': 1,
        'sync_status': 'SYNCED',
        'parent_id': 555,
        'title': 'waiting child',
      },
      relations: {
        'parent_id': {'table': 'sync_parents', 'uuid': testUuid('parent-late')},
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
      uuid: testUuid('parent-late'),
      version: 1,
      payload: {
        'uuid': testUuid('parent-late'),
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
      uuid: testUuid('foreign-item'),
      version: 1,
      payload: {
        'uuid': testUuid('foreign-item'),
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
      'uuid': testUuid('item-local'),
      'branch_id': 7,
      'sync_version': 2,
      'sync_status': 'LOCAL',
      'title': 'local-newer',
    });
    final incoming = event(
      table: 'sync_items',
      uuid: testUuid('item-local'),
      version: 1,
      payload: {
        'uuid': testUuid('item-local'),
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
      uuid: testUuid('item-2'),
      version: 1,
      payload: {
        'uuid': testUuid('item-2'),
        'branch_id': 7,
        'sync_version': 1,
        'sync_status': 'SYNCED',
        'is_deleted': 0,
        'title': 'one',
      },
    );
    final tampered = event(
      table: 'sync_items',
      uuid: testUuid('item-3'),
      version: 1,
      payload: {
        'uuid': testUuid('item-3'),
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
