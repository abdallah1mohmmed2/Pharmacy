import 'package:excel/excel.dart';
import 'opening_inventory_service.dart';

class OpeningExcelResult {
  const OpeningExcelResult(this.lines, this.errors);
  final List<OpeningStockLine> lines;
  final List<String> errors;
}

/// Spreadsheet import targets existing branch medicines/warehouses only.
/// Blank prices are intentionally null, allowing automatic price suggestions.
abstract final class OpeningInventoryExcel {
  static const headers = <String>[
    'معرّف الدواء',
    'اسم الدواء',
    'رمز المخزن',
    'عدد الكراتين',
    'الباكتات الإضافية',
    'الحبات الإضافية',
    'باكتات في الكرتون',
    'حبات في الباكت',
    'سعر الكرتون',
    'سعر الباكت',
    'سعر الحبة',
    'تاريخ الانتهاء',
    'رقم التشغيلة',
    'رقم الرف (اختياري)',
    'تاريخ الإدخال',
    'تكلفة الحبة',
    'ملاحظات',
  ];

  static List<int> templateBytes() {
    final excel = Excel.createExcel();
    final sheet = excel['الرصيد الافتتاحي'];
    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());
    final help = excel['إرشادات'];
    for (final description in [
      'أدخل كل تشغيلة أو تاريخ انتهاء في صف منفصل.',
      'معرّف الدواء أو اسمه المطابق تمامًا لما في فرع الصيدلية مطلوب.',
      'رمز المخزن اختياري؛ عند تركه فارغًا يستخدم المخزن المختار في التطبيق.',
      'رقم الرف اختياري. إن كتبته فيجب أن يكون رفًا موجودًا في ذلك المخزن.',
      'يمكن إدخال سعر الكرتون أو الباكت أو الحبة وحده؛ تحسب الأسعار الناقصة.',
      'أي سعر مُدخل يدويًا لا يُستبدل بالحساب الآلي.',
      'تواريخ الانتهاء والإدخال بصيغة YYYY-MM-DD، ولا تدخل كميات سالبة.',
      'يتم التحقق من جميع الصفوف وعرض الأخطاء قبل الترحيل؛ لا يُعدّل الملف إعدادات النظام.',
      'المخزون بالكميات في شاشة المخزون فقط؛ الأسعار والتعبئة تظهر في تفاصيل الدواء.',
    ]) {
      help.appendRow([TextCellValue(description)]);
    }
    excel.delete('Sheet1');
    excel.setDefaultSheet('الرصيد الافتتاحي');
    return excel.save()!;
  }

  static String _plainText(TextSpan value) {
    final own = value.text ?? '';
    return own + (value.children?.map(_plainText).join() ?? '');
  }

  static String _text(CellValue? value) {
    if (value == null) return '';
    if (value is TextCellValue) return _plainText(value.value).trim();
    if (value is IntCellValue) return value.value.toString();
    if (value is DoubleCellValue) return value.value.toString();
    if (value is DateCellValue) {
      return '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    }
    if (value is DateTimeCellValue) {
      return '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    }
    if (value is FormulaCellValue) {
      throw const FormatException('الصيغ الحسابية غير مدعومة؛ استخدم القيمة النهائية');
    }
    throw const FormatException('نوع خلية غير مدعوم');
  }

  static int _integer(String value, String label, {int defaultValue = 0}) {
    if (value.isEmpty) return defaultValue;
    final parsed = int.tryParse(value);
    if (parsed == null || parsed < 0) {
      throw FormatException('عدد غير صالح في $label');
    }
    return parsed;
  }

  static double? _optionalPrice(String value, String label) {
    if (value.isEmpty) return null;
    final parsed = double.tryParse(value);
    if (parsed == null || !parsed.isFinite || parsed < 0) {
      throw FormatException('سعر غير صالح في $label');
    }
    return parsed;
  }

  static OpeningExcelResult parse(
    List<int> bytes, {
    required int defaultWarehouseId,
    required Map<String, int> warehousesByCode,
  }) {
    if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
      throw const FormatException('ملف Excel فارغ أو يتجاوز 10 ميجابايت');
    }
    final workbook = Excel.decodeBytes(bytes);
    final sheet = workbook.tables['الرصيد الافتتاحي'] ??
        workbook.tables.values.firstWhere(
          (s) => s.rows.isNotEmpty,
          orElse: () => throw const FormatException('لا توجد بيانات في ملف Excel'),
        );
    if (sheet.rows.isEmpty) {
      throw const FormatException('ملف Excel لا يحتوي على عناوين');
    }
    final headerCells = sheet.rows.first;
    final columnIndex = <String, int>{};
    for (var i = 0; i < headerCells.length; i++) {
      final title = _text(headerCells[i]?.value);
      if (title.isNotEmpty && columnIndex.containsKey(title)) {
        throw FormatException('عنوان عمود مكرر: $title');
      }
      if (title.isNotEmpty) columnIndex[title] = i;
    }
    for (final name in headers) {
      if (!columnIndex.containsKey(name)) {
        throw FormatException('العمود المطلوب غير موجود: $name');
      }
    }
    if (sheet.rows.length > 5001) {
      throw const FormatException('الحد الأقصى 5000 صف لكل ملف');
    }
    final result = <OpeningStockLine>[];
    final errors = <String>[];
    for (var index = 1; index < sheet.rows.length; index++) {
      final row = sheet.rows[index];
      try {
        String cell(String heading) {
          final col = columnIndex[heading]!;
          return col < row.length ? _text(row[col]?.value) : '';
        }
        if (headers.every((h) => cell(h).isEmpty)) continue;
        final drugIdRaw = cell('معرّف الدواء');
        final drugId = drugIdRaw.isEmpty
            ? null
            : _integer(drugIdRaw, 'معرّف الدواء');
        if (drugId == null && cell('اسم الدواء').isEmpty) {
          throw const FormatException('معرّف الدواء أو الاسم مطلوب');
        }
        final warehouseCode = cell('رمز المخزن');
        final warehouseId = warehouseCode.isEmpty
            ? defaultWarehouseId
            : warehousesByCode[warehouseCode];
        if (warehouseId == null) {
          throw FormatException('رمز المخزن غير موجود: $warehouseCode');
        }
        final prices = OpeningStockPrices(
          carton: _optionalPrice(cell('سعر الكرتون'), 'سعر الكرتون'),
          packet: _optionalPrice(cell('سعر الباكت'), 'سعر الباكت'),
          unit: _optionalPrice(cell('سعر الحبة'), 'سعر الحبة'),
        );
        final packets = _integer(
            cell('باكتات في الكرتون'), 'باكتات في الكرتون');
        final units = _integer(cell('حبات في الباكت'), 'حبات في الباكت');
        if (packets == 0 || units == 0) {
          throw const FormatException('يجب تحديد تعبئة الكرتون والباكت');
        }
        result.add(OpeningStockLine(
          drugId: drugId,
          drugName: cell('اسم الدواء'),
          warehouseId: warehouseId,
          cartons: _integer(cell('عدد الكراتين'), 'عدد الكراتين'),
          packets: _integer(cell('الباكتات الإضافية'), 'الباكتات الإضافية'),
          units: _integer(cell('الحبات الإضافية'), 'الحبات الإضافية'),
          packetsPerCarton: packets,
          unitsPerPacket: units,
          prices: prices,
          batchNo: cell('رقم التشغيلة'),
          expiryDate: cell('تاريخ الانتهاء'),
          effectiveDate: cell('تاريخ الإدخال').isEmpty
              ? null
              : cell('تاريخ الإدخال'),
          shelfCode: cell('رقم الرف (اختياري)').isEmpty
              ? null
              : cell('رقم الرف (اختياري)'),
          unitCost: _optionalPrice(cell('تكلفة الحبة'), 'تكلفة الحبة') ?? 0,
          note: cell('ملاحظات'),
        ));
      } catch (e) {
        errors.add('صف ${index + 1}: $e');
      }
    }
    return OpeningExcelResult(result, errors);
  }
}
