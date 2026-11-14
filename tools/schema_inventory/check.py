"""Audit literal SQLite table/view declarations across all production Dart files.

This is a fail-closed source inventory, not a Dart/SQL interpreter. Runtime schema
coverage is checked separately in test/database_schema_test.dart.
"""
import argparse
from collections import Counter
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
CREATE_PREFIX = re.compile(r'\bCREATE\s+(?:VIRTUAL\s+)?(?:TABLE|VIEW)\s+', re.I)
CREATE = re.compile(r'\bCREATE\s+(?P<virtual>VIRTUAL\s+)?(?P<kind>TABLE|VIEW)\s+'
                    r'(?:IF\s+NOT\s+EXISTS\s+)?(?P<name>[A-Za-z_][A-Za-z_0-9]*)\b', re.I)
RENAME_PREFIX = re.compile(r'\bALTER\s+TABLE\s+\w+\s+RENAME\s+TO\s+', re.I)
RENAME = re.compile(r'\bALTER\s+TABLE\s+\w+\s+RENAME\s+TO\s+(?P<name>[A-Za-z_][A-Za-z_0-9]*)\b', re.I)
CATEGORIES = {'syncable': 'قابل للمزامنة بالحقول المعتمدة', 'local': 'محلي',
              'sensitive': 'حساس / غير معتمد للنقل', 'derived': 'مشتق'}


def scan_text(text, source):
    found = {}
    for prefix, pattern, rename in [(CREATE_PREFIX, CREATE, False), (RENAME_PREFIX, RENAME, True)]:
        for start in prefix.finditer(text):
            match = pattern.match(text, start.start())
            if not match or match.group('name').upper() in {'IF', 'NOT', 'EXISTS'}:
                raise ValueError(f'Unresolved schema declaration: {source}:{text.count(chr(10), 0, start.start()) + 1}')
            name = match.group('name')
            kind = 'table' if rename else ('virtual_table' if match.group('virtual') else match.group('kind').lower())
            record = found.setdefault(name, {'kind': kind, 'sources': []})
            if record['kind'] != kind:
                raise ValueError(f'Conflicting object kind: {name}')
            record['sources'].append({'path': source, 'line': text.count('\n', 0, start.start()) + 1,
                                      'operation': 'rename' if rename else 'create'})
    return found


def discover(root):
    result = {}
    for path in sorted((root / 'lib').rglob('*.dart')):
        for name, entry in scan_text(path.read_text(encoding='utf-8'), path.relative_to(root).as_posix()).items():
            if name in result:
                if result[name]['kind'] != entry['kind']:
                    raise ValueError(f'Conflicting object kind: {name}')
                result[name]['sources'].extend(entry['sources'])
            else:
                result[name] = entry
    if not result:
        raise ValueError('No schema objects found')
    return result


def read_allowlist(root):
    source = (root / 'lib/data/services/sync_table_policy.dart').read_text(encoding='utf-8')
    match = re.search(r'outboundTables\s*=\s*\{(.*?)\};', source, re.S)
    if not match:
        raise ValueError('Cannot locate explicit outbound table policy')
    return set(re.findall(r"'([a-z_][a-z_0-9]*)'", match.group(1)))


def validate(objects, registry, allowed):
    missing, stale = objects.keys() - registry.keys(), registry.keys() - objects.keys()
    if missing or stale:
        raise ValueError(f'Unclassified: {sorted(missing)}; stale: {sorted(stale)}')
    classified_allowed = set()
    for name, item in registry.items():
        if item['classification'] not in CATEGORIES or not item['reason_ar'].strip():
            raise ValueError(f'Invalid classification/reason: {name}')
        if item['lifecycle'] not in {'schema', 'conditional', 'legacy'}:
            raise ValueError(f'Invalid lifecycle: {name}')
        if type(item['sync_allowed']) is not bool:
            raise ValueError(f'Invalid sync flag: {name}')
        if item['sync_allowed']:
            classified_allowed.add(name)
            if item['classification'] != 'syncable' or objects[name]['kind'] != 'table':
                raise ValueError(f'Unsafe sync classification: {name}')
        elif item['classification'] == 'syncable':
            raise ValueError(f'Contradictory sync flag: {name}')
    if classified_allowed != allowed:
        raise ValueError(f'Allowlist drift: {sorted(classified_allowed ^ allowed)}')


