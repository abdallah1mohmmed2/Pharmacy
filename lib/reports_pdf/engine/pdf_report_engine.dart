// lib/reports_pdf/engine/pdf_report_engine.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models_and_contracts.dart';
import 'official_report_template.dart';

/// Shared local fonts for thermal receipts and dose labels.
/// Formal A4 reports use the same Noto Naskh fonts via OfficialReportTemplate.
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
      _cairo = pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf'),
      );
      _cairoBold = pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoNaskhArabic-Bold.ttf'),
      );
    } catch (_) {
      _cairo = pw.Font.helvetica();
      _cairoBold = pw.Font.helveticaBold();
    }
    try {
      _mono = pw.Font.ttf(
        await rootBundle.load('assets/fonts/RobotoMono-Regular.ttf'),
      );
    } catch (_) {
      _mono = pw.Font.courier();
    }
    _loaded = true;
  }

  pw.Font get regular => _cairo ?? pw.Font.helvetica();
  pw.Font get bold => _cairoBold ?? pw.Font.helveticaBold();
  pw.Font get mono => _mono ?? pw.Font.courier();
  pw.ThemeData get theme => pw.ThemeData.withFont(
        base: regular,
        bold: bold,
        italic: regular,
        boldItalic: bold,
      );
}

class CostMasker {
  const CostMasker();

  bool canShow(ReportParams params) =>
      params.canViewCost && params.showCostSetting;

  List<ReportColumn> filter(
    List<ReportColumn> columns,
    ReportParams params,
  ) {
    if (canShow(params)) {
      return columns.where((column) => column.visible).toList();
    }
    return columns
        .where((column) => column.visible && !column.costSensitive)
        .toList();
  }

  Map<String, Object?> filterRow(
    Map<String, Object?> row,
    List<ReportColumn> visibleColumns,
  ) =>
      {
        for (final column in visibleColumns) column.key: row[column.key],
      };
}

typedef PdfSaveFilePicker = Future<String?> Function({
  required String fileName,
  required Uint8List bytes,
});

Future<String?> _pickPdfSaveLocation({
  required String fileName,
  required Uint8List bytes,
}) {
  return FilePicker.platform.saveFile(
    dialogTitle: 'اختر مكان واسم ملف التقرير PDF',
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: const ['pdf'],
    bytes: bytes,
  );
}

/// The single PDF entry point for all formal reports R01–R55.
/// This class maps pharmacy data into the original official template and
/// retains the existing print, direct-print, save, share and CSV workflows.
class PdfReportEngine {
  PdfReportEngine({
    this.pharmacyName = 'نبض الصيدلية',
    this.licenseNumber = '',
    this.address = '',
    this.phone = '',
    this.branchName = 'الفرع الرئيسي',
    this.logoBytes,
    CostMasker? costMasker,
    PdfSaveFilePicker? saveFilePicker,
  })  : costMasker = costMasker ?? const CostMasker(),
        saveFilePicker = saveFilePicker ?? _pickPdfSaveLocation;

  final String pharmacyName;
  final String licenseNumber;
  final String address;
  final String phone;
  final String branchName;
  final Uint8List? logoBytes;
  final CostMasker costMasker;
  final PdfSaveFilePicker saveFilePicker;

