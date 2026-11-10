import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../database/global_uuid.dart';
import 'backup_and_sync_service.dart';
import 'sync_inbox_processor.dart';
import 'device_identity_service.dart';
import 'sync_table_policy.dart';
import 'sync_payload_policy.dart';

/// Firestore REST worker. Authentication is deliberately injected: callers
/// must supply a Firebase ID token issued for the signed-in branch account.
class FirestoreSyncWorker {
  FirestoreSyncWorker({
    DatabaseHelper? helper,
    http.Client? client,
    FirestoreInboxProcessor? inbox,
    String? emulatorHost,
    Future<String> Function()? deviceIdProvider,
    Set<String>? allowedTablesForTesting,
    Map<String, Set<String>>? payloadFieldsForTesting,
  })  : _payloadFieldsForTesting = payloadFieldsForTesting,
        _deviceIdProvider = deviceIdProvider ??
            DeviceIdentityService.instance.getOrCreateDeviceId,
        _emulatorHost = emulatorHost ??
            const String.fromEnvironment('FIRESTORE_EMULATOR_HOST'),
        _helper = helper ?? DatabaseHelper.instance,
        _client = client ?? http.Client(),
        _inbox = inbox ??
            FirestoreInboxProcessor(
              helper: helper,
              allowedTablesForTesting: allowedTablesForTesting,
              payloadFieldsForTesting: payloadFieldsForTesting,
            ),
        _allowedTables =
            allowedTablesForTesting ?? SyncTablePolicy.outboundTables;

  final Future<String> Function() _deviceIdProvider;
  final String _emulatorHost;
  final DatabaseHelper _helper;
  final http.Client _client;
  final FirestoreInboxProcessor _inbox;
  final Set<String> _allowedTables;
  final Map<String, Set<String>>? _payloadFieldsForTesting;

  /// Reads setting 35 and executes one upload/download cycle. The caller
  /// supplies a Firebase ID token from an authenticated Firebase user.
  Future<FirestoreSyncResult> syncConfigured({
    required int branchId,
    required String idToken,
  }) async {
    final rows = await _helper.query('system_settings',
        where: 'setting_no=?', whereArgs: [35], limit: 1);
    if (rows.isEmpty) throw StateError('إعداد المزامنة رقم 35 غير موجود');
    final config = jsonDecode(rows.first['setting_value'] as String);
    if (config is! Map || config['enabled'] != true) {
      throw StateError('المزامنة السحابية غير مفعّلة في الإعداد 35');
    }
    if ((config['provider'] ?? 'firestore') != 'firestore') {
      throw StateError('مزود المزامنة المحدد غير مدعوم');
    }
    final projectId = config['project_id']?.toString().trim() ?? '';
    if (projectId.isEmpty) {
      throw StateError('أدخل Firebase project_id في الإعداد 35');
    }
    return syncOnce(
      branchId: branchId,
      projectId: projectId,
      databaseId: config['database_id']?.toString() ?? '(default)',
      batchSize: (config['batch_size'] as num?)?.toInt() ?? 100,
      idToken: idToken,
    );
  }

