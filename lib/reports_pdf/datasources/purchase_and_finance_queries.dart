// lib/reports_pdf/datasources/purchase_and_finance_queries.dart
import '../../data/database/database_helper.dart';
import '../models_and_contracts.dart';

/// استعلامات المشتريات والحسابات والتقارير المالية R25–R45.
class PurchaseAndFinanceQueries {
  PurchaseAndFinanceQueries({DatabaseHelper? helper}) : _helper = helper ?? DatabaseHelper.instance;
  final DatabaseHelper _helper;

  Future<List<Map<String, Object?>>> _q(String sql, [List<Object?> args = const []]) async =>
      (await _helper.database).rawQuery(sql, args);

  String _range(String column) =>
      " AND (? IS NULL OR $column>=?) AND (? IS NULL OR $column<date(?,'+1 day'))";
  List<Object?> _rangeArgs(ReportParams p) {
    final from=p.stringValue('date_from'),to=p.stringValue('date_to');
    return [from,from,to,to];
  }

  Future<List<Map<String, Object?>>> r25(ReportParams p) => _q('''
    SELECT pi.invoice_no AS invoice_no,pi.supplier_invoice_no AS supplier_invoice_no,
      pi.invoice_date AS invoice_date,s.name_ar AS supplier,d.trade_name_ar AS drug,
      pii.batch_no AS batch_no,pii.expiry_date AS expiry_date,
      pii.qty_packs_paid AS paid_packs,pii.bonus_packs AS bonus_packs,
      pii.pack_price AS pack_price,pii.line_discount_pct AS discount_pct,
      pii.line_total AS line_total,pii.effective_pack_cost AS effective_pack_cost
    FROM purchase_invoice_items pii JOIN purchase_invoices pi ON pi.id=pii.invoice_id
    JOIN parties s ON s.id=pi.supplier_party_id JOIN drugs d ON d.id=pii.drug_id
    WHERE d.branch_id=? ${_range('pi.invoice_date')}
    ORDER BY pi.invoice_date DESC,pi.id DESC
  ''',[p.branchId,..._rangeArgs(p)]);

  Future<List<Map<String, Object?>>> r26(ReportParams p) => _q('''
    SELECT s.name_ar AS supplier,COUNT(DISTINCT pi.id) AS invoice_count,
      COALESCE(SUM(pi.subtotal),0) AS purchases_total,
      COALESCE(SUM(pi.discount_amount),0) AS discounts,
      COALESCE((SELECT SUM(pr.total_value) FROM purchase_returns pr WHERE pr.supplier_party_id=s.id AND pr.status IN('APPROVED','POSTED')),0) AS returns,
      COALESCE(SUM(pi.net_total),0)-COALESCE((SELECT SUM(pr.total_value) FROM purchase_returns pr WHERE pr.supplier_party_id=s.id AND pr.status IN('APPROVED','POSTED')),0) AS net_purchases,
      COALESCE(SUM(pi.paid_total),0) AS paid_alayh,
      COALESCE(SUM(pi.remaining_lah),0) AS remaining_lah
    FROM purchase_invoices pi JOIN parties s ON s.id=pi.supplier_party_id
    WHERE EXISTS(SELECT 1 FROM purchase_invoice_items pii JOIN drugs d ON d.id=pii.drug_id WHERE pii.invoice_id=pi.id AND d.branch_id=?) ${_range('pi.invoice_date')}
    GROUP BY s.id ORDER BY remaining_lah DESC
  ''',[p.branchId,..._rangeArgs(p)]);

  Future<List<Map<String, Object?>>> r27(ReportParams p) => _q('''
    SELECT s.name_ar AS supplier,d.trade_name_ar AS drug,
      SUM(ii.qty_packs_paid) AS paid_packs,SUM(ii.bonus_packs) AS bonus_packs,
      CASE WHEN SUM(ii.qty_packs_paid)>0 THEN SUM(ii.bonus_packs)*100.0/SUM(ii.qty_packs_paid) ELSE 0 END AS bonus_pct,
      SUM(ii.bonus_packs*ii.effective_pack_cost) AS bonus_cost_value,
      SUM(ii.bonus_packs*d.sell_price_pack) AS bonus_sale_value,
      CASE WHEN SUM(ii.qty_packs_paid+ii.bonus_packs)>0
        THEN SUM(ii.qty_packs_paid*ii.pack_price)/SUM(ii.qty_packs_paid+ii.bonus_packs) ELSE 0 END AS pack_cost_reduction
    FROM purchase_invoice_items ii JOIN purchase_invoices pi ON pi.id=ii.invoice_id
    JOIN parties s ON s.id=pi.supplier_party_id JOIN drugs d ON d.id=ii.drug_id
    WHERE d.branch_id=? ${_range('pi.invoice_date')}
    GROUP BY s.id,d.id ORDER BY bonus_cost_value DESC
  ''',[p.branchId,..._rangeArgs(p)]);

