import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/database_helper.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration16.dart';
import 'package:global_enterprise_pharmacy_erp/data/models/clinical_and_rx_models.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/clinical_regulatory_service.dart';
import 'package:global_enterprise_pharmacy_erp/reports_pdf/datasources/clinical_and_audit_queries.dart';
import 'package:global_enterprise_pharmacy_erp/reports_pdf/models_and_contracts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  late Database db;
  late ClinicalRegulatoryService service;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    for (final ddl in <String>[
      'CREATE TABLE branches (id INTEGER PRIMARY KEY)',
      '''CREATE TABLE drugs (id INTEGER PRIMARY KEY,branch_id INTEGER NOT NULL,
        trade_name_ar TEXT NOT NULL,is_controlled INTEGER NOT NULL DEFAULT 0,
        controlled_schedule TEXT,stock_total_units INTEGER NOT NULL DEFAULT 0)''',
      '''CREATE TABLE users (id INTEGER PRIMARY KEY,branch_id INTEGER,
        full_name TEXT)''',
      '''CREATE TABLE warehouses (id INTEGER PRIMARY KEY,branch_id INTEGER,
        name_ar TEXT)''',
      '''CREATE TABLE batches_fefo (id INTEGER PRIMARY KEY,drug_id INTEGER,
        warehouse_id INTEGER,batch_no TEXT,total_units INTEGER)''',
      '''CREATE TABLE sales_invoices (id INTEGER PRIMARY KEY,branch_id INTEGER,
        invoice_no TEXT)''',
      '''CREATE TABLE sales_invoice_items (id INTEGER PRIMARY KEY,invoice_id INTEGER)''',
      '''CREATE TABLE prescriptions (id INTEGER PRIMARY KEY,rx_no TEXT)''',
      '''CREATE TABLE patients (id INTEGER PRIMARY KEY,full_name TEXT)''',
      '''CREATE TABLE clinical_alert_logs (
        id INTEGER PRIMARY KEY,drug_id INTEGER,other_drug_id INTEGER,
        patient_id INTEGER,invoice_id INTEGER,alert_at TEXT,
        alert_category TEXT,level TEXT,message_ar TEXT,user_decision TEXT,
        decided_by INTEGER,manager_user_id INTEGER,override_reason TEXT)''',
      '''CREATE TABLE controlled_drug_log (
        id INTEGER PRIMARY KEY,invoice_item_id INTEGER,drug_id INTEGER,
        batch_id INTEGER,qty_units INTEGER,patient_name TEXT,
        patient_national_id TEXT,receiver_name TEXT,receiver_national_id TEXT,
        prescription_id INTEGER,doctor_name TEXT,pharmacist_user_id INTEGER,
        running_balance_units INTEGER,recorded_at TEXT)''',
      '''CREATE TABLE stock_movements (
        id INTEGER PRIMARY KEY,drug_id INTEGER,batch_id INTEGER,
        warehouse_id INTEGER,movement_type TEXT,qty_units INTEGER,
        balance_after_units INTEGER,movement_at TEXT,
        doc_type TEXT,doc_id INTEGER,note TEXT)''',
    ]) {
      await db.execute(ddl);
    }
    await db.insert('branches', {'id': 1});
    await db.insert('branches', {'id': 2});
    await db.insert('drugs', {
      'id': 11, 'branch_id': 1, 'trade_name_ar': 'دواء ألف',
      'is_controlled': 1, 'controlled_schedule': 'A',
      'stock_total_units': 85
    });
    await db.insert('drugs', {
      'id': 22, 'branch_id': 2, 'trade_name_ar': 'دواء باء',
      'is_controlled': 1, 'controlled_schedule': 'B',
      'stock_total_units': 30
    });
    await db.insert('warehouses', {'id': 1, 'branch_id': 1, 'name_ar': 'الصيدلية'});
    await db.insert('warehouses', {'id': 2, 'branch_id': 2, 'name_ar': 'مخزن 2'});
    await db.insert('batches_fefo', {
      'id': 101, 'drug_id': 11, 'warehouse_id': 1,
      'batch_no': 'B-1', 'total_units': 85
    });
    await db.insert('batches_fefo', {
      'id': 202, 'drug_id': 22, 'warehouse_id': 2,
      'batch_no': 'B-2', 'total_units': 30
    });
    await db.insert('sales_invoices',
        {'id': 1, 'branch_id': 1, 'invoice_no': 'SALE-1'});
    await db.insert('sales_invoices',
        {'id': 2, 'branch_id': 2, 'invoice_no': 'SALE-2'});
    await db.insert('sales_invoice_items', {'id': 1001, 'invoice_id': 1});
    await db.insert('sales_invoice_items', {'id': 2002, 'invoice_id': 2});
    await db.insert('prescriptions', {'id': 7, 'rx_no': 'RX-7'});
    await db.insert('users',
        {'id': 3, 'branch_id': 1, 'full_name': 'صيدلي فرع 1'});
    await SchemaIteration16.upgrade(db);
    service = ClinicalRegulatoryService(helper: DatabaseHelper.forTesting(db));
  });

  tearDown(() async => db.close());

  Future<void> addAlert(int id, int drugId,
      {String category = 'ALLERGY', String decision = 'ACKNOWLEDGED'}) async {
    await db.insert('clinical_alert_logs', {
      'id': id, 'drug_id': drugId, 'alert_at': '2026-11-14T08:00:00',
      'alert_category': category, 'level': 'WARNING',
      'message_ar': 'مراجعة الحساسية', 'user_decision': decision,
      'decided_by': 3, 'override_reason': 'تمت المراجعة'
    });
  }

  Future<void> addDispense(int id, int drugId, int batchId, int invoiceItem,
      {int historicalCounter = 15}) async {
    await db.insert('controlled_drug_log', {
      'id': id, 'invoice_item_id': invoiceItem,
      'drug_id': drugId, 'batch_id': batchId, 'qty_units': 15,
      'patient_name': 'المريض محمد علي', 'patient_national_id': '12345678901',
      'receiver_name': 'المستلم أحمد علي', 'receiver_national_id': '98765432109',
      'prescription_id': 7, 'doctor_name': 'الطبيب',
      'pharmacist_user_id': 3, 'running_balance_units': historicalCounter,
      'recorded_at': '2026-11-14T08:05:00'
    });
  }

  test('migration is additive, idempotent and immutable', () async {
    await addDispense(1, 11, 101, 1001);
    await SchemaIteration16.upgrade(db);
    final legacy = await db.query('controlled_drug_log', where: 'id=1');
    expect(legacy.single['running_balance_units'], 15);
    expect(await db.query('controlled_balance_snapshots'), isEmpty);
    await db.transaction((txn) => ClinicalRegulatoryService.recordVerifiedBalance(
      txn, branchId: 1, drugId: 11, logId: 1,
      physicalAfterUnits: 85, batchAfterUnits: 85));
    expect((await db.query('controlled_balance_snapshots')).single['physical_after_units'], 85);
    await expectLater(
      db.update('controlled_balance_snapshots', {'physical_after_units': 0},
          where: 'log_id=1'),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      db.delete('controlled_balance_snapshots', where: 'log_id=1'),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      db.transaction((txn) => ClinicalRegulatoryService.recordVerifiedBalance(
        txn, branchId: 1, drugId: 11, logId: 1,
        physicalAfterUnits: 85, batchAfterUnits: 85)),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('invoice correlations are branch checked, unique and atomic', () async {
    await addAlert(10, 11);
    await addAlert(20, 22);
    final valid = ClinicalVerdict([
      const ClinicalAlertModel(
        id: 10, drugId: 11, category: 'ALLERGY',
        level: ClinicalLevel.warning, messageAr: 'مراجعة الحساسية',
        userDecision: 'ACKNOWLEDGED',
      ),
    ]);
    await db.transaction((txn) => ClinicalRegulatoryService.linkDecisions(
      txn, branchId: 1, invoiceId: 1, verdict: valid));
    expect((await db.query('clinical_alert_invoice_links')).single['invoice_id'], 1);
    await expectLater(
      db.transaction((txn) => ClinicalRegulatoryService.linkDecisions(
        txn, branchId: 1, invoiceId: 1, verdict: valid)),
      throwsA(isA<DatabaseException>()),
    );
    final foreign = ClinicalVerdict([
      const ClinicalAlertModel(
        id: 20, drugId: 22, category: 'ALLERGY',
        level: ClinicalLevel.warning, messageAr: 'مراجعة الحساسية',
        userDecision: 'ACKNOWLEDGED',
      ),
    ]);
    await expectLater(
      db.transaction((txn) => ClinicalRegulatoryService.linkDecisions(
        txn, branchId: 1, invoiceId: 1, verdict: foreign)),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      db.transaction((txn) => ClinicalRegulatoryService.linkDecisions(
        txn, branchId: 1, invoiceId: 2, verdict: valid)),
      throwsA(isA<StateError>()),
    );
    expect(await db.query('clinical_alert_invoice_links'), hasLength(1));
    expect((await db.query('clinical_alert_logs', where: 'id=10')).single['invoice_id'], isNull);
  });

  test('records and movements never leak between branches', () async {
    await addAlert(10, 11);
    await addAlert(20, 22);
    await addDispense(1, 11, 101, 1001);
    await addDispense(2, 22, 202, 2002);
    for (final row in [
      {'id': 1, 'drug_id': 11, 'batch_id': 101, 'warehouse_id': 1},
      {'id': 2, 'drug_id': 22, 'batch_id': 202, 'warehouse_id': 2},
    ]) {
      await db.insert('stock_movements', {
        ...row, 'movement_type': 'SALE_OUT', 'qty_units': -15,
        'balance_after_units': 85, 'movement_at': '2026-11-14T09:00:00',
        'doc_type': 'PRESCRIPTION', 'doc_id': 1
      });
    }
    expect((await service.alerts(branchId: 1)).map((r) => r['id']), [10]);
    expect((await service.controlled(branchId: 1)).map((r) => r['id']), [1]);
    expect((await service.movements(branchId: 1)).map((r) => r['id']), [1]);
    expect((await service.summary(branchId: 1))['dispenses'], 1);
    expect((await service.summary(branchId: 2))['dispenses'], 1);
    expect(await service.controlled(branchId: 1, search: 'دواء باء'), isEmpty);
    expect(await service.alerts(branchId: 1, level: 'BLOCK'), isEmpty);
    expect(await service.movements(branchId: 1, offset: 10), isEmpty);
  });

  test('old balances stay unverified while new balances and redacted PDF agree',
      () async {
    await addDispense(1, 11, 101, 1001, historicalCounter: 99);
    await addDispense(2, 11, 101, 1001, historicalCounter: 85);
    await db.transaction((txn) => ClinicalRegulatoryService.recordVerifiedBalance(
      txn, branchId: 1, drugId: 11, logId: 2,
      physicalAfterUnits: 85, batchAfterUnits: 85));
    final rows = await service.controlled(branchId: 1);
    expect(rows.first['verified_balance_after_units'], 85);
    expect(rows.last['verified_balance_after_units'], isNull);
    expect(rows.last['running_balance_units'], 99);
    expect(ClinicalRegulatoryService.maskedId('12345678901'), '••••8901');
    expect(ClinicalRegulatoryService.maskedName('محمد علي'), 'محمد •••');

    final q = ClinicalAndAuditQueries(helper: DatabaseHelper.forTesting(db));
    final report = await q.r47(ReportParams(
      branchId: 1, userId: 3, userName: 'صيدلي',
      canViewCost: false, showCostSetting: false, values: const {},
    ));
    expect(report, hasLength(2));
    expect(report.first['balance_after'], 85);
    expect(report.last['balance_after'], isNull);
    expect(report.last['balance_status'], 'تاريخي غير مثبت');
    expect(report.first['patient_national_id'], '••••8901');
    expect(report.first['patient'], 'محجوب في النسخة العامة');
  });

  test('linked invoice appears in both screen query and clinical PDF', () async {
    await addAlert(10, 11, category: 'INTERACTION');
    final verdict = ClinicalVerdict([
      const ClinicalAlertModel(
        id: 10, drugId: 11, category: 'INTERACTION',
        level: ClinicalLevel.warning, messageAr: 'مراجعة الحساسية',
        userDecision: 'ACKNOWLEDGED',
      ),
    ]);
    await db.transaction((txn) => ClinicalRegulatoryService.linkDecisions(
      txn, branchId: 1, invoiceId: 1, verdict: verdict));
    expect((await service.alerts(branchId: 1)).single['invoice_no'], 'SALE-1');
    final q = ClinicalAndAuditQueries(helper: DatabaseHelper.forTesting(db));
    final pdf = await q.r48(ReportParams(
      branchId: 1, userId: 3, userName: 'صيدلي',
      canViewCost: false, showCostSetting: false, values: const {},
    ));
    expect(pdf.single['invoice_no'], 'SALE-1');
  });
}
