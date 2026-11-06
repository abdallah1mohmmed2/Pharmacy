// lib/reports_pdf/engine/pdf_report_engine.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models_and_contracts.dart';

class FontCache {
  FontCache._();
  static final FontCache instance = FontCache._();

  pw.Font? _cairo;
  pw.Font? _cairoBold;
  pw.Font? _mono;
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    try {
      _cairo = pw.Font.ttf(await rootBundle.load('assets/fonts/Cairo-Regular.ttf'));
      _cairoBold = pw.Font.ttf(await rootBundle.load('assets/fonts/Cairo-Bold.ttf'));
    } catch (_) {
      try {
        _cairo = await PdfGoogleFonts.cairoRegular();
        _cairoBold = await PdfGoogleFonts.cairoBold();
      } catch (_) {
        _cairo = pw.Font.helvetica();
        _cairoBold = pw.Font.helveticaBold();
      }
    }
    try {
      _mono = pw.Font.ttf(await rootBundle.load('assets/fonts/RobotoMono-Regular.ttf'));
    } catch (_) {
      try {
        _mono = await PdfGoogleFonts.robotoMonoRegular();
      } catch (_) {
        _mono = pw.Font.courier();
      }
    }
    _loaded = true;
  }

  pw.Font get regular => _cairo ?? pw.Font.helvetica();
  pw.Font get bold => _cairoBold ?? pw.Font.helveticaBold();
  pw.Font get mono => _mono ?? pw.Font.courier();
  pw.ThemeData get theme => pw.ThemeData.withFont(base: regular, bold: bold, italic: regular, boldItalic: bold);
}

class CostMasker {
  const CostMasker();

  bool canShow(ReportParams params) => params.canViewCost && params.showCostSetting;

  List<ReportColumn> filter(List<ReportColumn> columns, ReportParams params) {
    if (canShow(params)) return columns.where((c) => c.visible).toList();
    return columns.where((c) => c.visible && !c.costSensitive).toList();
  }

  Map<String, Object?> filterRow(
    Map<String, Object?> row,
    List<ReportColumn> visibleColumns,
  ) => {for (final column in visibleColumns) column.key: row[column.key]};
}

class PdfReportEngine {
  PdfReportEngine({
    this.pharmacyName = 'الصيدلية',
    this.licenseNumber = '',
    this.address = '',
    this.phone = '',
    this.branchName = 'الفرع الرئيسي',
    this.logoBytes,
    CostMasker? costMasker,
  }) : costMasker = costMasker ?? const CostMasker();

  final String pharmacyName;
  final String licenseNumber;
  final String address;
  final String phone;
  final String branchName;
  final Uint8List? logoBytes;
  final CostMasker costMasker;