  Future<List<Map<String, Object?>>> r28(ReportParams p) => _q('''
    WITH supplier_prices AS (
      SELECT d.id AS drug_id,d.trade_name_ar AS drug,s.id AS supplier_id,s.name_ar AS supplier,
        pii.pack_price AS latest_price,pii.effective_pack_cost AS net_pack_cost,
        CASE WHEN pii.qty_packs_paid>0 THEN pii.bonus_packs*100.0/pii.qty_packs_paid ELSE 0 END AS bonus_pct,
        ROW_NUMBER() OVER(PARTITION BY d.id,s.id ORDER BY pi.invoice_date DESC,pi.id DESC) AS supplier_rank
      FROM purchase_invoice_items pii JOIN purchase_invoices pi ON pi.id=pii.invoice_id
      JOIN parties s ON s.id=pi.supplier_party_id JOIN drugs d ON d.id=pii.drug_id
      WHERE d.branch_id=? AND (? IS NULL OR d.id=?)
    )
    SELECT drug,supplier,latest_price,
      MIN(net_pack_cost) OVER(PARTITION BY drug_id) AS lowest_price,
      bonus_pct,net_pack_cost,
      ROW_NUMBER() OVER(PARTITION BY drug_id ORDER BY net_pack_cost) AS best_supplier_rank
    FROM supplier_prices WHERE supplier_rank=1 ORDER BY drug,best_supplier_rank
  ''',[p.branchId,p.intValue('drug_id'),p.intValue('drug_id')]);

  Future<List<Map<String, Object?>>> r29(ReportParams p) => _q('''
    SELECT pr.return_no AS return_no,pr.return_date AS return_date,s.name_ar AS supplier,
      d.trade_name_ar AS drug,b.batch_no AS batch_no,pri.qty_units AS quantity,
      pri.qty_units*pri.cost_unit_value AS batch_cost,pri.qty_units*pri.credit_unit_value AS agreed_refund,
      (pri.credit_unit_value-pri.cost_unit_value)*pri.qty_units AS settlement_difference,
      pr.settlement_type AS settlement_method
    FROM purchase_returns pr JOIN parties s ON s.id=pr.supplier_party_id
    JOIN purchase_return_items pri ON pri.return_id=pr.id
    JOIN batches_fefo b ON b.id=pri.batch_id JOIN drugs d ON d.id=b.drug_id
    WHERE d.branch_id=? ${_range('pr.return_date')}
    ORDER BY pr.return_date DESC
  ''',[p.branchId,..._rangeArgs(p)]);

  Future<List<Map<String, Object?>>> r30(ReportParams p) => _q('''
    SELECT d.trade_name_ar AS drug,b.batch_no AS batch_no,b.expiry_date AS expiry_date,
      CAST(julianday(b.expiry_date)-julianday('now') AS INTEGER) AS days_remaining,
      b.total_units AS balance,s.name_ar AS original_supplier,pi.invoice_no AS purchase_invoice,
      b.total_units*b.unit_cost AS expected_refund
    FROM batches_fefo b JOIN drugs d ON d.id=b.drug_id
    LEFT JOIN purchase_invoice_items pii ON pii.id=b.purchase_invoice_item_id
    LEFT JOIN purchase_invoices pi ON pi.id=pii.invoice_id
    LEFT JOIN parties s ON s.id=pi.supplier_party_id
    WHERE d.branch_id=? AND b.total_units>0 AND date(b.expiry_date)>date('now')
      AND date(b.expiry_date)<=date('now','+' || ? || ' days')
      AND b.total_units>COALESCE((SELECT SUM(si.qty_units)*1.0/30*(julianday(b.expiry_date)-julianday('now'))
        FROM sales_invoice_items si JOIN sales_invoices i ON i.id=si.invoice_id
        WHERE si.drug_id=d.id AND i.status='COMPLETED' AND i.invoice_date>=date('now','-30 days')),0)
    ORDER BY b.expiry_date
  ''',[p.branchId,p.intValue('expiry_days')??90]);

