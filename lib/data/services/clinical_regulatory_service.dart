import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/clinical_and_rx_models.dart';

/// Branch-scoped, read-only clinical/controlled medicine audit queries.
/// Stock movements are the sole movement ledger: no duplicate accounting rows.
class ClinicalRegulatoryService {
  ClinicalRegulatoryService({DatabaseHelper? helper})
      : _helper = helper ?? DatabaseHelper.instance;
  final DatabaseHelper _helper;

  static String maskedId(Object? input) {
    final value = input?.toString().trim() ?? '';
    if (value.isEmpty) return '—';
    return value.length <= 4 ? '••••' : '••••${value.substring(value.length - 4)}';
  }

  static String maskedName(Object? input) {
    final name = input?.toString().trim() ?? '';
    if (name.isEmpty) return '—';
    final first = name.split(RegExp(r'\s+')).first;
    return '$first •••';
  }

  /// Link only decisions created in the active clinical review to this sale.
  /// The link is append-only, unique per alert and inside the posting transaction.
  /// Never retroactively assign old unlinked decisions to nearby invoices.
  static Future<void> linkDecisions(
    Transaction txn, {
    required int branchId,
    required int invoiceId,
    required ClinicalVerdict verdict,
  }) async {
    final seen = <int>{};
    final invoice = await txn.query('sales_invoices',
        columns: ['id'],
        where: 'id=? AND branch_id=?',
        whereArgs: [invoiceId, branchId],
        limit: 1);
    if (invoice.isEmpty) throw StateError('فاتورة خارج الفرع المحدد');
    for (final alert in verdict.alerts) {
      final logId = alert.id;
      if (logId == null || alert.userDecision == null) continue;
      if (!seen.add(logId)) throw StateError('تكرار قرار سريري في الفاتورة');
      final rows = await txn.rawQuery('''
        SELECT l.id FROM clinical_alert_logs l
        JOIN drugs d ON d.id=l.drug_id
        WHERE l.id=? AND d.branch_id=? AND l.user_decision=?
          AND l.alert_category=? AND l.message_ar=?
          AND (l.invoice_id IS NULL OR l.invoice_id=?)
      ''', [
        logId,
        branchId,
        alert.userDecision,
        alert.category,
        alert.messageAr,
        invoiceId
      ]);
      if (rows.length != 1) {
        throw StateError('قرار سريري غير موثق أو لا يخص هذا الفرع');
      }
      await txn.insert('clinical_alert_invoice_links', {
        'alert_log_id': logId,
        'invoice_id': invoiceId,
        'branch_id': branchId,
      });
    }
  }

  /// Newly posted snapshots only: legacy running_balance_units represented
  /// cumulative dispensed quantities and must never be silently relabeled.
  static Future<void> recordVerifiedBalance(
    Transaction txn, {
    required int branchId,
    required int drugId,
    required int logId,
    required int physicalAfterUnits,
    required int batchAfterUnits,
  }) async {
    if (physicalAfterUnits < 0 || batchAfterUnits < 0) {
      throw StateError('رصيد الدواء المراقب غير صالح');
    }
    final rows = await txn.rawQuery('''
      SELECT c.id FROM controlled_drug_log c
      JOIN drugs d ON d.id=c.drug_id
      WHERE c.id=? AND d.id=? AND d.branch_id=?
    ''', [logId, drugId, branchId]);
    if (rows.length != 1) {
      throw StateError('عملية الصرف المراقب لا تخص هذا الفرع');
    }
    await txn.insert('controlled_balance_snapshots', {
      'log_id': logId,
      'branch_id': branchId,
      'drug_id': drugId,
      'physical_after_units': physicalAfterUnits,
      'batch_after_units': batchAfterUnits,
    });
  }

