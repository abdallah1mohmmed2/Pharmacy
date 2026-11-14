import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../database/global_uuid.dart';
import 'sync_table_policy.dart';
import 'sync_payload_policy.dart';

/// Applies remote deltas once, inside the same SQLite transaction that records
/// their idempotency keys. Unknown or unsafe tables are never written.
class FirestoreInboxProcessor {
  FirestoreInboxProcessor({
    DatabaseHelper? helper,
    Database? database,
    Set<String>? allowedTablesForTesting,
    Map<String, Set<String>>? payloadFieldsForTesting,
  })  : _helper = helper ?? DatabaseHelper.instance,
        _database = database,
        _allowedTables =
            allowedTablesForTesting ?? SyncTablePolicy.inboundTables,
        _payloadFieldsForTesting = payloadFieldsForTesting;

  final DatabaseHelper _helper;
  final Database? _database;
  final Set<String> _allowedTables;
  final Map<String, Set<String>>? _payloadFieldsForTesting;

  static const _atomicPrefix = 'atomic-v1:';

  Future<InboxBatchResult> processBatch({
    required int branchId,
    required String batchUuid,
    required String payloadHash,
    required List<Map<String, Object?>> events,
    String? expectedBranchUuid,
  }) {
    if (batchUuid.startsWith(_atomicPrefix)) {
      throw const AtomicInboxBatchException('RESERVED_BATCH_NAMESPACE');
    }
    return _processBatch(
        branchId: branchId,
        batchUuid: batchUuid,
        payloadHash: payloadHash,
        events: events,
        expectedBranchUuid: expectedBranchUuid,
        requireAtomic: false);
  }

  /// Local application boundary for a future complete operation envelope.
  /// Does not enable financial tables, transport, or re-post business commands.
  /// Any rejection/dependency rolls back all rows AND all Inbox receipts.
  Future<InboxBatchResult> processAtomicBatch({
    required int branchId,
    required String operationUuid,
    required String expectedBranchUuid,
    required String payloadHash,
    required List<Map<String, Object?>> events,
  }) {
    if (!GlobalUuid.isValid(operationUuid) ||
        !GlobalUuid.isValid(expectedBranchUuid)) {
      throw const AtomicInboxBatchException('INVALID_OPERATION_IDENTITY');
    }
    final ids = events.map((event) => event['event_uuid']).toSet();
    if (ids.length != events.length) {
      throw const AtomicInboxBatchException('DUPLICATE_OPERATION_MEMBER');
    }
    return _processBatch(
        branchId: branchId,
        batchUuid: '$_atomicPrefix${operationUuid.toLowerCase()}',
        payloadHash: payloadHash,
        events: events,
        expectedBranchUuid: expectedBranchUuid,
        requireAtomic: true);
  }

