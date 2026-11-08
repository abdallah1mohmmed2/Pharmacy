import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:global_enterprise_pharmacy_erp/data/database/database_helper.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration11.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/firestore_sync_worker.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/backup_and_sync_service.dart';

const _branchUuid = '6a52f3a1-1e47-4a6d-9c10-5f8b2d3e4a70';
const _rowUuid = 'a1b2c3d4-e5f6-4789-8123-456789abcdef';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
      'legacy HTTP upload filters queued secrets and rejects a forbidden table',
      () async {
    final source = await _Device.open();
    addTearDown(source.dispose);
    await source.db.execute('''CREATE TABLE audit_logs (
      id INTEGER PRIMARY KEY, event_at TEXT, user_id INTEGER, branch_id INTEGER,
      device_id TEXT, action TEXT, entity_type TEXT, entity_id INTEGER,
      entity_label TEXT, old_values_json TEXT, new_values_json TEXT, reason TEXT,
      severity TEXT, prev_hash TEXT, row_hash TEXT)''');
    for (final table in ['drugs', 'users']) {
      await source.db.insert('sync_queue', {
        'table_name': table,
        'row_uuid': _rowUuid,
        'operation': 'UPSERT',
        'sync_version': 1,
        'status': 'PENDING',
        'payload_json': jsonEncode({
          'uuid': _rowUuid,
          'branch_id': 1,
          'trade_name_ar': 'دواء',
          'password_hash': 'PRIVATE_SENTINEL',
        }),
      });
    }
    var requests = 0;
    final service = BackupAndSyncService(
      helper: source.helper,
      client: MockClient((request) async {
        requests++;
        expect(request.body, isNot(contains('PRIVATE_SENTINEL')));
        final items = (jsonDecode(request.body) as Map)['items'] as List;
        expect(items, hasLength(1));
        expect((items.single as Map)['table'], 'drugs');
        return http.Response(
            jsonEncode({
              'results': [
                {'id': (items.single as Map)['id'], 'status': 'DONE'},
              ]
            }),
            200);
      }),
    );
    await service.syncNow(baseUrl: 'https://example.test');
    expect(requests, 1);
    final rows = await source.db.query('sync_queue', orderBy: 'id');
    expect(rows[0]['status'], 'DONE');
    expect(rows[1]['status'], 'CONFLICT');
    expect(rows[1]['last_error'], 'SYNC_PAYLOAD_POLICY_REJECTED');
  });

  test(
      'outbound projection protects old queued payloads without changing local data',
      () async {
    final source = await _Device.open(seedLocalItem: true);
    final server = _FakeFirestore();
    addTearDown(source.dispose);
    await source.db
        .execute('ALTER TABLE sync_items ADD COLUMN password_hash TEXT');
    await source.db.update('sync_items', {'password_hash': 'PRIVATE_SENTINEL'});
    final result = await _worker(source, server).syncOnce(
      branchId: source.branchId,
      projectId: 'pharmacy-emulator-test',
      idToken: 'test-token',
    );
    expect(result.uploadedEvents, 1);
    expect(jsonEncode(server.document), isNot(contains('PRIVATE_SENTINEL')));
    expect((await source.db.query('sync_items')).single['password_hash'],
        'PRIVATE_SENTINEL');
  });

  test('structured value in allowed field is quarantined before upload',
      () async {
    final source = await _Device.open(seedLocalItem: true);
    final server = _FakeFirestore();
    addTearDown(source.dispose);
    await source.db
        .update('sync_items', {'title': '{"token":"PRIVATE_SENTINEL"}'});
    final result = await _worker(source, server).syncOnce(
      branchId: source.branchId,
      projectId: 'pharmacy-emulator-test',
      idToken: 'test-token',
    );
    expect(result.uploadedEvents, 0);
    expect(server.document, isNull);
    final row = (await source.db.query('sync_queue')).single;
    expect(row['status'], 'CONFLICT');
    expect(row['last_error'], 'SYNC_PAYLOAD_POLICY_REJECTED');
  });

  test('uploads from device A, receives on device B, and safely replays',
      () async {
    final source = await _Device.open(seedLocalItem: true);
    final target = await _Device.open();
    final server = _FakeFirestore();
    addTearDown(() async {
      await source.dispose();
      await target.dispose();
    });

    final upload = await _worker(source, server).syncOnce(
      branchId: source.branchId,
      projectId: 'pharmacy-emulator-test',
      idToken: 'test-token',
    );
    expect(upload.uploadedEvents, 1);
    expect(source.deviceId, isNot(target.deviceId));
    expect(
      ((server.document!['fields'] as Map)['source_device_id']
          as Map)['stringValue'],
      source.deviceId,
    );
    expect((await source.db.query('sync_queue')).single['status'], 'DONE');
    expect(
        (await source.db.query('sync_items')).single['sync_status'], 'SYNCED');

    server.serveDocuments = true;
    final receive = await _worker(target, server).syncOnce(
      branchId: target.branchId,
      projectId: 'pharmacy-emulator-test',
      idToken: 'test-token',
    );
    expect(receive.receivedEvents, 1);
    final receivedRow = (await target.db.query('sync_items')).single;
    expect(receivedRow['uuid'], _rowUuid);
    expect(receivedRow['branch_id'], target.branchId);
    expect(receivedRow['title'], 'سجل صادر من الجهاز الأول');
    expect(receivedRow['sync_status'], 'SYNCED');

    await _worker(target, server).syncOnce(
      branchId: target.branchId,
      projectId: 'pharmacy-emulator-test',
      idToken: 'test-token',
    );
    expect(await target.db.query('sync_items'), hasLength(1));
    expect(await target.db.query('sync_inbox'), hasLength(1));
    expect(await target.db.query('sync_inbox_batches'), hasLength(1));
    expect((await target.db.query('sync_inbox')).single['status'], 'APPLIED');
  });

  test('rejects an event whose payload names a different branch', () async {
    final source = await _Device.open(seedLocalItem: true);
    final target = await _Device.open();
    final server = _FakeFirestore();
    addTearDown(() async {
      await source.dispose();
      await target.dispose();
    });

    await _worker(source, server).syncOnce(
      branchId: source.branchId,
      projectId: 'pharmacy-emulator-test',
      idToken: 'test-token',
    );
    server.rewriteFirstEventBranch('7b63f4a2-2f58-4b7e-8d21-6a9c3e4f5b81');
    server.serveDocuments = true;

    await _worker(target, server).syncOnce(
      branchId: target.branchId,
      projectId: 'pharmacy-emulator-test',
      idToken: 'test-token',
    );

    expect(await target.db.query('sync_items'), isEmpty);
    expect((await target.db.query('sync_inbox')).single['status'], 'FAILED');
  });

  test('retains the local outbox row through a network outage and resumes',
      () async {
    final source = await _Device.open(seedLocalItem: true);
    final server = _FakeFirestore()..offline = true;
    addTearDown(source.dispose);

    await expectLater(
      _worker(source, server).syncOnce(
        branchId: source.branchId,
        projectId: 'pharmacy-emulator-test',
        idToken: 'test-token',
      ),
      throwsA(isA<SocketException>()),
    );
    expect(
        (await source.db.query('sync_items')).single['sync_status'], 'QUEUED');
    final failedQueue = (await source.db.query('sync_queue')).single;
    expect(failedQueue['status'], 'FAILED');
    expect(failedQueue['last_error'], isNotNull);

    server.offline = false;
    final resumed = await _worker(source, server).syncOnce(
      branchId: source.branchId,
      projectId: 'pharmacy-emulator-test',
      idToken: 'test-token',
    );
    expect(resumed.uploadedEvents, 1);
    expect((await source.db.query('sync_queue')).single['status'], 'DONE');
    expect(
        (await source.db.query('sync_items')).single['sync_status'], 'SYNCED');
  });

  test('retries a failed local SQLite write without losing the remote event',
      () async {
    final source = await _Device.open(seedLocalItem: true);
    final target = await _Device.open();
    final server = _FakeFirestore();
    addTearDown(() async {
      await source.dispose();
      await target.dispose();
    });

    await _worker(source, server).syncOnce(
      branchId: source.branchId,
      projectId: 'pharmacy-emulator-test',
      idToken: 'test-token',
    );
    server.serveDocuments = true;
    await target.db.execute('''
      CREATE TRIGGER reject_sync_item_insert
      BEFORE INSERT ON sync_items
      BEGIN SELECT RAISE(ABORT, 'simulated local disk write failure'); END
    ''');

    await _worker(target, server).syncOnce(
      branchId: target.branchId,
      projectId: 'pharmacy-emulator-test',
      idToken: 'test-token',
    );
    expect(await target.db.query('sync_items'), isEmpty);
    expect((await target.db.query('sync_inbox')).single['status'], 'FAILED');

    await target.db.execute('DROP TRIGGER reject_sync_item_insert');
    await _worker(target, server).syncOnce(
      branchId: target.branchId,
      projectId: 'pharmacy-emulator-test',
      idToken: 'test-token',
    );

    expect((await target.db.query('sync_items')).single['uuid'], _rowUuid);
    expect((await target.db.query('sync_inbox')).single['status'], 'APPLIED');
    expect(await target.db.query('sync_inbox_batches'), hasLength(1));
  });

  test(
      'rolls back a failed inbox transaction and replays the untouched remote batch',
      () async {
    final source = await _Device.open(seedLocalItem: true);
    final target = await _Device.open();
    final server = _FakeFirestore();
    addTearDown(() async {
      await source.dispose();
      await target.dispose();
    });

    await _worker(source, server).syncOnce(
      branchId: source.branchId,
      projectId: 'pharmacy-emulator-test',
      idToken: 'test-token',
    );
    server.serveDocuments = true;
    await target.db.execute('''
      CREATE TRIGGER reject_batch_finalize
      BEFORE UPDATE ON sync_inbox_batches
      BEGIN SELECT RAISE(ABORT, 'simulated transaction finalization failure'); END
    ''');

    await expectLater(
      _worker(target, server).syncOnce(
        branchId: target.branchId,
        projectId: 'pharmacy-emulator-test',
        idToken: 'test-token',
      ),
      throwsA(anything),
    );
    expect(await target.db.query('sync_items'), isEmpty);
    expect(await target.db.query('sync_inbox'), isEmpty);
    expect(await target.db.query('sync_inbox_batches'), isEmpty);
    expect(await target.db.query('sync_inbox_cursors'), isEmpty);

    await target.db.execute('DROP TRIGGER reject_batch_finalize');
    await _worker(target, server).syncOnce(
      branchId: target.branchId,
      projectId: 'pharmacy-emulator-test',
      idToken: 'test-token',
    );
    expect((await target.db.query('sync_items')).single['uuid'], _rowUuid);
    expect((await target.db.query('sync_inbox')).single['status'], 'APPLIED');
    expect(await target.db.query('sync_inbox_batches'), hasLength(1));
  });

  test(
    'transfers between isolated SQLite devices through Firestore Emulator',
    () async {
      final host = Platform.environment['FIRESTORE_EMULATOR_HOST']!;
      final source = await _Device.open(seedLocalItem: true);
      final target = await _Device.open();
      final sourceClient = http.Client();
      final targetClient = http.Client();
      addTearDown(() async {
        sourceClient.close();
        targetClient.close();
        await source.dispose();
        await target.dispose();
      });

      final sourceResult = await FirestoreSyncWorker(
        helper: source.helper,
        client: sourceClient,
        emulatorHost: host,
        deviceIdProvider: () async => source.deviceId,
        allowedTablesForTesting: {'sync_items'},
        payloadFieldsForTesting: {
          'sync_items': {'title'}
        },
      ).syncOnce(
        branchId: source.branchId,
        projectId: 'pharmacy-dafb6',
        idToken: 'owner',
      );
      expect(sourceResult.uploadedEvents, 1);

      final targetResult = await FirestoreSyncWorker(
        helper: target.helper,
        client: targetClient,
        emulatorHost: host,
        deviceIdProvider: () async => target.deviceId,
        allowedTablesForTesting: {'sync_items'},
        payloadFieldsForTesting: {
          'sync_items': {'title'}
        },
      ).syncOnce(
        branchId: target.branchId,
        projectId: 'pharmacy-dafb6',
        idToken: 'owner',
      );
      expect(targetResult.receivedEvents, greaterThanOrEqualTo(1));
      expect((await target.db.query('sync_items')).single['uuid'], _rowUuid);
      expect(
        (await target.db.query('sync_items')).single['title'],
        'سجل صادر من الجهاز الأول',
      );
    },
    skip: Platform.environment['FIRESTORE_EMULATOR_HOST'] == null,
  );
}

