import 'dart:convert';

import 'package:flutter/material.dart';

/// Compact editor for the existing JSON columns; does not alter their schema.
class DrugJsonEditorField extends StatefulWidget {
  const DrugJsonEditorField({
    super.key,
    required this.fieldKey,
    required this.label,
    required this.controller,
  });

  final String fieldKey;
  final String label;
  final TextEditingController controller;

  @override
  State<DrugJsonEditorField> createState() => _DrugJsonEditorFieldState();
}

class _DrugJsonEditorFieldState extends State<DrugJsonEditorField> {
  static const _names = [
    'name', 'ingredient', 'name_ar', 'active', 'inn_name', 'ingredient_name'
  ];

  String? _nameKey(Object? element) {
    if (element is! Map) return null;
    for (final key in _names) {
      if (element[key] is String) return key;
    }
    return null;
  }

  String _name(Object? element) {
    if (element is String) return element;
    final key = _nameKey(element);
    return key == null ? '' : (element as Map)[key] as String;
  }

  Object? _parse(String raw) {
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }

  String _summary(String raw) {
    if (raw.trim().isEmpty) return 'لا توجد بيانات';
    final value = _parse(raw);
    if (value is List) {
      if (value.isEmpty) return 'لا توجد بيانات';
      if (widget.fieldKey == 'ingredients_json') {
        final names = value
            .map(_name)
            .where((name) => name.trim().isNotEmpty)
            .take(2)
            .join('، ');
        return value.length.toString() + ' مكونات' +
            (names.isEmpty ? ' محفوظة' : ': ' + names);
      }
      return value.length.toString() + ' عناصر محفوظة';
    }
    if (value is Map) return value.length.toString() + ' حقول محفوظة';
    return 'بيانات موجودة؛ افتح لمراجعتها';
  }

  Future<void> _edit() async {
    final original = widget.controller.text;
    final value = original.trim().isEmpty &&
            widget.fieldKey == 'ingredients_json'
        ? <dynamic>[]
        : _parse(original);
    final structured = widget.fieldKey == 'ingredients_json' &&
        value is List &&
        value.every((element) =>
            element is String || (element is Map && _nameKey(element) != null));
    final items =
        structured ? List<Object?>.from(value as List) : <Object?>[];
    final controllers = <TextEditingController>[
      for (final item in items) TextEditingController(text: _name(item)),
    ];
    final disposedLater = <TextEditingController>[];
    final rawController = TextEditingController(
      text: value == null
          ? original
          : const JsonEncoder.withIndent('  ').convert(value),
    );
    var changed = false;
    String? error;

    final route = DialogRoute<void>(
      context: context,
      builder: (routeContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          insetPadding: const EdgeInsets.all(12),
          title: Text(widget.label),
          content: SizedBox(
            width: MediaQuery.sizeOf(context).width.clamp(0.0, 560.0).toDouble(),
            height: (MediaQuery.sizeOf(context).height -
                    MediaQuery.viewInsetsOf(context).bottom -
                    190)
                .clamp(160.0, 460.0)
                .toDouble(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  structured
                      ? 'عدّل أسماء المكونات أو أضف مكونًا. التفاصيل السابقة محفوظة.'
                      : 'محتوى تفصيلي محفوظ. عدّله عند الحاجة فقط.',
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: structured
                      ? ListView.builder(
                          itemCount: controllers.length,
                          itemBuilder: (context, index) => Row(
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: TextField(
                                    key: ValueKey('drug-ingredient-' + index.toString()),
                                    controller: controllers[index],
                                    decoration: InputDecoration(
                                      labelText: 'المكون ' + (index + 1).toString(),
                                    ),
                                    onChanged: (_) => changed = true,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'حذف المكون',
                                icon: const Icon(Icons.remove_circle_outline),
                                onPressed: () => refresh(() {
                                  changed = true;
                                  items.removeAt(index);
                                  disposedLater.add(controllers.removeAt(index));
                                }),
                              ),
                            ],
                          ),
                        )
                      : TextField(
                          key: const ValueKey('drug-json-raw-editor'),
                          controller: rawController,
                          expands: true,
                          minLines: null,
                          maxLines: null,
                          textAlignVertical: TextAlignVertical.top,
                          keyboardType: TextInputType.multiline,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            hintText: 'البيانات التفصيلية',
                          ),
                          onChanged: (_) => changed = true,
                        ),
                ),
                if (structured)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () => refresh(() {
                        changed = true;
                        items.add({'name': ''});
                        controllers.add(TextEditingController());
                      }),
                      icon: const Icon(Icons.add),
                      label: const Text('إضافة مكون'),
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
              onPressed: () {
                if (!changed) {
                  Navigator.pop(routeContext);
                  return;
                }
                if (structured) {
                  final names =
                      controllers.map((c) => c.text.trim()).toList();
                  if (names.any((name) => name.isEmpty)) {
                    refresh(() => error = 'اكتب اسم المكون أو احذف السطر الفارغ');
                    return;
                  }
                  final updated = <Object?>[];
                  for (var i = 0; i < items.length; i++) {
                    final entry = items[i];
                    if (entry is String) {
                      updated.add(names[i]);
                    } else {
                      final item = Map<String, dynamic>.from(entry as Map);
                      item[_nameKey(entry)!] = names[i];
                      updated.add(item);
                    }
                  }
                  widget.controller.text = jsonEncode(updated);
                } else {
                  final candidate = rawController.text.trim();
                  try {
                    final parsed = jsonDecode(candidate);
                    if (parsed is! List && parsed is! Map) {
                      refresh(() => error = 'المحتوى يجب أن يكون قائمة أو مجموعة حقول');
                      return;
                    }
                    widget.controller.text = candidate;
                  } on FormatException {
                    refresh(() => error = 'تنسيق البيانات غير صحيح؛ لم تُحفظ التغييرات');
                    return;
                  }
                }
                Navigator.pop(routeContext);
              },
              child: const Text('حفظ التعديل'),
            ),
          ],
        ),
      ),
    );
    await Navigator.of(context, rootNavigator: true).push<void>(route);
    // Route.pop completes before its exit animation; keep controllers alive
    // until the overlay no longer contains any of these TextFields.
    await route.completed;
    for (final controller in [...controllers, ...disposedLater, rawController]) {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: widget.controller,
        builder: (context, value, _) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: OutlinedButton(
            key: ValueKey('drug-json-' + widget.fieldKey),
            onPressed: _edit,
            child: Row(
              children: [
                const Icon(Icons.list_alt_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.label,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(
                        _summary(value.text),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.edit_outlined, size: 18),
              ],
            ),
          ),
        ),
      );
}