  Future<InboxBatchResult> _processBatch({
    required int branchId,
    required String batchUuid,
    required String payloadHash,
    required List<Map<String, Object?>> events,
    String? expectedBranchUuid,
    required bool requireAtomic,
  }) async {
    if (branchId <= 0 || batchUuid.isEmpty || payloadHash.isEmpty) {
      throw ArgumentError('بيانات دفعة Inbox غير مكتملة');
    }
    if (events.isEmpty || events.length > 100) {
      throw RangeError('دفعة Inbox يجب أن تحتوي من 1 إلى 100 حدث');
    }
    if (_hash(_canonicalJson(events)) != payloadHash) {
      throw StateError('بصمة دفعة Inbox لا تطابق محتوى الأحداث');
    }
    final db = _database ?? await _helper.database;
    var applied = 0;
    var duplicates = 0;
    var deferred = 0;
    var rejected = 0;
    await db.transaction((txn) async {
      final existingBatch = await txn.query(
        'sync_inbox_batches',
        where: 'branch_id=? AND batch_uuid=?',
        whereArgs: [branchId, batchUuid],
        limit: 1,
      );
      if (existingBatch.isNotEmpty &&
          existingBatch.first['payload_hash'] != payloadHash) {
        throw StateError('batch_uuid مستخدم مسبقاً ببصمة مختلفة');
      }
      if (requireAtomic) {
        if (existingBatch.isNotEmpty &&
            (existingBatch.first['processed_at'] == null ||
                existingBatch.first['event_count'] != events.length)) {
          throw const AtomicInboxBatchException('INCOMPLETE_OPERATION_RECEIPT');
        }
        for (final event in events) {
          final payload = event['payload'];
          if (payload is! Map || payload['branch_id'] != expectedBranchUuid) {
            throw const AtomicInboxBatchException('OPERATION_BRANCH_MISMATCH');
          }
          final prior = await txn.query('sync_inbox',
              where: 'branch_id=? AND event_uuid=?',
              whereArgs: [branchId, event['event_uuid']],
              limit: 1);
          if (existingBatch.isEmpty && prior.isNotEmpty) {
            throw const AtomicInboxBatchException(
                'PREEXISTING_OPERATION_MEMBER');
          }
          if (existingBatch.isNotEmpty &&
              (prior.isEmpty ||
                  prior.first['batch_uuid'] != batchUuid ||
                  prior.first['status'] != 'APPLIED')) {
            throw const AtomicInboxBatchException(
                'INCOMPLETE_OPERATION_RECEIPT');
          }
        }
      }
      if (existingBatch.isEmpty) {
        await txn.insert('sync_inbox_batches', {
          'branch_id': branchId,
          'batch_uuid': batchUuid,
          'payload_hash': payloadHash,
          'received_at': DateTime.now().toUtc().toIso8601String(),
          'event_count': events.length,
        });
      }

      for (final event in events) {
        final outcome = await _processEvent(
          txn,
          branchId,
          batchUuid,
          event,
          expectedBranchUuid: expectedBranchUuid,
        );
        if (requireAtomic && outcome != 'APPLIED' && outcome != 'DUPLICATE') {
          throw AtomicInboxBatchException(outcome == 'NEEDS_DEPENDENCY'
              ? 'MISSING_DEPENDENCY'
              : 'MEMBER_REJECTED');
        }
        switch (outcome) {
          case 'APPLIED':
            applied++;
            break;
          case 'DUPLICATE':
            duplicates++;
            break;
          case 'NEEDS_DEPENDENCY':
            deferred++;
            break;
          default:
            rejected++;
            break;
        }
      }
      if (requireAtomic && existingBatch.isNotEmpty && applied != 0) {
        throw const AtomicInboxBatchException('INCOMPLETE_OPERATION_RECEIPT');
      }
      await txn.update(
        'sync_inbox_batches',
        {'processed_at': DateTime.now().toUtc().toIso8601String()},
        where: 'branch_id=? AND batch_uuid=?',
        whereArgs: [branchId, batchUuid],
      );
    });
    return InboxBatchResult(
      applied: applied,
      duplicates: duplicates,
      deferred: deferred,
      rejected: rejected,
    );
  }

  /// Retries events whose parent UUID had not arrived during the first pass.
  Future<int> retryDeferred(int branchId) async {
    final db = _database ?? await _helper.database;
    final pending = await db.query(
      'sync_inbox',
      where: "branch_id=? AND status='NEEDS_DEPENDENCY'",
      whereArgs: [branchId],
      orderBy: 'received_at,id',
      limit: 500,
    );
    var applied = 0;
    for (final row in pending) {
      final batches = await db.query(
        'sync_inbox_batches',
        where: 'branch_id=? AND batch_uuid=?',
        whereArgs: [branchId, row['batch_uuid']],
        limit: 1,
      );
      if (batches.isEmpty) continue;
      final event = <String, Object?>{
        'event_uuid': row['event_uuid'],
        'table': row['table_name'],
        'uuid': row['row_uuid'],
        'operation': row['operation'],
        'version': row['remote_version'],
        'payload': jsonDecode(row['payload_json'] as String),
        'relations': jsonDecode(row['relations_json'] as String),
      };
      await db.transaction((txn) async {
        final outcome = await _processEvent(
          txn,
          branchId,
          row['batch_uuid'] as String,
          event,
          retrying: true,
        );
        if (outcome == 'APPLIED') applied++;
      });
    }
    return applied;
  }

