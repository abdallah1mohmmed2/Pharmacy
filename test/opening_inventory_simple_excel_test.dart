import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/opening_inventory_excel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('opening-stock template has exactly four requested columns', () {
    final book = Excel.decodeBytes(OpeningInventoryExcel.simpleTemplateBytes());
    final columns = book['الرصيد الافتتاحي']
        .rows
        .first
        .map((cell) => (cell?.value as TextCellValue).value.text)
        .toList();
    expect(columns, [
      'اسم العلاج',
      'عدد الباكتات',
      'عدد الأشرطة داخل الباكت',
      'سعر الباكت',
    ]);
    expect(columns.length, 4);
  });

  test('12 packs x 3 strips is stock, not packaging count of 12 strips', () {
    final book = Excel.decodeBytes(OpeningInventoryExcel.simpleTemplateBytes());
    book['الرصيد الافتتاحي'].appendRow([
      TextCellValue('باراسيتامول 500'),
      IntCellValue(12),
      IntCellValue(3),
      DoubleCellValue(1000),
    ]);
    final parsed = OpeningInventoryExcel.parse(
      book.save()!,
      defaultWarehouseId: 4,
      warehousesByCode: const {},
      defaultExpiryDate: '2028-12-31',
    );
    expect(parsed.errors, isEmpty);
    expect(parsed.lines, hasLength(1));
    final stock = parsed.lines.single;
    expect(stock.drugName, 'باراسيتامول 500');
    expect(stock.cartons, 12);
    expect(stock.packetsPerCarton, 3);
    expect(stock.prices.carton, 1000);
    expect(stock.prices.packet, isNull);
    expect(stock.resolveUnitsFromCatalog, isTrue);
    // Until actual tablets-per-strip are loaded from the drug card the
    // temporary 36 MUST NOT be posted as stock units.
    expect(stock.quantityUnits, 36);
    final resolved = stock.withUnitsPerPacket(10);
    expect(resolved.resolveUnitsFromCatalog, isFalse);
    expect(resolved.quantityUnits, 360);
    expect(resolved.prices.carton, 1000);
  });

  test('selected medicines are separate, name-only rows are not stock', () {
    final book = Excel.decodeBytes(OpeningInventoryExcel.simpleTemplateBytes());
    final sheet = book['الرصيد الافتتاحي'];
    sheet.appendRow([TextCellValue('اسم للبحث'), null, null, null]);
    sheet.appendRow([
      TextCellValue('دواء أول'),
      IntCellValue(5),
      IntCellValue(2),
      DoubleCellValue(200),
    ]);
    sheet.appendRow([
      TextCellValue('دواء ثان'),
      IntCellValue(7),
      IntCellValue(4),
      DoubleCellValue(500),
    ]);
    final parsed = OpeningInventoryExcel.parse(
      book.save()!,
      defaultWarehouseId: 2,
      warehousesByCode: const {},
      defaultExpiryDate: '2028-12-31',
    );
    expect(parsed.errors, isEmpty);
    expect(parsed.lines.map((r) => r.drugName), ['دواء أول', 'دواء ثان']);
    expect(parsed.lines.map((r) => r.cartons), [5, 7]);
    expect(parsed.lines.map((r) => r.packetsPerCarton), [2, 4]);
  });

  test('expiry date must be selected in app, never fabricated', () {
    final book = Excel.decodeBytes(OpeningInventoryExcel.simpleTemplateBytes());
    book['الرصيد الافتتاحي'].appendRow([
      TextCellValue('دواء'),
      IntCellValue(2),
      IntCellValue(4),
      DoubleCellValue(600),
    ]);
    expect(
      () => OpeningInventoryExcel.parse(
        book.save()!,
        defaultWarehouseId: 1,
        warehousesByCode: const {},
      ),
      throwsFormatException,
    );
  });

  test('zero pack count, missing strips or missing price blocks posting', () {
    final book = Excel.decodeBytes(OpeningInventoryExcel.simpleTemplateBytes());
    final sheet = book['الرصيد الافتتاحي'];
    sheet.appendRow([
      TextCellValue('صنف بلا رصيد'),
      IntCellValue(0),
      IntCellValue(3),
      DoubleCellValue(100),
    ]);
    sheet.appendRow([
      TextCellValue('صنف بلا تعبئة'),
      IntCellValue(4),
      IntCellValue(0),
      DoubleCellValue(100),
    ]);
    sheet.appendRow([
      TextCellValue('صنف بلا سعر'),
      IntCellValue(4),
      IntCellValue(3),
      null,
    ]);
    final parsed = OpeningInventoryExcel.parse(
      book.save()!,
      defaultWarehouseId: 1,
      warehousesByCode: const {},
      defaultExpiryDate: '2028-12-31',
    );
    expect(parsed.lines, isEmpty);
    expect(parsed.errors, hasLength(3));
  });

  test('an old six-column workbook is never silently misinterpreted', () {
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
    sheet.appendRow([
      TextCellValue('دواء'),
      IntCellValue(5),
      IntCellValue(3),
      DoubleCellValue(500),
      DoubleCellValue(50),
      IntCellValue(20),
    ]);
    expect(
      () => OpeningInventoryExcel.parse(
        book.save()!,
        defaultWarehouseId: 1,
        warehousesByCode: const {},
        defaultExpiryDate: '2028-12-31',
      ),
      throwsFormatException,
    );
  });
}
