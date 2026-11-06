// lib/reports_pdf/engine/receipt_and_label_builder.dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'pdf_report_engine.dart';

enum ThermalPaper { mm80, mm58 }

class ReceiptLine {
  const ReceiptLine({
    required this.name,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
    required this.total,
  });

  final String name;
  final String unit;
  final num quantity;
  final num unitPrice;
  final num total;
}

class ReceiptData {
  const ReceiptData({
    required this.invoiceNumber,
    required this.dateTime,
    required this.customerName,
    required this.lines,
    required this.subtotal,
    required this.discount,
    required this.rounding,
    required this.netTotal,
    required this.paid,
    required this.paymentMethod,
    this.walletNotificationNumber,
    this.remainingAfterInvoice = 0,
    this.pharmacyName = 'الصيدلية',
    this.branchName = 'الفرع الرئيسي',
    this.phone = '',
    this.currency = 'ر.ي',
  });

  final String invoiceNumber;
  final DateTime dateTime;
  final String customerName;
  final List<ReceiptLine> lines;
  final num subtotal, discount, rounding, netTotal, paid;
  final String paymentMethod;
  final String? walletNotificationNumber;
  final num remainingAfterInvoice;
  final String pharmacyName, branchName, phone, currency;
}

class DoseLabelData {
  const DoseLabelData({
    required this.patientName,
    required this.drugName,
    required this.strength,
    required this.doseTextAr,
    required this.mealInstruction,
    required this.expiryDate,
    this.keepRefrigerated = false,
    this.pharmacyName = 'الصيدلية',
  });

  final String patientName, drugName, strength, doseTextAr;
  final String mealInstruction;
  final String expiryDate;
  final bool keepRefrigerated;
  final String pharmacyName;
}

class ReceiptAndLabelBuilder {
  const ReceiptAndLabelBuilder();

