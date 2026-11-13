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

  // Optional form input matches the existing drugs.dosage_form enum.
  // Arabic is for pharmacists; stored codes remain identical to the app.
  static const dosageForms = <String, String>{
    'أقراص': 'TABLET',
    'كبسولات': 'CAPSULE',
    'شراب': 'SYRUP',
    'معلق': 'SUSPENSION',
    'قطرات': 'DROPS',
    'حقن': 'INJECTION',
    'كريم': 'CREAM',
    'مرهم': 'OINTMENT',
    'بخاخ': 'INHALER',
    'تحاميل': 'SUPPOSITORY',
    'أكياس': 'SACHET',
    'أخرى': 'OTHER',
  };

  static String? _dosageForm(String text) {
    final raw = text.trim();
    if (raw.isEmpty) return null;
    final asCode = raw.toUpperCase();
    if (dosageForms.values.contains(asCode)) return asCode;
    final code = dosageForms[raw];
    if (code == null) {
      throw FormatException('نوع الدواء غير معتمد: $raw');
    }
    return code;
  }

  static List<int> templateBytes() {
    final excel = Excel.createExcel();
    final sheet = excel['الرصيد الافتتاحي'];
    // Added after the legacy 17-column layout for backwards compatibility.
    sheet.appendRow([
      ...headers.map((h) => TextCellValue(h)),
      TextCellValue('نوع الدواء'),
      TextCellValue('إدخال تكلفة الكرتون'),
      TextCellValue('إدخال تكلفة الباكت'),
      TextCellValue('إدخال تكلفة الحبة'),
    ]);
    final help = excel['إرشادات'];
    for (final description in [
      'أدخل كل تشغيلة أو تاريخ انتهاء في صف منفصل.',
      'معرّف الدواء أو اسمه المطابق تمامًا لما في فرع الصيدلية مطلوب.',
      'رمز المخزن اختياري؛ عند تركه فارغًا يستخدم المخزن المختار في التطبيق.',
      'رقم الرف اختياري. إن كتبته فيجب أن يكون رفًا موجودًا في ذلك المخزن.',
      'نوع الدواء اختياري؛ اختر الشكل الصيدلاني بالعربية من القائمة المعتمدة.',
      'إذا كان نوع الدواء معروفًا ويختلف عن المسجل في الفرع، يتوقف الاستيراد لمراجعة الصنف.',
      'يمكن إدخال سعر الكرتون أو الباكت أو الحبة وحده؛ تحسب الأسعار الناقصة.',
      'أدخل تكلفة شراء واحدة فقط: الكرتون أو الباكت أو الحبة، لحساب تكلفة الوحدة دون تقريب محاسبي.',
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
      throw const FormatException(
          'الصيغ الحسابية غير مدعومة؛ استخدم القيمة النهائية');
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
          orElse: () =>
              throw const FormatException('لا توجد بيانات في ملف Excel'),
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
    // Optional worksheet source-price columns. They are independent input
    // cells, while the three standard sell-price columns may hold spreadsheet
    // formulas. We never trust a formula cache for financial import values.
    const sourcePrices = <String>[
      'إدخال سعر الكرتون',
      'إدخال سعر الباكت',
      'إدخال سعر الحبة',
    ];
    final sourceColumnCount =
        sourcePrices.where(columnIndex.containsKey).length;
    if (sourceColumnCount != 0 && sourceColumnCount != sourcePrices.length) {
      throw const FormatException(
          'يجب أن تكون أعمدة إدخال الأسعار الثلاثة موجودة معاً');
    }
    final usesSourcePrices = sourceColumnCount == sourcePrices.length;
    // Cost source inputs are financial acquisition costs, not selling prices.
    // Their calculated displays may be formulas; only raw inputs are trusted.
    const sourceCosts = <String>[
      'إدخال تكلفة الكرتون',
      'إدخال تكلفة الباكت',
      'إدخال تكلفة الحبة',
    ];
    final sourceCostCount = sourceCosts.where(columnIndex.containsKey).length;
    if (sourceCostCount != 0 && sourceCostCount != sourceCosts.length) {
      throw const FormatException(
          'يجب أن تكون أعمدة إدخال التكاليف الثلاثة موجودة معاً');
    }
    final usesSourceCosts = sourceCostCount == sourceCosts.length;
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
          if (col >= row.length) return '';
          final value = row[col]?.value;
          // Formula cells in the three display-only prices are safe to
          // ignore only when all three independent input columns are present.
          // All other formulas are still rejected by _text.
          if (usesSourcePrices &&
              value is FormulaCellValue &&
              (heading == 'سعر الكرتون' ||
                  heading == 'سعر الباكت' ||
                  heading == 'سعر الحبة')) {
            return '';
          }
          if (usesSourceCosts &&
              value is FormulaCellValue &&
              heading == 'تكلفة الحبة') {
            return '';
          }
          return _text(value);
        }

        if (headers.every((h) => cell(h).isEmpty)) continue;
        final drugIdRaw = cell('معرّف الدواء');
        final drugId =
            drugIdRaw.isEmpty ? null : _integer(drugIdRaw, 'معرّف الدواء');
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
          carton: _optionalPrice(
              cell(usesSourcePrices ? 'إدخال سعر الكرتون' : 'سعر الكرتون'),
              'سعر الكرتون'),
          packet: _optionalPrice(
              cell(usesSourcePrices ? 'إدخال سعر الباكت' : 'سعر الباكت'),
              'سعر الباكت'),
          unit: _optionalPrice(
              cell(usesSourcePrices ? 'إدخال سعر الحبة' : 'سعر الحبة'),
              'سعر الحبة'),
        );
        final packets =
            _integer(cell('باكتات في الكرتون'), 'باكتات في الكرتون');
        final units = _integer(cell('حبات في الباكت'), 'حبات في الباكت');
        if (packets == 0 || units == 0) {
          throw const FormatException('يجب تحديد تعبئة الكرتون والباكت');
        }
        final legacyCostUnit =
            _optionalPrice(cell('تكلفة الحبة'), 'تكلفة الحبة');
        double unitCost = legacyCostUnit ?? 0;
        if (usesSourceCosts) {
          final cartonCost = _optionalPrice(
              cell('إدخال تكلفة الكرتون'), 'إدخال تكلفة الكرتون');
          final packetCost =
              _optionalPrice(cell('إدخال تكلفة الباكت'), 'إدخال تكلفة الباكت');
          final unitCostInput =
              _optionalPrice(cell('إدخال تكلفة الحبة'), 'إدخال تكلفة الحبة');
          final sources = [cartonCost, packetCost, unitCostInput]
              .where((price) => price != null)
              .length;
          if (sources > 1 || (sources > 0 && legacyCostUnit != null)) {
            throw const FormatException(
                'أدخل تكلفة شراء واحدة فقط: الكرتون أو الباكت أو الحبة');
          }
          unitCost = unitCostInput ??
              (packetCost != null ? packetCost / units : null) ??
              (cartonCost != null ? cartonCost / (packets * units) : null) ??
              unitCost;
        }
        result.add(OpeningStockLine(
          drugId: drugId,
          drugName: cell('اسم الدواء'),
          dosageForm: columnIndex.containsKey('نوع الدواء')
              ? _dosageForm(cell('نوع الدواء'))
              : null,
          warehouseId: warehouseId,
          cartons: _integer(cell('عدد الكراتين'), 'عدد الكراتين'),
          packets: _integer(cell('الباكتات الإضافية'), 'الباكتات الإضافية'),
          units: _integer(cell('الحبات الإضافية'), 'الحبات الإضافية'),
          packetsPerCarton: packets,
          unitsPerPacket: units,
          prices: prices,
          batchNo: cell('رقم التشغيلة'),
          expiryDate: cell('تاريخ الانتهاء'),
          effectiveDate:
              cell('تاريخ الإدخال').isEmpty ? null : cell('تاريخ الإدخال'),
          shelfCode: cell('رقم الرف (اختياري)').isEmpty
              ? null
              : cell('رقم الرف (اختياري)'),
          unitCost: unitCost,
          note: cell('ملاحظات'),
        ));
      } catch (e) {
        errors.add('صف ${index + 1}: $e');
      }
    }
    return OpeningExcelResult(result, errors);
  }
}