FirestoreSyncWorker _worker(_Device device, _FakeFirestore server) =>
    FirestoreSyncWorker(
      helper: device.helper,
      client: server.client(),
      emulatorHost: 'http://127.0.0.1:8080',
      deviceIdProvider: () async => device.deviceId,
      allowedTablesForTesting: {'sync_items'},
      payloadFieldsForTesting: {
        'sync_items': {'title'}
      },
    );

class _Device {
  _Device(this.directory, this.db, this.deviceId)
      : helper = DatabaseHelper.forTesting(db);

  static int _nextDeviceNumber = 0;
  final Directory directory;
  final Database db;
  final String deviceId;
  final DatabaseHelper helper;
  int get branchId => 1;

  static Future<_Device> open({bool seedLocalItem = false}) async {
    final directory =
        await Directory.systemTemp.createTemp('pharmacy-sync-device-');
    final db = await databaseFactoryFfi.openDatabase(
      directory.path + '/pharmacy.db',
    );
    await db.execute('''
      CREATE TABLE branches (
        id INTEGER PRIMARY KEY,
        uuid TEXT NOT NULL UNIQUE
      )
    ''');
    await db.execute('''
      CREATE TABLE sync_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        branch_id INTEGER NOT NULL,
        sync_version INTEGER NOT NULL DEFAULT 1,
        sync_status TEXT NOT NULL DEFAULT 'LOCAL',
        is_deleted INTEGER NOT NULL DEFAULT 0,
        title TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT NOT NULL,
        row_uuid TEXT NOT NULL,
        operation TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        sync_version INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'PENDING',
        attempts INTEGER NOT NULL DEFAULT 0,
        last_error TEXT
      )
    ''');
    await SchemaIteration11.upgrade(db);
    await db.insert('branches', {'id': 1, 'uuid': _branchUuid});
    if (seedLocalItem) {
      await db.insert('sync_items', {
        'uuid': _rowUuid,
        'branch_id': 1,
        'sync_version': 1,
        'sync_status': 'LOCAL',
        'is_deleted': 0,
        'title': 'سجل صادر من الجهاز الأول',
      });
    }
    final serial = (++_nextDeviceNumber).toString().padLeft(12, '0');
    final deviceId = '00000000-0000-4000-8000-$serial';
    return _Device(directory, db, deviceId);
  }

