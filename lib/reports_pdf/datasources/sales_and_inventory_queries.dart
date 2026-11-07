// lib/reports_pdf/datasources/sales_and_inventory_queries.dart
import '../../data/database/database_helper.dart';
import '../models_and_contracts.dart';

/// استعلامات التقارير 01–24. جميع القيم مشتقة من جداول الدورة 1–4.
class SalesAndInventoryQueries {
  SalesAndInventoryQueries({DatabaseHelper? helper})
      : _helper = helper ?? DatabaseHelper.instance;
  final DatabaseHelper _helper;

  Future<List<Map<String, Object?>>> _q(String sql,
          [List<Object?> args = const []]) async =>
      (await _helper.database).rawQuery(sql, args);

  String _range(String column, ReportParams p) =>
      " AND (? IS NULL OR $column >= ?) AND (? IS NULL OR $column < date(?, '+1 day'))";

  List<Object?> _rangeArgs(ReportParams p) {
    final from = p.stringValue('date_from');
    final to = p.stringValue('date_to');
    return [from, from, to, to];
  }

  Future<List<Map<String, Object?>>> r01(ReportParams p) => _q('''
    SELECT i.invoice_no AS invoice_no, time(i.invoice_date) AS invoice_time,
      COALESCE(c.name_ar,'عميل نقدي') AS customer, u.full_name AS cashier,
      COALESCE((SELECT GROUP_CONCAT(DISTINCT sp.method) FROM sales_payments sp WHERE sp.invoice_id=i.id),i.sale_type) AS payment_method, i.subtotal AS gross, i.discount_amount AS discount,
      i.net_total AS net, i.paid_total AS paid, i.remaining_alayh AS remaining
    FROM sales_invoices i
    LEFT JOIN parties c ON c.id=i.customer_party_id
    LEFT JOIN users u ON u.id=i.cashier_user_id
    WHERE i.branch_id=? AND i.is_deleted=0 AND i.status='COMPLETED'
      ${_range('i.invoice_date', p)}
    ORDER BY i.invoice_date DESC, i.id DESC
  ''', [p.branchId, ..._rangeArgs(p)]);

  Future<List<Map<String, Object?>>> r02(ReportParams p) => _q('''
    SELECT CASE WHEN ?='monthly' THEN substr(i.invoice_date,1,7) ELSE date(i.invoice_date) END AS period,
      COUNT(*) AS invoice_count, SUM(i.subtotal) AS gross_sales,
      SUM(i.discount_amount) AS discounts, COALESCE(SUM(sr.total_refund),0) AS returns,
      SUM(i.net_total)-COALESCE(SUM(sr.total_refund),0) AS net_sales,
      AVG(i.net_total) AS average_invoice
    FROM sales_invoices i
    LEFT JOIN (SELECT original_invoice_id,SUM(total_refund) total_refund FROM sales_returns WHERE status IN('APPROVED','POSTED') GROUP BY original_invoice_id) sr ON sr.original_invoice_id=i.id
    WHERE i.branch_id=? AND i.is_deleted=0 AND i.status='COMPLETED'
      ${_range('i.invoice_date', p)}
    GROUP BY period ORDER BY period
  ''', [p.stringValue('grouping') ?? 'daily', p.branchId, ..._rangeArgs(p)]);