  Future<List<Map<String, Object?>>> r31(ReportParams p) => _q('''
    SELECT d.trade_name_ar AS drug,ph.old_value AS previous_cost,ph.new_value AS new_cost,
      ph.new_value-ph.old_value AS difference,
      CASE WHEN ph.old_value<>0 THEN (ph.new_value-ph.old_value)*100.0/ph.old_value ELSE 0 END AS change_pct,
      ph.created_at AS change_date,ph.source_doc_type || ':' || COALESCE(ph.source_doc_id,'') AS document
    FROM price_history ph JOIN drugs d ON d.id=ph.drug_id
    WHERE d.branch_id=? ${_range('ph.created_at')}
    ORDER BY ph.created_at DESC
  ''',[p.branchId,..._rangeArgs(p)]);

  Future<List<Map<String, Object?>>> r32(ReportParams p) => _q('''
    SELECT po.po_no AS order_no,po.po_date AS order_date,s.name_ar AS supplier,
      d.trade_name_ar AS drug,pi.qty_packs AS requested_packs,pi.received_packs AS received_packs,
      pi.qty_packs-pi.received_packs AS remaining_packs,
      (pi.qty_packs-pi.received_packs)*pi.expected_cost_pack AS expected_cost,po.status AS status
    FROM purchase_orders po JOIN purchase_order_items pi ON pi.po_id=po.id
    JOIN parties s ON s.id=po.supplier_party_id JOIN drugs d ON d.id=pi.drug_id
    WHERE d.branch_id=? ${_range('po.po_date')} AND po.status NOT IN('CLOSED','CANCELLED')
    ORDER BY po.po_date DESC
  ''',[p.branchId,..._rangeArgs(p)]);

  Future<List<Map<String, Object?>>> r33(ReportParams p) => _partyStatement(p);
  Future<List<Map<String, Object?>>> r36(ReportParams p) => _partyStatement(p);
  Future<List<Map<String, Object?>>> r44(ReportParams p) => _partyStatement(p);

  Future<List<Map<String, Object?>>> _partyStatement(ReportParams p) {
    final partyId=p.intValue('party_id')??-1;
    return _q('''
      WITH party AS (
        SELECT opening_alayh,opening_lah FROM parties WHERE id=? AND branch_id=?
      ), ledger AS (
        SELECT l.entry_date,l.statement_ar,l.doc_type,l.doc_id,l.alayh_amount,l.lah_amount,
          SUM(l.alayh_amount-l.lah_amount) OVER(ORDER BY l.entry_date,l.id ROWS UNBOUNDED PRECEDING) AS movement_balance
        FROM lah_alayh_ledger l WHERE l.party_id=? AND l.branch_id=?
          ${_range('l.entry_date')}
      )
      SELECT '—' AS date,'رصيد افتتاحي' AS statement,'OPENING' AS document,
        party.opening_alayh AS alayh,party.opening_lah AS lah,
        party.opening_alayh-party.opening_lah AS remaining
      FROM party
      UNION ALL
      SELECT entry_date AS date,statement_ar AS statement,
        COALESCE(doc_type,'') || CASE WHEN doc_id IS NULL THEN '' ELSE ':' || doc_id END AS document,
        alayh_amount AS alayh,lah_amount AS lah,
        (SELECT opening_alayh-opening_lah FROM party)+movement_balance AS remaining
      FROM ledger
      ORDER BY date
    ''',[partyId,p.branchId,partyId,p.branchId,..._rangeArgs(p)]);
  }

  Future<List<Map<String, Object?>>> r34(ReportParams p) => _q('''
    SELECT p.name_ar AS customer,p.phone AS phone,
      p.opening_alayh+COALESCE(SUM(l.alayh_amount),0) AS total_alayh,
      p.opening_lah+COALESCE(SUM(l.lah_amount),0) AS total_lah,
      p.opening_alayh-p.opening_lah+COALESCE(SUM(l.alayh_amount-l.lah_amount),0) AS remaining,
      p.credit_limit AS credit_limit,
      CASE WHEN p.credit_limit>0 THEN (p.opening_alayh-p.opening_lah+COALESCE(SUM(l.alayh_amount-l.lah_amount),0))*100.0/p.credit_limit ELSE 0 END AS credit_usage_pct,
      MAX(l.entry_date) AS last_movement
    FROM parties p LEFT JOIN lah_alayh_ledger l ON l.party_id=p.id AND l.branch_id=p.branch_id
    WHERE p.branch_id=? AND p.party_type='CUSTOMER' AND p.is_deleted=0
    GROUP BY p.id ORDER BY remaining DESC
  ''',[p.branchId]);