  /// Performs a real authenticated Firestore query against the active
  /// branch's append-only batch collection. An empty result is still a
  /// successful connectivity and Security Rules check.
  Future<void> testConnection({
    required int branchId,
    required String projectId,
    required String idToken,
    String databaseId = '(default)',
  }) async {
    if (branchId <= 0 || projectId.trim().isEmpty || idToken.trim().isEmpty) {
      throw ArgumentError('بيانات فحص اتصال Firestore غير مكتملة');
    }
    final db = await _helper.database;
    final branchUuid = await _branchUuid(db, branchId);
    final uri = _firestoreUri(
      '/v1/projects/$projectId/databases/$databaseId/documents/pharmacy_sync_batches/$branchUuid:runQuery',
    );
    final response = await _client
        .post(
          uri,
          headers: _headers(idToken),
          body: jsonEncode({
            'structuredQuery': {
              'from': [
                {'collectionId': 'batches'}
              ],
              'where': {
                'fieldFilter': {
                  'field': {'fieldPath': 'branch_id'},
                  'op': 'EQUAL',
                  'value': {'stringValue': branchUuid},
                }
              },
              'limit': 1,
            }
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Firestore connection check HTTP ${response.statusCode}: ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const FormatException('استجابة فحص Firestore غير صالحة');
    }
  }

  Future<FirestoreSyncResult> syncOnce({
    required int branchId,
    required String projectId,
    required String idToken,
    int batchSize = 100,
    String databaseId = '(default)',
  }) async {
    if (branchId <= 0) throw ArgumentError('معرّف الفرع غير صالح');
    if (projectId.trim().isEmpty)
      throw ArgumentError('Firebase project_id مطلوب');
    if (idToken.trim().isEmpty) throw ArgumentError('Firebase ID token مطلوب');
    if (batchSize < 1 || batchSize > 100) {
      throw RangeError.range(batchSize, 1, 100, 'batchSize');
    }

    final db = await _helper.database;
    final branchUuid = await _branchUuid(db, branchId);
    final sourceDeviceId = await _deviceIdProvider();
    if (!DeviceIdentityService.isValidDeviceId(sourceDeviceId)) {
      throw StateError('معرّف الجهاز المحلي غير صالح؛ أوقفت المزامنة.');
    }
    await db.update('sync_queue', {'status': 'PENDING'},
        where: "status='SENDING'");
    await BackupAndSyncService(
      helper: _helper,
      client: _client,
      allowedTablesForTesting: _allowedTables,
    ).collectLocalChanges(maxRows: batchSize * 10);

    final pending = await _branchPending(db, branchId, batchSize);
    var uploaded = 0;
    if (pending.isNotEmpty) {
      final batch = await _buildBatch(db, branchId, branchUuid, pending);
      if (batch.items.isNotEmpty) {
        await db.transaction((txn) async {
          final ids = batch.queueIds;
          await txn.update('sync_queue', {'status': 'SENDING'},
              where: 'id IN (${List.filled(ids.length, '?').join(',')})',
              whereArgs: ids);
        });
        try {
          await _createBatchDocument(
            projectId: projectId,
            databaseId: databaseId,
            branchId: branchId,
            branchUuid: branchUuid,
            sourceDeviceId: sourceDeviceId,
            idToken: idToken,
            batch: batch,
          );
          await db.transaction((txn) async {
            for (final item in batch.items) {
              await txn.update(
                'sync_queue',
                {'status': 'DONE', 'last_error': null},
                where: 'id=?',
                whereArgs: [item.queueId],
              );
              await txn.update(
                item.tableName,
                {'sync_status': 'SYNCED'},
                where: 'uuid=? AND sync_version<=?',
                whereArgs: [item.rowUuid, item.version],
              );
            }
          });
          uploaded = batch.items.length;
        } catch (error) {
          await db.update(
            'sync_queue',
            {'status': 'FAILED', 'attempts': 1, 'last_error': error.toString()},
            where:
                'id IN (${List.filled(batch.queueIds.length, '?').join(',')})',
            whereArgs: batch.queueIds,
          );
          rethrow;
        }
      }
    }

    final received = await pullInbox(
      branchId: branchId,
      branchUuid: branchUuid,
      projectId: projectId,
      idToken: idToken,
      databaseId: databaseId,
    );
    await _inbox.retryDeferred(branchId);
    return FirestoreSyncResult(
        uploadedEvents: uploaded, receivedEvents: received);
  }

  Future<int> pullInbox({
    required int branchId,
    required String branchUuid,
    required String projectId,
    required String idToken,
    String databaseId = '(default)',
    int pageSize = 100,
  }) async {
    final db = await _helper.database;
    final cursorRows = await db.query(
      'sync_inbox_cursors',
      where: 'branch_id=?',
      whereArgs: [branchId],
      limit: 1,
    );
    var lastCreatedAt = cursorRows.isEmpty
        ? ''
        : cursorRows.first['page_token']?.toString() ?? '';
    var lastDocumentName = cursorRows.isEmpty
        ? ''
        : cursorRows.first['last_document_name']?.toString() ?? '';
    var processed = 0;
    while (true) {
      final structuredQuery = <String, Object?>{
        'from': [
          {'collectionId': 'batches'}
        ],
        'where': {
          'fieldFilter': {
            'field': {'fieldPath': 'branch_id'},
            'op': 'EQUAL',
            'value': {'stringValue': branchUuid},
          }
        },
        'orderBy': [
          {
            'field': {'fieldPath': 'created_at'},
            'direction': 'ASCENDING'
          },
          {
            'field': {'fieldPath': '__name__'},
            'direction': 'ASCENDING'
          }
        ],
        'limit': pageSize,
      };
      if (lastCreatedAt.isNotEmpty && lastDocumentName.isNotEmpty) {
        structuredQuery['startAt'] = {
          'values': [
            {'timestampValue': lastCreatedAt},
            {'referenceValue': lastDocumentName},
          ],
          'before': false,
        };
      }
      final uri = _firestoreUri(
        '/v1/projects/$projectId/databases/$databaseId/documents/pharmacy_sync_batches/$branchUuid:runQuery',
      );
      final response = await _client
          .post(uri,
              headers: _headers(idToken),
              body: jsonEncode({'structuredQuery': structuredQuery}))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
            'Firestore inbox HTTP ${response.statusCode}: ${response.body}');
      }
      final rawResults = jsonDecode(response.body) as List;
      final documents = rawResults
          .whereType<Map>()
          .map((entry) => entry['document'])
          .whereType<Map>()
          .toList();
      if (documents.isEmpty) break;
      for (final raw in documents) {
        final fields = _decodeFields(raw['fields'] as Map? ?? const {});
        if (fields['branch_id']?.toString() != branchUuid) continue;
        final batchId = fields['batch_uuid']?.toString() ??
            (raw['name']?.toString().split('/').last ?? '');
        final events = fields['events'];
        if (batchId.isEmpty || events is! List) continue;
        final batchHash =
            fields['payload_hash']?.toString() ?? _hash(jsonEncode(events));
        await _inbox.processBatch(
          branchId: branchId,
          batchUuid: batchId,
          payloadHash: batchHash,
          expectedBranchUuid: branchUuid,
          events: events
              .whereType<Map>()
              .map((e) => Map<String, Object?>.from(e))
              .toList(),
        );
        processed += events.length;
        final createdAt = fields['created_at']?.toString() ?? '';
        final documentName = raw['name']?.toString() ?? '';
        if (createdAt.isNotEmpty && documentName.isNotEmpty) {
          lastCreatedAt = createdAt;
          lastDocumentName = documentName;
          await db.insert(
            'sync_inbox_cursors',
            {
              'branch_id': branchId,
              'page_token': lastCreatedAt,
              'last_document_name': lastDocumentName,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
      if (documents.length < pageSize) break;
    }
    return processed;
  }

  Future<String> _branchUuid(Database db, int branchId) async {
    final rows = await db.query('branches',
        columns: ['uuid'], where: 'id=?', whereArgs: [branchId], limit: 1);
    if (rows.isEmpty || rows.first['uuid'] == null) {
      throw StateError('لا يوجد UUID عالمي للفرع الحالي');
    }
    final uuid = rows.first['uuid'].toString();
    if (!GlobalUuid.isValid(uuid)) {
      throw StateError(
        'هوية الفرع ليست UUID عالمياً صالحاً؛ أوقف المزامنة حتى اكتمال ترحيل الهوية.',
      );
    }
    return uuid;
  }

  Future<List<Map<String, Object?>>> _branchPending(
      Database db, int branchId, int limit) async {
    final rows = await db.query(
      'sync_queue',
      where: "status IN ('PENDING','FAILED')",
      orderBy: 'id',
      limit: limit * 10,
    );
    final selected = <Map<String, Object?>>[];
    for (final row in rows) {
      final payload = jsonDecode(row['payload_json'] as String);
      if (payload is! Map) continue;
      final rowBranch = (payload['branch_id'] as num?)?.toInt();
      if (rowBranch != branchId) continue;
      selected.add(row);
      if (selected.length == limit) break;
    }
    return selected;
  }

  Future<_FirestoreBatch> _buildBatch(
    Database db,
    int branchId,
    String branchUuid,
    List<Map<String, Object?>> rows,
  ) async {
    final items = <_FirestoreEvent>[];
    for (final queueRow in rows) {
      final table = queueRow['table_name'] as String;
      if (!_safeIdentifier.hasMatch(table)) continue;
      final exists = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        [table],
      );
      if (exists.isEmpty) continue;
      if (!_allowedTables.contains(table)) {
        await db.update(
          'sync_queue',
          {
            'status': 'CONFLICT',
            'last_error': 'الجدول غير موجود في قائمة السماح للمزامنة الصادرة',
          },
          where: 'id=?',
          whereArgs: [queueRow['id']],
        );
        continue;
      }
      final columns = await db.rawQuery('PRAGMA table_info($table)');
      final names = columns.map((e) => e['name'].toString()).toSet();
      if (!{'uuid', 'branch_id', 'sync_version'}.every(names.contains))
        continue;
      final uuid = queueRow['row_uuid'] as String;
      // Never export a legacy/local identifier as a global row identity.
      // Existing UUIDs are preserved; unresolved rows require provisioning.
      if (!GlobalUuid.isValid(uuid)) {
        await db.update(
          'sync_queue',
          {
            'status': 'CONFLICT',
            'last_error': 'INVALID_GLOBAL_ROW_UUID',
          },
          where: 'id=?',
          whereArgs: [queueRow['id']],
        );
        continue;
      }
      final row =
          await db.query(table, where: 'uuid=?', whereArgs: [uuid], limit: 1);
      if (row.isEmpty) continue;
      final current = row.first;
      if ((current['branch_id'] as num?)?.toInt() != branchId) continue;
      final version = (queueRow['sync_version'] as num? ?? 1).toInt();
      late final Map<String, Object?> payload;
      try {
        payload = SyncPayloadPolicy.project(
          table,
          jsonDecode(queueRow['payload_json'] as String),
          fieldsForTesting: _payloadFieldsForTesting?[table],
        );
      } on FormatException {
        await db.update(
            'sync_queue',
            {
              'status': 'CONFLICT',
              'last_error': 'SYNC_PAYLOAD_POLICY_REJECTED',
            },
            where: 'id=?',
            whereArgs: [queueRow['id']]);
        continue;
      }
      payload['branch_id'] = branchUuid;
      payload['sync_version'] = version;
      payload['sync_status'] = 'SYNCED';
      // Historical warehouse/batch parents may deliberately have no trusted
      // UUID yet. Quarantine only this event; never infer a cross-device
      // identity from a local SQLite ID or block unrelated queue entries.
      late final Map<String, Object?> relations;
      try {
        relations =
            await _relationsForRow(db, table, current, payload.keys.toSet());
      } on FormatException catch (error) {
        await db.update(
          'sync_queue',
          {'status': 'CONFLICT', 'last_error': error.message},
          where: 'id=?',
          whereArgs: [queueRow['id']],
        );
        continue;
      } on StateError catch (error) {
        await db.update(
          'sync_queue',
          {'status': 'CONFLICT', 'last_error': error.message},
          where: 'id=?',
          whereArgs: [queueRow['id']],
        );
        continue;
      }
      payload['__relations'] = relations;
      final operation = queueRow['operation'] as String;
      final eventUuid = _hash('$table|$uuid|$version|$operation');
      items.add(_FirestoreEvent(
        queueId: queueRow['id'] as int,
        tableName: table,
        rowUuid: uuid,
        operation: operation,
        version: version,
        eventUuid: eventUuid,
        payload: payload,
        relations: relations,
      ));
    }
    if (items.isEmpty) return _FirestoreBatch.empty;
    final eventValues = items.map((e) => e.toMap()).toList();
    final fingerprint = _hash(_canonicalJson(eventValues));
    final batchUuid = _hash('$branchUuid|$fingerprint');
    return _FirestoreBatch(
      batchUuid: batchUuid,
      payloadHash: fingerprint,
      queueIds: items.map((e) => e.queueId).toList(),
      items: items,
    );
  }

  Future<Map<String, Object?>> _relationsForRow(
    Database db,
    String table,
    Map<String, Object?> row,
    Set<String> allowedColumns,
  ) async {
    final result = <String, Object?>{};
    final foreignKeys = await db.rawQuery('PRAGMA foreign_key_list($table)');
    for (final fk in foreignKeys) {
      final column = fk['from']?.toString();
      final parentTable = fk['table']?.toString();
      final value = column == null ? null : row[column];
      if (column == null ||
          parentTable == null ||
          value == null ||
          column == 'branch_id' ||
          !allowedColumns.contains(column)) continue;
      if (!_safeIdentifier.hasMatch(parentTable) ||
          !_allowedTables.contains(parentTable)) {
        throw const FormatException('SYNC_PAYLOAD_POLICY_REJECTED');
      }
      final parent = await db.query(parentTable,
          where: 'id=?', whereArgs: [value], limit: 1);
      if (parent.isEmpty ||
          parent.first['uuid'] is! String ||
          !GlobalUuid.isValid(parent.first['uuid'] as String)) {
        throw StateError('تعذر تحويل العلاقة $table.$column إلى UUID');
      }
      result[column] = {'table': parentTable, 'uuid': parent.first['uuid']};
    }
    return result;
  }

  Future<void> _createBatchDocument({
    required String projectId,
    required String databaseId,
    required int branchId,
    required String branchUuid,
    required String sourceDeviceId,
    required String idToken,
    required _FirestoreBatch batch,
  }) async {
    final documentName =
        'projects/$projectId/databases/$databaseId/documents/pharmacy_sync_batches/$branchUuid/batches/${batch.batchUuid}';
    final uri = _firestoreUri(
      '/v1/projects/$projectId/databases/$databaseId/documents:commit',
    );
    final fields = <String, Object?>{
      'branch_id': branchUuid,
      'source_device_id': sourceDeviceId,
      'batch_uuid': batch.batchUuid,
      'payload_hash': batch.payloadHash,
      'schema_version': 1,
      'events': batch.items.map((e) => e.toMap()).toList(),
    };
    final body = jsonEncode({
      'writes': [
        {
          'update': {
            'name': documentName,
            'fields': _encodeFields(fields),
          },
          'updateTransforms': [
            {
              'fieldPath': 'created_at',
              'setToServerValue': 'REQUEST_TIME',
            }
          ],
          'currentDocument': {'exists': false},
        }
      ]
    });
    if (utf8.encode(body).length > 850000) {
      throw StateError('حجم دفعة Firestore تجاوز الحد الآمن؛ قلل batch_size');
    }
    final response = await _client
        .post(uri, headers: _headers(idToken), body: body)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    if (response.statusCode == 409 || response.statusCode == 400) {
      final documentUri = _firestoreUri('/v1/$documentName');
      final verify = await _client
          .get(documentUri, headers: _headers(idToken))
          .timeout(const Duration(seconds: 20));
      if (verify.statusCode >= 200 && verify.statusCode < 300) {
        final remote = jsonDecode(verify.body) as Map<String, dynamic>;
        final remoteFields =
            _decodeFields(remote['fields'] as Map? ?? const {});
        if (remoteFields['payload_hash'] == batch.payloadHash) return;
        throw StateError('تعارض batch_uuid مع بصمة دفعة مختلفة');
      }
    }
    throw HttpException(
        'Firestore batch write HTTP ${response.statusCode}: ${response.body}');
  }

  Uri _firestoreUri(String path) {
    if (_emulatorHost.isNotEmpty) {
      final rawHost = _emulatorHost.contains('://')
          ? _emulatorHost
          : 'http://' + _emulatorHost;
      final normalizedHost = rawHost.endsWith('/')
          ? rawHost.substring(0, rawHost.length - 1)
          : rawHost;
      return Uri.parse(normalizedHost + path);
    }
    return Uri.https('firestore.googleapis.com', path);
  }

  Map<String, String> _headers(String token) => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  Map<String, Object?> _encodeFields(Map<String, Object?> fields) =>
      fields.map((key, value) => MapEntry(key, _encodeValue(value)));

  Map<String, Object?> _encodeValue(Object? value) {
    if (value == null) return {'nullValue': null};
    if (value is bool) return {'booleanValue': value};
    if (value is int) return {'integerValue': value.toString()};
    if (value is double) return {'doubleValue': value};
    if (value is num) return {'doubleValue': value.toDouble()};
    if (value is String) return {'stringValue': value};
    if (value is List) {
      return {
        'arrayValue': {'values': value.map(_encodeValue).toList()}
      };
    }
    if (value is Map) {
      return {
        'mapValue': {'fields': _encodeFields(Map<String, Object?>.from(value))}
      };
    }
    return {'stringValue': value.toString()};
  }

  Map<String, Object?> _decodeFields(Map fields) => fields.map(
      (key, value) => MapEntry(key.toString(), _decodeValue(value as Map)));

  Object? _decodeValue(Map value) {
    if (value.containsKey('stringValue')) return value['stringValue'];
    if (value.containsKey('timestampValue')) return value['timestampValue'];
    if (value.containsKey('integerValue'))
      return int.tryParse(value['integerValue'].toString()) ?? 0;
    if (value.containsKey('doubleValue'))
      return (value['doubleValue'] as num).toDouble();
    if (value.containsKey('booleanValue')) return value['booleanValue'] == true;
    if (value.containsKey('nullValue')) return null;
    if (value.containsKey('arrayValue')) {
      final values =
          (value['arrayValue'] as Map)['values'] as List? ?? const [];
      return values.map((e) => _decodeValue(e as Map)).toList();
    }
    if (value.containsKey('mapValue')) {
      final fields = (value['mapValue'] as Map)['fields'] as Map? ?? const {};
      return _decodeFields(fields);
    }
    return null;
  }

  String _canonicalJson(Object? value) => jsonEncode(_canonicalize(value));

  Object? _canonicalize(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return {for (final key in keys) key: _canonicalize(value[key])};
    }
    if (value is List) return value.map(_canonicalize).toList();
    return value;
  }

  String _hash(String value) => sha256.convert(utf8.encode(value)).toString();

  static final _safeIdentifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
}

class _FirestoreEvent {
  const _FirestoreEvent({
    required this.queueId,
    required this.tableName,
    required this.rowUuid,
    required this.operation,
    required this.version,
    required this.eventUuid,
    required this.payload,
    required this.relations,
  });
  final int queueId;
  final String tableName, rowUuid, operation, eventUuid;
  final int version;
  final Map<String, Object?> payload, relations;
  Map<String, Object?> toMap() => {
        'event_uuid': eventUuid,
        'table': tableName,
        'uuid': rowUuid,
        'operation': operation,
        'version': version,
        'payload': payload,
        'relations': relations,
      };
}

class _FirestoreBatch {
  const _FirestoreBatch({
    required this.batchUuid,
    required this.payloadHash,
    required this.queueIds,
    required this.items,
  });
  static const empty =
      _FirestoreBatch(batchUuid: '', payloadHash: '', queueIds: [], items: []);
  final String batchUuid, payloadHash;
  final List<int> queueIds;
  final List<_FirestoreEvent> items;
}

class FirestoreSyncResult {
  const FirestoreSyncResult({
    required this.uploadedEvents,
    required this.receivedEvents,
  });
  final int uploadedEvents, receivedEvents;
}
