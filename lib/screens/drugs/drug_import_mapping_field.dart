import 'dart:convert';

import 'package:flutter/material.dart';

/// Edits the existing JSON map of CSV/JSON source columns to database fields.
/// An untouched or cancelled dialog never rewrites the saved representation.
class DrugImportMappingField extends StatefulWidget {
  const DrugImportMappingField({
    super.key,
    required this.controller,
    this.onChanged,
  });

  final TextEditingController controller;
  final VoidCallback? onChanged;

  @override
  State<DrugImportMappingField> createState() => _DrugImportMappingFieldState();
}

class _DrugImportMappingFieldState extends State<DrugImportMappingField> {
  static Map<String, String>? _decode(String raw) {
    if (raw.trim().isEmpty) return <String, String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final result = <String, String>{};
      for (final entry in decoded.entries) {
        if (entry.key is! String || entry.value is! String) return null;
        result[entry.key as String] = entry.value as String;
      }
      return result;
    } on FormatException {
      return null;
    }
  }

  Future<void> _edit() async {
    final original = widget.controller.text;
    final mapping = _decode(original);
    final sources = <TextEditingController>[
      if (mapping != null)
        for (final key in mapping.keys) TextEditingController(text: key),
    ];
    final targets = <TextEditingController>[
      if (mapping != null)
        for (final target in mapping.values)
          TextEditingController(text: target),
    ];
    final removedControllers = <TextEditingController>[];
    final raw = TextEditingController(text: original);
    var modified = false;
    String? error;

    final route = DialogRoute<void>(
      context: context,
      builder: (routeContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('ربط أعمدة الاستيراد'),
          insetPadding: const EdgeInsets.all(12),
          content: SizedBox(
            width: MediaQuery.sizeOf(context).width.clamp(0.0, 590.0).toDouble(),
            height: (MediaQuery.sizeOf(context).height -
                    MediaQuery.viewInsetsOf(context).bottom -
                    190)
                .clamp(170.0, 480.0)
                .toDouble(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(mapping == null
                    ? 'تنسيق الربط القديم غير معروف. يمكن تصحيحه يدويًا دون فقد المحتوى الأصلي.'
                    : 'اربط اسم العمود الموجود في الملف بالحقل المطلوب داخل النظام.'),
                const SizedBox(height: 8),
                Expanded(
                  child: mapping == null
                      ? TextField(
                          key: const ValueKey('import-mapping-raw-editor'),
                          controller: raw,
                          maxLines: null,
                          minLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          keyboardType: TextInputType.multiline,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'البيانات الأصلية للربط',
                          ),
                          onChanged: (_) => modified = true,
                        )
                      : ListView.builder(
                          itemCount: sources.length,
                          itemBuilder: (context, index) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextField(
                                  key: ValueKey('import-mapping-source-' +
                                      index.toString()),
                                  controller: sources[index],
                                  decoration: const InputDecoration(
                                    labelText: 'اسم العمود في الملف',
                                    isDense: true,
                                  ),
                                  onChanged: (_) => modified = true,
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        key: ValueKey('import-mapping-target-' +
                                            index.toString()),
                                        controller: targets[index],
                                        decoration: const InputDecoration(
                                          labelText: 'حقل النظام',
                                          isDense: true,
                                        ),
                                        onChanged: (_) => modified = true,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'حذف الربط',
                                      icon: const Icon(
                                          Icons.remove_circle_outline),
                                      onPressed: () => refresh(() {
                                        modified = true;
                                        removedControllers
                                            .add(sources.removeAt(index));
                                        removedControllers
                                            .add(targets.removeAt(index));
                                      }),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
                if (mapping != null)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      key: const ValueKey('import-mapping-add'),
                      onPressed: () => refresh(() {
                        modified = true;
                        sources.add(TextEditingController());
                        targets.add(TextEditingController());
                      }),
                      icon: const Icon(Icons.add),
                      label: const Text('إضافة ربط'),
                    ),
                  ),
                if (error != null)
                  Text(error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(routeContext),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              key: const ValueKey('import-mapping-save'),
              onPressed: () {
                if (!modified) {
                  Navigator.pop(routeContext);
                  return;
                }
                if (mapping == null) {
                  if (_decode(raw.text) == null) {
                    refresh(() => error = 'الربط يجب أن يكون JSON يحتوي على أسماء حقول نصية');
                    return;
                  }
                  widget.controller.text = raw.text;
                } else {
                  final output = <String, String>{};
                  for (var i = 0; i < sources.length; i++) {
                    final from = sources[i].text.trim();
                    final to = targets[i].text.trim();
                    if (from.isEmpty || to.isEmpty) {
                      refresh(() => error = 'اكتب اسم العمود وحقل النظام لكل ربط');
                      return;
                    }
                    if (output.containsKey(from)) {
                      refresh(() => error = 'اسم العمود مكرر: ' + from);
                      return;
                    }
                    output[from] = to;
                  }
                  widget.controller.text = jsonEncode(output);
                }
                widget.onChanged?.call();
                Navigator.pop(routeContext);
              },
              child: const Text('حفظ الربط'),
            ),
          ],
        ),
      ),
    );
    await Navigator.of(context, rootNavigator: true).push<void>(route);
    await route.completed;
    for (final controller in [
      ...sources,
      ...targets,
      ...removedControllers,
      raw,
    ]) {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: widget.controller,
        builder: (context, value, _) {
          final parsed = _decode(value.text);
          final count = parsed?.length;
          return OutlinedButton.icon(
            key: const ValueKey('import-mapping-open'),
            onPressed: _edit,
            icon: const Icon(Icons.tune_outlined),
            label: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ربط أعمدة الملف بحقول النظام'),
                Text(
                  count == null
                      ? 'صيغة الربط تحتاج إلى مراجعة'
                      : count == 0
                          ? 'لا يوجد ربط مخصص؛ سيستخدم النظام أسماء الحقول الموجودة'
                          : count.toString() + ' أعمدة مرتبطة',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          );
        },
      );
}
