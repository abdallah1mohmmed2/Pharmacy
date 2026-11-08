import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import 'backup_and_sync_service.dart';
import 'sync_inbox_processor.dart';

/// Firestore REST worker. Authentication is deliberately injected: callers
/// must supply a Firebase ID token issued for the signed-in branch account.
class FirestoreSyncWorker {
  FirestoreSyncWorker({
    DatabaseHelper? helper,
    http.Client? client,
    FirestoreInboxProcessor? inbox,
  })  : _helper = helper ?? DatabaseHelper.instance,
        _client = client ?? http.Client(),
        _inbox = inbox ?? FirestoreInboxProcessor(helper: helper);

  final DatabaseHelper _helper;
  final http.Client _client;
  final FirestoreInboxProcessor _inbox;

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
    await db.update('sync_queue', {'status': 'PENDING'},
        where: "status='SENDING'");
    await BackupAndSyncService(helper: _helper, client: _client)
        .collectLocalChanges(maxRows: batchSize * 10);

    final pending = await _branchPending(db, branchId, batchSize);
    var uploaded = 0;
    if (pending.isNotEmpty) {
      final batch = await _buildBatch(db, branchId, pending);
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
            'value': {'stringValue': branchId.toString()},
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
            {'stringValue': lastCreatedAt},
            {'referenceValue': lastDocumentName},
          ],
          'before': false,
        };
      }
      final uri = Uri.https(
        'firestore.googleapis.com',
        '/v1/projects/$projectId/databases/$databaseId/documents/pharmacy_sync_batches/$branchId:runQuery',
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
        if (fields['branch_id']?.toString() != branchId.toString()) continue;
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
      final columns = await db.rawQuery('PRAGMA table_info($table)');
      final names = columns.map((e) => e['name'].toString()).toSet();
      if (!{'uuid', 'branch_id', 'sync_version'}.every(names.contains))
        continue;
      final uuid = queueRow['row_uuid'] as String;
      final row =
          await db.query(table, where: 'uuid=?', whereArgs: [uuid], limit: 1);
      if (row.isEmpty) continue;
      final current = row.first;
      if ((current['branch_id'] as num?)?.toInt() != branchId) continue;
      final version = (queueRow['sync_version'] as num? ?? 1).toInt();
      final payload = Map<String, Object?>.from(
        jsonDecode(queueRow['payload_json'] as String) as Map,
      );
      payload.remove('id');
      payload['branch_id'] = branchId;
      payload['sync_version'] = version;
      payload['sync_status'] = 'SYNCED';
      final relations = await _relationsForRow(db, table, current);
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
    final fingerprint = _hash(jsonEncode(eventValues));
    final batchUuid = _hash('$branchId|$fingerprint');
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
  ) async {
    final result = <String, Object?>{};
    final foreignKeys = await db.rawQuery('PRAGMA foreign_key_list($table)');
    for (final fk in foreignKeys) {
      final column = fk['from']?.toString();
      final parentTable = fk['table']?.toString();
      final value = column == null ? null : row[column];
      if (column == null || parentTable == null || value == null) continue;
      if (!_safeIdentifier.hasMatch(parentTable)) continue;
      final parent = await db.query(parentTable,
          where: 'id=?', whereArgs: [value], limit: 1);
      if (parent.isEmpty || parent.first['uuid'] == null) {
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
    required String idToken,
    required _FirestoreBatch batch,
  }) async {
    final uri = Uri.https(
      'firestore.googleapis.com',
      '/v1/projects/$projectId/databases/$databaseId/documents/pharmacy_sync_batches/$branchId/batches/${batch.batchUuid}',
      {'currentDocument.exists': 'false'},
    );
    final fields = <String, Object?>{
      'branch_id': branchId.toString(),
      'batch_uuid': batch.batchUuid,
      'payload_hash': batch.payloadHash,
      'schema_version': 1,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'events': batch.items.map((e) => e.toMap()).toList(),
    };
    final body = jsonEncode({'fields': _encodeFields(fields)});
    if (utf8.encode(body).length > 850000) {
      throw StateError('حجم دفعة Firestore تجاوز الحد الآمن؛ قلل batch_size');
    }
    final response = await _client
        .patch(uri, headers: _headers(idToken), body: body)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    if (response.statusCode == 409 || response.statusCode == 400) {
      final verify = await _client
          .get(
            uri.replace(queryParameters: const {}),
            headers: _headers(idToken),
          )
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
