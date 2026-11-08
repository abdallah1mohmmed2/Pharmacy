import 'dart:convert';

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
      "AND name IN ('sync_queue','sync_inbox_batches','sync_inbox_cursors','system_settings')",
    );
    final available = tables.map((row) => row['name'].toString()).toSet();

    // An enabled cloud configuration may already be associated with a remote
    // branch identity even when this device has not yet received any batches.
    if (available.contains('system_settings')) {
      final columns = await db.rawQuery('PRAGMA table_info(system_settings)');
      final names = columns.map((row) => row['name'].toString()).toSet();
      final valueColumn = names.contains('setting_value')
          ? 'setting_value'
          : names.contains('value_text')
              ? 'value_text'
              : null;
      if (valueColumn != null && names.contains('setting_no')) {
        final settings = await db.query(
          'system_settings',
          columns: [valueColumn],
          where: 'setting_no=?',
          whereArgs: [35],
          limit: 1,
        );
        if (settings.isNotEmpty) {
          final raw = settings.first[valueColumn]?.toString() ?? '';
          try {
            final config = jsonDecode(raw);
            if (config is Map && config['enabled'] == true) return true;
          } catch (_) {
            // A malformed setting is not proof that cloud sync is disabled.
            if (raw.isNotEmpty) return true;
          }
        }
      }
    }

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
