// lib/reports_pdf/registry/report_registry_and_provider.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../data/services/settings_and_audit_service.dart';

import '../../data/database/database_helper.dart';
import '../../core/utils/label_guard.dart';
import '../datasources/clinical_and_audit_queries.dart';
import '../datasources/purchase_and_finance_queries.dart';
import '../datasources/sales_and_inventory_queries.dart';
import '../definitions/r01_to_r12_sales_definitions.dart';
import '../definitions/r13_to_r24_inventory_definitions.dart';
import '../definitions/r25_to_r32_purchase_definitions.dart';
import '../definitions/r33_to_r45_finance_lah_alayh_definitions.dart';
import '../definitions/r46_to_r55_clinical_definitions.dart';
import '../engine/pdf_report_engine.dart';
import '../models_and_contracts.dart';

class ReportRegistry {
  ReportRegistry({DatabaseHelper? helper})
      : _sales = SalesAndInventoryQueries(helper: helper),
        _finance = PurchaseAndFinanceQueries(helper: helper),
        _clinical = ClinicalAndAuditQueries(helper: helper) {
    final all = <ReportDefinition>[
      ...buildR01ToR12SalesDefinitions(_sales),
      ...buildR13ToR24InventoryDefinitions(_sales),
      ...buildR25ToR32PurchaseDefinitions(_finance),
      ...buildR33ToR45FinanceDefinitions(_finance),
      ...buildR46ToR55ClinicalDefinitions(_clinical),
    ]..sort((a, b) => a.number.compareTo(b.number));
    if (all.length != 55) {
      throw StateError('يجب تسجيل 55 تقريراً؛ العدد المسجل حالياً: ${all.length}');
    }
    for (var i = 0; i < all.length; i++) {
      if (all[i].number != i + 1) {
        throw StateError('فجوة أو تكرار في سجل التقارير عند الرقم ${i + 1}');
      }
    }
    _reports = List.unmodifiable(all);
  }

  final SalesAndInventoryQueries _sales;
  final PurchaseAndFinanceQueries _finance;
  final ClinicalAndAuditQueries _clinical;
  late final List<ReportDefinition> _reports;

  List<ReportDefinition> get all => _reports;
  ReportDefinition? byNumber(int number) =>
      number < 1 || number > _reports.length ? null : _reports[number - 1];

  List<ReportDefinition> byCategory(ReportCategory category) =>
      _reports.where((r) => r.category == category).toList(growable: false);

  List<ReportDefinition> search(String query, {ReportCategory? category}) {
    final normalized = query.trim().toLowerCase();
    return _reports.where((report) {
      if (category != null && report.category != category) return false;
      if (normalized.isEmpty) return true;
      return report.title.toLowerCase().contains(normalized) ||
          report.number.toString() == normalized ||
          report.number.toString().padLeft(2, '0') == normalized ||
          'r${report.number.toString().padLeft(2, '0')}'.contains(normalized);
    }).toList(growable: false);
  }
}

class ReportsCenterProvider extends ChangeNotifier {
  ReportsCenterProvider({
    DatabaseHelper? helper,
    ReportRegistry? registry,
    PdfReportEngine? engine,
  })  : _helper = helper ?? DatabaseHelper.instance,
        registry = registry ?? ReportRegistry(helper: helper),
        engine = engine ?? PdfReportEngine();

  final DatabaseHelper _helper;
  final ReportRegistry registry;
  final PdfReportEngine engine;

  int? _userId;
  String _userName = '';
  int _branchId = 1;
  bool _canViewCost = false;
  bool _showCostSetting = false;
  bool _loading = false;
  String? _error;
  ReportDefinition? _selected;
  ReportDataSet? _data;
  ReportParams _params = ReportParams();
  final Set<int> _favorites = {};
  final Map<ReportParamKind, Future<List<Map<String, Object?>>>> _optionCache = {};

  bool get isLoading => _loading;
  String? get error => _error;
  ReportDefinition? get selected => _selected;
  ReportDataSet? get data => _data;
  ReportParams get params => _params;
  Set<int> get favorites => Set.unmodifiable(_favorites);
  bool get canViewCost => _canViewCost && _showCostSetting;
  bool get hasCostPermission => _canViewCost;
  bool get showCostSetting => _showCostSetting;

