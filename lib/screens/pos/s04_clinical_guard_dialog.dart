// lib/screens/pos/s04_clinical_guard_dialog.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../data/models/clinical_and_rx_models.dart';
import '../../data/models/drug_model.dart';
import '../../providers/clinical_and_rx_provider.dart';
import '../../providers/pos_and_drugs_provider.dart';
import '../../providers/session_and_erp_provider.dart';
import 's05_drug_alternatives_sheet.dart';

class S04ClinicalGuardDialog extends StatefulWidget {
  const S04ClinicalGuardDialog({super.key});
  static Future<bool> show(BuildContext context,
      {List<DrugModel>? drugs}) async {
    final pos = context.read<PosAndDrugsProvider>();
    await context
        .read<ClinicalAndRxProvider>()
        .evaluateCart(drugs ?? pos.cart.map((e) => e.drug).toList());
    if (!context.mounted) return false;
    return await showDialog<bool>(
            context: context, builder: (_) => const S04ClinicalGuardDialog()) ??
        false;
  }

  @override
  State<S04ClinicalGuardDialog> createState() => _S04ClinicalGuardDialogState();
}

class _S04ClinicalGuardDialogState extends State<S04ClinicalGuardDialog> {
  final reason = TextEditingController();
  final foods = TextEditingController();
  final doseMg = TextEditingController();
  int? doseDrugId;
  @override
  void dispose() {
    reason.dispose();
    foods.dispose();
    doseMg.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clinical = context.watch<ClinicalAndRxProvider>();
    final pos = context.watch<PosAndDrugsProvider>();
    final session = context.read<SessionAndErpProvider>();
    final patient = clinical.currentPatient;
    return AlertDialog(
      title: const Row(children: [
        Icon(Icons.health_and_safety, color: Color(0xffEF5350)),
        SizedBox(width: 8),
        Expanded(child: Text('الحماية السريرية وفاحص التفاعلات'))
      ]),
      content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                DropdownButtonFormField<int?>(
                    value: patient?.id,
                    decoration: const InputDecoration(labelText: 'ملف المريض'),
                    items: [
                      const DropdownMenuItem<int?>(
                          value: null, child: Text('بدون ملف مريض')),
                      ...clinical.patients.map((p) => DropdownMenuItem<int?>(
                          value: p.id, child: Text(p.fullName)))
                    ],
                    onChanged: (id) => clinical.selectPatient(id == null
                        ? null
                        : clinical.patients.firstWhere((p) => p.id == id))),
                if (patient != null)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Wrap(spacing: 8, runSpacing: 8, children: [
                        _tag(
                            'العمر',
                            patient.ageYears == null
                                ? 'غير محدد'
                                : '${patient.ageYears} سنة'),
                        _tag(
                            'الوزن',
                            patient.weightKg == null
                                ? 'غير محدد'
                                : '${patient.weightKg} كجم'),
                        _tag(
                            'CrCl',
                            patient.crcl == null
                                ? 'غير محسوب'
                                : '${patient.crcl!.toStringAsFixed(1)} مل/دقيقة'),
                        _tag(
                            'الحمل',
                            !patient.pregnancyStatusKnown
                                ? 'غير محدد'
                                : patient.isPregnant
                                    ? 'نعم'
                                    : 'لا'),
                        _tag('الرضاعة', patient.isLactating ? 'نعم' : 'لا'),
                        _tag('الكبد', patient.childPughClass ?? 'غير محدد')
                      ])),
                if (patient != null)
                  Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton.icon(
                          onPressed: () => _editPatient(clinical, patient),
                          icon: const Icon(Icons.edit),
                          label: const Text('تعديل الملف السريري'))),
                TextField(
                    controller: foods,
                    decoration: const InputDecoration(
                        labelText: 'الأطعمة الحالية (افصل بينها بفاصلة)'),
                    onChanged: (value) => clinical.setFoodIntake(value
                        .split(',')
                        .map((x) => x.trim())
                        .where((x) => x.isNotEmpty)
                        .toList())),
                DropdownButtonFormField<int?>(
                    value: doseDrugId,
                    decoration:
                        const InputDecoration(labelText: 'دواء حاسبة الجرعة'),
                    items: [
                      const DropdownMenuItem<int?>(
                          value: null, child: Text('بدون جرعة مدخلة')),
                      ...pos.cart.map((x) => DropdownMenuItem<int?>(
                          value: x.drug.id, child: Text(x.drug.tradeNameAr)))
                    ],
                    onChanged: (value) => setState(() => doseDrugId = value)),
                TextField(
                    controller: doseMg,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'الجرعة المفردة المدخلة بالملغ (اختياري)')),
                Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton(
                        onPressed: () => clinical.evaluateCart(
                            pos.cart.map((x) => x.drug).toList(),
                            doses: doseDrugId == null ||
                                    double.tryParse(doseMg.text) == null
                                ? const {}
                                : {doseDrugId!: double.parse(doseMg.text)}),
                        child: const Text('إعادة الفحص'))),
                const Divider(),
                if (clinical.verdict.alerts.isEmpty)
                  const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('لا توجد تنبيهات مسجلة لهذه السلة حالياً.',
                          textAlign: TextAlign.center)),
                for (final alert in clinical.verdict.alerts)
                  Card(
                      child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(children: [
                                  _level(alert.level),
                                  const SizedBox(width: 8),
                                  Expanded(
                                      child: Text(alert.category,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold)))
                                ]),
                                const SizedBox(height: 6),
                                Text(alert.messageAr),
                                if (alert.recommendation.isNotEmpty)
                                  Text(alert.recommendation,
                                      style: const TextStyle(
                                          color: Colors.white70)),
                                if (alert.userDecision != null)
                                  Text('تم توثيق القرار: ${alert.userDecision}',
                                      style: const TextStyle(
                                          color: Color(0xff66BB6A))),
                                if (alert.userDecision == null)
                                  Wrap(spacing: 6, children: [
                                    if (alert.level == ClinicalLevel.info ||
                                        alert.level == ClinicalLevel.caution)
                                      TextButton(
                                          onPressed: () => _decide(
                                              clinical,
                                              alert,
                                              'ACKNOWLEDGED',
                                              session.currentUser?['id']
                                                  as int?),
                                          child: const Text('إقرار')),
                                    if (alert.level == ClinicalLevel.warning)
                                      FilledButton(
                                          onPressed: () async {
                                            if (reason.text.trim().length < 5) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(const SnackBar(
                                                      content: Text(
                                                          'اكتب سبباً لا يقل عن خمسة أحرف')));
                                              return;
                                            }
                                            await _decide(
                                                clinical,
                                                alert,
                                                'ACKNOWLEDGED',
                                                session.currentUser?['id']
                                                    as int?,
                                                reason.text.trim());
                                          },
                                          child: const Text('توثيق التجاوز')),
                                    TextButton(
                                        onPressed: () async {
                                          final id = alert.drugId;
                                          if (id != null) {
                                            final matches = pos.cart
                                                .where((x) => x.drug.id == id)
                                                .toList();
                                            if (matches.isNotEmpty) {
                                              await _decide(
                                                  clinical,
                                                  alert,
                                                  'CANCELLED_ITEM',
                                                  session.currentUser?['id']
                                                      as int?);
                                              pos.removeItem(matches.first);
                                            }
                                          }
                                        },
                                        child: const Text('حذف الصنف')),
                                    TextButton(
                                        onPressed: () async {
                                          final id = alert.drugId;
                                          if (id != null) {
                                            final matches = pos.cart
                                                .where((x) => x.drug.id == id)
                                                .toList();
                                            if (matches.isNotEmpty) {
                                              var replaced = false;
                                              await S05DrugAlternativesSheet
                                                  .show(context,
                                                      matches.first.drug,
                                                      (replacement) {
                                                pos.replaceCartItem(
                                                    matches.first, replacement);
                                                replaced = true;
                                              });
                                              if (replaced) {
                                                await _decide(
                                                    clinical,
                                                    alert,
                                                    'SUBSTITUTED',
                                                    session.currentUser?['id']
                                                        as int?);
                                                await clinical.evaluateCart(pos
                                                    .cart
                                                    .map((item) => item.drug)
                                                    .toList());
                                              }
                                            }
                                          }
                                        },
                                        child: const Text('استبدال ببديل آمن')),
                                    if (alert.level == ClinicalLevel.block)
                                      TextButton(
                                          onPressed: () async {
                                            final ok =
                                                await ManagerPinDialog.show(
                                                    context,
                                                    verifier: session
                                                        .verifyManagerPin);
                                            if (ok &&
                                                reason.text.trim().length >=
                                                    5) {
                                              final managerId = session
                                                  .consumeVerifiedManagerUserId();
                                              if (managerId != null)
                                                await _decide(
                                                    clinical,
                                                    alert,
                                                    'OVERRIDDEN_WITH_PIN',
                                                    session.currentUser?['id']
                                                        as int?,
                                                    reason.text.trim(),
                                                    managerId);
                                            }
                                          },
                                          child:
                                              const Text('تجاوز برمز المدير')),
                                  ]),
                                if (alert.level == ClinicalLevel.warning ||
                                    alert.level == ClinicalLevel.block)
                                  TextField(
                                      controller: reason,
                                      decoration: const InputDecoration(
                                          labelText: 'سبب القرار (إلزامي)'),
                                      maxLines: 2),
                              ]))),
                ExpansionTile(
                    title: const Text('مصفوفة التفاعلات التقاطعية'),
                    leading: const Icon(Icons.hub),
                    children: [
                      for (final alert in clinical.verdict.alerts
                          .where((a) => a.category == 'INTERACTION'))
                        ListTile(
                            title: Text(
                                'دواء ${alert.drugId ?? '—'} ↔ دواء ${alert.otherDrugId ?? 'غذاء'}'),
                            subtitle: Text(alert.messageAr),
                            trailing: _level(alert.level)),
                      if (clinical.verdict.alerts
                          .where((a) => a.category == 'INTERACTION')
                          .isEmpty)
                        const ListTile(
                            title: Text('لا توجد تفاعلات مرصودة حالياً')),
                    ]),
                ExpansionTile(
                    title: const Text('حاسبة جرعة الأطفال بالوزن'),
                    leading: const Icon(Icons.child_care),
                    children: [
                      for (final alert in clinical.verdict.alerts.where((a) =>
                          a.category == 'PEDIATRIC' ||
                          a.category == 'DOSE_EXCEEDED'))
                        ListTile(
                            title: Text(alert.messageAr),
                            subtitle: Text(alert.recommendation),
                            trailing: _level(alert.level)),
                      if (clinical.verdict.alerts
                          .where((a) =>
                              a.category == 'PEDIATRIC' ||
                              a.category == 'DOSE_EXCEEDED')
                          .isEmpty)
                        const ListTile(
                            title: Text(
                                'اختر ملف طفل بوزن معروف لإظهار حساب الجرعة')),
                    ]),
                const SizedBox(height: 8),
                Text(
                    'التنبيهات غير المحسومة: ${clinical.verdict.alerts.where((a) => (a.level == ClinicalLevel.warning || a.level == ClinicalLevel.block) && a.userDecision == null).length}'),
              ]))),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إغلاق')),
        FilledButton(
            onPressed: clinical.verdict.hasUnresolvedCritical
                ? null
                : () => Navigator.pop(context, true),
            child: const Text('اعتماد الفحص'))
      ],
    );
  }

  Future<void> _editPatient(
      ClinicalAndRxProvider provider, PatientClinicalModel patient) async {
    final age = TextEditingController(text: patient.ageYears?.toString() ?? '');
    final weight =
        TextEditingController(text: patient.weightKg?.toString() ?? '');
    final height =
        TextEditingController(text: patient.heightCm?.toString() ?? '');
    final creatinine =
        TextEditingController(text: patient.serumCreatinine?.toString() ?? '');
    final egfr =
        TextEditingController(text: patient.egfrMlMin?.toString() ?? '');
    final allergy = TextEditingController(text: patient.allergies.join(', '));
    var sex = patient.sex;
    bool? pregnant = patient.pregnancyStatusKnown ? patient.isPregnant : null;
    var lactating = patient.isLactating;
    var trimester = patient.pregnancyTrimester;
    var childPugh = patient.childPughClass;
    final save = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, setDialogState) => AlertDialog(
                    title: const Text('تعديل الملف السريري'),
                    content: SizedBox(
                        width: 520,
                        child: SingleChildScrollView(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              TextField(
                                  controller: age,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                      labelText: 'العمر بالسنوات')),
                              DropdownButtonFormField<String>(
                                  value: sex,
                                  decoration:
                                      const InputDecoration(labelText: 'الجنس'),
                                  items: const [
                                    DropdownMenuItem(
                                        value: 'M', child: Text('ذكر')),
                                    DropdownMenuItem(
                                        value: 'F', child: Text('أنثى'))
                                  ],
                                  onChanged: (v) =>
                                      setDialogState(() => sex = v ?? 'M')),
                              TextField(
                                  controller: weight,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration: const InputDecoration(
                                      labelText: 'الوزن كجم')),
                              TextField(
                                  controller: height,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration: const InputDecoration(
                                      labelText: 'الطول سم')),
                              DropdownButtonFormField<bool?>(
                                  value: pregnant,
                                  decoration: const InputDecoration(
                                      labelText: 'حالة الحمل'),
                                  items: const [
                                    DropdownMenuItem<bool?>(
                                        value: null, child: Text('غير محددة')),
                                    DropdownMenuItem<bool?>(
                                        value: false, child: Text('غير حامل')),
                                    DropdownMenuItem<bool?>(
                                        value: true, child: Text('حامل'))
                                  ],
                                  onChanged: (v) =>
                                      setDialogState(() => pregnant = v)),
                              if (pregnant == true)
                                DropdownButtonFormField<int>(
                                    value: trimester,
                                    decoration: const InputDecoration(
                                        labelText: 'ثلث الحمل'),
                                    items: const [
                                      DropdownMenuItem(
                                          value: 1, child: Text('الأول')),
                                      DropdownMenuItem(
                                          value: 2, child: Text('الثاني')),
                                      DropdownMenuItem(
                                          value: 3, child: Text('الثالث'))
                                    ],
                                    onChanged: (v) =>
                                        setDialogState(() => trimester = v)),
                              SwitchListTile(
                                  value: lactating,
                                  onChanged: (v) =>
                                      setDialogState(() => lactating = v),
                                  title: const Text('مرضع')),
                              TextField(
                                  controller: creatinine,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration: const InputDecoration(
                                      labelText: 'كرياتينين المصل')),
                              TextField(
                                  controller: egfr,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration: const InputDecoration(
                                      labelText: 'CrCl / eGFR يدوي (اختياري)')),
                              DropdownButtonFormField<String>(
                                  value: childPugh,
                                  decoration: const InputDecoration(
                                      labelText: 'Child-Pugh'),
                                  items: const [
                                    DropdownMenuItem(
                                        value: null, child: Text('غير محدد')),
                                    DropdownMenuItem(
                                        value: 'A', child: Text('A')),
                                    DropdownMenuItem(
                                        value: 'B', child: Text('B')),
                                    DropdownMenuItem(
                                        value: 'C', child: Text('C'))
                                  ],
                                  onChanged: (v) =>
                                      setDialogState(() => childPugh = v)),
                              TextField(
                                  controller: allergy,
                                  decoration: const InputDecoration(
                                      labelText:
                                          'الحساسيات (افصل بينها بفاصلة)')),
                            ]))),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('إلغاء')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('حفظ'))
                    ])));
    if (save == true) {
      final years = int.tryParse(age.text);
      final now = DateTime.now();
      final updated = PatientClinicalModel(
          id: patient.id,
          partyId: patient.partyId,
          fullName: patient.fullName,
          birthDate: years == null
              ? patient.birthDate
              : DateTime(now.year - years, now.month, now.day),
          sex: sex,
          weightKg: double.tryParse(weight.text),
          heightCm: double.tryParse(height.text),
          isPregnant: pregnant ?? false,
          pregnancyStatusKnown: pregnant != null,
          pregnancyTrimester: pregnant == true ? trimester : null,
          isLactating: lactating,
          serumCreatinine: double.tryParse(creatinine.text),
          egfrMlMin: double.tryParse(egfr.text),
          renalStage: patient.renalStage,
          childPughClass: childPugh,
          allergiesJson: jsonEncode(allergy.text
              .split(',')
              .map((x) => x.trim())
              .where((x) => x.isNotEmpty)
              .toList()),
          chronicConditionsJson: patient.chronicConditionsJson,
          currentMedsJson: patient.currentMedsJson);
      await provider.updatePatient(updated);
    }
    for (final controller in [age, weight, height, creatinine, egfr, allergy]) {
      controller.dispose();
    }
  }

  Widget _tag(String label, String value) =>
      Chip(label: Text('$label: $value'));
  Widget _level(ClinicalLevel level) {
    final color = switch (level) {
      ClinicalLevel.block => const Color(0xffEF5350),
      ClinicalLevel.warning => const Color(0xffFFB74D),
      ClinicalLevel.caution => const Color(0xff4DB6AC),
      ClinicalLevel.info => Colors.blueGrey
    };
    return Chip(
        backgroundColor: color.withValues(alpha: .18),
        label: Text(level.name.toUpperCase(), style: TextStyle(color: color)));
  }

  Future<void> _decide(
      ClinicalAndRxProvider p, ClinicalAlertModel a, String decision, int? user,
      [String? why, int? manager]) async {
    await p.decideAlert(a,
        decision: decision, userId: user, reason: why, managerUserId: manager);
  }
}
