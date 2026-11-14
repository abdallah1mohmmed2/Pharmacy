import 'package:sqflite/sqflite.dart';

/// Additive clinical/controlled-drug audit reconciliation.
////
//// Historic controlled_drug_log.running_balance_units values were cumulative
//// dispensed units, not physical balances. Never overwrite or reinterpret them.
abstract final class SchemaIteration16 {
  static Future<void> upgrade(DatabaseExecutor db) async {
    await db
        .execute('''CREATE TABLE IF NOT EXISTS controlled_balance_snapshots (
      log_id INTEGER PRIMARY KEY REFERENCES controlled_drug_log(id),
      branch_id INTEGER NOT NULL REFERENCES branches(id),
      drug_id INTEGER NOT NULL REFERENCES drugs(id),
      physical_after_units INTEGER NOT NULL CHECK(physical_after_units >= 0),
      batch_after_units INTEGER NOT NULL CHECK(batch_after_units >= 0),
      recorded_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_controlled_balance_branch
      ON controlled_balance_snapshots(branch_id, drug_id, log_id)''');
    await db.execute(
        '''CREATE TRIGGER IF NOT EXISTS trg_controlled_balance_no_update
      BEFORE UPDATE ON controlled_balance_snapshots
      BEGIN SELECT RAISE(ABORT, 'controlled balance snapshots are immutable'); END''');
    await db.execute(
        '''CREATE TRIGGER IF NOT EXISTS trg_controlled_balance_no_delete
      BEFORE DELETE ON controlled_balance_snapshots
      BEGIN SELECT RAISE(ABORT, 'controlled balance snapshots are immutable'); END''');

    // One clinical decision may only be attached to one posted invoice.
    // A separate append-only link keeps historic clinical logs unchanged.
    await db
        .execute('''CREATE TABLE IF NOT EXISTS clinical_alert_invoice_links (
      alert_log_id INTEGER PRIMARY KEY REFERENCES clinical_alert_logs(id),
      invoice_id INTEGER NOT NULL REFERENCES sales_invoices(id),
      branch_id INTEGER NOT NULL REFERENCES branches(id),
      linked_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )''');
    await db.execute(
        '''CREATE INDEX IF NOT EXISTS idx_clinical_invoice_links_invoice
      ON clinical_alert_invoice_links(branch_id, invoice_id)''');
    await db
        .execute('''CREATE TRIGGER IF NOT EXISTS trg_clinical_links_no_update
      BEFORE UPDATE ON clinical_alert_invoice_links
      BEGIN SELECT RAISE(ABORT, 'clinical invoice links are immutable'); END''');
    await db
        .execute('''CREATE TRIGGER IF NOT EXISTS trg_clinical_links_no_delete
      BEFORE DELETE ON clinical_alert_invoice_links
      BEGIN SELECT RAISE(ABORT, 'clinical invoice links are immutable'); END''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_clinical_logs_drug_date
      ON clinical_alert_logs(drug_id, alert_at, id)''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_controlled_logs_drug_date
      ON controlled_drug_log(drug_id, recorded_at, id)''');
  }
}