  Future<void> initialize({
    required int userId,
    required String userName,
    int branchId = 1,
  }) async {
    _userId = userId;
    _userName = userName;
    _branchId = branchId;
    await _loadCostPermission();
    await loadFavorites();
  }

  Future<void> _loadCostPermission() async {
    final id = _userId;
    if (id == null) return;
    final db = await _helper.database;
    // Iteration 6 uses role_permissions and system_settings as the
    // authoritative sources. The former user_permissions/app_settings tables
    // are legacy and are not part of a fresh database.
    final permissions = await db.rawQuery(
      '''
      SELECT rp.is_allowed
      FROM users u
      JOIN role_permissions rp
        ON rp.role_code=COALESCE(u.system_role_code,u.role_code)
      WHERE u.id=? AND u.is_active=1 AND u.is_deleted=0
        AND rp.permission_code=?
      LIMIT 1
      ''',
      [id, 'reports.cost.view'],
    );
    _canViewCost =
        permissions.isNotEmpty && (permissions.first['is_allowed'] as num) == 1;
    final setting = await db.query(
      'system_settings',
      columns: ['setting_value'],
      where: 'setting_key=?',
      whereArgs: ['sales.show_cost_to_pharmacist'],
      limit: 1,
    );
    final rawSetting = setting.isEmpty
        ? null
        : setting.first['setting_value']?.toString().trim();
    _showCostSetting = rawSetting == 'true' || rawSetting == '1';
    notifyListeners();
  }

  Future<List<Map<String, Object?>>> parameterOptions(ReportParamKind kind) {
    return _optionCache.putIfAbsent(kind, () async {
      final db = await _helper.database;
      switch (kind) {
        case ReportParamKind.customer:
          return db.query('parties',
              columns: ['id', 'name_ar'],
              where: "branch_id=? AND party_type='CUSTOMER' AND is_deleted=0",
              whereArgs: [_branchId], orderBy: 'name_ar');
        case ReportParamKind.supplier:
          return db.query('parties',
              columns: ['id', 'name_ar'],
              where: "branch_id=? AND party_type='SUPPLIER' AND is_deleted=0",
              whereArgs: [_branchId], orderBy: 'name_ar');
        case ReportParamKind.employee:
          return db.rawQuery('''
            SELECT p.id,p.name_ar FROM employees e
            JOIN parties p ON p.id=e.party_id
            WHERE e.branch_id=? AND p.is_deleted=0 ORDER BY p.name_ar
          ''', [_branchId]);
        case ReportParamKind.drug:
          return db.query('drugs',
              columns: ['id', 'trade_name_ar AS name_ar'],
              where: 'branch_id=? AND is_deleted=0',
              whereArgs: [_branchId], orderBy: 'trade_name_ar');
        case ReportParamKind.warehouse:
          return db.query('warehouses',
              columns: ['id', 'name_ar'],
              where: 'branch_id=?', whereArgs: [_branchId], orderBy: 'name_ar');
        case ReportParamKind.cashier:
          return db.query('users',
              columns: ['id', 'full_name AS name_ar'],
              where: 'branch_id=? AND is_deleted=0 AND is_active=1',
              whereArgs: [_branchId], orderBy: 'full_name');
        case ReportParamKind.category:
          return db.query('drug_categories',
              columns: ['id', 'name_ar'],
              where: 'branch_id=? AND is_deleted=0',
              whereArgs: [_branchId], orderBy: 'name_ar');
        default:
          return <Map<String, Object?>>[];
      }
    });
  }

  Future<void> loadFavorites() async {
    final id = _userId;
    if (id == null) return;
    final rows = await _helper.query(
      'report_favorites',
      where: 'user_id=?',
      whereArgs: [id],
    );
    _favorites
      ..clear()
      ..addAll(rows.map((r) => r['report_number'] as int));
    notifyListeners();
  }

