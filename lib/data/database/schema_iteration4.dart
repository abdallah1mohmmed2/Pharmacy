// lib/data/database/schema_iteration4.dart
import 'package:sqflite/sqflite.dart';

/// Additive migration: keeps the Iteration 3 pregnancy flag and installs
/// treasury, shift, expense, HR, payroll and partner-distribution structures.
abstract final class SchemaIteration4 {
  static Future<void> upgrade(DatabaseExecutor db) async {
    await _ensureColumn(db, 'patients', 'pregnancy_status_known',
        'INTEGER NOT NULL DEFAULT 0 CHECK(pregnancy_status_known IN(0,1))');
    final statements = <String>[
      '''CREATE TABLE IF NOT EXISTS app_settings(setting_key TEXT PRIMARY KEY,value_text TEXT NOT NULL,updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)''',
      '''CREATE TABLE IF NOT EXISTS cash_transactions(id INTEGER PRIMARY KEY AUTOINCREMENT,cash_account_id INTEGER NOT NULL REFERENCES cash_accounts(id),tx_date TEXT NOT NULL,direction TEXT NOT NULL CHECK(direction IN('IN','OUT')),amount REAL NOT NULL CHECK(amount>0),tx_type TEXT NOT NULL CHECK(tx_type IN('SALE','SALE_RETURN','RECEIPT_VOUCHER','PAYMENT_VOUCHER','EXPENSE','PURCHASE_PAYMENT','TRANSFER_BETWEEN_ACCOUNTS','SHIFT_HANDOVER','PARTNER_WITHDRAWAL','SALARY','ADVANCE','OPENING','SHIFT_DIFF','WALLET_RECONCILIATION')),doc_type TEXT,doc_id INTEGER,wallet_ref_no TEXT,cashier_shift_id INTEGER,balance_after REAL NOT NULL DEFAULT 0,note TEXT,branch_id INTEGER NOT NULL DEFAULT 1,created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)''',
      '''CREATE TABLE IF NOT EXISTS work_shifts(id INTEGER PRIMARY KEY AUTOINCREMENT,name_ar TEXT NOT NULL UNIQUE,start_time TEXT NOT NULL,end_time TEXT NOT NULL,crosses_midnight INTEGER NOT NULL DEFAULT 0 CHECK(crosses_midnight IN(0,1)))''',
      '''CREATE TABLE IF NOT EXISTS cashier_shifts(id INTEGER PRIMARY KEY AUTOINCREMENT,shift_no TEXT NOT NULL UNIQUE,user_id INTEGER NOT NULL REFERENCES users(id),cashier_party_id INTEGER REFERENCES parties(id),drawer_account_id INTEGER REFERENCES cash_accounts(id),work_shift_id INTEGER REFERENCES work_shifts(id),opened_at TEXT NOT NULL,opening_cash REAL NOT NULL DEFAULT 0,closed_at TEXT,expected_cash REAL,counted_cash REAL,diff_amount REAL,expected_wallets_json TEXT NOT NULL DEFAULT '{}',counted_wallets_json TEXT NOT NULL DEFAULT '{}',diff_handling TEXT NOT NULL DEFAULT 'NONE' CHECK(diff_handling IN('POST_TO_CASHIER','EXPENSE','SUSPENSE','NONE')),counted_denominations_json TEXT NOT NULL DEFAULT '{}',handover_to_user_id INTEGER REFERENCES users(id),status TEXT NOT NULL DEFAULT 'OPEN' CHECK(status IN('OPEN','CLOSED','HANDED_OVER')),branch_id INTEGER NOT NULL DEFAULT 1)''',
      '''CREATE TABLE IF NOT EXISTS expense_categories(id INTEGER PRIMARY KEY AUTOINCREMENT,name_ar TEXT NOT NULL UNIQUE,recurrence TEXT NOT NULL DEFAULT 'NONE' CHECK(recurrence IN('NONE','DAILY','MONTHLY','YEARLY')),monthly_budget_limit REAL NOT NULL DEFAULT 0 CHECK(monthly_budget_limit>=0),gl_account_id INTEGER REFERENCES chart_of_accounts(id),branch_id INTEGER NOT NULL DEFAULT 1)''',
      '''CREATE TABLE IF NOT EXISTS expenses(id INTEGER PRIMARY KEY AUTOINCREMENT,expense_no TEXT NOT NULL UNIQUE,category_id INTEGER NOT NULL REFERENCES expense_categories(id),expense_date TEXT NOT NULL,amount REAL NOT NULL CHECK(amount>0),cash_account_id INTEGER NOT NULL REFERENCES cash_accounts(id),paid_to TEXT,description TEXT,attachment_path TEXT,is_recurring_instance INTEGER NOT NULL DEFAULT 0 CHECK(is_recurring_instance IN(0,1)),cashier_shift_id INTEGER REFERENCES cashier_shifts(id),journal_entry_id INTEGER REFERENCES journal_entries(id),branch_id INTEGER NOT NULL DEFAULT 1)''',
      '''CREATE TABLE IF NOT EXISTS employees(id INTEGER PRIMARY KEY AUTOINCREMENT,party_id INTEGER NOT NULL UNIQUE REFERENCES parties(id),job_title TEXT NOT NULL CHECK(job_title IN('PHARMACIST','ASSISTANT','CASHIER','STOREKEEPER','CLEANER','DRIVER','OTHER')),pharmacist_license_no TEXT,hire_date TEXT NOT NULL,termination_date TEXT,pay_type TEXT NOT NULL CHECK(pay_type IN('DAILY','MONTHLY')),pay_rate REAL NOT NULL CHECK(pay_rate>=0),max_advance_pct REAL NOT NULL DEFAULT 50 CHECK(max_advance_pct BETWEEN 0 AND 100),branch_id INTEGER NOT NULL DEFAULT 1)''',
      '''CREATE TABLE IF NOT EXISTS employee_attendance(id INTEGER PRIMARY KEY AUTOINCREMENT,employee_id INTEGER NOT NULL REFERENCES employees(id),work_date TEXT NOT NULL,work_shift_id INTEGER REFERENCES work_shifts(id),check_in TEXT,check_out TEXT,status TEXT NOT NULL CHECK(status IN('PRESENT','ABSENT','LEAVE','HALF_DAY','OVERTIME')),overtime_hours REAL NOT NULL DEFAULT 0 CHECK(overtime_hours>=0),wage_earned REAL NOT NULL DEFAULT 0 CHECK(wage_earned>=0),UNIQUE(employee_id,work_date,work_shift_id))''',
      '''CREATE TABLE IF NOT EXISTS payroll_runs(id INTEGER PRIMARY KEY AUTOINCREMENT,employee_id INTEGER NOT NULL REFERENCES employees(id),period_code TEXT NOT NULL,gross_lah REAL NOT NULL DEFAULT 0,bonuses_lah REAL NOT NULL DEFAULT 0,advances_alayh REAL NOT NULL DEFAULT 0,deductions_alayh REAL NOT NULL DEFAULT 0,net_amount REAL NOT NULL DEFAULT 0,status TEXT NOT NULL DEFAULT 'DRAFT' CHECK(status IN('DRAFT','APPROVED','PAID')),paid_voucher_id INTEGER REFERENCES vouchers(id),UNIQUE(employee_id,period_code))''',
      '''CREATE TABLE IF NOT EXISTS partners(id INTEGER PRIMARY KEY AUTOINCREMENT,party_id INTEGER NOT NULL UNIQUE REFERENCES parties(id),capital_amount REAL NOT NULL DEFAULT 0 CHECK(capital_amount>=0),shares_count INTEGER CHECK(shares_count IS NULL OR shares_count>=0),percentage REAL CHECK(percentage IS NULL OR percentage BETWEEN 0 AND 100),needs_input INTEGER NOT NULL DEFAULT 0 CHECK(needs_input IN(0,1)),join_date TEXT NOT NULL,is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN(0,1)),branch_id INTEGER NOT NULL DEFAULT 1)''',
      '''CREATE TABLE IF NOT EXISTS partner_distributions(id INTEGER PRIMARY KEY AUTOINCREMENT,distribution_no TEXT NOT NULL UNIQUE,period_code TEXT NOT NULL,distribution_mode TEXT NOT NULL CHECK(distribution_mode IN('shares','percentage')),total_revenue REAL NOT NULL DEFAULT 0,total_cogs REAL NOT NULL DEFAULT 0,total_expenses_and_losses REAL NOT NULL DEFAULT 0,net_profit REAL NOT NULL DEFAULT 0,reserve_pct REAL NOT NULL DEFAULT 0 CHECK(reserve_pct BETWEEN 0 AND 100),distributable_profit REAL NOT NULL DEFAULT 0,status TEXT NOT NULL DEFAULT 'DRAFT' CHECK(status IN('DRAFT','APPROVED','POSTED')),journal_entry_id INTEGER REFERENCES journal_entries(id),branch_id INTEGER NOT NULL DEFAULT 1)''',
      '''CREATE TABLE IF NOT EXISTS partner_distribution_lines(id INTEGER PRIMARY KEY AUTOINCREMENT,distribution_id INTEGER NOT NULL REFERENCES partner_distributions(id) ON DELETE CASCADE,partner_id INTEGER NOT NULL REFERENCES partners(id),basis_value REAL NOT NULL,share_amount_lah REAL NOT NULL DEFAULT 0,withdrawals_alayh REAL NOT NULL DEFAULT 0,net_payable REAL NOT NULL DEFAULT 0,UNIQUE(distribution_id,partner_id))''',
      '''CREATE TABLE IF NOT EXISTS chronic_medication_schedules(id INTEGER PRIMARY KEY AUTOINCREMENT,customer_party_id INTEGER NOT NULL REFERENCES parties(id),drug_id INTEGER NOT NULL REFERENCES drugs(id),quantity_units INTEGER NOT NULL CHECK(quantity_units>0),cycle_days INTEGER NOT NULL DEFAULT 30 CHECK(cycle_days>0),next_due_date TEXT NOT NULL,status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK(status IN('ACTIVE','PAUSED','COMPLETED')),instructions TEXT,last_dispensed_at TEXT,last_dispensed_invoice_id INTEGER REFERENCES sales_invoices(id),branch_id INTEGER NOT NULL DEFAULT 1)''',
      '''CREATE TABLE IF NOT EXISTS representative_visit_days(id INTEGER PRIMARY KEY AUTOINCREMENT,representative_party_id INTEGER NOT NULL REFERENCES parties(id),weekday INTEGER NOT NULL CHECK(weekday BETWEEN 1 AND 7),visit_time TEXT,notes TEXT,UNIQUE(representative_party_id,weekday))''',
      '''CREATE TABLE IF NOT EXISTS party_settlements(id INTEGER PRIMARY KEY AUTOINCREMENT,settlement_no TEXT NOT NULL UNIQUE,from_party_id INTEGER NOT NULL REFERENCES parties(id),to_party_id INTEGER NOT NULL REFERENCES parties(id),amount REAL NOT NULL CHECK(amount>0),settlement_date TEXT NOT NULL,note TEXT,journal_entry_id INTEGER REFERENCES journal_entries(id),branch_id INTEGER NOT NULL DEFAULT 1)''',
      '''CREATE INDEX IF NOT EXISTS idx_cash_tx_account_date ON cash_transactions(cash_account_id,tx_date,id)''',
      '''CREATE INDEX IF NOT EXISTS idx_cashier_shift_status ON cashier_shifts(branch_id,status,opened_at)''',
      '''CREATE INDEX IF NOT EXISTS idx_expenses_date_category ON expenses(branch_id,expense_date,category_id)''',
      '''CREATE INDEX IF NOT EXISTS idx_attendance_period ON employee_attendance(work_date,employee_id)''',
      '''CREATE INDEX IF NOT EXISTS idx_partner_distribution_period ON partner_distributions(period_code,status)''',
      '''CREATE TRIGGER IF NOT EXISTS trg_partner_lock_pct_ins BEFORE INSERT ON partners WHEN NEW.percentage IS NOT NULL AND (SELECT value_text FROM app_settings WHERE setting_key='accounting.partner_distribution_mode')='shares' BEGIN SELECT RAISE(ABORT,'PARTNER_PCT_LOCKED_IN_SHARES_MODE'); END''',
      '''CREATE TRIGGER IF NOT EXISTS trg_partner_lock_pct_upd BEFORE UPDATE OF percentage ON partners WHEN NEW.percentage IS NOT NULL AND (SELECT value_text FROM app_settings WHERE setting_key='accounting.partner_distribution_mode')='shares' BEGIN SELECT RAISE(ABORT,'PARTNER_PCT_LOCKED_IN_SHARES_MODE'); END''',
      '''CREATE TRIGGER IF NOT EXISTS trg_partner_lock_shares_ins BEFORE INSERT ON partners WHEN NEW.shares_count IS NOT NULL AND (SELECT value_text FROM app_settings WHERE setting_key='accounting.partner_distribution_mode')='percentage' BEGIN SELECT RAISE(ABORT,'PARTNER_SHARES_LOCKED_IN_PERCENTAGE_MODE'); END''',
      '''CREATE TRIGGER IF NOT EXISTS trg_partner_lock_shares_upd BEFORE UPDATE OF shares_count ON partners WHEN NEW.shares_count IS NOT NULL AND (SELECT value_text FROM app_settings WHERE setting_key='accounting.partner_distribution_mode')='percentage' BEGIN SELECT RAISE(ABORT,'PARTNER_SHARES_LOCKED_IN_PERCENTAGE_MODE'); END''',
      '''CREATE TRIGGER IF NOT EXISTS trg_partner_mode_switch_requires_clear BEFORE UPDATE OF value_text ON app_settings WHEN OLD.setting_key='accounting.partner_distribution_mode' AND NEW.value_text='percentage' AND EXISTS(SELECT 1 FROM partners WHERE shares_count IS NOT NULL) BEGIN SELECT RAISE(ABORT,'PARTNER_MODE_SWITCH_REQUIRES_CLEARED_SHARES'); END''',
      '''CREATE TRIGGER IF NOT EXISTS trg_partner_mode_switch_requires_clear_ins BEFORE INSERT ON app_settings WHEN NEW.setting_key='accounting.partner_distribution_mode' AND NEW.value_text='percentage' AND EXISTS(SELECT 1 FROM partners WHERE shares_count IS NOT NULL) BEGIN SELECT RAISE(ABORT,'PARTNER_MODE_SWITCH_REQUIRES_CLEARED_SHARES'); END''',
      '''CREATE TRIGGER IF NOT EXISTS trg_partner_mode_switch_requires_clear_pct_ins BEFORE INSERT ON app_settings WHEN NEW.setting_key='accounting.partner_distribution_mode' AND NEW.value_text='shares' AND EXISTS(SELECT 1 FROM partners WHERE percentage IS NOT NULL) BEGIN SELECT RAISE(ABORT,'PARTNER_MODE_SWITCH_REQUIRES_CLEARED_PERCENTAGES'); END''',
      '''CREATE TRIGGER IF NOT EXISTS trg_partner_mode_switch_requires_clear_pct BEFORE UPDATE OF value_text ON app_settings WHEN OLD.setting_key='accounting.partner_distribution_mode' AND NEW.value_text='shares' AND EXISTS(SELECT 1 FROM partners WHERE percentage IS NOT NULL) BEGIN SELECT RAISE(ABORT,'PARTNER_MODE_SWITCH_REQUIRES_CLEARED_PERCENTAGES'); END''',
      '''CREATE TRIGGER IF NOT EXISTS trg_partner_mode_setting_delete BEFORE DELETE ON app_settings WHEN OLD.setting_key='accounting.partner_distribution_mode' BEGIN SELECT RAISE(ABORT,'PARTNER_MODE_SETTING_REQUIRED'); END''',
      '''CREATE TRIGGER IF NOT EXISTS trg_partner_mode_setting_value BEFORE INSERT ON app_settings WHEN NEW.setting_key='accounting.partner_distribution_mode' AND NEW.value_text NOT IN('shares','percentage') BEGIN SELECT RAISE(ABORT,'PARTNER_MODE_INVALID'); END''',
      '''CREATE TRIGGER IF NOT EXISTS trg_partner_mode_setting_value_upd BEFORE UPDATE OF value_text ON app_settings WHEN NEW.setting_key='accounting.partner_distribution_mode' AND NEW.value_text NOT IN('shares','percentage') BEGIN SELECT RAISE(ABORT,'PARTNER_MODE_INVALID'); END''',
    ];
    for (final sql in statements) {
      await db.execute(sql);
    }
    await _ensureColumn(
        db, 'chronic_medication_schedules', 'last_dispensed_at', 'TEXT');
    await _ensureColumn(db, 'chronic_medication_schedules',
        'last_dispensed_invoice_id', 'INTEGER');
    await db.insert(
        'app_settings',
        {
          'setting_key': 'accounting.partner_distribution_mode',
          'value_text': 'shares'
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
    // Demo patients, sample alternatives, employees, expenses, partners and shifts are not preloaded.
  }

  static Future<void> _ensureColumn(DatabaseExecutor db, String table,
      String column, String definition) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    if (!rows.any((row) => row['name'] == column)) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }
}