  Future<String> _processEvent(
    Transaction txn,
    int branchId,
    String batchUuid,
    Map<String, Object?> event, {
    String? expectedBranchUuid,
    bool retrying = false,
  }) async {
    final table = event['table']?.toString() ?? '';
    final uuid = event['uuid']?.toString() ?? '';
    final operation = event['operation']?.toString() ?? '';
    final rawVersion = event['version'];
    final version = rawVersion is int ? rawVersion : 0;
    final eventUuid = event['event_uuid']?.toString() ?? '';
    final payload = event['payload'];
    final relations = event['relations'];
    if (!_identifier.hasMatch(table) ||
        !GlobalUuid.isValid(uuid) ||
        version < 1 ||
        !{'INSERT', 'UPDATE', 'SOFT_DELETE'}.contains(operation) ||
        payload is! Map ||
        relations is! Map ||
        eventUuid != _hash('$table|$uuid|$version|$operation')) {
      return 'REJECTED';
    }

    // Validate before retaining untrusted payloads in Inbox or resolving FKs.
    late final Map<String, Object?> payloadMap;
    late final Map<String, Object?> relationMap;
    try {
      if (!_allowedTables.contains(table) ||
          payload.keys.any((key) => key is! String) ||
          relations.keys.any((key) => key is! String)) {
        throw const FormatException('SYNC_PAYLOAD_POLICY_REJECTED');
      }
      final scalarPayload = Map<String, Object?>.from(payload);
      final embeddedRelations = scalarPayload.remove('__relations');
      if (payload.containsKey('__relations') &&
          (embeddedRelations is! Map ||
              _canonicalJson(embeddedRelations) != _canonicalJson(relations))) {
        throw const FormatException('SYNC_PAYLOAD_POLICY_REJECTED');
      }
      payloadMap = SyncPayloadPolicy.validateIncoming(table, scalarPayload,
          fieldsForTesting: _payloadFieldsForTesting?[table]);
      if ((payloadMap.containsKey('uuid') && payloadMap['uuid'] != uuid) ||
          (payloadMap.containsKey('sync_version') &&
              payloadMap['sync_version'] != version)) {
        throw const FormatException('SYNC_PAYLOAD_POLICY_REJECTED');
      }
      relationMap = Map<String, Object?>.from(relations);
      final foreignKeys = await txn.rawQuery('PRAGMA foreign_key_list($table)');
      final fields = _payloadFieldsForTesting?[table] ??
          SyncPayloadPolicy.fieldsByTable[table] ??
          const <String>{};
      for (final entry in relationMap.entries) {
        final matching = foreignKeys.where((fk) => fk['from'] == entry.key);
        final relation = entry.value;
        if (!fields.contains(entry.key) ||
            matching.length != 1 ||
            relation is! Map ||
            relation.length != 2 ||
            !relation.containsKey('table') ||
            !relation.containsKey('uuid') ||
            relation['table'] != matching.single['table'] ||
            !_allowedTables.contains(relation['table']) ||
            relation['uuid'] is! String ||
            !GlobalUuid.isValid(relation['uuid'] as String)) {
          throw const FormatException('SYNC_PAYLOAD_POLICY_REJECTED');
        }
      }
    } on FormatException {
      // Also quarantine previously deferred events after a policy change.
      if (retrying) {
        await _setInboxStatus(
            txn, branchId, eventUuid, 'FAILED', 'SYNC_PAYLOAD_POLICY_REJECTED');
      }
      return 'REJECTED';
    }
    final payloadHash = _hash(_canonicalJson({
      'payload': payload,
      'relations': relationMap,
      'operation': operation,
      'version': version,
    }));
    final prior = await txn.query(
      'sync_inbox',
      where: 'branch_id=? AND event_uuid=?',
      whereArgs: [branchId, eventUuid],
      limit: 1,
    );
    if (prior.isNotEmpty) {
      if (prior.first['payload_hash'] != payloadHash) {
        throw StateError('event_uuid مستخدم مع محتوى مختلف');
      }
      final status = prior.first['status'];
      if (status == 'APPLIED' || status == 'IGNORED') return 'DUPLICATE';
    } else {
      await txn.insert('sync_inbox', {
        'branch_id': branchId,
        'event_uuid': eventUuid,
        'batch_uuid': batchUuid,
        'table_name': table,
        'row_uuid': uuid,
        'operation': operation,
        'remote_version': version,
        'payload_json': jsonEncode(payload),
        'relations_json': jsonEncode(relationMap),
        'payload_hash': payloadHash,
        'status': 'RECEIVED',
        'received_at': DateTime.now().toUtc().toIso8601String(),
      });
    }

    try {
      if (expectedBranchUuid != null &&
          payloadMap['branch_id']?.toString() != expectedBranchUuid) {
        await _setInboxStatus(
          txn,
          branchId,
          eventUuid,
          'FAILED',
          'هوية الفرع داخل الحدث لا تطابق فرع جلسة Firestore',
        );
        return 'REJECTED';
      }
      final tableRows = await txn.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        [table],
      );
      if (tableRows.isEmpty) {
        await _setInboxStatus(
            txn, branchId, eventUuid, 'FAILED', 'الجدول غير معروف');
        return 'REJECTED';
      }
      final columns = await txn.rawQuery('PRAGMA table_info($table)');
      final columnNames = columns.map((e) => e['name'].toString()).toSet();
      if (!{'id', 'uuid', 'branch_id', 'sync_version', 'sync_status'}
          .every(columnNames.contains)) {
        await _setInboxStatus(
            txn, branchId, eventUuid, 'FAILED', 'الجدول لا يطابق عقد المزامنة');
        return 'REJECTED';
      }

      final localRows = await txn.query(
        table,
        where: 'uuid=? AND branch_id=?',
        whereArgs: [uuid, branchId],
        limit: 1,
      );
      if (localRows.isNotEmpty &&
          (((localRows.first['sync_version'] as num?)?.toInt() ?? 0) >
                  version ||
              (((localRows.first['sync_version'] as num?)?.toInt() ?? 0) >=
                      version &&
                  localRows.first['sync_status'] != 'SYNCED'))) {
        await _setInboxStatus(
            txn, branchId, eventUuid, 'IGNORED', 'توجد نسخة محلية أحدث');
        return 'REJECTED';
      }

      final values = <String, Object?>{};
      for (final entry in payloadMap.entries) {
        final key = entry.key;
        if (key == 'id' ||
            key == 'branch_id' ||
            key == '__relations' ||
            !columnNames.contains(key)) {
          continue;
        }
        values[key] = entry.value;
      }
      values['uuid'] = uuid;
      values['branch_id'] = branchId;
      values['sync_version'] = version;
      values['sync_status'] = 'SYNCED';
      if (operation == 'SOFT_DELETE') {
        if (!columnNames.contains('is_deleted')) {
          await _setInboxStatus(txn, branchId, eventUuid, 'FAILED',
              'الجدول لا يدعم الحذف المنطقي');
          return 'REJECTED';
        }
        values['is_deleted'] = 1;
      }

      final foreignKeys = await txn.rawQuery('PRAGMA foreign_key_list($table)');
      for (final fk in foreignKeys) {
        final localColumn = fk['from']?.toString();
        final parentTable = fk['table']?.toString();
        if (localColumn == null ||
            parentTable == null ||
            localColumn == 'branch_id' ||
            !columnNames.contains(localColumn)) continue;
        final relation = relationMap[localColumn];
        if (relation == null) {
          if (values[localColumn] != null) {
            await _setInboxStatus(txn, branchId, eventUuid, 'NEEDS_DEPENDENCY',
                'بيانات العلاقة $localColumn غير متوفرة');
            return 'NEEDS_DEPENDENCY';
          }
          continue;
        }
        if (relation is! Map ||
            relation['table']?.toString() != parentTable ||
            !_identifier.hasMatch(parentTable)) {
          await _setInboxStatus(txn, branchId, eventUuid, 'FAILED',
              'مرجع العلاقة $localColumn غير صالح');
          return 'REJECTED';
        }
        final parentColumns =
            await txn.rawQuery('PRAGMA table_info($parentTable)');
        final parentNames =
            parentColumns.map((e) => e['name'].toString()).toSet();
        if (!parentNames.contains('uuid')) {
          await _setInboxStatus(txn, branchId, eventUuid, 'NEEDS_DEPENDENCY',
              'الجدول الأب لا يملك UUID عاماً');
          return 'NEEDS_DEPENDENCY';
        }
        final parentWhere = parentNames.contains('branch_id')
            ? 'uuid=? AND branch_id=?'
            : 'uuid=?';
        final parentArgs = parentNames.contains('branch_id')
            ? [relation['uuid'], branchId]
            : [relation['uuid']];
        final parents = await txn.query(parentTable,
            columns: ['id'],
            where: parentWhere,
            whereArgs: parentArgs,
            limit: 1);
        if (parents.isEmpty) {
          await _setInboxStatus(txn, branchId, eventUuid, 'NEEDS_DEPENDENCY',
              'السجل الأب لم يصل بعد: $parentTable');
          return 'NEEDS_DEPENDENCY';
        }
        values[localColumn] = parents.first['id'];
      }

      if (localRows.isEmpty) {
        await txn.insert(table, values,
            conflictAlgorithm: ConflictAlgorithm.abort);
      } else {
        await txn.update(table, values,
            where: 'uuid=? AND branch_id=?', whereArgs: [uuid, branchId]);
      }
      await _setInboxStatus(txn, branchId, eventUuid, 'APPLIED', null);
      return 'APPLIED';
    } catch (error) {
      await _setInboxStatus(
          txn, branchId, eventUuid, 'FAILED', error.toString());
      return 'REJECTED';
    }
  }

  Future<void> _setInboxStatus(
    Transaction txn,
    int branchId,
    String eventUuid,
    String status,
    String? error,
  ) async {
    await txn.update(
      'sync_inbox',
      {
        'status': status,
        'error_text': error,
        'applied_at': status == 'APPLIED'
            ? DateTime.now().toUtc().toIso8601String()
            : null,
      },
      where: 'branch_id=? AND event_uuid=?',
      whereArgs: [branchId, eventUuid],
    );
  }

  String _canonicalJson(Object? value) => jsonEncode(_canonicalize(value));

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

  String _hash(String value) => sha256.convert(utf8.encode(value)).toString();
  static final _identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
}

class InboxBatchResult {
  const InboxBatchResult({
    required this.applied,
    required this.duplicates,
    required this.deferred,
    required this.rejected,
  });
  final int applied, duplicates, deferred, rejected;
}

/// Safe, non-payload error codes for all-or-nothing application failures.
class AtomicInboxBatchException implements Exception {
  const AtomicInboxBatchException(this.code);
  final String code;
  @override
  String toString() => 'AtomicInboxBatchException: $code';
}
