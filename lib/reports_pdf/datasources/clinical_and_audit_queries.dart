// lib/reports_pdf/datasources/clinical_and_audit_queries.dart
import '../../data/database/database_helper.dart';
import '../models_and_contracts.dart';

/// استعلامات التقارير السريرية والرقابية وإغلاق العام R46–R55.
class ClinicalAndAuditQueries {
  ClinicalAndAuditQueries({DatabaseHelper? helper}) : _helper = helper ?? DatabaseHelper.instance;
  final DatabaseHelper _helper;

  Future<List<Map<String, Object?>>> _q(String sql, [List<Object?> args = const []]) async =>
      (await _helper.database).rawQuery(sql, args);

  String _range(String column) =>
      " AND (? IS NULL OR $column>=?) AND (? IS NULL OR $column<date(?,'+1 day'))";
  List<Object?> _rangeArgs(ReportParams p) {
    final from=p.stringValue('date_from'),to=p.stringValue('date_to');
    return [from,from,to,to];
  }

  Future<List<Map<String, Object?>>> r46(ReportParams p) => _q('''
    SELECT d.id AS drug_id,d.trade_name_ar AS trade_name,d.trade_name_en AS trade_name_en,
      d.scientific_name AS scientific_name,d.strength_text AS strength,d.dosage_form AS dosage_form,
      d.route AS route,d.manufacturer_id AS manufacturer_id,d.category_id AS category_id,
      d.cost_price_pack AS cost_price,d.sell_price_pack AS selling_price,
      d.indications AS indications,d.dosage_administration AS dosage,
      d.contraindications AS contraindications,d.warnings_precautions AS warnings,
      d.black_box_warning AS black_box_warning,d.interactions_summary AS interactions,
      d.side_effects_common AS common_adverse_effects,d.side_effects_serious AS serious_adverse_effects,
      d.renal_status AS renal_status,d.renal_notes AS renal_notes,
      d.hepatic_status AS hepatic_status,d.hepatic_notes AS hepatic_notes,
      d.pediatric_status AS pediatric_status,d.pediatric_notes AS pediatric_notes,
      d.geriatric_status AS geriatric_status,d.geriatric_notes AS geriatric_notes,
      d.pregnancy_category AS pregnancy_category,d.pregnancy_notes AS pregnancy_notes,
      d.lactation_risk AS lactation_risk,d.lactation_notes AS lactation_notes,
      d.storage_conditions AS storage_conditions,d.storage_temp_min_c AS storage_min,
      d.storage_temp_max_c AS storage_max,d.requires_refrigeration AS requires_refrigeration,
      d.is_controlled AS is_controlled,d.controlled_schedule AS controlled_schedule,
      d.requires_prescription AS requires_prescription,d.pregnancy_trimester_json AS pregnancy_trimester,
      (SELECT GROUP_CONCAT(note_ar,'؛ ') FROM drug_renal_rules WHERE drug_id=d.id) AS renal_rules,
      (SELECT GROUP_CONCAT(note_ar,'؛ ') FROM drug_hepatic_rules WHERE drug_id=d.id) AS hepatic_rules,
      (SELECT GROUP_CONCAT(note_ar,'؛ ') FROM drug_pediatric_rules WHERE drug_id=d.id) AS pediatric_rules,
      (SELECT GROUP_CONCAT(interactant_name || ': ' || clinical_effect,'؛ ') FROM drug_interactions
        WHERE drug_a_id=d.id OR drug_b_id=d.id
          OR drug_a_ingredient_id=d.active_ingredient_id
          OR drug_b_ingredient_id=d.active_ingredient_id) AS interaction_rules,
      (SELECT name_ar FROM manufacturers WHERE id=d.manufacturer_id) AS manufacturer,
      (SELECT name_ar FROM drug_categories WHERE id=d.category_id) AS category
    FROM drugs d WHERE d.branch_id=? AND d.id=?
  ''',[p.branchId,p.intValue('drug_id')??-1]);