  static (String, List<Object?>) _filters({
    required String dateColumn,
    required String searchExpr,
    String? search,
    String? dateFrom,
    String? dateTo,
  }) {
    final where = StringBuffer();
    final args = <Object?>[];
    if (dateFrom != null && dateFrom.isNotEmpty) {
      where.write(' AND substr($dateColumn,1,10)>=?');
      args.add(dateFrom);
    }
    if (dateTo != null && dateTo.isNotEmpty) {
      where.write(' AND substr($dateColumn,1,10)<=?');
      args.add(dateTo);
    }
    final term = search?.trim() ?? '';
    if (term.isNotEmpty) {
      where.write(' AND ($searchExpr)');
      args.addAll(List<Object?>.filled(
          searchExpr.split('?').length - 1, '%$term%'));
    }
    return (where.toString(), args);
  }

  Future<List<Map<String, Object?>>> alerts({
    required int branchId,
    String? search,
    String? dateFrom,
    String? dateTo,
    String? level,
    int limit = 50,
    int offset = 0,
  }) async {
    final (filters, args) = _filters(
      dateColumn: 'a.alert_at',
      searchExpr: '''d.trade_name_ar LIKE ? OR a.message_ar LIKE ?
        OR a.alert_category LIKE ? OR COALESCE(i.invoice_no,'') LIKE ?''',
      search: search,
      dateFrom: dateFrom,
      dateTo: dateTo,
    );
    final levelSql = level == null || level.isEmpty ? '' : ' AND a.level=?';
    final db = await _helper.database;
    return db.rawQuery('''
      SELECT a.*,d.trade_name_ar, d.branch_id,
        i.invoice_no,COALESCE(link.invoice_id,a.invoice_id) AS linked_invoice_id,
        u.full_name AS decided_by_name, mu.full_name AS manager_name
      FROM clinical_alert_logs a
      JOIN drugs d ON d.id=a.drug_id
      LEFT JOIN clinical_alert_invoice_links link ON link.alert_log_id=a.id
      LEFT JOIN sales_invoices i ON i.id=COALESCE(link.invoice_id,a.invoice_id)
        AND i.branch_id=d.branch_id
      LEFT JOIN users u ON u.id=a.decided_by AND u.branch_id=d.branch_id
      LEFT JOIN users mu ON mu.id=a.manager_user_id AND mu.branch_id=d.branch_id
      WHERE d.branch_id=? $filters $levelSql
      ORDER BY a.alert_at DESC,a.id DESC LIMIT ? OFFSET ?
    ''', [
      branchId,
      ...args,
      if (levelSql.isNotEmpty) level,
      limit.clamp(1, 200),
      offset < 0 ? 0 : offset
    ]);
  }

  Future<List<Map<String, Object?>>> controlled({
    required int branchId,
    String? search,
    String? dateFrom,
    String? dateTo,
    int limit = 50,
    int offset = 0,
  }) async {
    final (filters, args) = _filters(
      dateColumn: 'c.recorded_at',
      searchExpr: '''d.trade_name_ar LIKE ? OR c.patient_name LIKE ?
        OR COALESCE(i.invoice_no,'') LIKE ? OR COALESCE(pr.rx_no,'') LIKE ?''',
      search: search,
      dateFrom: dateFrom,
      dateTo: dateTo,
    );
    return (await _helper.database).rawQuery('''
      SELECT c.*,d.trade_name_ar,d.branch_id,d.controlled_schedule,
        i.invoice_no,pr.rx_no,b.batch_no,w.name_ar AS warehouse_name,
        u.full_name AS pharmacist_name,
        snap.physical_after_units AS verified_balance_after_units,
        snap.batch_after_units AS verified_batch_after_units,
        CASE WHEN snap.log_id IS NULL THEN 0 ELSE 1 END AS balance_verified
      FROM controlled_drug_log c
      JOIN drugs d ON d.id=c.drug_id
      LEFT JOIN controlled_balance_snapshots snap ON snap.log_id=c.id
        AND snap.branch_id=d.branch_id
      LEFT JOIN sales_invoice_items si ON si.id=c.invoice_item_id
      LEFT JOIN sales_invoices i ON i.id=si.invoice_id AND i.branch_id=d.branch_id
      LEFT JOIN prescriptions pr ON pr.id=c.prescription_id
      LEFT JOIN batches_fefo b ON b.id=c.batch_id AND b.drug_id=d.id
      LEFT JOIN warehouses w ON w.id=b.warehouse_id AND w.branch_id=d.branch_id
      LEFT JOIN users u ON u.id=c.pharmacist_user_id AND u.branch_id=d.branch_id
      WHERE d.branch_id=? $filters
      ORDER BY c.recorded_at DESC,c.id DESC LIMIT ? OFFSET ?
    ''', [branchId, ...args, limit.clamp(1, 200), offset < 0 ? 0 : offset]);
  }

