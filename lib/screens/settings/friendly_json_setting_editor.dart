import 'package:flutter/material.dart';
import '../../core/constants/setting_keys.dart';
import 'friendly_settings_labels.dart';

/// The UI edits the original JSON map, not a new schema. Unknown keys survive
/// unchanged, and existing settings validation/audit/manager PIN remain upstream.
class FriendlyJsonSettingEditor extends StatefulWidget {
  const FriendlyJsonSettingEditor({
    super.key,
    required this.spec,
    required this.initialValue,
  });
  final SettingSpec spec;
  final Map<String, Object?> initialValue;

  @override
  State<FriendlyJsonSettingEditor> createState() =>
      _FriendlyJsonSettingEditorState();
}

class _FriendlyJsonSettingEditorState extends State<FriendlyJsonSettingEditor> {
  final _form = GlobalKey<FormState>();
  late final Map<String, Object?> values;

  @override
  void initState() {
    super.initState();
    values = Map<String, Object?>.from(widget.initialValue);
  }

  Widget _switch(String key, String label, {String? hint}) =>
      SwitchListTile.adaptive(
        key: ValueKey('setting-json-switch-' + key),
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        subtitle: hint == null ? null : Text(hint),
        value: values[key] == true,
        onChanged: (enabled) => setState(() => values[key] = enabled),
      );