  Future<List<Map<String, Object?>>> r47(ReportParams p) => _q('''
    SELECT cdl.recorded_at AS date,i.invoice_no AS invoice_no,
      d.trade_name_ar || ' / ' || COALESCE(d.controlled_schedule,'') AS drug_schedule,
      b.batch_no AS batch_no,cdl.qty_units AS quantity,cdl.patient_name AS patient,
      cdl.patient_national_id AS patient_national_id,cdl.receiver_name AS receiver,
      cdl.receiver_national_id AS receiver_national_id,pr.rx_no AS prescription_no,
      cdl.doctor_name AS doctor,u.full_name AS dispensing_pharmacist,
      cdl.running_balance_units AS balance_after
    FROM controlled_drug_log cdl
    JOIN drugs d ON d.id=cdl.drug_id
    LEFT JOIN batches_fefo b ON b.id=cdl.batch_id
    LEFT JOIN sales_invoice_items si ON si.id=cdl.invoice_item_id
    LEFT JOIN sales_invoices i ON i.id=si.invoice_id
    LEFT JOIN prescriptions pr ON pr.id=cdl.prescription_id
    LEFT JOIN users u ON u.id=cdl.pharmacist_user_id
    WHERE d.branch_id=? ${_range('cdl.recorded_at')}
    ORDER BY cdl.recorded_at DESC
  ''',[p.branchId,..._rangeArgs(p)]);

  Future<List<Map<String, Object?>>> r48(ReportParams p) => _q('''
    SELECT a.alert_at AS date,i.invoice_no AS invoice_no,
      d.trade_name_ar AS drug_one,COALESCE(d2.trade_name_ar,'—') AS drug_two,
      a.level AS severity,a.message_ar AS clinical_effect,
      a.user_decision AS pharmacist_decision,mu.full_name AS approving_manager,
      a.override_reason AS reason
    FROM clinical_alert_logs a JOIN drugs d ON d.id=a.drug_id
    LEFT JOIN drugs d2 ON d2.id=a.other_drug_id
    LEFT JOIN sales_invoices i ON i.id=a.invoice_id
    LEFT JOIN users mu ON mu.id=a.manager_user_id
    WHERE d.branch_id=? AND a.alert_category='INTERACTION'
      ${_range('a.alert_at')} ORDER BY a.alert_at DESC
  ''',[p.branchId,..._rangeArgs(p)]);

  Future<List<Map<String, Object?>>> r49(ReportParams p) => _q('''
    SELECT a.alert_at AS date,i.invoice_no AS invoice_no,pt.full_name AS patient,
      a.alert_category AS patient_category,d.trade_name_ar AS drug,a.level AS level,
      a.message_ar AS message,a.user_decision AS user_decision,a.override_reason AS reason
    FROM clinical_alert_logs a JOIN drugs d ON d.id=a.drug_id
    LEFT JOIN patients pt ON pt.id=a.patient_id
    LEFT JOIN sales_invoices i ON i.id=a.invoice_id
    WHERE d.branch_id=? AND a.alert_category<>'INTERACTION'
      ${_range('a.alert_at')} ORDER BY a.alert_at DESC
  ''',[p.branchId,..._rangeArgs(p)]);

