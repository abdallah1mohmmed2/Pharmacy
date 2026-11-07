import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/enterprise_dark_theme.dart';
import '../../data/database/database_helper.dart';
import '../../data/models/catalog_drug_model.dart';
import '../../data/repositories/catalog_search_repository.dart';
import '../../data/services/central_catalog_api.dart';
import '../../providers/pos_and_drugs_provider.dart';

class CentralMedicinePickerScreen extends StatefulWidget {
  const CentralMedicinePickerScreen({super.key});
  @override
  State<CentralMedicinePickerScreen> createState() => _CentralMedicinePickerScreenState();
}

class _CentralMedicinePickerScreenState extends State<CentralMedicinePickerScreen> {
  static const _pageSize = 30;
  static const _baseUrl = String.fromEnvironment('CATALOG_API_BASE_URL');
  final _search = TextEditingController();
  CatalogSearchRepository? _repository;
  bool _initialized = false;
  Timer? _debounce;
  int _generation = 0;
  List<CatalogDrugSummary> _items = [];
  String _query = '';
  String? _cursor, _error;
  bool _loading = false, _loadingMore = false, _offline = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final uri = _baseUrl.trim().isEmpty ? null : Uri.tryParse(_baseUrl);
    final database = await DatabaseHelper.instance.database;
    if (!mounted) return;
    _repository = CatalogSearchRepository(
      database: database,
      remote: uri == null ? null : CentralCatalogApi(baseUri: uri),
    );
    setState(() => _initialized = true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _generation++;
    _search.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _debounce?.cancel();
    final generation = ++_generation;
    _query = value.trim();
    setState(() {
      _items = [];
      _cursor = null;
      _error = null;
      _offline = false;
      _loading = _query.length >= 2 || RegExp(r'^\d{8,14}$').hasMatch(_query);
      _loadingMore = false;
    });
    if (_query.isEmpty || (!_loading)) return;
    _debounce = Timer(const Duration(milliseconds: 300), () => _searchPage(generation, _query));
  }

  Future<void> _searchPage(int generation, String query) async {
    final repository = _repository;
    if (repository == null) return;
    try {
      final page = await repository.search(query: query, limit: _pageSize);
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = page.items.take(_pageSize).toList();
        _cursor = page.nextCursor;
        _offline = page.offlineFallback || page.source == CatalogSearchSource.localCache;
        _error = page.remoteError;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _loadMore() async {
    final cursor = _cursor;
    if (cursor == null || _loadingMore || _loading) return;
    final generation = _generation;
    setState(() => _loadingMore = true);
    final repository = _repository;
    if (repository == null) return;
    try {
      final page = await repository.search(query: _query, cursor: cursor, limit: _pageSize);
      if (!mounted || generation != _generation) return;
      final known = _items.map((e) => e.catalogUuid).toSet();
      setState(() {
        _items.addAll(page.items.where((e) => known.add(e.catalogUuid)).take(_pageSize));
        _cursor = page.nextCursor;
        _offline = page.offlineFallback || page.source == CatalogSearchSource.localCache;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() { _loadingMore = false; _error = e.toString(); });
    }
  }

  Future<void> _add(CatalogDrugSummary item) async {
    final provider = context.read<PosAndDrugsProvider>();
    final db = await DatabaseHelper.instance.database;
    final existing = await db.query('drugs', columns: ['id'],
      where: 'branch_id=? AND catalog_uuid=? AND is_deleted=0',
      whereArgs: [provider.branchId, item.catalogUuid], limit: 1);
    if (existing.isNotEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هذا الدواء مضاف بالفعل إلى صيدليتك')));
      return;
    }
    final now = DateTime.now().toIso8601String();
    final values = <String, Object?>{
      'uuid': 'drug-' + DateTime.now().microsecondsSinceEpoch.toString(),
      'branch_id': provider.branchId, 'created_at': now, 'updated_at': now,
      'internal_code': 'CAT-' + item.catalogUuid.hashCode.abs().toString(),
      'trade_name_ar': item.tradeNameAr, 'trade_name_en': item.tradeNameEn,
      'scientific_name': item.scientificName, 'dosage_form': _form(item.dosageForm),
      'strength_text': item.strengthText, 'barcode_international': item.barcodeInternational,
      'catalog_uuid': item.catalogUuid, 'catalog_version': item.catalogVersion,
      'stock_total_units': 0, 'cost_price_pack': 0, 'last_purchase_cost_pack': 0,
      'sell_price_pack': 0, 'sell_price_strip': 0, 'sell_price_unit': 0,
      'public_price_pack': 0,
    };
    try {
      await db.insert('drugs', values);
      await provider.loadDrugs();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تمت إضافة «' + item.tradeNameAr + '» دون إنشاء مخزون أو سعر')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذرت إضافة الدواء: ' + e.toString())));
    }
  }

