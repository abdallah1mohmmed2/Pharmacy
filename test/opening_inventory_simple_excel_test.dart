import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/opening_inventory_excel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('new opening inventory template has five columns including expiry', () {
    final sheet = Excel.decodeBytes(OpeningInventoryExcel.simpleTemplateBytes())
        ['الرصيد الافتتاحي'];
    final headers = sheet.rows.first
        .map((cell) => (cell?.value as TextCellValue).value.text)
        .toList();
    expect(headers, [
      'اسم العلاج',
      'عدد الباكتات',
      'عدد الأشرطة داخل الباكت',
      'سعر الباكت',
      'تاريخ الانتهاء'
    ]);
    expect(headers, hasLength(5));
  });

  test('expiry is read from each row, not one global default', () {
    final book = Excel.decodeBytes(OpeningInventoryExcel.simpleTemplateBytes());
    final sheet = book['الرصيد الافتتاحي'];
    sheet.appendRow([
      TextCellValue('باراسيتامول 500'),
      IntCellValue(12),
      IntCellValue(3),
      DoubleCellValue(1000),
      TextCellValue('2028-12-31'),
    ]);
    sheet.appendRow([
      TextCellValue('باراسيتامول 500'),
      IntCellValue(2),
      IntCellValue(3),
      DoubleCellValue(1000),
      TextCellValue('2029-06-30'),
    ]);
    final result = OpeningInventoryExcel.parse(book.save()!,
        defaultWarehouseId: 4, warehousesByCode: const {});
    expect(result.errors, isEmpty);
    expect(result.lines, hasLength(2));
    expect(result.lines.map((line) => line.expiryDate),
        ['2028-12-31', '2029-06-30']);
    expect(result.lines.map((line) => line.cartons), [12, 2]);
    expect(result.lines.first.packetsPerCarton, 3);
    expect(result.lines.first.prices.carton, 1000);
    expect(result.lines.first.resolveUnitsFromCatalog, isTrue);
    expect(result.lines.first.withUnitsPerPacket(10).quantityUnits, 360);
  });

  test('four-column files still use expiry selected in the app', () {
    final book = Excel.createExcel();
    final sheet = book['الرصيد الافتتاحي'];
    sheet.appendRow([
      TextCellValue('اسم العلاج'),
      TextCellValue('عدد الباكتات'),
      TextCellValue('عدد الأشرطة داخل الباكت'),
      TextCellValue('سعر الباكت'),
    ]);
    sheet.appendRow([
      TextCellValue('دواء قديم'),
      IntCellValue(5),
      IntCellValue(2),
      DoubleCellValue(200),
    ]);
    final bytes = book.save()!;
    expect(
      () => OpeningInventoryExcel.parse(bytes,
          defaultWarehouseId: 1, warehousesByCode: const {}),
      throwsFormatException,
    );
    final withExpiry = OpeningInventoryExcel.parse(bytes,
        defaultWarehouseId: 1,
        warehousesByCode: const {},
        defaultExpiryDate: '2028-10-31');
    expect(withExpiry.errors, isEmpty);
    expect(withExpiry.lines.single.expiryDate, '2028-10-31');
  });

  test('blank and impossible expiry dates reject only affected rows', () {
    final book = Excel.decodeBytes(OpeningInventoryExcel.simpleTemplateBytes());
    final sheet = book['الرصيد الافتتاحي'];
    sheet.appendRow([
      TextCellValue('بلا صلاحية'),
      IntCellValue(1),
      IntCellValue(2),
      DoubleCellValue(100),
      null,
    ]);
    sheet.appendRow([
      TextCellValue('تاريخ غير صحيح'),
      IntCellValue(1),
      IntCellValue(2),
      DoubleCellValue(100),
      TextCellValue('2028-02-30'),
    ]);
    sheet.appendRow([
      TextCellValue('صنف صحيح'),
      IntCellValue(1),
      IntCellValue(2),
      DoubleCellValue(100),
      TextCellValue('2028-02-29'),
    ]);
    final result = OpeningInventoryExcel.parse(book.save()!,
        defaultWarehouseId: 1, warehousesByCode: const {});
    expect(result.lines, hasLength(1));
    expect(result.lines.single.drugName, 'صنف صحيح');
    expect(result.errors, hasLength(2));
    expect(result.errors.every((e) => e.contains('تاريخ')), isTrue);
  });

  test('name-only catalog rows are ignored; quantities still required', () {
    final book = Excel.decodeBytes(OpeningInventoryExcel.simpleTemplateBytes());
    final sheet = book['الرصيد الافتتاحي'];
    sheet.appendRow([TextCellValue('مرجع فقط'), null, null, null, null]);
    sheet.appendRow([
      TextCellValue('لا يوجد رصيد'),
      IntCellValue(0),
      IntCellValue(3),
      DoubleCellValue(100),
      TextCellValue('2029-01-01'),
    ]);
    sheet.appendRow([
      TextCellValue('صنف بكمية'),
      IntCellValue(3),
      IntCellValue(2),
      DoubleCellValue(180),
      TextCellValue('2029-01-01'),
    ]);
    final result = OpeningInventoryExcel.parse(book.save()!,
        defaultWarehouseId: 2, warehousesByCode: const {});
    expect(result.errors, hasLength(1));
    expect(result.lines.map((r) => r.drugName), ['صنف بكمية']);
  });

  test('old six-column workbook is never silently misinterpreted', () {
    final book = Excel.createExcel();
    final sheet = book['الرصيد الافتتاحي'];
    sheet.appendRow([
      TextCellValue('اسم العلاج'),
      TextCellValue('عدد الباكتات'),
      TextCellValue('عدد الأشرطة'),
      TextCellValue('سعر الباكت'),
      TextCellValue('سعر العلاج'),
      TextCellValue('الأرصدة الافتتاحية'),
    ]);
    expect(
      () => OpeningInventoryExcel.parse(book.save()!,
          defaultWarehouseId: 1,
          warehousesByCode: const {},
          defaultExpiryDate: '2028-12-31'),
      throwsFormatException,
    );
  });
}
