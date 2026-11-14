import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/services/clinical_regulatory_service.dart';
import '../../providers/session_and_erp_provider.dart';

/// A branch-scoped, read-only regulatory review. Existing audit/movement rows
/// are never rewritten; historical balances lacking a snapshot are unverified.
class S08ClinicalAuditScreen extends StatefulWidget {
  const S08ClinicalAuditScreen({super.key});

  @override
  State<S08ClinicalAuditScreen> createState() => _S08ClinicalAuditScreenState();
}

class _S08ClinicalAuditScreenState extends State<S08ClinicalAuditScreen> {
  final _service = ClinicalRegulatoryService();
  final _search = TextEditingController();
  final _from = TextEditingController();
  final _to = TextEditingController();
  String? _level;
  int? _loadedBranch;
  int _alertsPage = 0, _controlledPage = 0, _movementsPage = 0;
  static const _pageSize = 50;

  late Future<List<Map<String, Object?>>> _alerts;
  late Future<List<Map<String, Object?>>> _controlled;
  late Future<List<Map<String, Object?>>> _movements;
  late Future<Map<String, int>> _summary;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final branchId = context.watch<SessionAndErpProvider>().branchId;
    if (_loadedBranch != branchId) {
      _loadedBranch = branchId;
      _alertsPage = _controlledPage = _movementsPage = 0;
      _load();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  void _load() {
    final branchId = _loadedBranch;
    if (branchId == null) return;
    final from = _from.text.trim();
    final to = _to.text.trim();
    final q = _search.text.trim();
    _summary = _service.summary(branchId: branchId);
    _alerts = _service.alerts(
      branchId: branchId,
      search: q,
      dateFrom: from,
      dateTo: to,
      level: _level,
      limit: _pageSize,
      offset: _alertsPage * _pageSize,
    );
    _controlled = _service.controlled(
      branchId: branchId,
      search: q,
      dateFrom: from,
      dateTo: to,
      limit: _pageSize,
      offset: _controlledPage * _pageSize,
    );
    _movements = _service.movements(
      branchId: branchId,
      search: q,
      dateFrom: from,
      dateTo: to,
      limit: _pageSize,
      offset: _movementsPage * _pageSize,
    );
  }

  Future<void> _refresh() async {
    setState(_load);
    await Future.wait<Object>([_alerts, _controlled, _movements, _summary]);
  }

  void _apply() {
    final from = _from.text.trim(), to = _to.text.trim();
    final datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if ((from.isNotEmpty && !datePattern.hasMatch(from)) ||
        (to.isNotEmpty && !datePattern.hasMatch(to)) ||
        (from.isNotEmpty && to.isNotEmpty && from.compareTo(to) > 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل تاريخًا صحيحًا YYYY-MM-DD وتأكد من ترتيب الفترة')),
      );
      return;
    }
    setState(() {
      _alertsPage = _controlledPage = _movementsPage = 0;
      _load();
    });
  }

  String _value(Object? value) =>
      value == null || value.toString().trim().isEmpty ? '—' : value.toString();

  bool get _canReveal {
    final role = context.read<SessionAndErpProvider>().currentUser?['role_code'];
    return role == 'OWNER' || role == 'MANAGER' || role == 'AUDITOR';
  }

  void _details(Map<String, Object?> record,
      {required String title, bool controlled = false}) {
    var reveal = false;
    final allowReveal = controlled && _canReveal;
    final fields = <(String, String)>[
      ('التاريخ', controlled
          ? _value(record['recorded_at'])
          : _value(record['alert_at'] ?? record['movement_at'])),
      ('الدواء', _value(record['trade_name_ar'])),
      ('رقم الفاتورة', _value(record['invoice_no'])),
      if (controlled) ...[
        ('الوصفة', _value(record['rx_no'])),
        ('التشغيلة', _value(record['batch_no'])),
        ('المخزن', _value(record['warehouse_name'])),
        ('الكمية المصروفة', _value(record['qty_units'])),
        ('الرصيد الفعلي بعد الصرف', record['balance_verified'] == 1
            ? _value(record['verified_balance_after_units'])
            : 'غير مثبت تاريخيًا'),
        ('رصيد التشغيلة بعد الصرف', record['balance_verified'] == 1
            ? _value(record['verified_batch_after_units'])
            : 'غير مثبت تاريخيًا'),
        ('المريض', _value(record['patient_name'])),
        ('هوية المريض', _value(record['patient_national_id'])),
        ('المستلم', _value(record['receiver_name'])),
        ('هوية المستلم', _value(record['receiver_national_id'])),
        ('الطبيب', _value(record['doctor_name'])),
        ('الصيدلي', _value(record['pharmacist_name'])),
      ] else ...[
        ('نوع السجل', _value(record['alert_category'] ?? record['movement_type'])),
        ('مستوى الخطورة', _value(record['level'])),
        ('القرار', _value(record['user_decision'])),
        ('المستخدم', _value(record['decided_by_name'])),
        ('المدير', _value(record['manager_name'])),
        ('السبب', _value(record['override_reason'])),
        ('مضمون التنبيه', _value(record['message_ar'])),
        if (record.containsKey('balance_after_units'))
          ('رصيد التشغيلة', _value(record['balance_after_units'])),
        if (record.containsKey('doc_type'))
          ('المستند', '${_value(record['doc_type'])} • ${_value(record['doc_id'])}'),
      ],
    ];
    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 550,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final (label, raw) in fields)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(label,
                            style: Theme.of(context).textTheme.labelSmall),
                        SelectableText(
                          controlled && !reveal && label.contains('هوية')
                              ? ClinicalRegulatoryService.maskedId(raw)
                              : controlled && !reveal &&
                                      (label == 'المريض' || label == 'المستلم')
                                  ? ClinicalRegulatoryService.maskedName(raw)
                                  : raw,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            if (allowReveal)
              TextButton(
                onPressed: () => update(() => reveal = !reveal),
                child: Text(reveal ? 'إخفاء الهويات' : 'عرض الهويات المخوّل'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filters() => Padding(
    padding: const EdgeInsets.all(8),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 220,
          child: TextField(
            controller: _search,
            decoration: const InputDecoration(
              labelText: 'بحث: دواء، فاتورة، وصفة',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
            onSubmitted: (_) => _apply(),
          ),
        ),
        for (final item in [
          (_from, 'من YYYY-MM-DD'),
          (_to, 'إلى YYYY-MM-DD'),
        ])
          SizedBox(
            width: 148,
            child: TextField(
              controller: item.$1,
              decoration:
                  InputDecoration(labelText: item.$2, isDense: true),
            ),
          ),
        SizedBox(
          width: 155,
          child: DropdownButtonFormField<String>(
            value: _level,
            isExpanded: true,
            decoration: const InputDecoration(
                labelText: 'خطورة التنبيه', isDense: true),
            items: const [
              DropdownMenuItem(value: null, child: Text('الكل')),
              DropdownMenuItem(value: 'BLOCK', child: Text('حظر')),
              DropdownMenuItem(value: 'WARNING', child: Text('تحذير')),
              DropdownMenuItem(value: 'CAUTION', child: Text('تنبيه')),
              DropdownMenuItem(value: 'INFO', child: Text('معلومة')),
            ],
            onChanged: (value) => setState(() => _level = value),
          ),
        ),
        FilledButton.icon(
          onPressed: _apply,
          icon: const Icon(Icons.filter_alt),
          label: const Text('تطبيق الفلاتر'),
        ),
      ],
    ),
  );

  Widget _overview() => FutureBuilder<Map<String, int>>(
        future: _summary,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return snapshot.hasError
                ? const Text('تعذر تحميل الإحصاءات')
                : const LinearProgressIndicator();
          }
          final counts = snapshot.data!;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                for (final item in [
                  ('القرارات', counts['decisions']),
                  ('الحظر السريري', counts['critical']),
                  ('تجاوزات المدير', counts['overrides']),
                  ('سجلات الصرف', counts['dispenses']),
                  ('أرصدة قديمة غير مثبتة', counts['unverifiedLegacy']),
                  ('حركات المخزون المراقب', counts['movements']),
                ])
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 15, vertical: 8),
                        child: Column(children: [
                          Text(item.$1,
                              style: Theme.of(context).textTheme.labelSmall),
                          Text('${item.$2 ?? 0}',
                              style: Theme.of(context).textTheme.titleMedium),
                        ]),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      );