  String _form(String? value) {
    final v = (value ?? '').toUpperCase();
    const allowed = {'TABLET','CAPSULE','SYRUP','SUSPENSION','DROPS','INJECTION','CREAM','OINTMENT','INHALER','SUPPOSITORY','SACHET','OTHER'};
    if (allowed.contains(v)) return v;
    if (v.contains('TAB')) return 'TABLET';
    if (v.contains('CAP')) return 'CAPSULE';
    if (v.contains('SYR')) return 'SYRUP';
    if (v.contains('SUSP')) return 'SUSPENSION';
    if (v.contains('INJ')) return 'INJECTION';
    if (v.contains('DROP')) return 'DROPS';
    return 'OTHER';
  }

  List<MapEntry<String, String>> _clinicalDetails(CatalogDrugSummary item) {
    const clinicalTerms = [
      'indication', 'contraindication', 'dosage', 'dose', 'warning',
      'adverse', 'side_effect', 'interaction', 'pregnancy', 'lactation',
      'renal', 'hepatic', 'pediatric', 'paediatric', 'geriatric',
      'monitoring', 'overdose', 'mechanism', 'pharmacology',
      'precaution', 'administration', 'toxicity', 'allergy',
      'استطباب', 'موانع', 'جرع', 'تحذير', 'تداخل', 'حمل', 'رضاعة',
      'كلوي', 'كبدي', 'أطفال', 'اطفال', 'آثار', 'اثار', 'سمية',
      'مراقبة', 'احتياط', 'استعمال',
    ];
    final labels = <String, String>{
      'indications': 'دواعي الاستعمال',
      'indication': 'دواعي الاستعمال',
      'contraindications': 'موانع الاستعمال',
      'contraindication': 'موانع الاستعمال',
      'dosage': 'الجرعات',
      'dose': 'الجرعة',
      'warnings': 'التحذيرات',
      'warning': 'التحذيرات',
      'adverse_reactions': 'التفاعلات/الآثار الجانبية',
      'side_effects': 'الآثار الجانبية',
      'drug_interactions': 'التداخلات الدوائية',
      'interactions': 'التداخلات الدوائية',
      'pregnancy': 'الحمل',
      'lactation': 'الرضاعة',
      'renal': 'الاعتبارات الكلوية',
      'hepatic': 'الاعتبارات الكبدية',
      'pediatric': 'استخدام الأطفال',
      'paediatric': 'استخدام الأطفال',
      'geriatric': 'استخدام كبار السن',
      'overdose': 'الجرعة الزائدة',
      'monitoring': 'المراقبة',
      'mechanism_of_action': 'آلية العمل',
      'precautions': 'الاحتياطات',
      'storage': 'التخزين',
    };
    final result = <MapEntry<String, String>>[];
    try {
      final root = jsonDecode(item.payloadJson);
      void visit(dynamic value, [String parent = '']) {
        if (value is Map) {
          for (final entry in value.entries) {
            final key = entry.key.toString();
            final normalized = key
                .replaceAll(RegExp(r'([a-z])([A-Z])'), r'$1_$2')
                .toLowerCase();
            final child = entry.value;
            final isClinical = clinicalTerms.any(normalized.contains);
            if (isClinical && child != null && child is! Map && child is! List) {
              final text = child.toString().trim();
              if (text.isNotEmpty) {
                result.add(MapEntry(labels[normalized] ?? key, text));
              }
            } else if (child is Map || child is List) {
              visit(child, key);
            }
          }
        } else if (value is List) {
          for (final child in value) {
            visit(child, parent);
          }
        }
      }
      visit(root);
    } catch (_) {
      // Malformed or absent clinical payload is never presented as verified data.
    }
    final seen = <String>{};
    return result.where((entry) => seen.add(entry.key + entry.value)).toList();
  }

