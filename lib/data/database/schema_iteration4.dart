// lib/data/database/schema_iteration4.dart
import 'dart:convert';
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
      '''CREATE TABLE IF NOT EXISTS chronic_medication_schedules(id INTEGER PRIMARY KEY AUTOINCREMENT,customer_party_id INTEGER NOT NULL REFERENCES parties(id),drug_id INTEGER NOT NULL REFERENCES drugs(id),quantity_units INTEGER NOT NULL CHECK(quantity_units>0),cycle_days INTEGER NOT NULL DEFAULT 30 CHECK(cycle_days>0),next_due_date TEXT NOT NULL,status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK(status IN('ACTIVE','PAUSED','COMPLETED')),instructions TEXT,branch_id INTEGER NOT NULL DEFAULT 1)''',
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
    ];
    for (final sql in statements) { await db.execute(sql); }
    await db.insert('app_settings', {'setting_key':'accounting.partner_distribution_mode','value_text':'shares'}, conflictAlgorithm: ConflictAlgorithm.ignore);
    await _seed(db);
  }

  static Future<void> _ensureColumn(DatabaseExecutor db,String table,String column,String definition) async {
    final rows=await db.rawQuery('PRAGMA table_info($table)');
    if(!rows.any((row)=>row['name']==column)){await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');}
  }

  static Future<void> _seed(DatabaseExecutor db) async {
    final branches=await db.query('branches',columns:['id'],orderBy:'id',limit:1);
    if(branches.isEmpty)return;
    final branchId=branches.first['id'] as int;
    final users=await db.query('users',columns:['id'],where:'branch_id=? AND is_deleted=0',whereArgs:[branchId],orderBy:'id',limit:1);
    final cash=await db.query('cash_accounts',columns:['id','code'],where:'branch_id=? AND is_deleted=0',whereArgs:[branchId],orderBy:'id');
    final drawer=cash.firstWhere((r)=>r['code']=='CASH-DRAWER',orElse:()=>cash.first);
    final safe=cash.firstWhere((r)=>r['code']=='CASH-MAIN',orElse:()=>cash.first);
    final now=DateTime.now().toIso8601String();
    final shifts=<List<String>>[['صباحية','08:00','16:00'],['مسائية','16:00','00:00'],['ليلية','00:00','08:00']];
    for(final s in shifts){await db.insert('work_shifts',{'name_ar':s[0],'start_time':s[1],'end_time':s[2],'crosses_midnight':s[0]!='صباحية'},conflictAlgorithm:ConflictAlgorithm.ignore);}
    final categories=<List<Object>>[
      ['إيجار',50000.0,'5203'],['كهرباء',15000.0,'5204'],['ماء',5000.0,'5204'],['أكياس وتغليف',10000.0,'5201'],['ضيافة',5000.0,'5201'],['صيانة',12000.0,'5201'],['مواصلات',8000.0,'5201'],['أخرى',10000.0,'5201']
    ];
    for(final c in categories){final gl=await db.query('chart_of_accounts',columns:['id'],where:'code=?',whereArgs:[c[2]],limit:1);await db.insert('expense_categories',{'name_ar':c[0],'recurrence':'MONTHLY','monthly_budget_limit':c[1],'gl_account_id':gl.isEmpty?null:gl.first['id'],'branch_id':branchId},conflictAlgorithm:ConflictAlgorithm.ignore);}
    final catRows=await db.query('expense_categories',columns:['id','name_ar'],where:'branch_id=?',whereArgs:[branchId],orderBy:'id');
    final expSeeds=<List<Object>>[['كهرباء',1200.0,'فاتورة كهرباء تجريبية'],['ماء',300.0,'فاتورة ماء تجريبية'],['أكياس وتغليف',450.0,'مواد تغليف تجريبية']];
    for(var i=0;i<expSeeds.length;i++){final e=expSeeds[i];final exists=await db.query('expenses',columns:['id'],where:'expense_no=?',whereArgs:['SEED-EXP-${i+1}']);if(exists.isNotEmpty)continue;final cat=catRows.firstWhere((r)=>r['name_ar']==e[0]);await db.insert('expenses',{'expense_no':'SEED-EXP-${i+1}','category_id':cat['id'],'expense_date':now,'amount':e[1],'cash_account_id':safe['id'],'paid_to':'مورد تجريبي','description':e[2],'branch_id':branchId});}
    final partySeeds=<List<Object>>[
      ['EMPLOYEE','EMP-PHARM','صيدلي تجريبي','PHARMACIST','MONTHLY',45000.0],
      ['EMPLOYEE','EMP-CASH','كاشير تجريبي','CASHIER','MONTHLY',30000.0],
      ['EMPLOYEE','EMP-DAILY','عامل يومي تجريبي','OTHER','DAILY',1500.0],
    ];
    final employeeIds=<int>[];
    for(final p in partySeeds){var rows=await db.query('parties',columns:['id'],where:'code=?',whereArgs:[p[1]],limit:1);int partyId;if(rows.isEmpty){partyId=await db.insert('parties',{'uuid':'it4-party-${p[1]}','branch_id':branchId,'created_at':now,'updated_at':now,'party_type':p[0],'code':p[1],'name_ar':p[2],'opening_alayh':0,'opening_lah':0});}else{partyId=rows.first['id'] as int;}final emp=await db.query('employees',columns:['id'],where:'party_id=?',whereArgs:[partyId],limit:1);int employeeId;if(emp.isEmpty){employeeId=await db.insert('employees',{'party_id':partyId,'job_title':p[3],'hire_date':now.substring(0,10),'pay_type':p[4],'pay_rate':p[5],'max_advance_pct':50,'branch_id':branchId});}else{employeeId=emp.first['id'] as int;}employeeIds.add(employeeId);}
    final work=await db.query('work_shifts',columns:['id'],where:'name_ar=?',whereArgs:['صباحية'],limit:1);
    for(final employeeId in employeeIds){await db.insert('employee_attendance',{'employee_id':employeeId,'work_date':now.substring(0,10),'work_shift_id':work.first['id'],'status':'PRESENT','wage_earned':0},conflictAlgorithm:ConflictAlgorithm.ignore);}
    final cashierParty=await db.query('parties',columns:['id'],where:'code=?',whereArgs:['EMP-CASH'],limit:1);
    if(users.isNotEmpty){final open=await db.query('cashier_shifts',columns:['id'],where:"branch_id=? AND status='OPEN'",whereArgs:[branchId],limit:1);if(open.isEmpty){await db.insert('cashier_shifts',{'shift_no':'SHIFT-SEED-${now.substring(0,10)}','user_id':users.first['id'],'cashier_party_id':cashierParty.isEmpty?null:cashierParty.first['id'],'drawer_account_id':drawer['id'],'work_shift_id':work.first['id'],'opened_at':now,'opening_cash':0,'status':'OPEN','branch_id':branchId});}}
    final partnerSeeds=<List<Object>>[['PART-50','الشريك الأول',50],['PART-30','الشريك الثاني',30],['PART-20','الشريك الثالث',20]];
    for(final p in partnerSeeds){var rows=await db.query('parties',columns:['id'],where:'code=?',whereArgs:[p[0]],limit:1);int partyId;if(rows.isEmpty){partyId=await db.insert('parties',{'uuid':'it4-party-${p[0]}','branch_id':branchId,'created_at':now,'updated_at':now,'party_type':'PARTNER','code':p[0],'name_ar':p[1],'opening_alayh':0,'opening_lah':0});}else{partyId=rows.first['id'] as int;}await db.insert('partners',{'party_id':partyId,'capital_amount':0,'shares_count':p[2],'percentage':null,'needs_input':0,'join_date':now.substring(0,10),'is_active':1,'branch_id':branchId},conflictAlgorithm:ConflictAlgorithm.ignore);}
    final existingWithdrawal=await db.query('lah_alayh_ledger',columns:['id'],where:"entry_type='PARTNER_WITHDRAWAL' AND statement_ar='سحب شخصي تجريبي للشريك'",limit:1);
    if(existingWithdrawal.isEmpty){final partner=await db.query('partners',columns:['id','party_id'],orderBy:'id',limit:1);if(partner.isNotEmpty){await db.insert('lah_alayh_ledger',{'uuid':'it4-partner-withdrawal','branch_id':branchId,'created_at':now,'updated_at':now,'party_id':partner.first['party_id'],'entry_date':now,'entry_type':'PARTNER_WITHDRAWAL','alayh_amount':500,'lah_amount':0,'doc_type':'SEED','doc_id':null,'statement_ar':'سحب شخصي تجريبي للشريك'});}}
  }
}