  Future<Uint8List> build({
    required ReportDefinition definition,
    required ReportDataSet data,
    required ReportParams params,
  }) async {
    final columns = costMasker.filter(data.columns, params);
    final safeRows = data.rows
        .map((row) => costMasker.filterRow(row, columns))
        .toList(growable: false);
    final totals = costMasker.canShow(params)
        ? data.totals
        : Map<String, double>.fromEntries(
            data.totals.entries.where(
              (entry) => columns.any((column) => column.key == entry.key),
            ),
          );

    // R46 contains the full 19-point drug monograph. Render each clinical
    // point as a labeled row so the original content remains readable.
    final List<String> tableColumns;
    final List<List<String>> tableRows;
    if (data.reportNumber == 46) {
      tableColumns = const ['النقطة السريرية', 'البيانات'];
      final source = safeRows.isEmpty ? <String, Object?>{} : safeRows.first;
      tableRows = columns
          .map(
            (column) => <String>[
              column.label,
              column.display(source[column.key]),
            ],
          )
          .toList(growable: false);
    } else {
      tableColumns = columns.map((column) => column.label).toList();
      tableRows = safeRows
          .map(
            (row) => columns
                .map((column) => column.display(row[column.key]))
                .toList(growable: false),
          )
          .toList(growable: false);
    }

    List<String>? footerTotalRow;
    if (definition.includeTotals &&
        totals.isNotEmpty &&
        tableColumns.isNotEmpty) {
      footerTotalRow = [
        for (var index = 0; index < columns.length; index++)
          index == 0
              ? definition.totals.label
              : totals.containsKey(columns[index].key)
                  ? columns[index].display(totals[columns[index].key])
                  : '',
      ];
    }

    final summaryBoxes = <StatBoxData>[];
    if (costMasker.canShow(params)) {
      var number = 1;
      for (final entry in data.summary.entries) {
        summaryBoxes.add(
          StatBoxData(
            number: number.toString(),
            title: entry.key,
            value: _displaySummaryValue(entry.value),
            isBlueTint: number.isOdd,
            isLarge: data.summary.length <= 3 && number == 1,
          ),
        );
        number++;
      }
    }

    final generatedAt = params.generatedAt;
    final date = '${generatedAt.year.toString().padLeft(4, '0')}/'
        '${generatedAt.month.toString().padLeft(2, '0')}/'
        '${generatedAt.day.toString().padLeft(2, '0')}';
    final reportCode = 'R${definition.number.toString().padLeft(2, '0')}';
    final headerDetails = <String>[
      branchName,
      if (licenseNumber.isNotEmpty) 'الترخيص: $licenseNumber',
      if (address.isNotEmpty) address,
      if (phone.isNotEmpty) phone,
    ].join(' | ');

    return OfficialReportTemplate.preview(
      rightHeader1: 'الجمهورية اليمنية',
      rightHeader2: pharmacyName,
      rightHeader3: headerDetails,
      date: date,
      refNumber: reportCode,
      attachments: '—',
      reportTitle: 'تقرير رقم ${definition.number}: ${definition.title}',
      summaryBoxes: summaryBoxes,
      columns: tableColumns,
      rows: tableRows,
      footerTotalRow: footerTotalRow,
      emblemImageBytes: logoBytes,
      thirdSignatureLabel: 'الاعتماد والختم',
      signatureLabels: definition.signatures.labels,
      brandMarkText: 'نبض',
      documentAuthor: params.userName.isEmpty ? pharmacyName : params.userName,
      documentCreator: '$pharmacyName – Pharmacy ERP',
      fileName: 'nabdh-${reportCode.toLowerCase()}.pdf',
      minTableRows: 7,
      pageFormat: (params.paperLandscape ?? definition.isLandscape)
          ? PdfPageFormat.a4.landscape
          : PdfPageFormat.a4,
      preferredRowsPerPage: 30,
      printAfterGenerate: false,
    );
  }

  String _displaySummaryValue(Object? value) {
    if (value == null) return '—';
    if (value is num) return value.toStringAsFixed(2);
    return value.toString();
  }

  Future<void> preview({
    required ReportDefinition definition,
    required ReportDataSet data,
    required ReportParams params,
  }) async {
    final bytes = await build(
      definition: definition,
      data: data,
      params: params,
    );
    await Printing.layoutPdf(
      name: 'nabdh-report-${definition.number}.pdf',
      onLayout: (_) async => bytes,
    );
  }

  Future<void> printDirect({
    required BuildContext context,
    required ReportDefinition definition,
    required ReportDataSet data,
    required ReportParams params,
  }) async {
    final bytes = await build(
      definition: definition,
      data: data,
      params: params,
    );
    final printer = await Printing.pickPrinter(context: context);
    if (printer == null) return;
    await Printing.directPrintPdf(
      printer: printer,
      onLayout: (_) async => bytes,
    );
  }

  /// Opens the operating-system Save As dialog. A null result means the user
  /// cancelled; no fallback directory is used and no hidden copy is created.
  Future<String?> save({
    required ReportDefinition definition,
    required ReportDataSet data,
    required ReportParams params,
  }) async {
    final bytes = await build(
      definition: definition,
      data: data,
      params: params,
    );
    final reportCode = 'R${definition.number.toString().padLeft(2, '0')}';
    final fileName = 'nabdh_report_${reportCode}_'
        '${DateTime.now().millisecondsSinceEpoch}.pdf';
    return saveFilePicker(fileName: fileName, bytes: bytes);
  }

  Future<void> share({
    required ReportDefinition definition,
    required ReportDataSet data,
    required ReportParams params,
  }) async {
    final bytes = await build(
      definition: definition,
      data: data,
      params: params,
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'nabdh-report-${definition.number}.pdf',
    );
  }

  Future<Uint8List> exportCsv({
    required ReportDataSet data,
    required ReportParams params,
  }) async {
    final columns = costMasker.filter(data.columns, params);
    final table = <List<Object?>>[
      columns.map((column) => column.label).toList(),
      ...data.rows.map(
        (row) => columns.map((column) => row[column.key]).toList(),
      ),
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
    final file = File(
      '${directory.path}/nabdh_report_${definition.number}_'
      '${DateTime.now().millisecondsSinceEpoch}.csv',
    );
    return file.writeAsBytes(bytes, flush: true);
  }
}