  Future<List<Map<String, Object?>>> r03(ReportParams p) => _q('''
    WITH payment_by_invoice AS (
      SELECT invoice_id,
        SUM(CASE WHEN method='CASH' THEN amount ELSE 0 END) AS cash_total,
        SUM(CASE WHEN method<>'CASH' THEN amount ELSE 0 END) AS wallets_total
      FROM sales_payments GROUP BY invoice_id
    ), return_by_invoice AS (
      SELECT original_invoice_id,SUM(total_refund) AS returns
      FROM sales_returns WHERE status IN('APPROVED','POSTED') GROUP BY original_invoice_id
    ), shift_by_user AS (
      SELECT user_id,SUM(COALESCE(diff_amount,0)) AS shift_difference
      FROM cashier_shifts cs WHERE cs.branch_id=? ${_range('cs.opened_at', p)}
      GROUP BY user_id
    )
    SELECT u.full_name AS cashier,COUNT(i.id) AS invoice_count,
      COALESCE(SUM(i.subtotal),0) AS gross_sales,
      COALESCE(SUM(pay.cash_total),0) AS cash_total,
      COALESCE(SUM(pay.wallets_total),0) AS wallets_total,
      COALESCE(SUM(i.remaining_alayh),0) AS credit_total,
      COALESCE(SUM(i.discount_amount),0) AS discounts,
      COALESCE(SUM(ret.returns),0) AS returns,
      COALESCE(MAX(sh.shift_difference),0) AS shift_difference,
      AVG(i.net_total) AS average_invoice
    FROM sales_invoices i JOIN users u ON u.id=i.cashier_user_id
    LEFT JOIN payment_by_invoice pay ON pay.invoice_id=i.id
    LEFT JOIN return_by_invoice ret ON ret.original_invoice_id=i.id
    LEFT JOIN shift_by_user sh ON sh.user_id=u.id
    WHERE i.branch_id=? AND i.is_deleted=0 AND i.status='COMPLETED'
      ${_range('i.invoice_date', p)}
    GROUP BY u.id,u.full_name ORDER BY gross_sales DESC
  ''', [p.branchId, ..._rangeArgs(p), p.branchId, ..._rangeArgs(p)]);

  Future<List<Map<String, Object?>>> r04(ReportParams p) => _q('''
    WITH filtered AS (
      SELECT sp.method,sp.amount FROM sales_payments sp
      JOIN sales_invoices i ON i.id=sp.invoice_id
      WHERE i.branch_id=? AND i.status='COMPLETED' ${_range('i.invoice_date', p)}
    )
    SELECT COALESCE(method,'غير محدد') AS payment_method,COUNT(*) AS operation_count,
      SUM(amount) AS amount,
      CASE WHEN (SELECT COALESCE(SUM(amount),0) FROM filtered)>0 THEN SUM(amount)*100.0/(SELECT COALESCE(SUM(amount),0) FROM filtered) ELSE 0 END AS percentage
    FROM filtered GROUP BY method ORDER BY amount DESC
  ''', [p.branchId, ..._rangeArgs(p)]);

  Future<List<Map<String, Object?>>> r05(ReportParams p) => _q('''
    SELECT i.invoice_date AS tx_date,i.invoice_no AS document_no,
      ca.name_ar AS wallet,sp.wallet_ref_no AS notification_no,
      sp.wallet_sender_phone AS sender_phone,sp.amount AS amount,
      u.full_name AS cashier,
      CASE WHEN sp.wallet_ref_no IS NOT NULL AND sp.wallet_ref_no<>'' AND
        (SELECT COUNT(*) FROM sales_payments x WHERE x.wallet_ref_no=sp.wallet_ref_no)>1 THEN 1 ELSE 0 END AS duplicate_alert
    FROM sales_payments sp JOIN sales_invoices i ON i.id=sp.invoice_id
    LEFT JOIN cash_accounts ca ON ca.id=sp.cash_account_id
    LEFT JOIN users u ON u.id=i.cashier_user_id
    WHERE i.branch_id=? AND i.status='COMPLETED' AND sp.wallet_ref_no IS NOT NULL
      ${_range('i.invoice_date', p)}
    ORDER BY i.invoice_date DESC
  ''', [p.branchId, ..._rangeArgs(p)]);

  Future<List<Map<String, Object?>>> r06(ReportParams p) => _q('''
    SELECT i.invoice_no AS invoice_no,i.invoice_date AS invoice_date,
      i.net_total AS net_sales,i.total_cost AS cogs,
      i.net_total-i.total_cost AS gross_profit,
      CASE WHEN i.net_total>0 THEN (i.net_total-i.total_cost)*100.0/i.net_total ELSE 0 END AS margin_pct
    FROM sales_invoices i WHERE i.branch_id=? AND i.status='COMPLETED'
      ${_range('i.invoice_date', p)} ORDER BY i.invoice_date DESC
  ''', [p.branchId, ..._rangeArgs(p)]);