  Widget _pagination(int page, int count, void Function(int) onPage) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: page == 0 ? null : () => onPage(page - 1),
              child: const Text('السابق'),
            ),
            Text('صفحة ${page + 1}'),
            TextButton(
              onPressed: count < _pageSize ? null : () => onPage(page + 1),
              child: const Text('التالي'),
            ),
          ],
        ),
      );

  Widget _paged(
    Future<List<Map<String, Object?>>> future,
    int page,
    void Function(int) onPage,
    Widget Function(Map<String, Object?>) item,
  ) =>
      FutureBuilder<List<Map<String, Object?>>>(
        future: future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(
              child: snapshot.hasError
                  ? Text('تعذر تحميل السجل: ${snapshot.error}')
                  : const CircularProgressIndicator(),
            );
          }
          final rows = snapshot.data!;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(8),
              itemCount: rows.length + 1,
              itemBuilder: (context, index) {
                if (index == rows.length) {
                  return Column(
                    children: [
                      if (rows.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('لا توجد نتائج في هذا الفرع والفترة'),
                        ),
                      _pagination(page, rows.length, onPage),
                    ],
                  );
                }
                return item(rows[index]);
              },
            ),
          );
        },
      );

  Widget _alertCard(Map<String, Object?> row) {
    final level = row['level']?.toString() ?? '';
    final color = level == 'BLOCK'
        ? const Color(0xffEF5350)
        : level == 'WARNING'
            ? const Color(0xffFFB74D)
            : const Color(0xff4DB6AC);
    return Card(
      color: const Color(0xff1E1E1E),
      child: ListTile(
        leading: Icon(Icons.health_and_safety, color: color),
        title: Text('${_value(row['trade_name_ar'])} • ${_value(row['alert_category'])}'),
        subtitle: Text(
          '${_value(row['message_ar'])}\n'
          'القرار: ${_value(row['user_decision'])} • '
          'الفاتورة: ${_value(row['invoice_no'])}\n'
          'التاريخ: ${_value(row['alert_at'])}',
        ),
        isThreeLine: true,
        trailing: IconButton(
          tooltip: 'تفاصيل القرار',
          icon: const Icon(Icons.info_outline),
          onPressed: () => _details(row, title: 'تفاصيل القرار السريري'),
        ),
      ),
    );
  }

  Widget _controlledCard(Map<String, Object?> row) {
    final verified = row['balance_verified'] == 1;
    return Card(
      color: const Color(0xff1E1E1E),
      child: ListTile(
        leading: const Icon(Icons.medication, color: Color(0xffFFB74D)),
        title: Text(_value(row['trade_name_ar'])),
        subtitle: Text(
          'الكمية: ${_value(row['qty_units'])} وحدة • '
          'الرصيد بعد الصرف: ${verified ? _value(row['verified_balance_after_units']) : 'غير مثبت تاريخيًا'}\n'
          'المريض: ${ClinicalRegulatoryService.maskedName(row['patient_name'])} • '
          'الهوية: ${ClinicalRegulatoryService.maskedId(row['patient_national_id'])}\n'
          'الفاتورة: ${_value(row['invoice_no'])} • '
          'التاريخ: ${_value(row['recorded_at'])}',
        ),
        isThreeLine: true,
        trailing: IconButton(
          tooltip: 'تفاصيل صرف الدواء المراقب',
          icon: const Icon(Icons.info_outline),
          onPressed: () => _details(
            row,
            title: 'تفاصيل صرف الدواء المراقب',
            controlled: true,
          ),
        ),
      ),
    );
  }

  Widget _movementCard(Map<String, Object?> row) => Card(
        color: const Color(0xff1E1E1E),
        child: ListTile(
          leading: const Icon(Icons.swap_horiz, color: Color(0xff4DB6AC)),
          title: Text('${_value(row['trade_name_ar'])} • ${_value(row['movement_type'])}'),
          subtitle: Text(
            'التغير: ${_value(row['qty_units'])} وحدة • '
            'رصيد التشغيلة: ${_value(row['balance_after_units'])}\n'
            'التشغيلة: ${_value(row['batch_no'])} • '
            'المخزن: ${_value(row['warehouse_name'])}\n'
            'التاريخ: ${_value(row['movement_at'])}',
          ),
          isThreeLine: true,
          trailing: IconButton(
            tooltip: 'تفاصيل حركة المخزون',
            icon: const Icon(Icons.info_outline),
            onPressed: () => _details(row, title: 'تفاصيل حركة المخزون'),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('سجل الرقابة السريرية والأدوية المراقبة'),
            actions: [
              IconButton(
                tooltip: 'تحديث السجلات',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
            bottom: const TabBar(
              isScrollable: true,
              tabs: [
                Tab(icon: Icon(Icons.health_and_safety), text: 'القرارات السريرية'),
                Tab(icon: Icon(Icons.medication), text: 'الأدوية المراقبة'),
                Tab(icon: Icon(Icons.swap_horiz), text: 'دفتر الحركة'),
              ],
            ),
          ),
          body: Column(
            children: [
              _overview(),
              _filters(),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'الإحصاءات لجميع الفترات في هذا الفرع. تقارير PDF الرقابية: 47 و48 و49.',
                  style: TextStyle(fontSize: 11),
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _paged(_alerts, _alertsPage, (page) {
                      setState(() { _alertsPage = page; _load(); });
                    }, _alertCard),
                    _paged(_controlled, _controlledPage, (page) {
                      setState(() { _controlledPage = page; _load(); });
                    }, _controlledCard),
                    _paged(_movements, _movementsPage, (page) {
                      setState(() { _movementsPage = page; _load(); });
                    }, _movementCard),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}