  Widget _choice(
    String key,
    String label,
    List<String> options, {
    void Function(String)? whenChanged,
  }) {
    final current = values[key]?.toString() ?? '';
    final allOptions = [
      ...options,
      if (!options.contains(current)) current,
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<String>(
        key: ValueKey('setting-json-choice-' + key),
        isExpanded: true,
        value: current,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final option in allOptions)
            DropdownMenuItem<String>(
              value: option,
              child: Text(
                option.isEmpty
                    ? 'غير محدد'
                    : FriendlySettingsLabels.choice(option),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (next) {
          if (next == null) return;
          setState(() {
            values[key] = next;
            whenChanged?.call(next);
          });
        },
      ),
    );
  }

  Widget _text(String key, String label,
      {int maxLines = 1,
      bool isSecret = false,
      TextInputType? keyboardType,
      String? hint,
      String? Function(String?)? validator}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        key: ValueKey('setting-json-text-' + key +
            (key == 'symbol' ? (values['code']?.toString() ?? '') : '')),
        initialValue: values[key]?.toString() ?? '',
        keyboardType: keyboardType ??
            (maxLines > 1 ? TextInputType.multiline : TextInputType.text),
        obscureText: isSecret,
        maxLines: isSecret ? 1 : maxLines,
        decoration: InputDecoration(labelText: label, helperText: hint),
        validator: validator,
        onChanged: (text) => values[key] = text,
        onSaved: (text) => values[key] = text ?? '',
      ),
    );
  }

  Widget _number(
    String key,
    String label, {
    required num minimum,
    required num maximum,
    bool integer = false,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        key: ValueKey('setting-json-number-' + key),
        initialValue: (values[key] ?? minimum).toString(),
        keyboardType: TextInputType.numberWithOptions(decimal: !integer),
        decoration: InputDecoration(labelText: label, helperText: hint),
        validator: (text) {
          final n = integer ? int.tryParse(text?.trim() ?? '') :
              num.tryParse(text?.trim() ?? '');
          if (n == null || n < minimum || n > maximum) {
            return 'أدخل قيمة بين ' + minimum.toString() +
                ' و' + maximum.toString();
          }
          return null;
        },
        onChanged: (text) {
          final parsed = integer ? int.tryParse(text.trim()) :
              num.tryParse(text.trim());
          if (parsed != null) values[key] = parsed;
        },
        onSaved: (text) {
          values[key] = integer ? int.parse(text!.trim()) :
              num.parse(text!.trim()).toDouble();
        },
      ),
    );
  }

  Future<void> _chooseLockDate() async {
    final old = values['locked_through']?.toString();
    DateTime? initial = old == null ? null : DateTime.tryParse(old);
    final now = DateTime.now();
    initial ??= DateTime(now.year, now.month, now.day);
    final next = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'اختر آخر يوم تريد قفل العمليات قبله أو عنده',
    );
    if (next == null || !mounted) return;
    setState(() => values['locked_through'] =
        next.toIso8601String().substring(0, 10));
  }

  Widget _lockDate() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'لا يسمح النظام بتسجيل عمليات مالية بتاريخ يقع في الفترة المقفلة. '
        'تغيير التاريخ يحتاج إلى اعتماد المدير.',
      ),
      const SizedBox(height: 12),
      Text(values['locked_through'] == null
          ? 'لا يوجد تاريخ قفل محدد'
          : 'الفترات مقفلة حتى ' + values['locked_through'].toString()),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        children: [
          OutlinedButton.icon(
            key: const ValueKey('setting-period-pick-date'),
            onPressed: _chooseLockDate,
            icon: const Icon(Icons.calendar_month),
            label: const Text('اختيار تاريخ القفل'),
          ),
          TextButton(
            key: const ValueKey('setting-period-clear-date'),
            onPressed: values['locked_through'] == null
                ? null : () => setState(() => values['locked_through'] = null),
            child: const Text('إلغاء تحديد التاريخ'),
          ),
        ],
      ),
    ],
  );

  Widget _currency() => Column(
    children: [
      _choice('code', 'نوع العملة', ['YER', 'SAR', 'USD', 'EUR'],
          whenChanged: (code) {
        final defaults = <String, (String, int)>{
          'YER': ('ر.ي', 0), 'SAR': ('ر.س', 2),
          'USD': (r', 'EUR': ('€', 2),
        };
        if (defaults.containsKey(code)) {
          values['symbol'] = defaults[code]!.$1;
          values['decimals'] = defaults[code]!.$2;
        }
      }),
      _text('symbol', 'رمز العملة'),
      _choice('decimals', 'عدد المنازل العشرية', ['0', '2', '3']),
      const Text('تغيير العملة لا يحوّل أرصدة العمليات السابقة أو أسعارها.'),
    ],
  );

  Widget _sections() {
    switch (widget.spec.key) {
      case SettingKey.reportHeaderFooter:
        return Column(children: [
          _text('header', 'النص الذي يظهر أعلى التقرير', maxLines: 3),
          _text('footer', 'النص الذي يظهر أسفل التقرير', maxLines: 3),
        ]);
      case SettingKey.currency:
        return _currency();
      case SettingKey.periodLock:
        return _lockDate();
      case SettingKey.vat:
        return Column(children: [
          _switch('enabled', 'تفعيل ضريبة القيمة المضافة'),
          _number('rate_pct', 'نسبة الضريبة (%)',
              minimum: 0, maximum: 100, hint: 'مثال: 15'),
        ]);
      case SettingKey.reportPaper:
        return Column(children: [
          _choice('size', 'حجم الورق', ['A4']),
          _choice('orientation', 'اتجاه الصفحة', ['portrait', 'landscape']),
          const Text(
            'يتوفر حجم A4 حاليًا في قالب الطباعة التجريبي. '
            'قد تختلف إعدادات التقارير الأخرى بحسب نوع التقرير.',
          ),
        ]);
      case SettingKey.autoLocalOnClose:
        return Column(children: [
          _switch('enabled', 'إنشاء نسخة احتياطية تلقائيًا'),
          _number('keep_last', 'عدد النسخ الداخلية المحتفظ بها',
              minimum: 1, maximum: 1000, integer: true),
          _switch('compress', 'ضغط النسخة لتوفير مساحة التخزين'),
        ]);
      case SettingKey.cloudSync:
        return Column(children: [
          _switch('enabled', 'تشغيل المزامنة السحابية',
              hint: 'لا تُفعّلها قبل إكمال الربط والصلاحيات.'),
          const SizedBox(height: 4),
          ExpansionTile(
            key: const ValueKey('setting-cloud-advanced'),
            title: const Text('إعداد الاتصال بالخادم'),
            subtitle: const Text('مخصص لمسؤول تهيئة النظام'),
            children: [
              _choice('provider', 'خدمة المزامنة', ['firestore']),
              _text('project_id', 'معرّف مشروع Firebase'),
              _text('api_key', 'مفتاح ربط Firebase', isSecret: true),
              _text('database_id', 'معرّف قاعدة Firestore',
                  hint: 'استخدم (default) عند الاعتماد على القاعدة الرئيسية.'),
              _number('batch_size', 'عدد السجلات في كل دفعة',
                  minimum: 1, maximum: 1000, integer: true),
            ],
          ),
        ]);
      default:
        return const Text('هذا الإعداد غير متاح للتحرير هنا.');
    }
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    _form.currentState!.save();
    // Preserve data types, including integers, when a choice is selected.
    if (widget.spec.key == SettingKey.currency) {
      values['decimals'] = int.tryParse(values['decimals'].toString()) ??
          widget.initialValue['decimals'] ?? 0;
    }
    Navigator.of(context).pop(Map<String, Object?>.from(values));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(FriendlySettingsLabels.title(widget.spec)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(FriendlySettingsLabels.explanation(widget.spec)),
                const SizedBox(height: 16),
                _sections(),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: const ValueKey('friendly-settings-save'),
          onPressed: _save,
          child: const Text('حفظ الإعداد'),
        ),
      ],
    );
  }
}
, 2), 'EUR': ('€', 2),
        };
        if (defaults.containsKey(code)) {
          values['symbol'] = defaults[code]!.$1;
          values['decimals'] = defaults[code]!.$2;
        }
      }),
      _text('symbol', 'رمز العملة'),
      _choice('decimals', 'عدد المنازل العشرية', ['0', '2', '3']),
      const Text('تغيير العملة لا يحوّل أرصدة العمليات السابقة أو أسعارها.'),
    ],
  );

  Widget _sections() {
    switch (widget.spec.key) {
      case SettingKey.reportHeaderFooter:
        return Column(children: [
          _text('header', 'النص الذي يظهر أعلى التقرير', maxLines: 3),
          _text('footer', 'النص الذي يظهر أسفل التقرير', maxLines: 3),
        ]);
      case SettingKey.currency:
        return _currency();
      case SettingKey.periodLock:
        return _lockDate();
      case SettingKey.vat:
        return Column(children: [
          _switch('enabled', 'تفعيل ضريبة القيمة المضافة'),
          _number('rate_pct', 'نسبة الضريبة (%)',
              minimum: 0, maximum: 100, hint: 'مثال: 15'),
        ]);
      case SettingKey.reportPaper:
        return Column(children: [
          _choice('size', 'حجم الورق', ['A4']),
          _choice('orientation', 'اتجاه الصفحة', ['portrait', 'landscape']),
          const Text(
            'يتوفر حجم A4 حاليًا في قالب الطباعة التجريبي. '
            'قد تختلف إعدادات التقارير الأخرى بحسب نوع التقرير.',
          ),
        ]);
      case SettingKey.autoLocalOnClose:
        return Column(children: [
          _switch('enabled', 'إنشاء نسخة احتياطية تلقائيًا'),
          _number('keep_last', 'عدد النسخ الداخلية المحتفظ بها',
              minimum: 1, maximum: 1000, integer: true),
          _switch('compress', 'ضغط النسخة لتوفير مساحة التخزين'),
        ]);
      case SettingKey.cloudSync:
        return Column(children: [
          _switch('enabled', 'تشغيل المزامنة السحابية',
              hint: 'لا تُفعّلها قبل إكمال الربط والصلاحيات.'),
          const SizedBox(height: 4),
          ExpansionTile(
            key: const ValueKey('setting-cloud-advanced'),
            title: const Text('إعداد الاتصال بالخادم'),
            subtitle: const Text('مخصص لمسؤول تهيئة النظام'),
            children: [
              _choice('provider', 'خدمة المزامنة', ['firestore']),
              _text('project_id', 'معرّف مشروع Firebase'),
              _text('api_key', 'مفتاح ربط Firebase', isSecret: true),
              _text('database_id', 'معرّف قاعدة Firestore',
                  hint: 'استخدم (default) عند الاعتماد على القاعدة الرئيسية.'),
              _number('batch_size', 'عدد السجلات في كل دفعة',
                  minimum: 1, maximum: 1000, integer: true),
            ],
          ),
        ]);
      default:
        return const Text('هذا الإعداد غير متاح للتحرير هنا.');
    }
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    _form.currentState!.save();
    // Preserve data types, including integers, when a choice is selected.
    if (widget.spec.key == SettingKey.currency) {
      values['decimals'] = int.tryParse(values['decimals'].toString()) ??
          widget.initialValue['decimals'] ?? 0;
    }
    Navigator.of(context).pop(Map<String, Object?>.from(values));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(FriendlySettingsLabels.title(widget.spec)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(FriendlySettingsLabels.explanation(widget.spec)),
                const SizedBox(height: 16),
                _sections(),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: const ValueKey('friendly-settings-save'),
          onPressed: _save,
          child: const Text('حفظ الإعداد'),
        ),
      ],
    );
  }
}