  Future<Uint8List> build({
    required ReportDefinition definition,
    required ReportDataSet data,
    required ReportParams params,
  }) async {
    await FontCache.instance.load();
    final columns = costMasker.filter(data.columns, params);
    final rows = data.rows.map((r) => costMasker.filterRow(r, columns)).toList();
    final totals = costMasker.canShow(params)
        ? data.totals
        : Map<String, double>.fromEntries(
            data.totals.entries.where((e) => columns.any((c) => c.key == e.key)),
          );
    final document = pw.Document(
      title: 'تقرير رقم ${definition.number}: ${definition.title}',
      author: params.userName,
      creator: 'Global Enterprise Pharmacy ERP',
    );
    final landscape = params.paperLandscape ?? definition.isLandscape;
    final pageFormat = landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;

    document.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        theme: FontCache.instance.theme,
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 34),
        header: (context) => pw.Column(
          children: [
            HeaderBuilder(
              pharmacyName: pharmacyName,
              licenseNumber: licenseNumber,
              address: address,
              phone: phone,
              branchName: branchName,
              logoBytes: logoBytes,
            ).build(),
            if (context.pageNumber > 1) TableBuilder(columns: columns, rows: const []).buildHeader(),
          ],
        ),
        footer: (context) => FooterBuilder(
          printedAt: params.generatedAt,
          printedBy: params.userName,
          pageNumber: context.pageNumber,
          pagesCount: context.pagesCount,
        ).build(),
        build: (context) => [
          TitleBlock(
            reportNumber: definition.number,
            title: definition.title,
            params: params,
          ).build(),
          if (definition.description.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Text(definition.description, style: const pw.TextStyle(fontSize: 8)),
            ),
          TableBuilder(columns: columns, rows: rows).build(),
          if (definition.includeTotals && totals.isNotEmpty)
            TotalsRow(columns: columns, totals: totals, label: definition.totals.label).build(),
          pw.SizedBox(height: 22),
          SignatureBlock(spec: definition.signatures).build(),
        ],
      ),
    );
    return document.save();
  }

  Future<void> preview({
    required ReportDefinition definition,
    required ReportDataSet data,
    required ReportParams params,
  }) async {
    final bytes = await build(definition: definition, data: data, params: params);
    await Printing.layoutPdf(
      name: 'report-${definition.number}.pdf',
      onLayout: (_) async => bytes,
    );
  }

  Future<void> printDirect({
    required BuildContext context,
    required ReportDefinition definition,
    required ReportDataSet data,
    required ReportParams params,
  }) async {
    final bytes = await build(definition: definition, data: data, params: params);
    await Printing.directPrintPdf(
      printer: await Printing.pickPrinter(context: context),
      onLayout: (_) async => bytes,
    );
  }

  Future<File> save({
    required ReportDefinition definition,
    required ReportDataSet data,
    required ReportParams params,
    String? directoryPath,
  }) async {
    final bytes = await build(definition: definition, data: data, params: params);
    final directory = directoryPath == null
        ? await getApplicationDocumentsDirectory()
        : Directory(directoryPath);
    await directory.create(recursive: true);
    final file = File('${directory.path}/report_${definition.number}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    return file.writeAsBytes(bytes, flush: true);
  }

  Future<void> share({
    required ReportDefinition definition,
    required ReportDataSet data,
    required ReportParams params,
  }) async {
    final bytes = await build(definition: definition, data: data, params: params);
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'report_${definition.number}.pdf',
    );
  }

  Future<Uint8List> exportCsv({
    required ReportDataSet data,
    required ReportParams params,
  }) async {
    final columns = costMasker.filter(data.columns, params);
    final table = <List<Object?>>[
      columns.map((c) => c.label).toList(),
      ...data.rows.map((row) => columns.map((c) => row[c.key]).toList()),
    ];
    final csv = const ListToCsvConverter(fieldDelimiter: ',').convert(table);
    return Uint8List.fromList([0xEF, 0xBB, 0xBF, ...csv.codeUnits]);
  }

  Future<File> saveCsv({
    required ReportDefinition definition,
    required ReportDataSet data,
    required ReportParams params,
    String? directoryPath,
  }) async {
    final bytes = await exportCsv(data: data, params: params);
    final directory = directoryPath == null
        ? await getApplicationDocumentsDirectory()
        : Directory(directoryPath);
    await directory.create(recursive: true);
    final file = File('${directory.path}/report_${definition.number}_${DateTime.now().millisecondsSinceEpoch}.csv');
    return file.writeAsBytes(bytes, flush: true);
  }
}

class HeaderBuilder {
  const HeaderBuilder({
    required this.pharmacyName,
    required this.licenseNumber,
    required this.address,
    required this.phone,
    required this.branchName,
    this.logoBytes,
  });

  final String pharmacyName, licenseNumber, address, phone, branchName;
  final Uint8List? logoBytes;

  pw.Widget build() => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 9),
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(width: 1.2)),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (logoBytes != null)
              pw.Container(
                width: 42,
                height: 42,
                margin: const pw.EdgeInsetsDirectional.only(end: 10),
                child: pw.Image(pw.MemoryImage(logoBytes!), fit: pw.BoxFit.contain),
              ),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(pharmacyName, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                  pw.Text('الفرع: $branchName', style: const pw.TextStyle(fontSize: 9)),
                  if (licenseNumber.isNotEmpty) pw.Text('رقم الترخيص: $licenseNumber', style: const pw.TextStyle(fontSize: 8)),
                  if (address.isNotEmpty || phone.isNotEmpty)
                    pw.Text([address, phone].where((e) => e.isNotEmpty).join(' • '), style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
            ),
          ],
        ),
      );
}

class TitleBlock {
  const TitleBlock({required this.reportNumber, required this.title, required this.params});
  final int reportNumber;
  final String title;
  final ReportParams params;

  pw.Widget build() {
    final from = params.stringValue('date_from') ?? params.stringValue('from');
    final to = params.stringValue('date_to') ?? params.stringValue('to');
    final filters = params.values.entries
        .where((e) => !{'date_from', 'date_to', 'from', 'to'}.contains(e.key) && e.value != null)
        .map((e) => '${e.key}: ${e.value}')
        .join('  |  ');
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('تقرير رقم $reportNumber: $title', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          if (from != null || to != null)
            pw.Text('الفترة: ${from ?? 'البداية'} إلى ${to ?? 'حتى الآن'}', style: const pw.TextStyle(fontSize: 9)),
          if (filters.isNotEmpty)
            pw.Container(
              width: double.infinity,
              margin: const pw.EdgeInsets.only(top: 5),
              padding: const pw.EdgeInsets.all(5),
              color: PdfColors.grey200,
              child: pw.Text('الفلاتر: $filters', style: const pw.TextStyle(fontSize: 8)),
            ),
        ],
      ),
    );
  }
}

