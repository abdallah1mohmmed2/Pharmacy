import 'package:flutter/material.dart';

import '../../data/database/database_helper.dart';

enum DrugReferenceKind { manufacturer, ingredient, category }

class DrugReferenceChoice {
  const DrugReferenceChoice(this.id, this.title);
  final int id;
  final String title;
}

typedef DrugReferenceSearcher = Future<List<DrugReferenceChoice>> Function(
    DrugReferenceKind kind, String query, int branchId);

/// Search only 30 references at a time instead of loading full catalogs.
class DrugReferenceLookup {
  DrugReferenceLookup({DatabaseHelper? helper})
      : _helper = helper ?? DatabaseHelper.instance;
  final DatabaseHelper _helper;

  Future<List<DrugReferenceChoice>> search(
      DrugReferenceKind kind, String query, int branchId) async {
    final (table, labelExpression, searchColumns, branchScoped) =
        switch (kind) {
      DrugReferenceKind.manufacturer => (
          'manufacturers',
          "COALESCE(NULLIF(name_ar,''),name_en)",
          const ['name_ar', 'name_en'],
          false
        ),
      DrugReferenceKind.ingredient => (
          'active_ingredients',
          "COALESCE(NULLIF(name_ar,''),inn_name)",
          const ['name_ar', 'inn_name'],
          false
        ),
      DrugReferenceKind.category => (
          'drug_categories',
          "COALESCE(NULLIF(name_ar,''),name_en,code)",
          const ['name_ar', 'name_en', 'code'],
          true
        ),
    };
    final text = query.trim();
    final escaped = text
        .replaceAll('\\', '\\\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    final pattern = '%$escaped%';
    final sql = StringBuffer(
        'SELECT id, $labelExpression AS display_name FROM $table WHERE is_deleted=0');
    final params = <Object?>[];
    if (branchScoped) {
      sql.write(' AND branch_id=?');
      params.add(branchId);
    }
    if (text.isNotEmpty) {
      sql.write(' AND (');
      sql.write(searchColumns
          .map((name) => "COALESCE($name,'') LIKE ? ESCAPE '\\'")
          .join(' OR '));
      sql.write(')');
      params.addAll(List.filled(searchColumns.length, pattern));
    }
    sql.write(' ORDER BY display_name,id LIMIT 30');
    final rows = await _helper.rawQuery(sql.toString(), params);
    return rows
        .map((row) => DrugReferenceChoice(
              row['id'] as int,
              (row['display_name']?.toString().trim().isNotEmpty ?? false)
                  ? row['display_name'].toString()
                  : 'مرجع رقم ${row['id']}',
            ))
        .toList(growable: false);
  }
}

/// UI looks up a reference by name while the controller retains the original ID.
class DrugReferencePickerField extends StatefulWidget {
  const DrugReferencePickerField({
    super.key,
    required this.fieldKey,
    required this.label,
    required this.kind,
    required this.controller,
    required this.branchId,
    this.searcher,
  });

  final String fieldKey, label;
  final DrugReferenceKind kind;
  final TextEditingController controller;
  final int branchId;
  final DrugReferenceSearcher? searcher;

  @override
  State<DrugReferencePickerField> createState() =>
      _DrugReferencePickerFieldState();
}

class _DrugReferencePickerFieldState extends State<DrugReferencePickerField> {
  String? _selectedTitle;

  Future<void> _pick() async {
    final search = widget.searcher ?? DrugReferenceLookup().search;
    var results = search(widget.kind, '', widget.branchId);
    final chosen = await showModalBottomSheet<DrugReferenceChoice>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (sheetContext, setSheetState) => SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(sheetContext).height * .76,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('اختيار ${widget.label}',
                        style: Theme.of(sheetContext).textTheme.titleMedium),
                    const SizedBox(height: 10),
                    TextField(
                      key: ValueKey('drug-ref-search-${widget.fieldKey}'),
                      autofocus: true,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        labelText: 'بحث بالاسم أو الرمز',
                      ),
                      onChanged: (query) => setSheetState(() {
                        results = search(widget.kind, query, widget.branchId);
                      }),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: FutureBuilder<List<DrugReferenceChoice>>(
                        future: results,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState !=
                              ConnectionState.done) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }
                          if (snapshot.hasError) {
                            return const Center(
                              child: Text('تعذر البحث. يمكنك المحاولة مجدداً.'),
                            );
                          }
                          final items =
                              snapshot.data ?? const <DrugReferenceChoice>[];
                          if (items.isEmpty) {
                            return const Center(
                                child: Text('لا توجد نتائج مطابقة.'));
                          }
                          return ListView.builder(
                            itemCount: items.length,
                            itemBuilder: (context, index) => ListTile(
                              key: ValueKey(
                                  'drug-ref-choice-${items[index].id}'),
                              title: Text(items[index].title),
                              subtitle:
                                  Text('الرقم المرجعي: ${items[index].id}'),
                              onTap: () =>
                                  Navigator.of(context).pop(items[index]),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    if (!mounted || chosen == null) return;
    setState(() => _selectedTitle = chosen!.title);
    widget.controller.text = chosen.id.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              key: ValueKey('drug-reference-${widget.fieldKey}'),
              onPressed: _pick,
              icon: const Icon(Icons.manage_search),
              label: Text(
                widget.controller.text.trim().isEmpty
                    ? 'اختيار ${widget.label}'
                    : '${widget.label}: ${_selectedTitle ?? 'رقم ${widget.controller.text}'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (widget.controller.text.trim().isNotEmpty)
            IconButton(
              tooltip: 'إلغاء اختيار ${widget.label}',
              onPressed: () {
                widget.controller.clear();
                setState(() => _selectedTitle = null);
              },
              icon: const Icon(Icons.clear),
            ),
        ],
      ),
    );
  }
}
