import 'package:sqflite/sqflite.dart';

/// P0-06: local-only, append-only capture of complete financial operations.
///
/// These tables are NOT part of SyncTablePolicy. Never push their raw contents
/// through the general row sync queue. Only a trusted financial transport may
/// publish the validated operation envelope.
abstract final class SchemaIteration13 {
  static Future<void> upgrade(DatabaseExecutor db) async {
    final columns = await db.rawQuery('PRAGMA table_info(cash_transactions)');
    if (!columns.any((column) => column['name'] == 'uuid')) {
      // Historical rows remain NULL and must not be assigned new identities
      // without a separately approved provenance/mapping migration.
      await db.execute('ALTER TABLE cash_transactions ADD COLUMN uuid TEXT');
    }
    await db.execute('''CREATE UNIQUE INDEX IF NOT EXISTS idx_cash_transactions_uuid
      ON cash_transactions(uuid) WHERE uuid IS NOT NULL''');

    await db.execute('''CREATE TABLE IF NOT EXISTS financial_operation_outbox(
      operation_uuid TEXT PRIMARY KEY,
      branch_id INTEGER NOT NULL,
      branch_uuid TEXT NOT NULL,
      voucher_uuid TEXT NOT NULL UNIQUE,
      payload_json TEXT NOT NULL,
      payload_hash TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'PENDING'
        CHECK(status IN ('PENDING','SENT')),
      created_at TEXT NOT NULL,
      sent_at TEXT
    )''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_financial_outbox_pending
      ON financial_operation_outbox(branch_id,status,created_at)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS financial_operation_inbox(
      operation_uuid TEXT PRIMARY KEY,
      branch_id INTEGER NOT NULL,
      voucher_uuid TEXT NOT NULL UNIQUE,
      payload_hash TEXT NOT NULL,
      applied_at TEXT NOT NULL
    )''');

    // Status may advance once a trusted relay acknowledges the exact hash.
    // The envelope itself cannot be modified after source transaction commit.
    await db.execute('''CREATE TRIGGER IF NOT EXISTS trg_financial_outbox_immutable
      BEFORE UPDATE ON financial_operation_outbox
      WHEN NEW.operation_uuid != OLD.operation_uuid
        OR NEW.branch_id != OLD.branch_id
        OR NEW.branch_uuid != OLD.branch_uuid
        OR NEW.voucher_uuid != OLD.voucher_uuid
        OR NEW.payload_json != OLD.payload_json
        OR NEW.payload_hash != OLD.payload_hash
        OR NEW.created_at != OLD.created_at
      BEGIN SELECT RAISE(ABORT, 'FINANCIAL_OUTBOX_IMMUTABLE'); END''');
    await db.execute('''CREATE TRIGGER IF NOT EXISTS trg_financial_outbox_no_delete
      BEFORE DELETE ON financial_operation_outbox
      BEGIN SELECT RAISE(ABORT, 'FINANCIAL_OUTBOX_IMMUTABLE'); END''');
    await db.execute('''CREATE TRIGGER IF NOT EXISTS trg_financial_inbox_no_update
      BEFORE UPDATE ON financial_operation_inbox
      BEGIN SELECT RAISE(ABORT, 'FINANCIAL_INBOX_IMMUTABLE'); END''');
    await db.execute('''CREATE TRIGGER IF NOT EXISTS trg_financial_inbox_no_delete
      BEFORE DELETE ON financial_operation_inbox
      BEGIN SELECT RAISE(ABORT, 'FINANCIAL_INBOX_IMMUTABLE'); END''');
  }
}