class TableBuilder {
  const TableBuilder({required this.columns, required this.rows});
  final List<ReportColumn> columns;
  final List<Map<String, Object?>> rows;

  pw.Widget _cell(ReportColumn column, Object? value, {bool header = false}) {
    final numeric = column.type != ColType.text && column.type != ColType.boolean;
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: pw.Text(
        header ? column.label : column.display(value),
        textAlign: column.align == ColAlign.center
            ? pw.TextAlign.center
            : column.align == ColAlign.end
                ? pw.TextAlign.left
                : pw.TextAlign.right,
        style: pw.TextStyle(
          font: header ? FontCache.instance.bold : numeric ? FontCache.instance.mono : FontCache.instance.regular,
          fontSize: header ? 7.5 : 7,
          fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: header ? PdfColors.white : PdfColors.black,
        ),
      ),
    );
  }

  pw.TableRow _headerRow() => pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
        children: columns.map((c) => _cell(c, null, header: true)).toList(),
      );

  pw.Widget buildHeader() => pw.Table(
        columnWidths: {
          for (var i = 0; i < columns.length; i++) i: pw.FlexColumnWidth(columns[i].widthWeight),
        },
        border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.35),
        children: [_headerRow()],
      );

  pw.Widget build() {
    if (columns.isEmpty) return pw.Text('لا توجد أعمدة معرفة لهذا التقرير');
    if (rows.isEmpty) {
      return pw.Column(children: [_headerRowWidget(), pw.Padding(
        padding: const pw.EdgeInsets.all(8),
        child: pw.Text('لا توجد بيانات ضمن المعاملات المحددة', style: const pw.TextStyle(fontSize: 8)),
      )]);
    }
    return pw.Table(
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      columnWidths: {
        for (var i = 0; i < columns.length; i++) i: pw.FlexColumnWidth(columns[i].widthWeight),
      },
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.35),
      children: [
        _headerRow(),
        for (var rowIndex = 0; rowIndex < rows.length; rowIndex++)
          pw.TableRow(
            decoration: rowIndex.isOdd ? const pw.BoxDecoration(color: PdfColors.grey100) : null,
            children: columns.map((column) => _cell(column, rows[rowIndex][column.key])).toList(),
          ),
      ],
    );
  }

  pw.Widget _headerRowWidget() => buildHeader();
}

class TotalsRow {
  const TotalsRow({required this.columns, required this.totals, required this.label});
  final List<ReportColumn> columns;
  final Map<String, double> totals;
  final String label;

  pw.Widget build() => pw.Container(
        margin: const pw.EdgeInsets.only(top: 4),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(width: 1.2), bottom: pw.BorderSide(width: 0.5)),
        ),
        padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 3),
        child: pw.Row(
          children: [
            for (final column in columns)
              pw.Expanded(
                flex: (column.widthWeight * 100).round().clamp(1, 1000),
                child: pw.Text(
                  column.key == columns.first.key
                      ? label
                      : (totals.containsKey(column.key) ? column.display(totals[column.key]) : ''),
                  textAlign: column.align == ColAlign.center
                      ? pw.TextAlign.center
                      : column.align == ColAlign.end
                          ? pw.TextAlign.left
                          : pw.TextAlign.right,
                  style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, font: column.type == ColType.text ? FontCache.instance.bold : FontCache.instance.mono),
                ),
              ),
          ],
        ),
      );
}

class SignatureBlock {
  const SignatureBlock({required this.spec});
  final SignatureSpec spec;

  pw.Widget build() => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          for (final label in spec.labels)
            pw.Expanded(
              child: pw.Column(
                children: [
                  pw.Text(label, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 28),
                  pw.Container(width: 100, decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.6)))),
                ],
              ),
            ),
        ],
      );
}

class FooterBuilder {
  const FooterBuilder({
    required this.printedAt,
    required this.printedBy,
    required this.pageNumber,
    required this.pagesCount,
  });

  final DateTime printedAt;
  final String printedBy;
  final int pageNumber, pagesCount;

  pw.Widget build() => pw.Container(
        alignment: pw.Alignment.center,
        padding: const pw.EdgeInsets.only(top: 6),
        decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.5))),
        child: pw.Text(
          'تاريخ ووقت الطباعة: ${printedAt.toIso8601String().substring(0, 16).replaceFirst('T', ' ')}   •   طُبع بواسطة: ${printedBy.isEmpty ? 'النظام' : printedBy}   •   صفحة $pageNumber من $pagesCount',
          style: const pw.TextStyle(fontSize: 7),
        ),
      );
}