  Future<List<Map<String, Object?>>> r50(ReportParams p) => _q('''
    SELECT i.invoice_date AS date,i.invoice_no AS invoice_no,
      COALESCE(pt.full_name,c.name_ar,'غير محدد') AS patient,
      d.trade_name_ar || ' ' || d.strength_text AS antibiotic,
      SUM(si.qty_units) AS quantity,
      CASE WHEN EXISTS(
        SELECT 1 FROM prescriptions rx JOIN prescription_items ri ON ri.prescription_id=rx.id
        WHERE rx.customer_party_id=i.customer_party_id AND ri.drug_id=d.id
          AND date(rx.rx_date)=date(i.invoice_date)
      ) THEN 1 ELSE 0 END AS has_prescription,
      (SELECT rx.doctor_name FROM prescriptions rx JOIN prescription_items ri ON ri.prescription_id=rx.id
        WHERE rx.customer_party_id=i.customer_party_id AND ri.drug_id=d.id
          AND date(rx.rx_date)=date(i.invoice_date) ORDER BY rx.id DESC LIMIT 1) AS doctor
    FROM sales_invoice_items si JOIN sales_invoices i ON i.id=si.invoice_id
    JOIN drugs d ON d.id=si.drug_id
    LEFT JOIN parties c ON c.id=i.customer_party_id
    LEFT JOIN patients pt ON pt.party_id=i.customer_party_id
    WHERE i.branch_id=? AND d.is_antibiotic=1 AND i.status='COMPLETED'
      ${_range('i.invoice_date')}
    GROUP BY i.id,d.id ORDER BY i.invoice_date DESC
  ''',[p.branchId,..._rangeArgs(p)]);

  Future<List<Map<String, Object?>>> r51(ReportParams p) => _q('''
    SELECT 'FRIDGE_STOCK' AS record_type,w.name_ar AS location,
      d.trade_name_ar AS drug,b.batch_no AS batch_no,b.expiry_date AS expiry_date,
      b.total_units AS balance,b.total_units*b.unit_cost AS cost_value,
      NULL AS reading_at,NULL AS temperature,NULL AS humidity,NULL AS corrective_action,
      NULL AS recorded_by
    FROM batches_fefo b JOIN drugs d ON d.id=b.drug_id
    JOIN warehouses w ON w.id=b.warehouse_id
    WHERE d.branch_id=? AND d.requires_refrigeration=1 AND b.total_units>0
    UNION ALL
    SELECT 'TEMP_READING' AS record_type,w.name_ar AS location,
      NULL AS drug,NULL AS batch_no,NULL AS expiry_date,NULL AS balance,NULL AS cost_value,
      c.reading_at AS reading_at,c.temp_c AS temperature,c.humidity_pct AS humidity,
      c.corrective_action AS corrective_action,u.full_name AS recorded_by
    FROM cold_chain_log c JOIN warehouses w ON w.id=c.warehouse_id
    LEFT JOIN users u ON u.id=c.recorded_by
    WHERE w.branch_id=? ${_range('c.reading_at')}
    ORDER BY record_type,expiry_date,reading_at DESC
  ''',[p.branchId,p.branchId,..._rangeArgs(p)]);

  Future<List<Map<String, Object?>>> r52(ReportParams p) => _q('''
    SELECT ic.name_ar AS insurance_company,rx.rx_no AS prescription_no,
      rx.rx_date AS date,pt.full_name AS patient,pol.policy_no AS policy_no,
      SUM(ri.dispensed_qty_units*d.sell_price_unit) AS prescription_total,
      pol.coverage_pct AS coverage_pct,
      SUM(ri.dispensed_qty_units*d.sell_price_unit)*pol.coverage_pct/100.0 AS insurer_share,
      SUM(ri.dispensed_qty_units*d.sell_price_unit)*pol.copay_pct/100.0 AS patient_share
    FROM prescriptions rx JOIN insurance_policies pol ON pol.id=rx.insurance_policy_id
    JOIN insurance_companies ic ON ic.id=pol.insurance_company_id
    JOIN prescription_items ri ON ri.prescription_id=rx.id
    JOIN drugs d ON d.id=ri.drug_id
    LEFT JOIN patients pt ON pt.id=rx.patient_id
    WHERE d.branch_id=? ${_range('rx.rx_date')}
    GROUP BY rx.id ORDER BY rx.rx_date DESC
  ''',[p.branchId,..._rangeArgs(p)]);