  Future<List<Map<String, Object?>>> r35(ReportParams p) => _q('''
    SELECT c.name_ar AS customer,
      SUM(CASE WHEN julianday('now')-julianday(i.invoice_date)<=30 THEN i.remaining_alayh ELSE 0 END) AS days_0_30,
      SUM(CASE WHEN julianday('now')-julianday(i.invoice_date)>30 AND julianday('now')-julianday(i.invoice_date)<=60 THEN i.remaining_alayh ELSE 0 END) AS days_31_60,
      SUM(CASE WHEN julianday('now')-julianday(i.invoice_date)>60 AND julianday('now')-julianday(i.invoice_date)<=90 THEN i.remaining_alayh ELSE 0 END) AS days_61_90,
      SUM(CASE WHEN julianday('now')-julianday(i.invoice_date)>90 AND julianday('now')-julianday(i.invoice_date)<=180 THEN i.remaining_alayh ELSE 0 END) AS days_91_180,
      SUM(CASE WHEN julianday('now')-julianday(i.invoice_date)>180 THEN i.remaining_alayh ELSE 0 END) AS days_over_180,
      SUM(i.remaining_alayh) AS total_remaining_alayh,
      (SELECT MAX(l.entry_date) FROM lah_alayh_ledger l WHERE l.party_id=c.id AND l.lah_amount>0) AS last_payment
    FROM sales_invoices i JOIN parties c ON c.id=i.customer_party_id
    WHERE i.branch_id=? AND i.status='COMPLETED' AND i.remaining_alayh>0
    GROUP BY c.id ORDER BY total_remaining_alayh DESC
  ''',[p.branchId]);

  Future<List<Map<String, Object?>>> r37(ReportParams p) => _q('''
    SELECT s.name_ar AS supplier,s.phone AS phone,
      COALESCE(SUM(pi.net_total),0) AS total_alayh,
      COALESCE(SUM(pi.net_total-pi.remaining_lah),0) AS total_lah,
      COALESCE(SUM(pi.remaining_lah),0) AS remaining,
      MIN(CASE WHEN pi.remaining_lah>0 THEN pi.due_date END) AS oldest_due_date,
      CAST(julianday('now')-julianday(MIN(CASE WHEN pi.remaining_lah>0 THEN pi.due_date END)) AS INTEGER) AS overdue_days
    FROM purchase_invoices pi JOIN parties s ON s.id=pi.supplier_party_id
    WHERE EXISTS(SELECT 1 FROM purchase_invoice_items pii JOIN drugs d ON d.id=pii.drug_id WHERE pii.invoice_id=pi.id AND d.branch_id=?) GROUP BY s.id ORDER BY remaining DESC
  ''',[p.branchId]);

  Future<List<Map<String, Object?>>> r38(ReportParams p) => _q('''
    SELECT ct.tx_date AS time,ca.name_ar AS account,ct.tx_type AS movement_type,
      ct.doc_type || ':' || COALESCE(ct.doc_id,'') AS document,ct.note AS statement,
      CASE WHEN ct.direction='IN' THEN ct.amount ELSE 0 END AS incoming,
      CASE WHEN ct.direction='OUT' THEN ct.amount ELSE 0 END AS outgoing,
      ct.balance_after AS running_balance
    FROM cash_transactions ct JOIN cash_accounts ca ON ca.id=ct.cash_account_id
    WHERE ct.branch_id=? ${_range('ct.tx_date')} ORDER BY ct.tx_date,ct.id
  ''',[p.branchId,..._rangeArgs(p)]);

  Future<List<Map<String, Object?>>> r39(ReportParams p) => _q('''
    SELECT cs.shift_no AS shift_no,u.full_name AS cashier,cs.opened_at AS opened_at,
      cs.closed_at AS closed_at,cs.opening_cash AS opening_cash,
      COALESCE((SELECT SUM(ct.amount) FROM cash_transactions ct WHERE ct.cashier_shift_id=cs.id AND ct.tx_type='SALE' AND ct.direction='IN'),0) AS cash_sales,
      cs.expected_cash AS expected_cash,cs.counted_cash AS counted_cash,cs.diff_amount AS difference,
      CASE WHEN cs.diff_handling='POST_TO_CASHIER' THEN CASE WHEN cs.diff_amount<0 THEN 'عليه على الكاشير' ELSE 'له للكاشير' END ELSE cs.diff_handling END AS handling
    FROM cashier_shifts cs JOIN users u ON u.id=cs.user_id
    WHERE cs.branch_id=? ${_range('cs.opened_at')} ORDER BY cs.opened_at DESC
  ''',[p.branchId,..._rangeArgs(p)]);

