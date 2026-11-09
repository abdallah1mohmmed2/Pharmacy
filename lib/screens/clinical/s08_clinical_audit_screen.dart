// lib/screens/clinical/s08_clinical_audit_screen.dart
import 'package:flutter/material.dart';
import '../../data/database/database_helper.dart';

class S08ClinicalAuditScreen extends StatefulWidget {
  const S08ClinicalAuditScreen({super.key});

  @override
  State<S08ClinicalAuditScreen> createState() => _S08ClinicalAuditScreenState();
}

class _S08ClinicalAuditScreenState extends State<S08ClinicalAuditScreen> {
  late Future<List<Map<String, Object?>>> _alerts;
  late Future<List<Map<String, Object?>>> _controlled;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _alerts = DatabaseHelper.instance.rawQuery(
      'SELECT l.*, d.trade_name_ar FROM clinical_alert_logs l '
      'LEFT JOIN drugs d ON d.id = l.drug_id ORDER BY l.id DESC LIMIT 500',
    );
    _controlled = DatabaseHelper.instance.rawQuery(
      'SELECT c.*, d.trade_name_ar FROM controlled_drug_log c '
      'LEFT JOIN drugs d ON d.id = c.drug_id ORDER BY c.id DESC LIMIT 500',
    );
  }

  Future<void> _refresh() async {
    setState(_reload);
    await Future.wait([_alerts, _controlled]);
  }

  String _value(Object? value) =>
      value == null || value.toString().isEmpty ? '—' : value.toString();

  Widget _alertList() => FutureBuilder<List<Map<String, Object?>>>(
        future: _alerts,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('تعذر تحميل سجل التنبيهات: ${snapshot.error}'));
          }
          final rows = snapshot.data ?? const [];
          if (rows.isEmpty) {
            return const Center(child: Text('لا توجد قرارات سريرية مسجلة بعد.'));
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final row = rows[index];
                final level = _value(row['level']);
                final color = level == 'BLOCK'
                    ? const Color(0xffEF5350)
                    : level == 'WARNING'
                        ? const Color(0xffFFB74D)
                        : const Color(0xff4DB6AC);
                return Card(
                  color: const Color(0xff1E1E1E),
                  child: ListTile(
                    leading: Icon(Icons.health_and_safety, color: color),
                    title: Text(
                      '${_value(row['trade_name_ar'])} • ${_value(row['alert_category'])}',
                    ),
                    subtitle: Text(
                      '${_value(row['message_ar'])}\n'
                      'القرار: ${_value(row['user_decision'])} • '
                      'المستخدم: ${_value(row['decided_by'])}\n'
                      'السبب: ${_value(row['override_reason'])}\n'
                      'التاريخ: ${_value(row['alert_at'])}',
                    ),
                    isThreeLine: true,
                  ),
                );
              },
            ),
          );
        },
      );

  Widget _controlledList() => FutureBuilder<List<Map<String, Object?>>>(
        future: _controlled,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('تعذر تحميل سجل الأدوية المراقبة: ${snapshot.error}'));
          }
          final rows = snapshot.data ?? const [];
          if (rows.isEmpty) {
            return const Center(child: Text('لا توجد عمليات صرف مراقبة مسجلة بعد.'));
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final row = rows[index];
                return Card(
                  color: const Color(0xff1E1E1E),
                  child: ListTile(
                    leading: const Icon(Icons.medication, color: Color(0xffFFB74D)),
                    title: Text(_value(row['trade_name_ar'])),
                    subtitle: Text(
                      'الكمية: ${_value(row['qty_units'])} حبة • '
                      'الرصيد التراكمي: ${_value(row['running_balance_units'])}\n'
                      'المريض: ${_value(row['patient_name'])} • '
                      'هوية المريض: ${_value(row['patient_national_id'])}\n'
                      'المستلم: ${_value(row['receiver_name'])} • '
                      'هوية المستلم: ${_value(row['receiver_national_id'])}\n'
                      'الطبيب: ${_value(row['doctor_name'])} • '
                      'الصيدلي: ${_value(row['pharmacist_user_id'])} • '
                      'الوصفة: ${_value(row['prescription_id'])}',
                    ),
                    isThreeLine: true,
                  ),
                );
              },
            ),
          );
        },
      );

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
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
              tabs: [
                Tab(icon: Icon(Icons.health_and_safety), text: 'القرارات السريرية'),
                Tab(icon: Icon(Icons.medication), text: 'الأدوية المراقبة'),
              ],
            ),
          ),
          body: TabBarView(children: [_alertList(), _controlledList()]),
        ),
      );
}
