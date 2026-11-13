import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../data/models/drug_model.dart';
import '../../data/services/opening_inventory_excel.dart';
import '../../data/services/opening_inventory_service.dart';
import '../../providers/inventory_and_purchase_provider.dart';
import '../../providers/pos_and_drugs_provider.dart';
import '../drugs/s08_s09_drug_encyclopedia_screen.dart';

class OpeningInventoryScreen extends StatefulWidget {
  const OpeningInventoryScreen({super.key});

  @override
  State<OpeningInventoryScreen> createState() => _OpeningInventoryScreenState();
}

class _OpeningInventoryScreenState extends State<OpeningInventoryScreen> {
  final service = OpeningInventoryService();
  final cartons = TextEditingController(text: '0');
  final packets = TextEditingController(text: '0');
  final units = TextEditingController(text: '0');
  final packetsPerCarton = TextEditingController(text: '1');
  final unitsPerPacket = TextEditingController(text: '1');
  final cartonPrice = TextEditingController();
  final packetPrice = TextEditingController();
  final unitPrice = TextEditingController();
  final batchNo = TextEditingController();
  final costUnit = TextEditingController();
  final notes = TextEditingController();

  final Set<String> manualPriceFields = {};
  List<OpeningStockLine> lines = [];
  List<String> issues = [];
  bool busy = false;
  bool computingPrices = false;
  int? drugId;
  int? warehouseId;
  String? shelfCode;
  String? sourceHash;
  String? sourceName;
  DateTime effectiveDate = DateTime.now();
  DateTime? expiryDate;
  late String operationUuid = _operationId();