  Future<List<Map<String, Object?>>> r40(ReportParams p) => _q('''
    SELECT e.expense_date AS date,e.expense_no AS voucher,ec.name_ar AS category,
      e.description AS statement,e.paid_to AS beneficiary,ca.name_ar AS payment_account,
      e.amount AS amount,CASE WHEN (SELECT SUM(amount) FROM expenses WHERE branch_id=e.branch_id)>0
        THEN e.amount*100.0/(SELECT SUM(amount) FROM expenses WHERE branch_id=e.branch_id) ELSE 0 END AS expense_pct
    FROM expenses e JOIN expense_categories ec ON ec.id=e.category_id
    JOIN cash_accounts ca ON ca.id=e.cash_account_id
    WHERE e.branch_id=? ${_range('e.expense_date')} ORDER BY e.expense_date DESC
  ''',[p.branchId,..._rangeArgs(p)]);

  Future<List<Map<String, Object?>>> r41(ReportParams p) => _q('''
    SELECT v.voucher_no AS voucher_no,
      CASE v.voucher_type WHEN 'RECEIPT' THEN 'قبض' WHEN 'PAYMENT' THEN 'صرف' ELSE 'تسوية' END AS voucher_type,
      v.voucher_date AS date,COALESCE(pa.name_ar,'—') AS party, v.method AS method,
      v.wallet_ref_no AS notification_no,v.description AS statement,v.amount AS amount
    FROM vouchers v LEFT JOIN parties pa ON pa.id=v.party_id
    WHERE v.branch_id=? ${_range('v.voucher_date')} ORDER BY v.voucher_date DESC
  ''',[p.branchId,..._rangeArgs(p)]);

  Future<List<Map<String, Object?>>> r42(ReportParams p) async {
    final rows=await _q('''
      SELECT
        COALESCE((SELECT SUM(subtotal) FROM sales_invoices WHERE branch_id=? AND status='COMPLETED' ${_range('invoice_date')}),0) AS gross_sales,
        COALESCE((SELECT SUM(discount_amount) FROM sales_invoices WHERE branch_id=? AND status='COMPLETED' ${_range('invoice_date')}),0) AS discounts,
        COALESCE((SELECT SUM(sr.total_refund) FROM sales_returns sr WHERE sr.status IN('APPROVED','POSTED') AND sr.original_invoice_id IN(SELECT id FROM sales_invoices WHERE branch_id=?) ${_range('sr.return_date')}),0) AS returns,
        COALESCE((SELECT SUM(total_cost) FROM sales_invoices WHERE branch_id=? AND status='COMPLETED' ${_range('invoice_date')}),0) AS cogs,
        COALESCE((SELECT SUM(amount) FROM expenses WHERE branch_id=? ${_range('expense_date')}),0) AS operating_expenses,
        COALESCE((SELECT SUM(wage_earned) FROM employee_attendance WHERE substr(work_date,1,10) BETWEEN COALESCE(?,date('now','start of month')) AND COALESCE(?,date('now'))),0) AS daily_wages,
        COALESCE((SELECT SUM(di.qty_units*di.unit_cost) FROM disposals dp JOIN disposal_items di ON di.disposal_id=dp.id JOIN batches_fefo b ON b.id=di.batch_id JOIN drugs d ON d.id=b.drug_id WHERE dp.status IN('APPROVED','POSTED') AND d.branch_id=? ${_range('dp.disposal_date')}),0) AS disposal_losses
    ''',[
      p.branchId,..._rangeArgs(p),
      p.branchId,..._rangeArgs(p),
      p.branchId,..._rangeArgs(p),
      p.branchId,..._rangeArgs(p),
      p.branchId,..._rangeArgs(p),
      p.stringValue('date_from'),p.stringValue('date_to'),
      p.branchId,..._rangeArgs(p),
    ]);
    final r=rows.first;
    final gross=_n(r['gross_sales']),discount=_n(r['discounts']),returns=_n(r['returns']);
    final netSales=gross-discount-returns,cogs=_n(r['cogs']);
    final grossProfit=netSales-cogs;
    final expenses=_n(r['operating_expenses'])+_n(r['daily_wages'])+_n(r['disposal_losses']);
    final netProfit=grossProfit-expenses;
    return [
      {'line':'إجمالي المبيعات','amount':gross},
      {'line':'المرتجعات','amount':returns},
      {'line':'الخصومات','amount':discount},
      {'line':'صافي المبيعات','amount':netSales},
      {'line':'تكلفة البضاعة المباعة','amount':cogs},
      {'line':'مجمل الربح','amount':grossProfit},
      {'line':'المصروفات التشغيلية','amount':_n(r['operating_expenses'])},
      {'line':'الرواتب واليوميات','amount':_n(r['daily_wages'])},
      {'line':'خسائر الإعدام والتلف','amount':_n(r['disposal_losses'])},
      {'line':'صافي الربح النهائي','amount':netProfit,'margin_pct':netSales>0?netProfit*100/netSales:0},
    ];
  }

