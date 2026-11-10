import 'package:sqflite/sqflite.dart';

/// F10 v17 migration: source sale capture, immutable local outbox and
/// optionally provisioned warehouse/batch UUIDs. Historical rows stay NULL.
abstract final class SchemaIteration14 {
  static Future<void> upgrade(DatabaseExecutor db) async {
    // F10: master references must be provisioned, never inferred from local IDs.
    // Historical warehouse/batch rows deliberately remain NULL until a trusted
    // identity migration maps them across independently provisioned devices.
    for (final table in ['warehouses', 'batches_fefo']) {
      final names = await db.rawQuery('PRAGMA table_info($table)');
      if (!names.any((row) => row['name'] == 'uuid')) {
        await db.execute('ALTER TABLE $table ADD COLUMN uuid TEXT');
      }
      await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_${table}_uuid '
          'ON $table(uuid) WHERE uuid IS NOT NULL');
    }

    // F10 local-only snapshots. Deliberately isolated from voucher transport.
    await db
        .execute('''CREATE TABLE IF NOT EXISTS financial_sale_capture_outbox(
      operation_uuid TEXT PRIMARY KEY,
      branch_id INTEGER NOT NULL,
      payload_json TEXT NOT NULL,
      payload_hash TEXT NOT NULL,
      created_at TEXT NOT NULL
    )''');
    await db.execute(
        '''CREATE TRIGGER IF NOT EXISTS trg_financial_sale_capture_no_update
      BEFORE UPDATE ON financial_sale_capture_outbox
      BEGIN SELECT RAISE(ABORT, 'F10_CAPTURE_IMMUTABLE'); END''');
    await db.execute(
        '''CREATE TRIGGER IF NOT EXISTS trg_financial_sale_capture_no_delete
      BEFORE DELETE ON financial_sale_capture_outbox
      BEGIN SELECT RAISE(ABORT, 'F10_CAPTURE_IMMUTABLE'); END''');

    // Separate ACK ledger: capture snapshots remain strictly immutable.
    await db.execute('''CREATE TABLE IF NOT EXISTS financial_sale_delivery_acks(
      operation_uuid TEXT PRIMARY KEY,
      payload_hash TEXT NOT NULL,
      acknowledged_at TEXT NOT NULL
    )''');

  }
}