  Future<void> dispose() async {
    await helper.close();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

class _FakeFirestore {
  Map<String, Object?>? document;
  bool serveDocuments = false;
  bool offline = false;

  http.Client client() => MockClient((request) async {
        if (request.method == 'POST' &&
            request.url.path.endsWith('/documents:commit')) {
          if (offline) throw const SocketException('simulated network outage');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final write = (body['writes'] as List).single as Map<String, dynamic>;
          final update = write['update'] as Map<String, dynamic>;
          final fields = Map<String, Object?>.from(
            update['fields'] as Map,
          );
          fields['created_at'] = {
            'timestampValue': '2026-11-08T12:00:00.000Z',
          };
          document = {
            'name': update['name'],
            'fields': fields,
          };
          return _jsonResponse('{}', 200);
        }
        if (request.method == 'POST' &&
            request.url.path.contains(':runQuery')) {
          if (!serveDocuments || document == null) {
            return _jsonResponse('[]', 200);
          }
          return _jsonResponse(
            jsonEncode([
              {'document': document}
            ]),
            200,
          );
        }
        return _jsonResponse('{}', 404);
      });

  void rewriteFirstEventBranch(String branchUuid) {
    final fields = document!['fields'] as Map<String, Object?>;
    final events = _decodeValue(fields['events'] as Map) as List;
    final first = Map<String, Object?>.from(events.single as Map);
    final payload = Map<String, Object?>.from(first['payload'] as Map);
    payload['branch_id'] = branchUuid;
    first['payload'] = payload;
    final rewritten = [first];
    fields['events'] = _encodeValue(rewritten);
    fields['payload_hash'] = {
      'stringValue': sha256
          .convert(utf8.encode(jsonEncode(_canonicalize(rewritten))))
          .toString(),
    };
  }
}

Object? _decodeValue(Map value) {
  if (value.containsKey('stringValue')) return value['stringValue'];
  if (value.containsKey('timestampValue')) return value['timestampValue'];
  if (value.containsKey('integerValue')) {
    return int.parse(value['integerValue'].toString());
  }
  if (value.containsKey('doubleValue')) return value['doubleValue'];
  if (value.containsKey('booleanValue')) return value['booleanValue'];
  if (value.containsKey('nullValue')) return null;
  if (value.containsKey('arrayValue')) {
    final values = (value['arrayValue'] as Map)['values'] as List? ?? const [];
    return values.map((entry) => _decodeValue(entry as Map)).toList();
  }
  if (value.containsKey('mapValue')) {
    final fields = (value['mapValue'] as Map)['fields'] as Map? ?? const {};
    return fields.map(
      (key, entry) => MapEntry(key.toString(), _decodeValue(entry as Map)),
    );
  }
  return null;
}

Object? _encodeValue(Object? value) {
  if (value == null) return {'nullValue': null};
  if (value is bool) return {'booleanValue': value};
  if (value is int) return {'integerValue': value.toString()};
  if (value is num) return {'doubleValue': value.toDouble()};
  if (value is String) return {'stringValue': value};
  if (value is List) {
    return {
      'arrayValue': {'values': value.map(_encodeValue).toList()}
    };
  }
  if (value is Map) {
    return {
      'mapValue': {
        'fields': value.map(
          (key, entry) => MapEntry(key.toString(), _encodeValue(entry)),
        )
      }
    };
  }
  throw ArgumentError.value(value, 'value', 'Unsupported Firestore test value');
}

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return {
      for (final key in keys) key: _canonicalize(value[key]),
    };
  }
  if (value is List) return value.map(_canonicalize).toList();
  return value;
}

http.Response _jsonResponse(String body, int statusCode) => http.Response(
      body,
      statusCode,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