  static String _operationId() {
    final random = Random.secure();
    final b = List<int>.generate(16, (_) => random.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  static String _date(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await context.read<InventoryAndPurchaseProvider>().loadAll();
        if (!mounted) return;
        await context.read<PosAndDrugsProvider>().loadDrugs();
      } catch (e) {
        _message(e.toString());
      }
    });
  }

  @override
  void dispose() {
    for (final field in [
      cartons,
      packets,
      units,
      packetsPerCarton,
      unitsPerPacket,
      cartonPrice,
      packetPrice,
      unitPrice,
      batchNo,
      costUnit,
      notes,
    ]) {
      field.dispose();
    }
    super.dispose();
  }

  void _message(String value) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));
    }
  }

  TextEditingController _priceController(String name) => switch (name) {
        'carton' => cartonPrice,
        'packet' => packetPrice,
        _ => unitPrice,
      };

  void _priceChanged(String field, String text) {
    if (computingPrices) return;
    if (text.trim().isEmpty) {
      manualPriceFields.remove(field);
    } else {
      manualPriceFields.add(field);
    }
    final source = _priceController(field);
    final amount = double.tryParse(source.text.trim());
    final ppc = int.tryParse(packetsPerCarton.text.trim()) ?? 0;
    final upp = int.tryParse(unitsPerPacket.text.trim()) ?? 0;
    if (amount == null || amount < 0 || ppc <= 0 || upp <= 0) return;
    try {
      final suggested = OpeningStockPrices(
        carton: field == 'carton' ? amount : null,
        packet: field == 'packet' ? amount : null,
        unit: field == 'unit' ? amount : null,
      ).fillMissing(ppc, upp);
      computingPrices = true;
      for (final entry in {
        'carton': suggested.carton!,
        'packet': suggested.packet!,
        'unit': suggested.unit!,
      }.entries) {
        if (entry.key != field && !manualPriceFields.contains(entry.key)) {
          _priceController(entry.key).text = entry.value.toStringAsFixed(2);
        }
      }
    } finally {
      computingPrices = false;
    }
  }

  void _recalculateFromPrimaryPrice() {
    for (final name in ['carton', 'packet', 'unit']) {
      if (manualPriceFields.contains(name)) {
        _priceChanged(name, _priceController(name).text);
        return;
      }
    }
  }

  Widget _numberField(String title, TextEditingController controller,
      {bool integer = true, ValueChanged<String>? onChanged}) {
    return SizedBox(
      width: 190,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.numberWithOptions(decimal: !integer),
        inputFormatters:
            integer ? [FilteringTextInputFormatter.digitsOnly] : null,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: title,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  void _selectDrug(DrugModel drug) {
    setState(() => drugId = drug.id);
    packetsPerCarton.text = (drug.stripsPerPack ?? 1).toString();
    unitsPerPacket.text = (drug.unitsPerStrip ?? 1).toString();
    for (final controller in [cartonPrice, packetPrice, unitPrice]) {
      controller.clear();
    }
    manualPriceFields.clear();
  }

  Future<void> _createMedicine() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('إضافة دواء في الموسوعة')),
        body: const S08S09DrugEncyclopediaScreen(),
      ),
    ));
    if (!mounted) return;
    await context.read<PosAndDrugsProvider>().loadDrugs();
    if (mounted) _message('اختر الدواء الجديد من البحث أعلاه');
  }

  Future<void> _pickDate({required bool expiry}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: expiry
          ? (expiryDate ?? now.add(const Duration(days: 365)))
          : effectiveDate,
      firstDate: DateTime(2000),
      lastDate: expiry ? DateTime(2100) : now,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (expiry) {
        expiryDate = picked;
      } else {
        effectiveDate = picked;
      }
    });
  }

  OpeningStockLine _manualLine() {
    if (drugId == null) throw StateError('اختر الدواء من القائمة أولًا');
    if (warehouseId == null) throw StateError('حدد المخزن');
    if (expiryDate == null) throw StateError('تاريخ انتهاء الصلاحية مطلوب');
    int count(TextEditingController c, String name) {
      final value = int.tryParse(c.text.trim());
      if (value == null || value < 0) throw StateError('عدد غير صحيح: $name');
      return value;
    }

    double? price(TextEditingController c) {
      if (c.text.trim().isEmpty) return null;
      final value = double.tryParse(c.text.trim());
      if (value == null || value < 0 || !value.isFinite) {
        throw StateError('سعر غير صالح');
      }
      return value;
    }

    return OpeningStockLine(
      drugId: drugId,
      warehouseId: warehouseId!,
      cartons: count(cartons, 'الكراتين'),
      packets: count(packets, 'الباكتات'),
      units: count(units, 'الحبات'),
      packetsPerCarton: count(packetsPerCarton, 'الباكتات في الكرتون'),
      unitsPerPacket: count(unitsPerPacket, 'الحبات في الباكت'),
      prices: OpeningStockPrices(
        carton: price(cartonPrice),
        packet: price(packetPrice),
        unit: price(unitPrice),
      ),
      batchNo: batchNo.text.trim(),
      expiryDate: _date(expiryDate!),
      effectiveDate: _date(effectiveDate),
      shelfCode: shelfCode,
      unitCost: price(costUnit) ?? 0,
      note: notes.text.trim(),
    );
  }

  Future<void> _addManual() async {
    try {
      final line = _manualLine();
      final p = context.read<InventoryAndPurchaseProvider>();
      final result = await service.preview(
        branchId: p.branchId,
        effectiveDate: _date(effectiveDate),
        lines: [line],
      );
      if (!result.isValid) {
        _message(result.errors.join('؛ '));
        return;
      }
      setState(() {
        // Excel imports form their own operation. Replacing an Excel preview
        // with a manual draft avoids claiming its file hash for different data.
        if (sourceHash != null) {
          sourceHash = null;
          sourceName = null;
          lines = [];
          issues = [];
          operationUuid = _operationId();
        }
        lines.add(line);
        batchNo.clear();
        cartons.text = '0';
        packets.text = '0';
        units.text = '0';
        expiryDate = null;
        shelfCode = null;
      });
    } catch (e) {
      _message(e.toString());
    }
  }

  Future<void> _loadExcel() async {
    if (busy) return;
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    setState(() => busy = true);
    try {
      final file = picked.files.single;
      if (file.size > 10 * 1024 * 1024) {
        throw const FormatException('الملف أكبر من 10 ميجابايت');
      }
      final bytes = file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null) throw StateError('تعذرت قراءة ملف Excel');
      if (!mounted) return;
      final inventory = context.read<InventoryAndPurchaseProvider>();
      if (inventory.warehouses.isEmpty)
        throw StateError('لا يوجد مخزن في الفرع');
      final fallbackId = warehouseId ?? inventory.warehouses.first.id;
      final parsed = OpeningInventoryExcel.parse(
        bytes,
        defaultWarehouseId: fallbackId,
        warehousesByCode: {
          for (final w in inventory.warehouses) w.code: w.id,
        },
        defaultExpiryDate: expiryDate == null ? null : _date(expiryDate!),
      );
      final validation = await service.preview(
        branchId: inventory.branchId,
        effectiveDate: _date(effectiveDate),
        lines: parsed.lines,
      );
      if (!mounted) return;
      setState(() {
        lines = parsed.lines;
        issues = [...parsed.errors, ...validation.errors];
        sourceHash = sha256.convert(bytes).toString();
        sourceName = file.name;
        operationUuid = _operationId();
      });
      _message(issues.isEmpty
          ? 'تمت معاينة ${lines.length} صفًا بنجاح، ولم يُرحّل أي رصيد بعد'
          : 'يوجد ${issues.length} خطأ؛ صحح الملف وأعد اختياره');
    } catch (e) {
      _message(e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _saveTemplate() async {
    try {
      final data =
          Uint8List.fromList(OpeningInventoryExcel.simpleTemplateBytes());
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'حفظ نموذج الأرصدة الافتتاحية',
        fileName: 'pharmacy_opening_stock_5_columns_with_expiry.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        bytes: data,
      );
      if (path != null && !Platform.isAndroid && !Platform.isIOS) {
        await File(path).writeAsBytes(data);
      }
      if (path != null) _message('تم اختيار مكان حفظ نموذج Excel');
    } catch (e) {
      _message('تعذر حفظ القالب: $e');
    }
  }

  Future<void> _post() async {
    if (busy || lines.isEmpty || issues.isNotEmpty) return;
    final p = context.read<InventoryAndPurchaseProvider>();
    final preview = await service.preview(
      branchId: p.branchId,
      effectiveDate: _date(effectiveDate),
      lines: lines,
    );
    if (!mounted) return;
    if (!preview.isValid) {
      setState(() => issues = preview.errors);
      _message('توجد أخطاء؛ لم يُحفظ أي رصيد');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('اعتماد الأرصدة الافتتاحية؟'),
        content: Text(
          'سيُضاف ${lines.length} صف بإجمالي ${preview.totalUnits} وحدة مخزنية إلى '
          'المخزون الحالي، وتُحفظ حركة لكل تشغيلة. '
          'يتحدد تاريخ الانتهاء لكل صف من عمود Excel، ويُسجّل لكل تشغيلة على حدة. '
          'القالب لا يحتوي على تكلفة الشراء؛ ستُسجل تكلفة الوحدات الجديدة بصفر '
          'وقد تتأثر تقارير الأرباح حتى تُراجع التكاليف. '
          'لا يمكن إلغاء العملية بحذف الملف. تأكد من عدم إدخالها سابقًا.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('رجوع')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('اعتماد الترحيل')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => busy = true);
    try {
      final id = await service.post(
        branchId: p.branchId,
        operationUuid: operationUuid,
        effectiveDate: _date(effectiveDate),
        lines: List.of(lines),
        sourceHash: sourceHash,
        sourceName: sourceName,
      );
      if (!mounted) return;
      await context.read<InventoryAndPurchaseProvider>().loadAll();
      if (!mounted) return;
      await context.read<PosAndDrugsProvider>().loadDrugs();
      if (!mounted) return;
      setState(() {
        lines = [];
        issues = [];
        sourceHash = null;
        sourceName = null;
        operationUuid = _operationId();
      });
      _message('تم اعتماد الرصيد الافتتاحي، رقم العملية: $id');
    } catch (e) {
      _message('تعذر الترحيل، ولم تُقبل عملية جزئية: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryAndPurchaseProvider>();
    final warehouses = inventory.warehouses;
    final activeWarehouseId = warehouses.any((w) => w.id == warehouseId)
        ? warehouseId
        : (warehouses.isEmpty ? null : warehouses.first.id);
    if (warehouseId != activeWarehouseId) warehouseId = activeWarehouseId;
    final shelves = inventory.shelves
        .where((s) => s.warehouseId == activeWarehouseId)
        .toList();
    final selectedShelf =
        shelves.any((s) => s.code == shelfCode) ? shelfCode : null;
    if (shelfCode != selectedShelf) shelfCode = selectedShelf;

    final dateLabel = _date(effectiveDate);
    final usesCompactExcel = lines.any((l) => l.resolveUnitsFromCatalog);
    final unitsTotal = lines.fold<int>(0, (sum, l) => sum + l.quantityUnits);
    final packsTotal = lines.fold<int>(0, (sum, l) => sum + l.cartons);
    return Scaffold(
      appBar: AppBar(title: const Text('إدخال البضاعة — الرصيد الافتتاحي')),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          const Text(
              'تُضاف البضاعة الموجودة فعلًا في الصيدلية، دون تغيير إعدادات النظام أو مسار البيانات.',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                    onPressed: busy ? null : _saveTemplate,
                    icon: const Icon(Icons.file_download_outlined),
                    label: const Text('تنزيل نموذج Excel')),
                OutlinedButton.icon(
                    onPressed: busy ? null : _loadExcel,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('استيراد ملف Excel')),
                OutlinedButton.icon(
                    onPressed: busy ? null : _createMedicine,
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة دواء جديد للموسوعة')),
              ]),
          const SizedBox(height: 8),
          const Text(
            'جميع الصفوف في Excel أرصدة افتتاحية. الأعمدة الخمسة: اسم العلاج، '
            'عدد الباكتات الموجودة، عدد الأشرطة في الباكت، سعر الباكت، وتاريخ الانتهاء لكل صف (YYYY-MM-DD). '
            'يمكن إدخال الصنف نفسه في صفوف متعددة عند اختلاف تواريخ الصلاحية. '
            'يؤخذ عدد الحبات في الشريط من بطاقة الدواء، ولا يُخمّن. '
            'الأدوية غير الموجودة تحتاج إلى بطاقة دواء مكتملة التعبئة قبل الترحيل.',
          ),
          const SizedBox(height: 16),
          Text('الإدخال اليدوي', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Autocomplete<DrugModel>(
            displayStringForOption: (d) =>
                '${d.tradeNameAr} • ${d.strengthText} [${d.internalCode}]',
            optionsBuilder: (value) async {
              final term = value.text.trim();
              if (term.length < 2) return const <DrugModel>[];
              return context.read<PosAndDrugsProvider>().searchPurchaseDrugs(
                    term,
                    branchId: inventory.branchId,
                    limit: 30,
                  );
            },
            onSelected: _selectDrug,
            fieldViewBuilder: (context, controller, focusNode, submit) =>
                TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: (_) => drugId = null,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'ابحث عن الدواء ثم اختر النتيجة',
                prefixIcon: Icon(Icons.medication_outlined),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 12, children: [
            SizedBox(
              width: 245,
              child: DropdownButtonFormField<int>(
                value: activeWarehouseId,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'المخزن', border: OutlineInputBorder()),
                items: warehouses
                    .map((w) => DropdownMenuItem(
                          value: w.id,
                          child: Text('${w.nameAr} (${w.code})'),
                        ))
                    .toList(),
                onChanged: (v) => setState(() {
                  warehouseId = v;
                  shelfCode = null;
                }),
              ),
            ),
            SizedBox(
              width: 245,
              child: DropdownButtonFormField<String?>(
                value: selectedShelf,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'رقم الرف (اختياري)',
                    border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('بدون رف')),
                  ...shelves.map((s) => DropdownMenuItem<String?>(
                      value: s.code, child: Text(s.code))),
                ],
                onChanged: (v) => setState(() => shelfCode = v),
              ),
            ),
            OutlinedButton(
              onPressed: () => _pickDate(expiry: false),
              child: Text('تاريخ الإدخال: $dateLabel'),
            ),
            OutlinedButton(
              onPressed: () => _pickDate(expiry: true),
              child: Text(
                  'تاريخ الانتهاء *: ${expiryDate == null ? 'اختر التاريخ' : _date(expiryDate!)}'),
            ),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, children: [
            _numberField('عدد الكراتين', cartons),
            _numberField('باكتات إضافية', packets),
            _numberField('حبات إضافية', units),
            _numberField('باكتات في الكرتون', packetsPerCarton,
                onChanged: (_) => _recalculateFromPrimaryPrice()),
            _numberField('حبات في الباكت', unitsPerPacket,
                onChanged: (_) => _recalculateFromPrimaryPrice()),
          ]),
          const SizedBox(height: 12),
          const Text(
              'أدخل أي سعر، وستُحسب الأسعار الأخرى. يمكنك تعديل كل سعر مستقلًا.'),
          const SizedBox(height: 8),
          Wrap(spacing: 10, runSpacing: 10, children: [
            _numberField('سعر بيع الكرتون', cartonPrice,
                integer: false, onChanged: (v) => _priceChanged('carton', v)),
            _numberField('سعر بيع الباكت', packetPrice,
                integer: false, onChanged: (v) => _priceChanged('packet', v)),
            _numberField('سعر بيع الحبة', unitPrice,
                integer: false, onChanged: (v) => _priceChanged('unit', v)),
            _numberField('تكلفة الحبة (اختياري)', costUnit, integer: false),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, children: [
            SizedBox(
                width: 230,
                child: TextField(
                  controller: batchNo,
                  decoration: const InputDecoration(
                    labelText: 'رقم التشغيلة (اختياري)',
                    border: OutlineInputBorder(),
                  ),
                )),
            SizedBox(
                width: 290,
                child: TextField(
                  controller: notes,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات',
                    border: OutlineInputBorder(),
                  ),
                )),
            FilledButton.icon(
              onPressed: busy ? null : _addManual,
              icon: const Icon(Icons.playlist_add),
              label: const Text('أضف إلى قائمة المراجعة'),
            ),
          ]),
          const Divider(height: 32),
          Text(
              usesCompactExcel
                  ? 'المراجعة قبل الاعتماد — ${lines.length} صف / $packsTotal باكت (الأشرطة والحبات تُحسب من التعبئة)'
                  : 'المراجعة قبل الاعتماد — ${lines.length} صف / $unitsTotal وحدة',
              style: Theme.of(context).textTheme.titleLarge),
          if (sourceName != null) Text('الملف: $sourceName'),
          if (issues.isNotEmpty) ...[
            Text('أخطاء التحقق (${issues.length}) — لن يتم ترحيل أي رصيد',
                style: const TextStyle(color: Colors.redAccent)),
            for (final error in issues.take(30))
              Text('• $error', style: const TextStyle(color: Colors.redAccent)),
            if (issues.length > 30) Text('و${issues.length - 30} أخطاء أخرى'),
          ],
          for (var i = 0; i < lines.length && i < 50; i++)
            ListTile(
              dense: true,
              title: Text(
                  '${i + 1}. ${lines[i].drugName.isNotEmpty ? lines[i].drugName : 'دواء #${lines[i].drugId}'} '
                  '${lines[i].resolveUnitsFromCatalog ? '• ${lines[i].cartons} باكت، ${lines[i].packetsPerCarton} شريط في كل باكت' : '• ${lines[i].quantityUnits} وحدة'}'),
              subtitle: Text(
                  'صلاحية ${lines[i].expiryDate} | تشغيلة ${lines[i].batchNo.isEmpty ? 'تلقائية' : lines[i].batchNo} '
                  '| رف ${lines[i].shelfCode ?? 'غير محدد'}'),
              trailing: sourceHash == null
                  ? IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'حذف من المراجعة',
                      onPressed:
                          busy ? null : () => setState(() => lines.removeAt(i)),
                    )
                  : null,
            ),
          if (lines.length > 50)
            Text('يُعرض أول 50 صفًا فقط؛ الإجمالي ${lines.length} صفًا'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed:
                busy || lines.isEmpty || issues.isNotEmpty ? null : _post,
            icon: const Icon(Icons.verified_outlined),
            label: Text(busy
                ? 'جارٍ حفظ البيانات...'
                : 'اعتماد وإضافة الرصيد الافتتاحي'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
