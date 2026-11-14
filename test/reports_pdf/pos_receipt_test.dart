import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_enterprise_pharmacy_erp/reports_pdf/engine/receipt_and_label_builder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final paper in ThermalPaper.values) {
    test('Arabic POS receipt renders on ${paper.name}', () async {
      final receipt = ReceiptData(
        invoiceNumber: 'POS-42',
        dateTime: DateTime(2026, 11, 14),
        customerName: 'عميل اختبار',
        lines: const [
          ReceiptLine(
              name: 'شراب اختبار',
              unit: 'زجاجة',
              quantity: 2,
              unitPrice: 300,
              total: 600),
          ReceiptLine(
              name: 'كبسولات اختبار',
              unit: 'شريط',
              quantity: 1,
              unitPrice: 400,
              total: 400),
        ],
        subtotal: 1000,
        discount: 100,
        rounding: 0,
        netTotal: 900,
        paid: 400,
        paymentMethod: 'نقدي + آجل',
        remainingAfterInvoice: 500,
      );
      final bytes = await const ReceiptAndLabelBuilder()
          .buildReceipt(receipt, paper: paper);
      expect(utf8.decode(bytes.take(5).toList()), '%PDF-');
      expect(bytes.length, greaterThan(1000));
    });
  }
}