  Future<List<Map<String, Object?>>> r07(ReportParams p) => _q('''
    WITH sold AS (
      SELECT d.id,d.trade_name_ar AS drug,d.category_id AS category_id,
        SUM(si.qty_units) AS units_sold,SUM(si.line_total) AS sales_value,
        SUM(si.line_cost) AS cost_value
      FROM sales_invoice_items si JOIN sales_invoices i ON i.id=si.invoice_id
      JOIN drugs d ON d.id=si.drug_id
      WHERE i.branch_id=? AND i.status='COMPLETED' ${_range('i.invoice_date', p)}
      GROUP BY d.id
    ), totals AS (SELECT SUM(sales_value) total_sales,SUM(sales_value-cost_value) total_profit FROM sold)
    SELECT (SELECT COUNT(*)+1 FROM sold ranked WHERE ranked.units_sold>s.units_sold OR (ranked.units_sold=s.units_sold AND ranked.id<s.id)) AS rank,s.drug,
      dc.name_ar AS category,s.units_sold,s.sales_value,s.cost_value,
      s.sales_value-s.cost_value AS profit,
      CASE WHEN s.sales_value>0 THEN (s.sales_value-s.cost_value)*100.0/s.sales_value ELSE 0 END AS margin_pct,
      CASE WHEN t.total_profit>0 THEN (s.sales_value-s.cost_value)*100.0/t.total_profit ELSE 0 END AS contribution_pct
    FROM sold s LEFT JOIN drug_categories dc ON dc.id=s.category_id CROSS JOIN totals t
    ORDER BY s.units_sold DESC
  ''', [p.branchId, ..._rangeArgs(p)]);

  Future<List<Map<String, Object?>>> r08(ReportParams p) => _q('''
    SELECT d.id AS drug_id,d.trade_name_ar AS drug,d.stock_total_units AS balance,
      d.stock_total_units*d.last_purchase_cost_pack/CASE WHEN COALESCE(d.units_per_pack,0)>0 THEN d.units_per_pack ELSE 1 END AS cost_value,
      (SELECT MAX(i.invoice_date) FROM sales_invoice_items si JOIN sales_invoices i ON i.id=si.invoice_id WHERE si.drug_id=d.id AND i.status='COMPLETED') AS last_sale,
      CAST(julianday('now')-julianday((SELECT MAX(i.invoice_date) FROM sales_invoice_items si JOIN sales_invoices i ON i.id=si.invoice_id WHERE si.drug_id=d.id AND i.status='COMPLETED')) AS INTEGER) AS idle_days,
      (SELECT MIN(b.expiry_date) FROM batches_fefo b WHERE b.drug_id=d.id AND b.total_units>0) AS nearest_expiry
    FROM drugs d WHERE d.branch_id=? AND d.is_active=1 AND d.stock_total_units>0
      AND NOT EXISTS(SELECT 1 FROM sales_invoice_items si JOIN sales_invoices i ON i.id=si.invoice_id
        WHERE si.drug_id=d.id AND i.status='COMPLETED' AND i.invoice_date>=date('now','-' || ? || ' days'))
    ORDER BY idle_days DESC
  ''', [p.branchId, p.intValue('idle_days') ?? 60]);

