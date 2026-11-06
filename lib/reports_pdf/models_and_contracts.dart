// lib/reports_pdf/models_and_contracts.dart
import 'dart:collection';

/// التصنيف الوظيفي للتقارير الخمسة والخمسين.
enum ReportCategory {
  salesAndProfit('المبيعات والأرباح', 1, 12),
  inventoryAndExpiry('المخزون والتشغيلات والصلاحية', 13, 24),
  purchasesAndSuppliers('المشتريات والمذاخر والبونص', 25, 32),
  financeAndParties('التقارير المحاسبية والمالية', 33, 45),
  clinicalAndAudit('التقارير السريرية والرقابية', 46, 55);

  const ReportCategory(this.title, this.firstNumber, this.lastNumber);
  final String title;
  final int firstNumber;
  final int lastNumber;
  int get reportCount => lastNumber - firstNumber + 1;
}

enum ColAlign { start, center, end }
enum ColType { text, integer, decimal, currency, percent, date, dateTime, boolean }

typedef ReportQuery = Future<List<Map<String, Object?>>> Function(ReportParams params);

class ReportColumn {
  const ReportColumn({
    required this.key,
    required this.label,
    this.type = ColType.text,
    this.align = ColAlign.start,
    this.widthWeight = 1,
    this.sumInTotals = false,
    this.costSensitive = false,
    this.visible = true,
    this.format,
  }) : assert(widthWeight > 0);

  final String key;
  final String label;
  final ColType type;
  final ColAlign align;
  final double widthWeight;
  final bool sumInTotals;
  final bool costSensitive;
  final bool visible;
  final String Function(Object? value)? format;

  String display(Object? value) {
    if (value == null) return '—';
    if (format != null) return format!(value);
    switch (type) {
      case ColType.boolean:
        return value == true || value == 1 ? 'نعم' : 'لا';
      case ColType.integer:
        return _number(value).toStringAsFixed(0);
      case ColType.decimal:
      case ColType.currency:
        return _number(value).toStringAsFixed(2);
      case ColType.percent:
        return '${_number(value).toStringAsFixed(2)}%';
      case ColType.date:
      case ColType.dateTime:
      case ColType.text:
        return value.toString();
    }
  }
}

class ReportParam {
  const ReportParam({
    required this.key,
    required this.label,
    required this.kind,
    this.required = false,
    this.defaultValue,
    this.options = const <String>[],
    this.helpText,
  });

  final String key;
  final String label;
  final ReportParamKind kind;
  final bool required;
  final Object? defaultValue;
  final List<String> options;
  final String? helpText;
}

enum ReportParamKind {
  date,
  dateRange,
  customer,
  supplier,
  employee,
  drug,
  warehouse,
  cashier,
  category,
  number,
  text,
  boolean,
  orientation,
}

class ReportParams {
  ReportParams({
    Map<String, Object?> values = const {},
    this.branchId = 1,
    this.userId,
    this.userName = '',
    this.canViewCost = false,
    this.showCostSetting = false,
    this.paperLandscape,
    DateTime? generatedAt,
  })  : _values = Map<String, Object?>.from(values),
        generatedAt = generatedAt ?? DateTime.now();

  final Map<String, Object?> _values;
  final int branchId;
  final int? userId;
  final String userName;
  final bool canViewCost;
  final bool showCostSetting;
  final bool? paperLandscape;
  final DateTime generatedAt;

  UnmodifiableMapView<String, Object?> get values =>
      UnmodifiableMapView<String, Object?>(_values);

  Object? operator [](String key) => _values[key];
  T? value<T>(String key) {
    final v = _values[key];
    return v is T ? v : null;
  }

  String? stringValue(String key) {
    final v = _values[key];
    return v == null ? null : v.toString();
  }

  int? intValue(String key) {
    final v = _values[key];
    return v is num ? v.toInt() : int.tryParse('$v');
  }

  double? doubleValue(String key) {
    final v = _values[key];
    return v is num ? v.toDouble() : double.tryParse('$v');
  }

  bool boolValue(String key, {bool fallback = false}) {
    final v = _values[key];
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v == 'true' || v == '1';
    return fallback;
  }

  DateTime? dateValue(String key) {
    final v = _values[key];
    if (v is DateTime) return v;
    return v == null ? null : DateTime.tryParse(v.toString());
  }

  ReportParams copyWith({
    Map<String, Object?>? values,
    int? branchId,
    int? userId,
    String? userName,
    bool? canViewCost,
    bool? showCostSetting,
    bool? paperLandscape,
    DateTime? generatedAt,
  }) =>
      ReportParams(
        values: values ?? _values,
        branchId: branchId ?? this.branchId,
        userId: userId ?? this.userId,
        userName: userName ?? this.userName,
        canViewCost: canViewCost ?? this.canViewCost,
        showCostSetting: showCostSetting ?? this.showCostSetting,
        paperLandscape: paperLandscape ?? this.paperLandscape,
        generatedAt: generatedAt ?? this.generatedAt,
      );
}