def render(objects, data):
    registry = data['objects']
    counts = Counter(x['classification'] for x in registry.values())
    kinds = Counter(x['kind'] for x in objects.values())
    lines = ['# جرد مخطط SQLite وتصنيف المزامنة — P0-04', '',
             f"المصدر المراجع: `{data['reviewed_commit']}`؛ قاعدة البيانات v{data['schema_version']}.", '',
             'هذا جرد لجميع تعريفات TABLE وVIRTUAL TABLE وVIEW وأهداف RENAME في ملفات lib/**/*.dart، بما فيها الترحيلات والخدمات والمستودعات. تعدد تعريف جدول في الترحيلات لا يزيد العدد.', '',
             f"**الإجمالي: {len(objects)} اسمًا**: {kinds['table']} أسماء جداول عادية (تشمل أسماء الترحيل القديمة والإنشاء المشروط)، و{kinds['virtual_table']} جدول افتراضي، و{kinds['view']} عروض. ليست جميعها موجودة معاً في كل قاعدة جهاز.", '',
             '| التصنيف | العدد |', '|---|---:|']
    lines += [f'| {label} | {counts[key]} |' for key, label in CATEGORIES.items()]
    lines += ['', '## حدود الاعتماد', '',
              '- «قابل للمزامنة» يصف قائمة السماح البرمجية الحالية فقط، ولا يثبت سلامة دورة مالية أو تشغيل جهازين. الحقول تحكمها sync_payload_policy.dart.',
              '- لا يغيّر هذا الجرد قائمة السماح أو قاعدة البيانات، ولا يفعّل Firebase.',
              '- الجداول المالية والشخصية غير المعتمدة تبقى محظورة. أرصدة وحركات المخزون المرتبطة بها تحتاج P0-05 وP0-06 قبل اعتماد التشغيل.',
              f'- فحص المصدر لا ينفذ Dart ولا SQL ولا يدعي استخراج كل عمود أو كل علاقة. اختبار قاعدة البيانات يقارن الجداول والعروض الفعلية في إنشاء v{data["schema_version"]} بالجرد؛ تغير صيغة DDL أو استعمال أسماء ديناميكية يتطلب تحديث الفاحص ومراجعة صريحة.',
              '- الأسماء القديمة تنشأ حسب مسار الترحيل؛ branch_identity_provisioning ينشأ عند اعتماد الهوية، وcatalog_cache_fts ينشأ عند توفر FTS5.',
              '- sqlite_sequence وsqlite_stat* كائنات داخلية تديرها SQLite. جداول FTS5 الداخلية catalog_cache_fts_data وcatalog_cache_fts_idx وcatalog_cache_fts_docsize وcatalog_cache_fts_config مشتقة من الفهرس وليست جداول أعمال أو أهداف مزامنة مستقلة.', '',
              '## الجرد التفصيلي', '',
              '| الاسم | النوع / دورة الإنشاء | التصنيف | المزامنة الحالية | السبب | مصادر التعريف |',
              '|---|---|---|---|---|---|']
    for name, obj in sorted(objects.items()):
        item = registry[name]
        sources = '، '.join(f"[{s['path'].split('/')[-1]}:{s['line']}](../{s['path']}#L{s['line']})" for s in obj['sources'])
        lines.append(f"| `{name}` | {obj['kind']} / {item['lifecycle']} | {CATEGORIES[item['classification']]} | {'مسموحة بالحقول المعتمدة' if item['sync_allowed'] else 'محظورة'} | {item['reason_ar']} | {sources} |")
    lines += ['', '## نقاط تسليم إلى P0-05 وP0-06', '',
              '- sales_invoice_item_batches.invoice_item_id يشير إلى بنود بيع غير مسموح بمزامنتها حالياً؛ لا يكفي نقل توزيع التشغيلات منفرداً.',
              '- batches_fefo.purchase_invoice_item_id وdisposals.journal_entry_id ومراجع doc_id/doc_line_id/source_doc_id تحتاج عقد تحويل مراجع وعمليات مركبة؛ بعضها ليس FK معلناً في SQLite.',
              '- number_sequences يحتاج سياسة ترقيم متعددة الأجهزة، ولا يجوز حل تعارضاته بنسخ last_no.',
              '- لا تُعاد توليد قيود journal_entries/journal_lines من إسقاط مالي مستقبَل؛ يثبت العقد المالي وحدة العملية ومنع التطبيق مرتين.', '',
              '## إعادة التحقق', '', '```sh', 'python tools/schema_inventory/check.py --check',
              'python -m unittest discover -s tools/schema_inventory -p "test_*.py"',
              'flutter test test/database_schema_test.dart', '```', '',
              'بعد تعديل التعريفات أو التصنيف، شغّل `python tools/schema_inventory/check.py --write` ثم راجع الفرق وشغّل --check. الفاحص لا يصنف جدولاً جديداً تلقائياً.', '']
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--write', action='store_true')
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    objects = discover(ROOT)
    data = json.loads((ROOT / 'docs/SYNC_SCHEMA_CLASSIFICATION.json').read_text(encoding='utf-8'))
    validate(objects, data['objects'], read_allowlist(ROOT))
    output = render(objects, data)
    path = ROOT / 'docs/SYNC_SCHEMA_INVENTORY.md'
    if args.write:
        path.write_text(output, encoding='utf-8')
    elif not path.exists() or path.read_text(encoding='utf-8') != output:
        raise ValueError('Inventory document is stale; run --write and review the diff')
    print(f'Inventory verified: {len(objects)} objects, {len(read_allowlist(ROOT))} allowed tables')


if __name__ == '__main__':
    main()