  Future<List<Map<String, Object?>>> r09(ReportParams p) => _q('''
    SELECT d.trade_name_ar AS drug,
      SUM(CASE WHEN si.sell_unit='PACK' THEN si.qty_in_sell_unit ELSE 0 END) AS pack_qty,
      SUM(CASE WHEN si.sell_unit='PACK' THEN si.line_total ELSE 0 END) AS pack_value,
      SUM(CASE WHEN si.sell_unit='STRIP' THEN si.qty_in_sell_unit ELSE 0 END) AS strip_qty,
      SUM(CASE WHEN si.sell_unit='STRIP' THEN si.line_total ELSE 0 END) AS strip_value,
      SUM(CASE WHEN si.sell_unit='UNIT' THEN si.qty_in_sell_unit ELSE 0 END) AS unit_qty,
      SUM(CASE WHEN si.sell_unit='UNIT' THEN si.line_total ELSE 0 END) AS unit_value,
      SUM(si.line_total) AS total_value,
      CASE WHEN SUM(si.line_total)>0 THEN
        SUM(CASE WHEN si.sell_unit IN('STRIP','UNIT') THEN si.line_total ELSE 0 END)*100.0/SUM(si.line_total) ELSE 0 END AS loose_pct
    FROM sales_invoice_items si JOIN sales_invoices i ON i.id=si.invoice_id
    JOIN drugs d ON d.id=si.drug_id
    WHERE i.branch_id=? AND i.status='COMPLETED' ${_range('i.invoice_date', p)}
    GROUP BY d.id ORDER BY total_value DESC
  ''', [p.branchId, ..._rangeArgs(p)]);

  Future<List<Map<String, Object?>>> r10(ReportParams p) => _q('''
    SELECT i.invoice_date AS date,i.invoice_no AS invoice_no,COALESCE(c.name_ar,'عميل نقدي') AS customer,
      u.full_name AS cashier,i.subtotal AS gross,
      CASE WHEN i.subtotal>0 THEN i.discount_amount*100.0/i.subtotal ELSE 0 END AS discount_pct,
      i.discount_amount AS discount,NULL AS approving_manager
    FROM sales_invoices i LEFT JOIN parties c ON c.id=i.customer_party_id
    LEFT JOIN users u ON u.id=i.cashier_user_id
    WHERE i.branch_id=? AND i.discount_amount>0 ${_range('i.invoice_date', p)}
    ORDER BY i.invoice_date DESC
  ''', [p.branchId, ..._rangeArgs(p)]);

  Future<List<Map<String, Object?>>> r11(ReportParams p) => _q('''
    SELECT sr.return_no AS return_no,sr.return_date AS return_date,i.invoice_no AS original_invoice,
      d.trade_name_ar AS drug,SUM(sri.qty_units) AS quantity,SUM(sri.refund_amount) AS refund_value,
      sr.refund_method AS refund_method,COALESCE(sr.reason_text,sr.reason_code) AS reason,
      sri.disposition AS inspection_decision
    FROM sales_returns sr JOIN sales_invoices i ON i.id=sr.original_invoice_id
    JOIN sales_return_items sri ON sri.sales_return_id=sr.id
    JOIN sales_invoice_items si ON si.id=sri.invoice_item_id
    JOIN drugs d ON d.id=si.drug_id
    WHERE i.branch_id=? ${_range('sr.return_date', p)}
    GROUP BY sr.id,sri.invoice_item_id ORDER BY sr.return_date DESC
  ''', [p.branchId, ..._rangeArgs(p)]);

  Future<List<Map<String, Object?>>> r12(ReportParams p) => _q('''
    WITH filtered AS (
      SELECT CAST(strftime('%H',invoice_date) AS INTEGER) AS hour,net_total
      FROM sales_invoices WHERE branch_id=? AND status='COMPLETED' ${_range('invoice_date', p)}
    )
    SELECT hour,COUNT(*) AS invoice_count,SUM(net_total) AS sales_total,
      AVG(net_total) AS average_invoice,
      CASE WHEN (SELECT COALESCE(SUM(net_total),0) FROM filtered)>0 THEN SUM(net_total)*100.0/(SELECT COALESCE(SUM(net_total),0) FROM filtered) ELSE 0 END AS day_percentage
    FROM filtered GROUP BY hour ORDER BY hour
  ''', [p.branchId, ..._rangeArgs(p)]);