class TotalsSpec {
  const TotalsSpec({
    this.label = 'الإجمالي',
    this.sumKeys = const <String>[],
    this.averageKeys = const <String>[],
    this.derivedValues = const <String, double Function(Map<String, double>)>{},
    this.description,
  });

  final String label;
  final List<String> sumKeys;
  final List<String> averageKeys;
  final Map<String, double Function(Map<String, double>)> derivedValues;
  final String? description;

  Map<String, double> calculate(
    List<Map<String, Object?>> rows,
    List<ReportColumn> columns,
  ) {
    final result = <String, double>{};
    final keys = <String>{
      ...sumKeys,
      ...averageKeys,
      for (final c in columns)
        if (c.sumInTotals) c.key,
    };
    for (final key in keys) {
      final values = rows.map((r) => _number(r[key])).toList();
      if (sumKeys.contains(key) ||
          columns.any((c) => c.key == key && c.sumInTotals)) {
        result[key] = values.fold<double>(0, (a, b) => a + b);
      } else if (averageKeys.contains(key)) {
        result[key] = values.isEmpty
            ? 0
            : values.fold<double>(0, (a, b) => a + b) / values.length;
      }
    }
    for (final entry in derivedValues.entries) {
      result[entry.key] = entry.value(result);
    }
    return result;
  }
}

class SignatureSpec {
  const SignatureSpec(this.labels);
  final List<String> labels;

  static const sales = SignatureSpec(['المُعِدّ', 'المدير']);
  static const inventory =
      SignatureSpec(['أمين المخزن', 'الصيدلي المسؤول', 'المدير']);
  static const purchases = SignatureSpec(['مسؤول المشتريات', 'المحاسب']);
  static const finance = SignatureSpec(['المحاسب', 'المالك']);
  static const clinical = SignatureSpec(['الصيدلي المسؤول', 'المدير']);
  static const controlled = SignatureSpec(
      ['الصيدلي المسؤول', 'صيدلي ثانٍ', 'المدير']);
  static const yearEnd = SignatureSpec(['المحاسب', 'المالك', 'الشركاء']);
}

class ReportDataSet {
  ReportDataSet({
    required this.reportNumber,
    required this.title,
    required List<ReportColumn> columns,
    required List<Map<String, Object?>> rows,
    this.totals = const {},
    this.summary = const {},
    this.generatedAt,
    this.warnings = const [],
  })  : columns = List.unmodifiable(columns),
        rows = List.unmodifiable(rows.map((r) => Map<String, Object?>.unmodifiable(r))),
        totals = Map.unmodifiable(totals),
        summary = Map.unmodifiable(summary);

  final int reportNumber;
  final String title;
  final List<ReportColumn> columns;
  final List<Map<String, Object?>> rows;
  final Map<String, double> totals;
  final Map<String, Object?> summary;
  final DateTime? generatedAt;
  final List<String> warnings;

  bool get isEmpty => rows.isEmpty;
}

abstract class ReportDefinition {
  const ReportDefinition({
    required this.number,
    required this.title,
    required this.category,
    required this.columns,
    required this.query,
    this.params = const [],
    this.totals = const TotalsSpec(),
    this.signatures = SignatureSpec.finance,
    this.forceLandscape = false,
    this.description = '',
    this.includeTotals = true,
  }) : assert(number >= 1 && number <= 55);

  final int number;
  final String title;
  final ReportCategory category;
  final List<ReportColumn> columns;
  final ReportQuery query;
  final List<ReportParam> params;
  final TotalsSpec totals;
  final SignatureSpec signatures;
  final bool forceLandscape;
  final String description;
  final bool includeTotals;

  bool get isLandscape => forceLandscape || columns.length > 8;

  Future<ReportDataSet> run(ReportParams params) async {
    _validate(params);
    final rows = await query(params);
    final visibleColumns = columns.where((c) => c.visible).toList();
    final aggregate = includeTotals
        ? totals.calculate(rows, visibleColumns)
        : <String, double>{};
    return ReportDataSet(
      reportNumber: number,
      title: title,
      columns: visibleColumns,
      rows: rows,
      totals: aggregate,
      generatedAt: params.generatedAt,
    );
  }

  void _validate(ReportParams params) {
    for (final param in this.params) {
      if (!param.required) continue;
      final value = params[param.key];
      if (value == null || (value is String && value.trim().isEmpty)) {
        throw ArgumentError('الحقل "${param.label}" مطلوب لتشغيل التقرير');
      }
    }
  }
}

double _number(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
