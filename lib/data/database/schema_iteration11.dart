import 'package:sqflite/sqflite.dart';

/// Durable idempotency ledger for changes received from Firestore.
abstract final class SchemaIteration11 {
  static Future<void> upgrade(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS sync_inbox(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      branch_id INTEGER NOT NULL,
      event_uuid TEXT NOT NULL,
      batch_uuid TEXT NOT NULL,
      table_name TEXT NOT NULL,
      row_uuid TEXT NOT NULL,
      operation TEXT NOT NULL CHECK(operation IN ('INSERT','UPDATE','SOFT_DELETE')),
      remote_version INTEGER NOT NULL,
      payload_json TEXT NOT NULL,
      relations_json TEXT NOT NULL DEFAULT '{}',
      payload_hash TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'RECEIVED'
        CHECK(status IN ('RECEIVED','APPLIED','IGNORED','NEEDS_DEPENDENCY','FAILED')),
      error_text TEXT,
      received_at TEXT NOT NULL,
      applied_at TEXT,
      UNIQUE(branch_id,event_uuid)
    )''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_sync_inbox_status
      ON sync_inbox(branch_id,status,received_at)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS sync_inbox_batches(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      branch_id INTEGER NOT NULL,
      batch_uuid TEXT NOT NULL,
      payload_hash TEXT NOT NULL,
      received_at TEXT NOT NULL,
      processed_at TEXT,
      event_count INTEGER NOT NULL DEFAULT 0,
      UNIQUE(branch_id,batch_uuid)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS sync_inbox_cursors(
      branch_id INTEGER PRIMARY KEY,
      page_token TEXT,
      last_document_name TEXT,
      updated_at TEXT NOT NULL
    )''');
  }
}