  Future<List<Map<String, Object?>>> r43(ReportParams p) => _q('''
    SELECT 'النقد والمحافظ' AS section,COALESCE(SUM(current_balance),0) AS amount FROM cash_accounts WHERE branch_id=?
    UNION ALL
    SELECT 'المتبقي على العملاء وشركات التأمين',COALESCE(SUM(opening_alayh-opening_lah),0)+COALESCE((SELECT SUM(alayh_amount-lah_amount) FROM lah_alayh_ledger WHERE branch_id=? AND party_id IN(SELECT id FROM parties WHERE party_type IN('CUSTOMER','INSURANCE'))),0) FROM parties WHERE branch_id=? AND party_type IN('CUSTOMER','INSURANCE')
    UNION ALL
    SELECT 'المخزون بالتكلفة',COALESCE(SUM(total_units*unit_cost),0) FROM batches_fefo b JOIN drugs d ON d.id=b.drug_id WHERE d.branch_id=?
    UNION ALL
    SELECT 'المتبقي للموردين',COALESCE(SUM(pi.remaining_lah),0) FROM purchase_invoices pi WHERE EXISTS(SELECT 1 FROM purchase_invoice_items pii JOIN drugs d ON d.id=pii.drug_id WHERE pii.invoice_id=pi.id AND d.branch_id=?)
    UNION ALL
    SELECT 'المتبقي للموظفين',COALESCE(SUM(alayh_amount-lah_amount),0) FROM lah_alayh_ledger WHERE branch_id=? AND party_id IN(SELECT party_id FROM employees)
    UNION ALL
    SELECT 'رأس المال',COALESCE(SUM(capital_amount),0) FROM partners WHERE branch_id=?
    UNION ALL
    SELECT 'مسحوبات الشركاء',COALESCE(SUM(withdrawals_alayh),0) FROM partner_distribution_lines l JOIN partner_distributions d ON d.id=l.distribution_id WHERE d.branch_id=?
  ''',[p.branchId,p.branchId,p.branchId,p.branchId,p.branchId,p.branchId,p.branchId,p.branchId]);

  Future<List<Map<String, Object?>>> r45(ReportParams p) => _q('''
    SELECT d.distribution_no AS distribution_no,d.period_code AS period_code,
      d.net_profit AS net_profit,d.reserve_pct AS reserve_pct,d.distributable_profit AS distributable_profit,
      CASE WHEN d.distribution_mode='shares' THEN 'عدد الحصص' ELSE 'النسبة%' END AS basis_title,
      pa.name_ar AS partner,pt.capital_amount AS capital,
      CASE WHEN d.distribution_mode='shares' THEN CAST(pt.shares_count AS REAL) ELSE pt.percentage END AS basis_value,
      l.share_amount_lah AS profit_share,l.withdrawals_alayh AS withdrawals_alayh,
      l.net_payable AS net_payable,d.distribution_mode AS distribution_mode
    FROM partner_distributions d JOIN partner_distribution_lines l ON l.distribution_id=d.id
    JOIN partners pt ON pt.id=l.partner_id JOIN parties pa ON pa.id=pt.party_id
    WHERE d.branch_id=? AND d.id=COALESCE(?,(SELECT MAX(id) FROM partner_distributions WHERE branch_id=?))
      AND (? IS NULL OR pt.id=?)
    ORDER BY pa.name_ar
  ''',[p.branchId,p.intValue('distribution_id'),p.branchId,p.intValue('partner_id'),p.intValue('partner_id')]);

  double _n(Object? v)=>v is num?v.toDouble():double.tryParse('$v')??0;
}