  /// Complete stock movement ledger for medicines under regulation.
  /// balance_after_units is the recorded balance of the BATCH, never the branch.
  Future<List<Map<String, Object?>>> movements({
    required int branchId,
    String? search,
    String? dateFrom,
    String? dateTo,
    int limit = 50,
    int offset = 0,
  }) async {
    final (filters, args) = _filters(
      dateColumn: 'm.movement_at',
      searchExpr: '''d.trade_name_ar LIKE ? OR b.batch_no LIKE ?
        OR m.movement_type LIKE ? OR COALESCE(m.doc_type,'') LIKE ?''',
      search: search,
      dateFrom: dateFrom,
      dateTo: dateTo,
    );
    return (await _helper.database).rawQuery('''
      SELECT m.id,m.drug_id,m.batch_id,m.warehouse_id,m.movement_type,
        m.qty_units,m.balance_after_units,m.movement_at,m.doc_type,m.doc_id,
        m.note,d.trade_name_ar,b.batch_no,w.name_ar AS warehouse_name
      FROM stock_movements m
      JOIN drugs d ON d.id=m.drug_id
      JOIN warehouses w ON w.id=m.warehouse_id AND w.branch_id=d.branch_id
      JOIN batches_fefo b ON b.id=m.batch_id AND b.drug_id=d.id
      WHERE d.branch_id=? AND
        (d.is_controlled=1 OR EXISTS(
          SELECT 1 FROM controlled_drug_log c WHERE c.drug_id=d.id))
        $filters
      ORDER BY m.movement_at DESC,m.id DESC LIMIT ? OFFSET ?
    ''', [branchId, ...args, limit.clamp(1, 200), offset < 0 ? 0 : offset]);
  }

  Future<Map<String, int>> summary({required int branchId}) async {
    final db = await _helper.database;
    Future<int> count(String sql) async {
      final rows = await db.rawQuery(sql, [branchId]);
      return (rows.first.values.first as num).toInt();
    }
    return {
      'decisions': await count('''
        SELECT COUNT(*) FROM clinical_alert_logs a
        JOIN drugs d ON d.id=a.drug_id WHERE d.branch_id=?'''),
      'critical': await count('''
        SELECT COUNT(*) FROM clinical_alert_logs a
        JOIN drugs d ON d.id=a.drug_id
        WHERE d.branch_id=? AND a.level='BLOCK' '''),
      'overrides': await count('''
        SELECT COUNT(*) FROM clinical_alert_logs a
        JOIN drugs d ON d.id=a.drug_id
        WHERE d.branch_id=? AND a.user_decision='OVERRIDDEN_WITH_PIN' '''),
      'dispenses': await count('''
        SELECT COUNT(*) FROM controlled_drug_log c
        JOIN drugs d ON d.id=c.drug_id WHERE d.branch_id=?'''),
      'unverifiedLegacy': await count('''
        SELECT COUNT(*) FROM controlled_drug_log c
        JOIN drugs d ON d.id=c.drug_id
        LEFT JOIN controlled_balance_snapshots snap ON snap.log_id=c.id
        WHERE d.branch_id=? AND snap.log_id IS NULL'''),
      'movements': await count('''
        SELECT COUNT(*) FROM stock_movements m
        JOIN drugs d ON d.id=m.drug_id
        JOIN warehouses w ON w.id=m.warehouse_id AND w.branch_id=d.branch_id
        WHERE d.branch_id=? AND (d.is_controlled=1 OR EXISTS(
          SELECT 1 FROM controlled_drug_log c WHERE c.drug_id=d.id))''')
    };
  }
}
