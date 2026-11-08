import 'package:sqflite/sqflite.dart';
import 'global_uuid.dart';

/// Replaces legacy non-UUID branch identifiers before cloud sync has begun.
/// Once remote history exists, automatic rotation is refused to avoid
/// disconnecting the local database from its Firestore branch path/claims.
abstract final class SchemaIteration12 {
  static Future<void> upgrade(DatabaseExecutor db) async {
    final branches = await db.query('branches', columns: ['id', 'uuid']);
    final legacy = branches
        .where((row) => !GlobalUuid.isValid(row['uuid']?.toString() ?? ''))
        .toList();
    if (legacy.isEmpty) return;

    final remoteHistory = await _hasRemoteHistory(db);
    if (remoteHistory) {
      throw StateError(
        'تعذر تغيير هوية الفرع تلقائياً: توجد آثار مزامنة سحابية سابقة. '
        'يلزم ترحيل branch UUID بمراجعة إدارية قبل المتابعة.',
      );
    }

    for (final branch in legacy) {
      await db.update(
        'branches',
        {
          'uuid': GlobalUuid.generateV4(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id=?',
        whereArgs: [branch['id']],
      );
    }
  }

  static Future<bool> _hasRemoteHistory(DatabaseExecutor db) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' "
      "AND name IN ('sync_queue','sync_inbox_batches','sync_inbox_cursors')",
    );
    final available = tables.map((row) => row['name'].toString()).toSet();

    if (available.contains('sync_queue')) {
      final rows = await db.rawQuery(
        "SELECT COUNT(*) AS total FROM sync_queue "
        "WHERE status IN ('DONE','SYNCED')",
      );
      if ((rows.first['total'] as num).toInt() > 0) return true;
    }
    for (final table in ['sync_inbox_batches', 'sync_inbox_cursors']) {
      if (!available.contains(table)) continue;
      final rows = await db.rawQuery('SELECT COUNT(*) AS total FROM $table');
      if ((rows.first['total'] as num).toInt() > 0) return true;
    }
    return false;
  }
}