  Future<void> toggleFavorite(int reportNumber) async {
    final id = _userId;
    if (id == null) throw StateError('يجب تحديد المستخدم الحالي أولاً');
    final db = await _helper.database;
    if (_favorites.contains(reportNumber)) {
      await db.delete(
        'report_favorites',
        where: 'user_id=? AND report_number=?',
        whereArgs: [id, reportNumber],
      );
      _favorites.remove(reportNumber);
    } else {
      await db.insert('report_favorites', {
        'user_id': id,
        'report_number': reportNumber,
      });
      _favorites.add(reportNumber);
    }
    notifyListeners();
  }

  void selectReport(int number) {
    _selected = registry.byNumber(number);
    _data = null;
    _error = null;
    _params = ReportParams(
      branchId: _branchId,
      userId: _userId,
      userName: _userName,
      canViewCost: _canViewCost,
      showCostSetting: _showCostSetting,
    );
    notifyListeners();
  }

  Future<void> updateCostVisibility(bool show) async {
    if (!_canViewCost) return;
    final db = await _helper.database;
    final oldValue = _showCostSetting;
    final updated = await db.update(
      'system_settings',
      {
        'setting_value': show ? 'true' : 'false',
        'updated_at': DateTime.now().toIso8601String(),
        'updated_by': _userId,
      },
      where: 'setting_key=?',
      whereArgs: ['sales.show_cost_to_pharmacist'],
    );
    if (updated != 1) {
      throw StateError('تعذر حفظ إعداد إظهار التكلفة في قاعدة البيانات');
    }
    await AuditService(helper: _helper).record(
      action: 'SETTING_CHANGE',
      userId: _userId,
      branchId: _branchId,
      entityType: 'system_settings',
      entityLabel: 'sales.show_cost_to_pharmacist',
      oldValues: {'value': oldValue},
      newValues: {'value': show},
      severity: 'WARNING',
    );
    _showCostSetting = show;
    _params = _params.copyWith(showCostSetting: show);
    notifyListeners();
  }

  void updateParams(Map<String, Object?> values, {bool? paperLandscape}) {
    _params = _params.copyWith(
      values: {..._params.values, ...values},
      paperLandscape: paperLandscape,
    );
    notifyListeners();
  }

  Future<ReportDataSet?> runSelected() async {
    final definition = _selected;
    if (definition == null) return null;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final raw = await definition.run(_params);
      final visibleColumns = engine.costMasker.filter(raw.columns, _params);
      final visibleRows = raw.rows.map((row) {
        final filtered=engine.costMasker.filterRow(row,visibleColumns);
        return Map<String,Object?>.fromEntries(filtered.entries.map((entry)=>MapEntry(entry.key,entry.value is String?LabelGuard.sanitize(entry.value as String):entry.value)));
      }).toList(growable:false);
      final visibleTotals = Map<String, double>.fromEntries(
        raw.totals.entries.where((entry) =>
            visibleColumns.any((column) => column.key == entry.key)),
      );
      _data = ReportDataSet(
        reportNumber: raw.reportNumber,
        title: raw.title,
        columns: visibleColumns,
        rows: visibleRows,
        totals: visibleTotals,
        summary: engine.costMasker.canShow(_params) ? raw.summary : const <String,Object?>{},
        generatedAt: raw.generatedAt,
        warnings: raw.warnings,
      );
      return _data;
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<Uint8List?> buildPdf() async {
    final definition = _selected;
    final data = _data;
    if (definition == null || data == null) return null;
    return engine.build(definition: definition, data: data, params: _params);
  }

  Future<File?> savePdf() async {
    final definition = _selected, data = _data;
    if (definition == null || data == null) return null;
    return engine.save(definition: definition, data: data, params: _params);
  }

  Future<File?> exportCsv() async {
    final definition = _selected, data = _data;
    if (definition == null || data == null) return null;
    return engine.saveCsv(definition: definition, data: data, params: _params);
  }

  Future<void> printSelected() async {
    final definition = _selected, data = _data;
    if (definition == null || data == null) return;
    await engine.preview(definition: definition, data: data, params: _params);
  }

  Future<void> sharePdf() async {
    final definition = _selected, data = _data;
    if (definition == null || data == null) return;
    await engine.share(definition: definition, data: data, params: _params);
  }

  void clearResult() {
    _data = null;
    _error = null;
    notifyListeners();
  }
}