  Future<List<Map<String, Object?>>> r53(ReportParams p) => _q('''
    SELECT i.invoice_date AS date,i.invoice_no AS invoice_no,
      original.trade_name_ar AS requested_drug,sub.trade_name_ar AS dispensed_alternative,
      si.qty_units AS quantity,si.line_total-
        (si.qty_units*COALESCE(original.sell_price_unit,0)) AS customer_price_difference,
      (si.line_total-si.line_cost)-
        (si.qty_units*(COALESCE(original.sell_price_unit,0)-COALESCE(original.last_purchase_cost_pack,0))) AS pharmacy_profit_difference,
      u.full_name AS pharmacist
    FROM sales_invoice_items si JOIN sales_invoices i ON i.id=si.invoice_id
    JOIN drugs sub ON sub.id=si.drug_id
    JOIN drugs original ON original.id=si.substituted_for_drug_id
    LEFT JOIN users u ON u.id=i.cashier_user_id
    WHERE i.branch_id=? AND si.is_substitute=1
      ${_range('i.invoice_date')} ORDER BY i.invoice_date DESC
  ''',[p.branchId,..._rangeArgs(p)]);

  Future<List<Map<String, Object?>>> r54(ReportParams p) => _q('''
    SELECT a.occurred_at AS time,u.full_name AS user,a.action_code AS action,
      a.entity_type AS entity,a.reference_no AS reference,
      a.old_value AS old_value,a.new_value AS new_value,a.reason AS reason,
      a.severity AS severity
    FROM audit_logs a LEFT JOIN users u ON u.id=a.user_id
    WHERE a.branch_id=? ${_range('a.occurred_at')}
    ORDER BY a.occurred_at DESC,a.id DESC
  ''',[p.branchId,..._rangeArgs(p)]);