  Future<List<Map<String, Object?>>> r13(ReportParams p) => _q('''
    SELECT d.trade_name_ar AS drug,d.strength_text AS strength,
      SUM(b.sealed_packs) AS sealed_packs,SUM(b.loose_units) AS loose_units,
      SUM(b.total_units) AS total_units,d.units_per_pack AS units_per_pack,
      d.last_purchase_cost_pack AS pack_cost,
      SUM(b.total_units)*d.last_purchase_cost_pack/CASE WHEN COALESCE(d.units_per_pack,0)>0 THEN d.units_per_pack ELSE 1 END AS cost_value,
      d.sell_price_pack AS sell_pack,
      SUM(b.total_units)*d.sell_price_pack/CASE WHEN COALESCE(d.units_per_pack,0)>0 THEN d.units_per_pack ELSE 1 END AS sale_value,
      SUM(b.total_units)*(d.sell_price_pack-d.last_purchase_cost_pack)/CASE WHEN COALESCE(d.units_per_pack,0)>0 THEN d.units_per_pack ELSE 1 END AS expected_profit
    FROM batches_fefo b JOIN drugs d ON d.id=b.drug_id
    WHERE d.branch_id=? AND b.total_units>0 GROUP BY d.id ORDER BY d.trade_name_ar
  ''', [p.branchId]);

  Future<List<Map<String, Object?>>> r14(ReportParams p) => _q('''
    SELECT d.trade_name_ar AS drug,b.batch_no AS batch_no,b.expiry_date AS expiry_date,
      CAST(julianday('now')-julianday(b.expiry_date) AS INTEGER) AS days_expired,
      b.total_units AS balance,b.unit_cost AS unit_cost,b.total_units*b.unit_cost AS loss_value,
      w.name_ar AS location,COALESCE(s.name_ar,'غير محدد') AS supplier
    FROM batches_fefo b JOIN drugs d ON d.id=b.drug_id
    JOIN warehouses w ON w.id=b.warehouse_id
    LEFT JOIN purchase_invoice_items pii ON pii.id=b.purchase_invoice_item_id
    LEFT JOIN purchase_invoices pi ON pi.id=pii.invoice_id
    LEFT JOIN parties s ON s.id=pi.supplier_party_id
    WHERE d.branch_id=? AND b.total_units>0 AND date(b.expiry_date)<date('now')
    ORDER BY b.expiry_date
  ''', [p.branchId]);

  Future<List<Map<String, Object?>>> r15(ReportParams p) => _q('''
    SELECT CASE WHEN julianday(b.expiry_date)-julianday('now')<=30 THEN '30 يوماً'
      WHEN julianday(b.expiry_date)-julianday('now')<=60 THEN '60 يوماً' ELSE '90 يوماً' END AS segment,
      d.trade_name_ar AS drug,b.batch_no AS batch_no,b.expiry_date AS expiry_date,
      CAST(julianday(b.expiry_date)-julianday('now') AS INTEGER) AS days_remaining,
      b.total_units AS balance,b.total_units*b.unit_cost AS cost_value,
      COALESCE((SELECT SUM(si.qty_units)*1.0/30 FROM sales_invoice_items si JOIN sales_invoices i ON i.id=si.invoice_id
        WHERE si.drug_id=d.id AND i.status='COMPLETED' AND i.invoice_date>=date('now','-30 days')),0) AS average_daily_sales,
      CASE WHEN COALESCE((SELECT SUM(si.qty_units)*1.0/30 FROM sales_invoice_items si JOIN sales_invoices i ON i.id=si.invoice_id
        WHERE si.drug_id=d.id AND i.status='COMPLETED' AND i.invoice_date>=date('now','-30 days')),0)>0
        THEN b.total_units/(SELECT SUM(si.qty_units)*1.0/30 FROM sales_invoice_items si JOIN sales_invoices i ON i.id=si.invoice_id WHERE si.drug_id=d.id AND i.status='COMPLETED' AND i.invoice_date>=date('now','-30 days')) ELSE NULL END AS expected_clearance_days,
      CASE WHEN b.total_units>0 THEN 'مراجعة المورد والتصريف' ELSE 'لا يلزم إجراء' END AS recommended_action
    FROM batches_fefo b JOIN drugs d ON d.id=b.drug_id
    WHERE d.branch_id=? AND b.total_units>0 AND date(b.expiry_date)>=date('now')
      AND date(b.expiry_date)<=date('now','+' || ? || ' days')
    ORDER BY b.expiry_date
  ''', [p.branchId, p.intValue('expiry_days') ?? 90]);

