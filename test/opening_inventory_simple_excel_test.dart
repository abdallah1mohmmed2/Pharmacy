import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/opening_inventory_excel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('six-column template contains exactly the requested headers', () {
    final workbook =
        Excel.decodeBytes(OpeningInventoryExcel.simpleTemplateBytes());
    final sheet = workbook['الرصيد الافتتاحي'];
    final names = sheet.rows.first
        .map((cell) => (cell?.value as TextCellValue).value.text)
        .toList();
    expect(names, [
      'اسم العلاج',
      'عدد الباكتات',
      'عدد الأشرطة',
      'سعر الباكت',
      'سعر العلاج',
      'الأرصدة الافتتاحية'
    ]);
    expect(names, hasLength(6));
  });

  test('each simple row posts to its own medicine and multiplies stock units',
      () {
    final workbook =
        Excel.decodeBytes(OpeningInventoryExcel.simpleTemplateBytes());
    workbook['الرصيد الافتتاحي'].appendRow([
      TextCellValue('دواء أول'),
      IntCellValue(5),
      IntCellValue(10),
      DoubleCellValue(120),
      DoubleCellValue(12),
      IntCellValue(3),
    ]);
    workbook['الرصيد الافتتاحي'].appendRow([
      TextCellValue('دواء ثان'),
      IntCellValue(2),
      IntCellValue(7),
      DoubleCellValue(140),
      DoubleCellValue(20),
      IntCellValue(4),
    ]);
    final parsed = OpeningInventoryExcel.parse(
      workbook.save()!,
      defaultWarehouseId: 4,
      warehousesByCode: const {},
      defaultExpiryDate: '2028-12-31',
    );
    expect(parsed.errors, isEmpty);
    expect(parsed.lines, hasLength(2));
    expect(parsed.lines[0].drugName, 'دواء أول');
    expect(parsed.lines[0].quantityUnits, 150);
    expect(parsed.lines[0].prices.packet, 120);
    expect(parsed.lines[0].prices.unit, 12);
    expect(parsed.lines[0].expiryDate, '2028-12-31');
    expect(parsed.lines[1].drugName, 'دواء ثان');
    expect(parsed.lines[1].quantityUnits, 56);
    expect(parsed.lines[1].warehouseId, 4);
    expect(parsed.lines[1].prices.packet, 140);
    expect(parsed.lines[1].prices.unit, 20);
  });

  test('simple template never invents expiry dates', () {
    final workbook =
        Excel.decodeBytes(OpeningInventoryExcel.simpleTemplateBytes());
    workbook['الرصيد الافتتاحي'].appendRow([
      TextCellValue('دواء'),
      IntCellValue(1),
      IntCellValue(1),
      IntCellValue(10),
      IntCellValue(10),
      IntCellValue(1),
    ]);
    expect(
        () => OpeningInventoryExcel.parse(
              workbook.save()!,
              defaultWarehouseId: 1,
              warehousesByCode: const {},
            ),
        throwsFormatException);
  });

  test('invalid row blocks import without inventing quantities', () {
    final workbook =
        Excel.decodeBytes(OpeningInventoryExcel.simpleTemplateBytes());
    workbook['الرصيد الافتتاحي'].appendRow([
      TextCellValue('دواء'),
      IntCellValue(0),
      IntCellValue(10),
      IntCellValue(10),
      IntCellValue(1),
      IntCellValue(5),
    ]);
    final parsed = OpeningInventoryExcel.parse(
      workbook.save()!,
      defaultWarehouseId: 1,
      warehousesByCode: const {},
      defaultExpiryDate: '2028-12-31',
    );
    expect(parsed.lines, isEmpty);
    expect(parsed.errors, hasLength(1));
  });
}