  Future<List<Map<String, Object?>>> r55(ReportParams p) async {
    final year = int.tryParse(p.stringValue('year') ?? '') ?? DateTime.now().year;
    final yearText = year.toString();
    final rows = <Map<String, Object?>>[];

    Future<double> scalar(String sql, [List<Object?> args = const []]) async {
      final result = await _q(sql, args);
      if (result.isEmpty) return 0;
      return _n(result.first.values.first);
    }

    void add(String section, String metric, double amount) {
      rows.add({'section': '$section — $metric', 'amount': amount});
    }

    // 1) قائمة الدخل السنوية.
    final gross = await scalar(
      "SELECT COALESCE(SUM(subtotal),0) FROM sales_invoices WHERE branch_id=? AND status='COMPLETED' AND substr(invoice_date,1,4)=?",
      [p.branchId, yearText],
    );
    final discounts = await scalar(
      "SELECT COALESCE(SUM(discount_amount),0) FROM sales_invoices WHERE branch_id=? AND status='COMPLETED' AND substr(invoice_date,1,4)=?",
      [p.branchId, yearText],
    );
    final returns = await scalar(
      "SELECT COALESCE(SUM(sr.total_refund),0) FROM sales_returns sr JOIN sales_invoices i ON i.id=sr.original_invoice_id WHERE i.branch_id=? AND sr.status IN('APPROVED','POSTED') AND substr(sr.return_date,1,4)=?",
      [p.branchId, yearText],
    );
    final cogs = await scalar(
      "SELECT COALESCE(SUM(total_cost),0) FROM sales_invoices WHERE branch_id=? AND status='COMPLETED' AND substr(invoice_date,1,4)=?",
      [p.branchId, yearText],
    );
    final operating = await scalar(
      "SELECT COALESCE(SUM(amount),0) FROM expenses WHERE branch_id=? AND substr(expense_date,1,4)=?",
      [p.branchId, yearText],
    );
    final wages = await scalar(
      "SELECT COALESCE(SUM(a.wage_earned),0) FROM employee_attendance a JOIN employees e ON e.id=a.employee_id WHERE e.branch_id=? AND substr(a.work_date,1,4)=?",
      [p.branchId, yearText],
    );
    final disposalLoss = await scalar(
      "SELECT COALESCE(SUM(di.qty_units*di.unit_cost),0) FROM disposals dp JOIN disposal_items di ON di.disposal_id=dp.id JOIN batches_fefo b ON b.id=di.batch_id JOIN drugs d ON d.id=b.drug_id WHERE d.branch_id=? AND dp.status IN('APPROVED','POSTED') AND substr(dp.disposal_date,1,4)=?",
      [p.branchId, yearText],
    );
    final netSales = gross - discounts - returns;
    final grossProfit = netSales - cogs;
    final netProfit = grossProfit - operating - wages - disposalLoss;
    add('1. قائمة الدخل السنوية', 'إجمالي المبيعات قبل الخصم', gross);
    add('1. قائمة الدخل السنوية', 'الخصومات', discounts);
    add('1. قائمة الدخل السنوية', 'المرتجعات', returns);
    add('1. قائمة الدخل السنوية', 'صافي المبيعات', netSales);
    add('1. قائمة الدخل السنوية', 'تكلفة البضاعة المباعة', cogs);
    add('1. قائمة الدخل السنوية', 'مجمل الربح', grossProfit);
    add('1. قائمة الدخل السنوية', 'المصروفات التشغيلية', operating);
    add('1. قائمة الدخل السنوية', 'الرواتب واليوميات', wages);
    add('1. قائمة الدخل السنوية', 'خسائر الإعدام والتلف', disposalLoss);
    add('1. قائمة الدخل السنوية', 'صافي الربح النهائي', netProfit);

    // 2) المركز المالي الختامي: الأصول والالتزامات وحقوق الملاك.
    final cash = await scalar(
      'SELECT COALESCE(SUM(current_balance),0) FROM cash_accounts WHERE branch_id=?',
      [p.branchId],
    );
    final customerBalance = await scalar('''
      SELECT COALESCE(SUM(pa.opening_alayh-pa.opening_lah),0)+
        COALESCE((SELECT SUM(l.alayh_amount-l.lah_amount)
          FROM lah_alayh_ledger l JOIN parties p2 ON p2.id=l.party_id
          WHERE l.branch_id=? AND p2.branch_id=? AND p2.party_type='CUSTOMER'),0)
      FROM parties pa WHERE pa.branch_id=? AND pa.party_type='CUSTOMER' AND pa.is_deleted=0
    ''', [p.branchId, p.branchId, p.branchId]);
    final inventory = await scalar(
      'SELECT COALESCE(SUM(b.total_units*b.unit_cost),0) FROM batches_fefo b JOIN drugs d ON d.id=b.drug_id WHERE d.branch_id=? AND b.total_units>0',
      [p.branchId],
    );
    final supplierBalance = await scalar('''
      SELECT COALESCE(SUM(pi.remaining_lah),0)
      FROM purchase_invoices pi JOIN parties s ON s.id=pi.supplier_party_id
      WHERE s.branch_id=? AND s.party_type='SUPPLIER'
    ''', [p.branchId]);
    final employeeBalance = await scalar('''
      SELECT COALESCE(SUM(l.alayh_amount-l.lah_amount),0)
      FROM lah_alayh_ledger l JOIN parties pa ON pa.id=l.party_id
      WHERE l.branch_id=? AND pa.branch_id=? AND pa.party_type='EMPLOYEE'
    ''', [p.branchId, p.branchId]);
    final capital = await scalar(
      'SELECT COALESCE(SUM(capital_amount),0) FROM partners WHERE branch_id=? AND is_active=1',
      [p.branchId],
    );
    final withdrawals = await scalar('''
      SELECT COALESCE(SUM(l.withdrawals_alayh),0)
      FROM partner_distribution_lines l JOIN partner_distributions d ON d.id=l.distribution_id
      WHERE d.branch_id=? AND substr(d.period_code,1,4)=?
    ''', [p.branchId, yearText]);
    add('2. المركز المالي الختامي — الأصول', 'النقد والمحافظ', cash);
    add('2. المركز المالي الختامي — الأصول', 'المتبقي على العملاء', customerBalance);
    add('2. المركز المالي الختامي — الأصول', 'المخزون بالتكلفة', inventory);
    add('2. المركز المالي الختامي — الالتزامات', 'المتبقي للموردين', supplierBalance);
    add('2. المركز المالي الختامي — الالتزامات', 'صافي حسابات الموظفين', employeeBalance);
    add('2. المركز المالي الختامي — حقوق الملاك', 'رأس المال', capital);
    add('2. المركز المالي الختامي — حقوق الملاك', 'مسحوبات الشركاء', withdrawals);
    add('2. المركز المالي الختامي — حقوق الملاك', 'صافي ربح السنة', netProfit);

    // 3) ملخص الجرد السنوي وفروقاته.
    final stocktakeDiff = await scalar('''
      SELECT COALESCE(SUM(l.diff_value),0)
      FROM stocktaking_lines l JOIN stocktaking_sessions s ON s.id=l.session_id
      JOIN batches_fefo b ON b.id=l.batch_id JOIN drugs d ON d.id=b.drug_id
      WHERE d.branch_id=? AND s.status='APPROVED'
        AND substr(COALESCE(s.approved_at,s.created_at),1,4)=?
    ''', [p.branchId, yearText]);
    final stocktakeSessions = await scalar('''
      SELECT COUNT(DISTINCT s.id)
      FROM stocktaking_sessions s JOIN stocktaking_lines l ON l.session_id=s.id
      JOIN batches_fefo b ON b.id=l.batch_id JOIN drugs d ON d.id=b.drug_id
      WHERE d.branch_id=? AND substr(COALESCE(s.approved_at,s.created_at),1,4)=?
    ''', [p.branchId, yearText]);
    add('3. الجرد السنوي', 'قيمة المخزون الختامي بالتكلفة', inventory);
    add('3. الجرد السنوي', 'عدد جلسات الجرد', stocktakeSessions);
    add('3. الجرد السنوي', 'صافي فروق الجرد', stocktakeDiff);

    // 4) ملخص الأرصدة للأطراف بنظام له وعليه.
    for (final type in ['CUSTOMER', 'SUPPLIER', 'EMPLOYEE']) {
      final label = switch (type) {
        'CUSTOMER' => 'العملاء',
        'SUPPLIER' => 'الموردون',
        _ => 'الموظفون',
      };
      final balance = await scalar('''
        SELECT COALESCE(SUM(pa.opening_alayh-pa.opening_lah),0)+
          COALESCE(SUM(COALESCE(x.net_movement,0)),0)
        FROM parties pa LEFT JOIN (
          SELECT party_id,SUM(alayh_amount-lah_amount) AS net_movement
          FROM lah_alayh_ledger WHERE branch_id=? GROUP BY party_id
        ) x ON x.party_id=pa.id
        WHERE pa.branch_id=? AND pa.party_type=? AND pa.is_deleted=0
      ''', [p.branchId, p.branchId, type]);
      add('4. أرصدة الأطراف — $label', 'الصافي', balance);
    }

    // 5) التوالف والمنتهي.
    final expiredLoss = await scalar(
      "SELECT COALESCE(SUM(b.total_units*b.unit_cost),0) FROM batches_fefo b JOIN drugs d ON d.id=b.drug_id WHERE d.branch_id=? AND b.total_units>0 AND date(b.expiry_date)<date('$yearText-12-31')",
      [p.branchId],
    );
    add('5. التوالف والمنتهي', 'قيمة التوالف المعتمدة خلال السنة', disposalLoss);
    add('5. التوالف والمنتهي', 'قيمة أرصدة التشغيلات المنتهية حتى نهاية السنة', expiredLoss);

    // 6) ملخص توزيعات أرباح الشركاء.
    final distributions = await scalar('''
      SELECT COALESCE(SUM(distributable_profit),0)
      FROM partner_distributions WHERE branch_id=? AND status IN('APPROVED','POSTED')
        AND substr(period_code,1,4)=?
    ''', [p.branchId, yearText]);
    add('6. توزيعات أرباح الشركاء', 'صافي الأرباح الموزعة', distributions);
    add('6. توزيعات أرباح الشركاء', 'إجمالي المسحوبات الشخصية', withdrawals);
    return rows;
  }

}