  Future<List<Map<String, Object?>>> r16(ReportParams p) => _q('''
    WITH selected_drug AS (
      SELECT id,stock_total_units FROM drugs WHERE branch_id=? AND id=?
    ), opening AS (
      SELECT COALESCE(d.stock_total_units,0)-COALESCE((
        SELECT SUM(m.qty_units) FROM stock_movements m
        WHERE m.drug_id=d.id AND (? IS NULL OR m.movement_at>=?)
      ),0) AS opening_balance
      FROM selected_drug d
    ), report_rows AS (
      SELECT 0 AS sort_order,COALESCE(?,'بداية السجل') AS movement_date,
        'رصيد افتتاحي' AS movement_type,'—' AS document,'' AS batch_no,
        0 AS incoming,0 AS outgoing,o.opening_balance AS running_balance,0 AS unit_cost,
        '' AS movement_id
      FROM opening o
      UNION ALL
      SELECT 1 AS sort_order,m.movement_at AS movement_date,m.movement_type AS movement_type,
        m.doc_type || ':' || COALESCE(m.doc_id,'') AS document,
        COALESCE(b.batch_no,'') AS batch_no,
        CASE WHEN m.qty_units>0 THEN m.qty_units ELSE 0 END AS incoming,
        CASE WHEN m.qty_units<0 THEN -m.qty_units ELSE 0 END AS outgoing,
        m.balance_after_units AS running_balance,m.unit_cost AS unit_cost,
        CAST(m.id AS TEXT) AS movement_id
      FROM stock_movements m JOIN drugs d ON d.id=m.drug_id
      LEFT JOIN batches_fefo b ON b.id=m.batch_id
      WHERE d.branch_id=? AND d.id=? ${_range('m.movement_at', p)}
    )
    SELECT movement_date,movement_type,document,batch_no,incoming,outgoing,
      running_balance,unit_cost FROM report_rows
    ORDER BY sort_order,movement_date,movement_id
  ''', [
        p.branchId,
        p.intValue('drug_id') ?? -1,
        p.stringValue('date_from'),
        p.stringValue('date_from'),
        p.stringValue('date_from'),
        p.branchId,
        p.intValue('drug_id') ?? -1,
        ..._rangeArgs(p)
      ]);

  Future<List<Map<String, Object?>>> r17(ReportParams p) => _q('''
    SELECT d.trade_name_ar AS drug,d.stock_total_units AS current_balance,d.min_stock_units AS minimum_stock,
      MAX(d.min_stock_units-d.stock_total_units,0) AS shortage,
      COALESCE((SELECT SUM(si.qty_units)*1.0/30 FROM sales_invoice_items si JOIN sales_invoices i ON i.id=si.invoice_id
        WHERE si.drug_id=d.id AND i.status='COMPLETED' AND i.invoice_date>=date('now','-30 days')),0) AS average_daily_sales,
      MAX(d.reorder_qty_packs,0) AS suggested_order_packs,
      (SELECT p.name_ar FROM purchase_invoice_items pii JOIN purchase_invoices pi ON pi.id=pii.invoice_id JOIN parties p ON p.id=pi.supplier_party_id WHERE pii.drug_id=d.id GROUP BY p.id ORDER BY AVG(pii.effective_pack_cost) LIMIT 1) AS preferred_supplier,
      MAX(d.reorder_qty_packs,0)*d.last_purchase_cost_pack AS expected_cost
    FROM drugs d WHERE d.branch_id=? AND d.is_active=1 AND d.stock_total_units<=d.min_stock_units
    ORDER BY shortage DESC
  ''', [p.branchId]);

