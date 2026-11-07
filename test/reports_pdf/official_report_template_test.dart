import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_enterprise_pharmacy_erp/reports_pdf/engine/pdf_report_engine.dart';
import 'package:global_enterprise_pharmacy_erp/reports_pdf/models_and_contracts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('formal pharmacy report is built through the Nabd official template', () async {
    const column = ReportColumn(key: 'drug_name', label: 'اسم الدواء');
    const definition = ConfiguredReportDefinition(
      number: 13,
      title: 'تقرير رصيد المخزون',
      category: ReportCategory.inventoryAndExpiry,
      columns: [column],
      query: _emptyQuery,
    );
    final data = ReportDataSet(
      reportNumber: 13,
      title: definition.title,
      columns: const [column],
      rows: const [{'drug_name': 'أوجمنتين'}],
      summary: const {'عدد الأصناف': 1},
    );
    final bytes = await PdfReportEngine().build(
      definition: definition,
      data: data,
      params: ReportParams(userName: 'اختبار'),
    );
    expect(utf8.decode(bytes.take(5).toList()), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  });

  test('19-point clinical report is laid out as labeled rows', () async {
    const columns = [
      ReportColumn(key: 'trade_name', label: '01 الهوية الدوائية'),
      ReportColumn(key: 'scientific_name', label: '02 الاسم العلمي'),
      ReportColumn(key: 'cost_price', label: 'سعر التكلفة', costSensitive: true),
    ];
    const definition = ConfiguredReportDefinition(
      number: 46,
      title: 'البطاقة السريرية الكاملة للدواء - 19 نقطة',
      category: ReportCategory.clinicalAndAudit,
      columns: columns,
      query: _emptyQuery,
    );
    final data = ReportDataSet(
      reportNumber: 46,
      title: definition.title,
      columns: columns,
      rows: const [{'trade_name': 'أوجمنتين', 'scientific_name': 'Amoxicillin + Clavulanate', 'cost_price': 5000}],
    );
    final bytes = await PdfReportEngine().build(
      definition: definition,
      data: data,
      params: ReportParams(userName: 'اختبار'),
    );
    expect(utf8.decode(bytes.take(5).toList()), '%PDF-');
  });
}

Future<List<Map<String, Object?>>> _emptyQuery(ReportParams params) async => [];