  Future<Uint8List> buildReceipt(
    ReceiptData receipt, {
    ThermalPaper paper = ThermalPaper.mm80,
  }) async {
    await FontCache.instance.load();
    final width = (paper == ThermalPaper.mm80 ? 80 : 58) * PdfPageFormat.mm;
    final pageFormat = PdfPageFormat(
      width,
      500 * PdfPageFormat.mm,
      marginLeft: 3 * PdfPageFormat.mm,
      marginRight: 3 * PdfPageFormat.mm,
      marginTop: 3 * PdfPageFormat.mm,
      marginBottom: 3 * PdfPageFormat.mm,
    );
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        theme: FontCache.instance.theme,
        textDirection: pw.TextDirection.rtl,
        build: (context) => [
          pw.Center(
            child: pw.Column(
              children: [
                pw.Text(receipt.pharmacyName, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                pw.Text(receipt.branchName, style: const pw.TextStyle(fontSize: 8)),
                if (receipt.phone.isNotEmpty) pw.Text(receipt.phone, style: const pw.TextStyle(fontSize: 8)),
                pw.Divider(thickness: 1),
                pw.Text('فاتورة رقم: ${receipt.invoiceNumber}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                pw.Text(_dateTime(receipt.dateTime), style: const pw.TextStyle(fontSize: 8)),
                pw.Text('العميل: ${receipt.customerName}', style: const pw.TextStyle(fontSize: 8)),
              ],
            ),
          ),
          pw.SizedBox(height: 5),
          _receiptItemsTable(receipt.lines, paper),
          pw.Divider(),
          _moneyLine('الإجمالي قبل الخصم', receipt.subtotal, receipt.currency),
          _moneyLine('الخصم', receipt.discount, receipt.currency),
          _moneyLine('التقريب', receipt.rounding, receipt.currency),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 4),
            decoration: const pw.BoxDecoration(border: pw.Border.symmetric(horizontal: pw.BorderSide(width: 1))),
            child: _moneyLine('الصافي', receipt.netTotal, receipt.currency, bold: true),
          ),
          _moneyLine('المدفوع', receipt.paid, receipt.currency),
          pw.Text('طريقة الدفع: ${receipt.paymentMethod}', style: const pw.TextStyle(fontSize: 8)),
          if ((receipt.walletNotificationNumber ?? '').isNotEmpty)
            pw.Text('رقم إشعار المحفظة: ${receipt.walletNotificationNumber}', style: const pw.TextStyle(fontSize: 8)),
          if (receipt.remainingAfterInvoice > 0)
            pw.Container(
              margin: const pw.EdgeInsets.only(top: 4),
              padding: const pw.EdgeInsets.all(5),
              decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.8)),
              child: _moneyLine('المتبقي عليه بعد الفاتورة', receipt.remainingAfterInvoice, receipt.currency, bold: true),
            ),
          pw.SizedBox(height: 10),
          pw.Center(child: pw.BarcodeWidget(
            barcode: pw.Barcode.code128(),
            data: receipt.invoiceNumber,
            width: width * 0.68,
            height: 38,
            drawText: false,
          )),
          pw.Center(child: pw.Text('شكراً لزيارتكم', style: const pw.TextStyle(fontSize: 8))),
        ],
      ),
    );
    return doc.save();
  }

  pw.Widget _receiptItemsTable(List<ReceiptLine> lines, ThermalPaper paper) {
    final narrow = paper == ThermalPaper.mm58;
    final headers = narrow
        ? ['الصنف / الوحدة', 'كمية', 'السعر', 'الإجمالي']
        : ['الصنف', 'الوحدة', 'الكمية', 'السعر', 'الإجمالي'];
    final rows = <List<String>>[
      headers,
      ...lines.map((line) => narrow
          ? [line.name, '${line.quantity}', _money(line.unitPrice), _money(line.total)]
          : [line.name, line.unit, '${line.quantity}', _money(line.unitPrice), _money(line.total)]),
    ];
    return pw.TableHelper.fromTextArray(
      data: rows,
      headerCount: 1,
      cellAlignment: pw.Alignment.centerRight,
      headerAlignment: pw.Alignment.centerRight,
      headerStyle: pw.TextStyle(fontSize: narrow ? 6 : 7, fontWeight: pw.FontWeight.bold),
      cellStyle: pw.TextStyle(fontSize: narrow ? 6 : 7),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3),
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(width: 0.25, color: PdfColors.grey500),
        bottom: pw.BorderSide(width: 0.5, color: PdfColors.black),
      ),
    );
  }

  pw.Widget _moneyLine(String label, num amount, String currency, {bool bold = false}) =>
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(child: pw.Text(label, style: pw.TextStyle(fontSize: 8, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal))),
          pw.Text('${_money(amount)} $currency', style: pw.TextStyle(fontSize: 8, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ],
      );

  Future<Uint8List> buildDoseLabel(DoseLabelData label) async {
    await FontCache.instance.load();
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          58 * PdfPageFormat.mm,
          40 * PdfPageFormat.mm,
          marginAll: 2 * PdfPageFormat.mm,
        ),
        theme: FontCache.instance.theme,
        build: (context) => pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Container(
            decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.8)),
            padding: const pw.EdgeInsets.all(3),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Center(child: pw.Text(label.pharmacyName, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold))),
                pw.Text('المريض: ${label.patientName}', style: const pw.TextStyle(fontSize: 6)),
                pw.Text('${label.drugName} ${label.strength}', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
                pw.Text(label.doseTextAr, style: const pw.TextStyle(fontSize: 7)),
                pw.Text('تعليمات الأكل: ${label.mealInstruction}', style: const pw.TextStyle(fontSize: 6)),
                pw.Text('الصلاحية: ${label.expiryDate}', style: const pw.TextStyle(fontSize: 6)),
                if (label.keepRefrigerated)
                  pw.Text('يحفظ في الثلاجة (2–8°م)', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.red800)),
              ],
            ),
          ),
        ),
      ),
    );
    return doc.save();
  }

  Future<void> previewReceipt(BuildContext context, ReceiptData receipt, {ThermalPaper paper = ThermalPaper.mm80}) async {
    final bytes = await buildReceipt(receipt, paper: paper);
    await Printing.layoutPdf(name: 'receipt-${receipt.invoiceNumber}.pdf', onLayout: (_) async => bytes);
  }

  Future<void> printReceiptNow(BuildContext context, ReceiptData receipt, {ThermalPaper paper = ThermalPaper.mm80}) async {
    final bytes = await buildReceipt(receipt, paper: paper);
    final printer = await Printing.pickPrinter(context: context);
    if (printer == null) return;
    await Printing.directPrintPdf(printer: printer, onLayout: (_) async => bytes);
  }

  Future<void> printDoseLabelNow(BuildContext context, DoseLabelData label) async {
    final bytes = await buildDoseLabel(label);
    final printer = await Printing.pickPrinter(context: context);
    if (printer == null) return;
    await Printing.directPrintPdf(printer: printer, onLayout: (_) async => bytes);
  }

  String _dateTime(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  String _money(num value) => value.toStringAsFixed(2);
}