  Future<List<Map<String, Object?>>> r18(ReportParams p) => _q('''
    SELECT w.name_ar || ' / ' || COALESCE(sl.code,'') AS location,d.trade_name_ar AS drug,b.batch_no AS batch_no,
      b.expiry_date AS expiry_date,b.total_units AS balance,b.total_units*b.unit_cost AS cost_value
    FROM batches_fefo b JOIN drugs d ON d.id=b.drug_id
    JOIN warehouses w ON w.id=b.warehouse_id LEFT JOIN shelf_locations sl ON sl.id=b.location_id
    WHERE d.branch_id=? AND b.total_units>0
    ORDER BY w.name_ar,sl.code,d.trade_name_ar,b.expiry_date
  ''', [p.branchId]);

  Future<List<Map<String, Object?>>> r19(ReportParams p) => _q('''
    SELECT d.trade_name_ar AS drug,b.batch_no AS batch_no,b.expiry_date AS expiry_date,
      b.status AS status,b.sealed_packs AS sealed_packs,b.loose_units AS loose_units,
      b.total_units AS total_units,b.pack_cost AS pack_cost,b.total_units*b.unit_cost AS total_value
    FROM batches_fefo b JOIN drugs d ON d.id=b.drug_id
    WHERE d.branch_id=? ORDER BY d.trade_name_ar,b.expiry_date
  ''', [p.branchId]);

  Future<List<Map<String, Object?>>> r20(ReportParams p) => _q('''
    SELECT d.trade_name_ar AS drug,b.batch_no AS batch_no,l.system_units AS book_balance,
      l.counted_units AS actual_count,l.diff_units AS difference,
      CASE WHEN l.diff_units<0 THEN 'عجز' WHEN l.diff_units>0 THEN 'زيادة' ELSE 'مطابق' END AS difference_type,
      l.unit_cost AS unit_cost,l.diff_value AS difference_value,l.reason_code AS reason
    FROM stocktaking_lines l JOIN stocktaking_sessions s ON s.id=l.session_id
    JOIN batches_fefo b ON b.id=l.batch_id JOIN drugs d ON d.id=b.drug_id
    WHERE d.branch_id=? AND s.id=? ORDER BY d.trade_name_ar,b.batch_no
  ''', [p.branchId, p.intValue('session_id') ?? -1]);

  Future<List<Map<String, Object?>>> r21(ReportParams p) => _q('''
    SELECT d.disposal_no AS document_no,d.disposal_date AS date,dr.trade_name_ar AS drug,
      b.batch_no AS batch_no,di.qty_units AS quantity,d.reason AS reason,d.method AS disposal_method,
      di.qty_units*di.unit_cost AS loss_value,d.witness_name AS witness
    FROM disposals d JOIN disposal_items di ON di.disposal_id=d.id
    JOIN batches_fefo b ON b.id=di.batch_id JOIN drugs dr ON dr.id=b.drug_id
    WHERE dr.branch_id=? AND d.status IN('APPROVED','POSTED') ${_range('d.disposal_date', p)}
    ORDER BY d.disposal_date DESC
  ''', [p.branchId, ..._rangeArgs(p)]);

  Future<List<Map<String, Object?>>> r22(ReportParams p) => _q('''
    SELECT t.transfer_no AS transfer_no,t.created_at AS date,
      wf.name_ar AS from_warehouse,wt.name_ar AS to_warehouse,d.trade_name_ar AS drug,
      b.batch_no AS batch_no,ti.qty_units AS sent_qty,ti.received_qty_units AS received_qty,
      ti.qty_units-COALESCE(ti.received_qty_units,0) AS receiving_difference,
      ti.qty_units*ti.unit_cost AS value,t.status AS status
    FROM stock_transfers t JOIN stock_transfer_items ti ON ti.transfer_id=t.id
    JOIN warehouses wf ON wf.id=t.from_warehouse_id JOIN warehouses wt ON wt.id=t.to_warehouse_id
    JOIN batches_fefo b ON b.id=ti.from_batch_id JOIN drugs d ON d.id=b.drug_id
    WHERE d.branch_id=? ${_range('t.created_at', p)} ORDER BY t.created_at DESC
  ''', [p.branchId, ..._rangeArgs(p)]);