  void _details(CatalogDrugSummary item) {
    showModalBottomSheet<void>(context: context, isScrollControlled: true,
      backgroundColor: AppColors.surface, builder: (ctx) => SafeArea(
        child: Padding(padding: const EdgeInsets.all(20), child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text(item.tradeNameAr, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            if (item.tradeNameEn != null) Text(item.tradeNameEn!),
            const Divider(height: 24),
            _detail('الاسم العلمي', item.scientificName),
            _detail('المادة الفعالة', item.activeIngredientName),
            _detail('الشكل الصيدلاني', item.dosageForm),
            _detail('التركيز', item.strengthText),
            _detail('الشركة المصنعة', item.manufacturerName),
            _detail('الباركود', item.barcodeInternational),
            _detail('المصدر', item.sourceName),
            _detail('حالة المراجعة', item.reviewStatus),
            const Divider(height: 24),
            const Text('التفاصيل السريرية', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_clinicalDetails(item).isEmpty)
              const Text('لا تتوفر تفاصيل سريرية موثقة لهذا الدواء في بيانات الموسوعة الحالية.',
                style: TextStyle(color: Colors.white60))
            else
              ..._clinicalDetails(item).map((entry) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(entry.key, style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(entry.value),
                ]),
              )),
            const SizedBox(height: 8),
            Text('المصدر: ${item.sourceName ?? 'غير محدد'} • حالة المراجعة: ${item.reviewStatus}',
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: () { Navigator.pop(ctx); _add(item); },
              icon: const Icon(Icons.add), label: const Text('إضافة إلى صيدليتي')),
          ]),
        )),
      ));
  }

  Widget _detail(String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [
      SizedBox(width: 115, child: Text(label, style: const TextStyle(color: Colors.white60))),
      Expanded(child: Text(value)),
    ]));
  }

  @override
  Widget build(BuildContext context) {
    final remoteConfigured = _baseUrl.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('اختيار الأدوية من الموسوعة')),
      body: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
        TextField(controller: _search, onChanged: _changed,
          decoration: InputDecoration(hintText: 'ابحث بالاسم التجاري أو العلمي أو الباركود',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(onPressed: () { _search.clear(); _changed(''); },
              icon: const Icon(Icons.close)))),
        const SizedBox(height: 8),
        if (!remoteConfigured) const Align(alignment: AlignmentDirectional.centerStart,
          child: Text('الاتصال بالموسوعة المركزية غير مضبوط؛ ستظهر النتائج المحفوظة محلياً فقط.',
            style: TextStyle(color: Colors.orangeAccent, fontSize: 12))),
        if (_offline) const Align(alignment: AlignmentDirectional.centerStart,
          child: Text('نتائج من الذاكرة المحلية', style: TextStyle(color: Colors.orangeAccent))),
        if (_error != null) Align(alignment: AlignmentDirectional.centerStart,
          child: Text('تعذر الاتصال: ' + _error!, style: const TextStyle(color: Colors.orangeAccent))),
        const SizedBox(height: 8),
        Expanded(child: !_initialized || _loading ? const Center(child: CircularProgressIndicator())
          : _query.isEmpty ? const Center(child: Text('اكتب حرفين على الأقل للبحث في الموسوعة'))
          : _items.isEmpty ? const Center(child: Text('لا توجد نتائج مطابقة'))
          : ListView.separated(itemCount: _items.length, separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, index) {
              final item = _items[index];
              final sub = [item.scientificName, item.strengthText, item.dosageForm]
                .whereType<String>().where((s) => s.isNotEmpty).join(' • ');
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.medication_outlined)),
                title: Text(item.tradeNameAr),
                subtitle: Text(sub),
                onTap: () => _details(item),
                trailing: const Icon(Icons.chevron_left),
              );
            })),
        if (_cursor != null) SizedBox(width: double.infinity,
          child: OutlinedButton.icon(onPressed: _loadingMore ? null : _loadMore,
            icon: _loadingMore ? const SizedBox(width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.expand_more),
            label: Text(_loadingMore ? 'جارٍ تحميل الصفحة التالية' : 'تحميل 30 نتيجة أخرى'))),
        if (_items.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6),
          child: Text('عدد النتائج المعروضة: ' + _items.length.toString(),
            style: const TextStyle(color: Colors.white54))),
      ])),
    );
  }
}
