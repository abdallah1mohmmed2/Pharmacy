// lib/screens/reports/s27_reports_center_pdf_screen.dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:printing/printing.dart';

import '../../providers/session_and_erp_provider.dart';
import '../../reports_pdf/models_and_contracts.dart';
import '../../reports_pdf/registry/report_registry_and_provider.dart';

class S27ReportsCenterPdfScreen extends StatefulWidget {
  const S27ReportsCenterPdfScreen({super.key});

  @override
  State<S27ReportsCenterPdfScreen> createState() => _S27ReportsCenterPdfScreenState();
}

class _S27ReportsCenterPdfScreenState extends State<S27ReportsCenterPdfScreen> {
  final TextEditingController _search = TextEditingController();
  ReportCategory? _category;
  bool _favoritesOnly = false;
  bool _showPdf = false;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final session = context.read<SessionAndErpProvider>();
      final user = session.currentUser;
      if (user == null) return;
      await context.read<ReportsCenterProvider>().initialize(
        userId: user['id'] as int,
        userName: user['full_name'] as String? ?? '',
        branchId: session.branchId,
      );
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ReportsCenterProvider>();
    final reports = provider.registry.search(_search.text, category: _category)
        .where((r) => !_favoritesOnly || provider.favorites.contains(r.number))
        .toList();
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 1000;
      final sidebar = _buildSidebar(provider, reports);
      final workspace = _buildWorkspace(provider);
      if (!wide) {
        return Column(
          children: [
            SizedBox(height: 250, child: sidebar),
            const Divider(height: 1),
            Expanded(child: workspace),
          ],
        );
      }
      return Row(
        children: [
          SizedBox(width: 290, child: sidebar),
          const VerticalDivider(width: 1),
          Expanded(child: workspace),
        ],
      );
    });
  }

  Widget _buildSidebar(ReportsCenterProvider provider, List<ReportDefinition> reports) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'ابحث بالاسم أو رقم التقرير 1–55',
                suffixIcon: IconButton(
                  onPressed: () => setState(() { _search.clear(); _category = null; }),
                  icon: const Icon(Icons.close),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          SwitchListTile(
            dense: true,
            title: const Text('المفضلة فقط ⭐'),
            value: _favoritesOnly,
            onChanged: (v) => setState(() => _favoritesOnly = v),
          ),
          if (_category != null)
            ListTile(
              dense: true,
              leading: const Icon(Icons.filter_alt_off),
              title: Text('إلغاء تصفية ${_category!.title}'),
              onTap: () => setState(() => _category = null),
            ),
          Expanded(
            child: ListView(
              children: [
                for (final category in ReportCategory.values)
                  ExpansionTile(
                    initiallyExpanded: _category == category || _search.text.isNotEmpty,
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(category.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${category.reportCount} تقريراً'),
                    onExpansionChanged: (open) {
                      if (open) setState(() => _category = category);
                    },
                    children: [
                      for (final report in reports.where((r) => r.category == category))
                        ListTile(
                          dense: true,
                          selected: provider.selected?.number == report.number,
                          leading: SizedBox(
                            width: 30,
                            child: Text(report.number.toString().padLeft(2, '0')),
                          ),
                          title: Text(report.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                          trailing: IconButton(
                            tooltip: provider.favorites.contains(report.number)
                                ? 'إزالة من المفضلة' : 'إضافة للمفضلة',
                            icon: Icon(
                              provider.favorites.contains(report.number)
                                  ? Icons.star : Icons.star_border,
                              color: provider.favorites.contains(report.number)
                                  ? Colors.amber : null,
                            ),
                            onPressed: () => provider.toggleFavorite(report.number),
                          ),
                          onTap: () {
                            provider.selectReport(report.number);
                            setState(() => _showPdf = false);
                          },
                        ),
                    ],
                  ),
                if (reports.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('لا توجد تقارير مطابقة للبحث.'),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text('إجمالي النتائج: ${reports.length} من 55',
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkspace(ReportsCenterProvider provider) {
    final report = provider.selected;
    if (report == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.assessment_outlined, size: 54),
            SizedBox(height: 12),
            Text('اختر تقريراً من القائمة لعرض معاملاته وبياناته.'),
          ],
        ),
      );
    }
    return Column(
      children: [
        _buildParameterPanel(provider, report),
        if (provider.error != null)
          MaterialBanner(
            content: Text(provider.error!),
            leading: const Icon(Icons.error_outline),
            actions: [TextButton(onPressed: provider.clearResult, child: const Text('إغلاق'))],
          ),
        Expanded(
          child: provider.data == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.table_chart_outlined, size: 44),
                      const SizedBox(height: 8),
                      const Text('حدد المعاملات ثم اضغط «تشغيل التقرير».'),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: provider.isLoading ? null : () => _run(provider),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('تشغيل التقرير'),
                      ),
                    ],
                  ),
                )
              : _buildResults(provider),
        ),
      ],
    );
  }

  Widget _buildParameterPanel(ReportsCenterProvider provider, ReportDefinition report) {
    return Card(
      margin: const EdgeInsets.all(10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('تقرير رقم ${report.number}: ${report.title}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                if (provider.hasCostPermission)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('إظهار التكلفة'),
                      Switch(
                        value: provider.showCostSetting,
                        onChanged: provider.updateCostVisibility,
                      ),
                    ],
                  ),
              ],
            ),
            if (report.params.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: report.params.map((param) => _parameterControl(provider, param)).toList(),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ActionChip(label: const Text('اليوم'), onPressed: () => _quickRange(provider, 'today')),
                ActionChip(label: const Text('هذا الشهر'), onPressed: () => _quickRange(provider, 'month')),
                ActionChip(label: const Text('هذه السنة'), onPressed: () => _quickRange(provider, 'year')),
                FilterChip(
                  label: const Text('ورقة عرضية'),
                  selected: provider.params.paperLandscape ?? report.isLandscape,
                  onSelected: (v) => provider.updateParams(const {}, paperLandscape: v),
                ),
                FilledButton.icon(
                  onPressed: provider.isLoading ? null : () => _run(provider),
                  icon: provider.isLoading
                      ? const SizedBox(width: 16,height: 16,child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.play_arrow),
                  label: const Text('تشغيل التقرير'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _parameterControl(ReportsCenterProvider provider, ReportParam param) {
    final value = provider.params[param.key];
    if (param.kind == ReportParamKind.boolean) {
      return SizedBox(
        width: 220,
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(param.label),
          value: value == true || value == 1,
          onChanged: (v) => provider.updateParams({param.key: v}),
        ),
      );
    }
    const optionKinds = {
      ReportParamKind.customer,
      ReportParamKind.supplier,
      ReportParamKind.employee,
      ReportParamKind.drug,
      ReportParamKind.warehouse,
      ReportParamKind.cashier,
    };
    if (optionKinds.contains(param.kind)) {
      return SizedBox(
        width: 250,
        child: FutureBuilder<List<Map<String, Object?>>>(
          future: provider.parameterOptions(param.kind),
          builder: (context, snapshot) {
            final options = snapshot.data ?? const <Map<String, Object?>>[];
            final selected = value == null ? null : int.tryParse(value.toString());
            return DropdownButtonFormField<int>(
              value: options.any((row) => row['id'] == selected) ? selected : null,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: param.label,
                helperText: snapshot.connectionState == ConnectionState.waiting
                    ? 'جارٍ تحميل الخيارات…'
                    : options.isEmpty ? 'لا توجد عناصر متاحة' : null,
              ),
              items: options.map((row) => DropdownMenuItem<int>(
                value: row['id'] as int,
                child: Text(row['name_ar']?.toString() ?? ''),
              )).toList(),
              onChanged: snapshot.connectionState == ConnectionState.waiting ||
                      options.isEmpty
                  ? null
                  : (selectedId) {
                      if (selectedId != null) {
                        provider.updateParams({param.key: selectedId});
                      }
                    },
            );
          },
        ),
      );
    }
    if (param.kind == ReportParamKind.category || param.kind == ReportParamKind.orientation) {
      return SizedBox(
        width: 220,
        child: DropdownButtonFormField<String>(
          value: value?.toString() ?? param.defaultValue?.toString(),
          decoration: InputDecoration(labelText: param.label),
          items: param.options.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: (v) { if (v != null) provider.updateParams({param.key: v}); },
        ),
      );
    }
    return SizedBox(
      width: 220,
      child: TextFormField(
        key: ValueKey('${param.key}-${value ?? param.defaultValue ?? ''}'),
        initialValue: value?.toString() ?? param.defaultValue?.toString() ?? '',
        keyboardType: param.kind == ReportParamKind.number
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        decoration: InputDecoration(
          labelText: param.label,
          hintText: param.kind == ReportParamKind.date ? 'YYYY-MM-DD' : param.helpText,
          suffixIcon: param.kind == ReportParamKind.date
              ? IconButton(
                  icon: const Icon(Icons.calendar_month),
                  onPressed: () => _pickDate(provider, param.key, value),
                )
              : null,
        ),
        onChanged: (v) => provider.updateParams({
          param.key: param.kind == ReportParamKind.number ? num.tryParse(v) ?? v : v,
        }),
      ),
    );
  }

  Future<void> _pickDate(ReportsCenterProvider provider, String key, Object? current) async {
    final initial = DateTime.tryParse(current?.toString() ?? '') ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      provider.updateParams({key: picked.toIso8601String().substring(0, 10)});
    }
  }

  void _quickRange(ReportsCenterProvider provider, String mode) {
    final now = DateTime.now();
    late DateTime from;
    if (mode == 'today') {
      from = DateTime(now.year, now.month, now.day);
    } else if (mode == 'month') {
      from = DateTime(now.year, now.month, 1);
    } else {
      from = DateTime(now.year, 1, 1);
    }
    provider.updateParams({
      'date_from': from.toIso8601String().substring(0, 10),
      'date_to': now.toIso8601String().substring(0, 10),
    });
  }

  Future<void> _run(ReportsCenterProvider provider) async {
    try {
      await provider.runSelected();
      if (mounted) setState(() => _showPdf = false);
    } catch (_) {}
  }

  Widget _buildResults(ReportsCenterProvider provider) {
    final data = provider.data!;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            children: [
              Expanded(child: Text('معاينة البيانات: ${data.rows.length} صف')),
              TextButton.icon(
                onPressed: () => setState(() => _showPdf = !_showPdf),
                icon: const Icon(Icons.picture_as_pdf),
                label: Text(_showPdf ? 'إخفاء PDF' : 'معاينة PDF'),
              ),
            ],
          ),
        ),
        if (_showPdf)
          Expanded(
            flex: 3,
            child: PdfPreview(
              build: (format) async => await provider.buildPdf() ?? Uint8List(0),
              canChangeOrientation: false,
              canChangePageFormat: false,
              allowPrinting: false,
              allowSharing: false,
              pdfFileName: 'nabdh-report-${data.reportNumber}.pdf',
              maxPageWidth: 700,
            ),
          )
        else
          Expanded(
            flex: 3,
            child: _dataTable(data),
          ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: () async {
                  await provider.buildPdf();
                  if (mounted) setState(() => _showPdf = true);
                },
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('توليد ومعاينة PDF'),
              ),
              OutlinedButton.icon(
                onPressed: () => provider.engine.printDirect(
                  context: context,
                  definition: provider.selected!,
                  data: data,
                  params: provider.params,
                ),
                icon: const Icon(Icons.print),
                label: const Text('طباعة مباشرة'),
              ),
              OutlinedButton.icon(
                onPressed: () => _savePdf(provider),
                icon: const Icon(Icons.save_alt),
                label: const Text('حفظ ملف PDF'),
              ),
              OutlinedButton.icon(
                onPressed: () => _exportCsv(provider),
                icon: const Icon(Icons.table_view),
                label: const Text('تصدير CSV / Excel'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dataTable(ReportDataSet data) {
    if (data.rows.isEmpty) return const Center(child: Text('لا توجد بيانات ضمن المعاملات المحددة.'));
    return Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: DataTable(
            headingRowHeight: 44,
            dataRowMinHeight: 38,
            dataRowMaxHeight: 64,
            columns: data.columns.map((c) => DataColumn(label: Text(c.label))).toList(),
            rows: [
              ...data.rows.map((row) => DataRow(
                cells: data.columns.map((c) => DataCell(
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(c.display(row[c.key]), overflow: TextOverflow.ellipsis),
                  ),
                )).toList(),
              )),
              if (data.totals.isNotEmpty)
                DataRow(
                  color: WidgetStatePropertyAll(Theme.of(context).colorScheme.surfaceContainerHighest),
                  cells: data.columns.map((c) => DataCell(Text(
                    c.key == data.columns.first.key
                        ? 'الإجمالي'
                        : data.totals.containsKey(c.key) ? c.display(data.totals[c.key]) : '',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ))).toList(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _savePdf(ReportsCenterProvider provider) async {
    try {
      final file = await provider.savePdf();
      if (!mounted || file == null) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم حفظ PDF: ${file.path}')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر حفظ PDF: $e')));
    }
  }

  Future<void> _exportCsv(ReportsCenterProvider provider) async {
    try {
      final file = await provider.exportCsv();
      if (!mounted || file == null) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم تصدير ملف CSV المتوافق مع Excel: ${file.path}')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر التصدير: $e')));
    }
  }
}