  Future<List<Map<String, Object?>>> r23(ReportParams p) => _q('''
    WITH inventory AS (
      SELECT d.category_id,COUNT(DISTINCT d.id) AS drug_count,SUM(b.total_units) AS total_units,
        SUM(b.total_units*b.unit_cost) AS cost_value,
        SUM(b.total_units*d.sell_price_pack/CASE WHEN COALESCE(d.units_per_pack,0)>0 THEN d.units_per_pack ELSE 1 END) AS sale_value
      FROM drugs d JOIN batches_fefo b ON b.drug_id=d.id WHERE d.branch_id=? AND b.total_units>0 GROUP BY d.category_id
    )
    SELECT c.name_ar AS therapeutic_category,i.drug_count,i.total_units,i.cost_value,i.sale_value,
      CASE WHEN (SELECT SUM(cost_value) FROM inventory)>0 THEN i.cost_value*100.0/(SELECT SUM(cost_value) FROM inventory) ELSE 0 END AS inventory_percentage
    FROM inventory i LEFT JOIN drug_categories c ON c.id=i.category_id ORDER BY i.cost_value DESC
  ''', [p.branchId]);

  Future<List<Map<String, Object?>>> r24(ReportParams p) => _q('''
    WITH sales_cost AS (
      SELECT si.drug_id,SUM(si.line_cost) AS cogs
      FROM sales_invoice_items si JOIN sales_invoices i ON i.id=si.invoice_id
      WHERE i.branch_id=? AND i.status='COMPLETED' ${_range('i.invoice_date', p)}
      GROUP BY si.drug_id
    ), period_movements AS (
      SELECT m.drug_id,SUM(m.qty_units) AS movement_units
      FROM stock_movements m
      WHERE (? IS NULL OR m.movement_at>=?)
        AND (? IS NULL OR m.movement_at<date(?,'+1 day'))
      GROUP BY m.drug_id
    )
    SELECT d.trade_name_ar AS drug,
      MAX(d.stock_total_units-COALESCE(pm.movement_units,0),0) AS opening_stock,
      d.stock_total_units AS closing_stock,
      (MAX(d.stock_total_units-COALESCE(pm.movement_units,0),0)+d.stock_total_units)/2.0 AS average_stock,
      COALESCE(sc.cogs,0) AS cogs,
      CASE WHEN ((MAX(d.stock_total_units-COALESCE(pm.movement_units,0),0)+d.stock_total_units)/2.0)>0
        THEN COALESCE(sc.cogs,0)/(((MAX(d.stock_total_units-COALESCE(pm.movement_units,0),0)+d.stock_total_units)/2.0)*d.last_purchase_cost_pack/CASE WHEN COALESCE(d.units_per_pack,0)>0 THEN d.units_per_pack ELSE 1 END)
        ELSE 0 END AS turnover_rate,
      CASE WHEN COALESCE(sc.cogs,0)>0
        THEN (((MAX(d.stock_total_units-COALESCE(pm.movement_units,0),0)+d.stock_total_units)/2.0)*d.last_purchase_cost_pack/CASE WHEN COALESCE(d.units_per_pack,0)>0 THEN d.units_per_pack ELSE 1 END)*365.0/sc.cogs
        ELSE 0 END AS days_inventory
    FROM drugs d LEFT JOIN sales_cost sc ON sc.drug_id=d.id
    LEFT JOIN period_movements pm ON pm.drug_id=d.id
    WHERE d.branch_id=? ORDER BY turnover_rate DESC
  ''', [p.branchId, ..._rangeArgs(p), ..._rangeArgs(p), p.branchId]);
}
