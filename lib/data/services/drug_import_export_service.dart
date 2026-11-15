// lib/data/services/drug_import_export_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/drug_model.dart';
import 'drug_import_field_catalog.dart';
import '../models/settings_audit_sync_models.dart';
import 'settings_and_audit_service.dart';

part 'drug_import_export_streaming.dart';

/// A bounded sample of *actual values from the selected file*, resolved to
/// the real SQLite/model column (or explicitly flagged as protected/unmapped).
class DrugImportColumnPreview {
  const DrugImportColumnPreview({
    required this.sourceField,
    required this.targetField,
    required this.sampleValue,
    required this.status,
  });

  final String sourceField;
  final String targetField;
  final String sampleValue;
  final String status;

  String get targetLabel => DrugImportFieldCatalog.label(targetField);
  bool get willImport => DrugImportFieldCatalog.isEditable(targetField);
}

class ImportRowIssue {
  const ImportRowIssue(this.rowNumber, this.message);
  final int rowNumber;
  final String message;
}

class ImportDryRunResult {
  const ImportDryRunResult(
      {required this.totalRows,
      required this.validRows,
      required this.errors,
      required this.duplicates,
      this.barcodeDuplicates = 0});
  final int totalRows, validRows, duplicates, barcodeDuplicates;
  final List<ImportRowIssue> errors;
}

class ImportExecutionResult {
  const ImportExecutionResult(
      {required this.jobId,
      required this.inserted,
      required this.updated,
      required this.skipped,
      required this.errors,
      this.barcodeConflicts = 0});
  final int jobId, inserted, updated, skipped, errors, barcodeConflicts;
}

class DrugImportExportService {
  DrugImportExportService({DatabaseHelper? helper, http.Client? client})
      : _helper = helper ?? DatabaseHelper.instance,
        _client = client ?? http.Client();
  final DatabaseHelper _helper;
  final http.Client _client;
  static const List<String> clinicalPointColumns = [
    'trade_name_ar',
    'trade_name_en',
    'scientific_name',
    'ingredients_json',
    'therapeutic_class',
    'indications',
    'dosage_administration',
    'contraindications',
    'warnings_precautions',
    'interactions_summary',
    'side_effects_common',
    'side_effects_serious',
    'geriatric_notes',
    'pediatric_notes',
    'pregnancy_notes',
    'min_age_months',
    'pregnancy_category',
    'lactation_notes',
    'storage_conditions'
  ];
  static const List<ColumnMappingTemplate> templates = [
    ColumnMappingTemplate(name: 'قالب CSV عربي', columns: {
      'الاسم التجاري': 'trade_name_ar',
      'الاسم العلمي': 'scientific_name',
      'الشركة': 'manufacturer_id',
      'الفئة': 'category_id',
      'التركيز': 'strength_text',
      'الشكل': 'dosage_form',
      'دواعي الاستعمال': 'indications',
      'الجرعة': 'dosage_administration',
      'موانع الاستعمال': 'contraindications',
      'التحذيرات': 'warnings_precautions',
      'التفاعلات': 'interactions_summary',
      'الأعراض الجانبية': 'side_effects_common',
      'الحمل': 'pregnancy_category',
      'التخزين': 'storage_conditions'
    }),
    ColumnMappingTemplate(name: 'قالب قياسي', columns: {
      'brand_name': 'trade_name_en',
      'generic_name': 'scientific_name',
      'indications_and_usage': 'indications',
      'dosage_and_administration': 'dosage_administration',
      'contraindications': 'contraindications',
      'warnings': 'warnings_precautions',
      'drug_interactions': 'interactions_summary',
      'adverse_reactions': 'side_effects_common',
      'pregnancy': 'pregnancy_notes',
      'pediatric_use': 'pediatric_notes',
      'geriatric_use': 'geriatric_notes',
      'storage_and_handling': 'storage_conditions'
    }),
  ];
  Future<List<Map<String, Object?>>> parse(String source,
      {required String format, Map<String, String> mapping = const {}}) async {
    final normalized = format.toUpperCase();
    if (normalized == 'JSON') {
      final decoded = jsonDecode(source);
      final rows = decoded is List
          ? decoded
          : (decoded is Map && decoded['drugs'] is List
              ? decoded['drugs'] as List
              : throw FormatException('يجب أن يحتوي JSON على قائمة أدوية'));
      return rows.map((e) {
        if (e is! Map)
          throw const FormatException('كل صف JSON يجب أن يكون كائناً');
        return _mapFields(Map<String, Object?>.from(e), mapping);
      }).toList();
    }
    if (normalized == 'CSV') {
      final rows =
          const CsvToListConverter(shouldParseNumbers: false).convert(source);
      if (rows.isEmpty) return [];
      final headers = rows.first.map((e) => e.toString().trim()).toList();
      return rows
          .skip(1)
          .where((r) => r.any((e) => e.toString().trim().isNotEmpty))
          .map((r) {
        final sourceRow = <String, Object?>{};
        for (var i = 0; i < headers.length && i < r.length; i++) {
          sourceRow[headers[i]] = r[i];
        }
        return _mapFields(sourceRow, mapping);
      }).toList();
    }
    throw ArgumentError('الصيغة المدعومة CSV أو JSON فقط');
  }

  Map<String, Object?> _mapFields(
      Map<String, Object?> source, Map<String, String> mapping) {
    final result = <String, Object?>{};
    for (final entry in mapping.entries) {
      if (!DrugImportFieldCatalog.isEditable(entry.value)) {
        throw FormatException('حقل الربط غير موجود أو محمي: ' +
            entry.value +
            ' (' +
            entry.key +
            ')');
      }
    }
    bool meaningful(Object? value) =>
        value != null && (value is! String || value.trim().isNotEmpty);
    for (final entry in source.entries) {
      final target = mapping[entry.key] ?? entry.key;
      // IDs, sync metadata and computed stock are exported for reference only.
      if (!mapping.containsKey(entry.key) &&
          DrugImportFieldCatalog.isProtected(target)) {
        continue;
      }
      if (!DrugImportFieldCatalog.isEditable(target)) {
        // A custom mapping may intentionally omit extra external columns.
        if (mapping.isNotEmpty && !mapping.containsKey(entry.key)) continue;
        throw FormatException('حقل غير معروف في الملف: ' +
            entry.key +
            '؛ اربطه بحقل موجود في التطبيق');
      }
      if (!meaningful(entry.value)) continue;
      if (result.containsKey(target)) {
        throw FormatException('أكثر من عمود مرتبط بالحقل: ' + target);
      }
      result[target] = entry.value;
    }
    const intFields = [
      'manufacturer_id',
      'active_ingredient_id',
      'category_id',
      'strips_per_pack',
      'units_per_strip',
      'ped_doses_per_day',
      'min_age_months',
      'max_age_months',
      'geriatric_age_threshold',
      'min_stock_units',
      'reorder_qty_packs'
    ];
    const doubleFields = [
      'strength_value',
      'adult_dose_min_mg',
      'adult_dose_max_mg_per_day',
      'ped_dose_mg_per_kg_min',
      'ped_dose_mg_per_kg_max',
      'ped_max_daily_mg_per_kg',
      'storage_temp_min_c',
      'storage_temp_max_c',
      'cost_price_pack',
      'last_purchase_cost_pack',
      'sell_price_pack',
      'sell_price_strip',
      'sell_price_unit',
      'profit_margin_pct',
      'public_price_pack',
      'tax_rate_pct'
    ];
    const boolFields = [
      'is_active',
      'is_strip_based',
      'has_critical_interactions',
      'is_nephrotoxic',
      'neonate_allowed',
      'requires_refrigeration',
      'protect_from_light',
      'is_controlled',
      'requires_prescription',
      'prescription_restricted',
      'is_antibiotic'
    ];
    for (final key in intFields) {
      if (result[key] != null) {
        final parsed = int.tryParse(result[key].toString());
        if (parsed == null)
          throw FormatException('قيمة عددية غير صحيحة للحقل ' + key);
        result[key] = parsed;
      }
    }
    for (final key in doubleFields) {
      if (result[key] != null) {
        final parsed = double.tryParse(result[key].toString());
        if (parsed == null)
          throw FormatException('قيمة عشرية غير صحيحة للحقل ' + key);
        result[key] = parsed;
      }
    }
    for (final key in boolFields) {
      if (result[key] != null) {
        final raw = result[key].toString().toLowerCase();
        if (!{'1', '0', 'true', 'false', 'yes', 'no'}.contains(raw))
          throw FormatException('قيمة منطقية غير صحيحة للحقل ' + key);
        result[key] = {'1', 'true', 'yes'}.contains(raw) ? 1 : 0;
      }
    }
    const choices = <String, Set<String>>{
      'dosage_form': {
        'TABLET',
        'CAPSULE',
        'SYRUP',
        'SUSPENSION',
        'DROPS',
        'INJECTION',
        'CREAM',
        'OINTMENT',
        'INHALER',
        'SUPPOSITORY',
        'SACHET',
        'OTHER'
      },
      'route': {
        'ORAL',
        'IV',
        'IM',
        'SC',
        'TOPICAL',
        'OPHTHALMIC',
        'INHALATION',
        'RECTAL',
        'OTHER'
      },
      'take_with_food': {'BEFORE', 'WITH', 'AFTER', 'ANY'},
      'strip_price_mode': {'AUTO', 'MANUAL'},
      'hepatic_status': {
        'SAFE',
        'ADJUST',
        'AVOID',
        'CONTRAINDICATED',
        'UNKNOWN'
      },
      'renal_status': {'SAFE', 'ADJUST', 'AVOID', 'CONTRAINDICATED', 'UNKNOWN'},
      'geriatric_status': {'SAFE', 'ADJUST', 'AVOID', 'UNKNOWN'},
      'pediatric_status': {
        'SAFE',
        'ADJUST',
        'AVOID',
        'CONTRAINDICATED',
        'UNKNOWN'
      },
      'pregnancy_category': {'A', 'B', 'C', 'D', 'X', 'N', 'UNKNOWN'},
      'lactation_risk': {'L1', 'L2', 'L3', 'L4', 'L5', 'UNKNOWN'}
    };
    for (final key in result.keys.toList()) {
      final value = result[key];
      if (key.endsWith('_json')) {
        if (value is Map || value is List) {
          result[key] = jsonEncode(value);
        } else if (value is String) {
          final decoded = jsonDecode(value);
          if (decoded is! Map && decoded is! List) {
            throw FormatException(
                'الحقل ' + key + ' يحتاج JSON من نوع كائن أو قائمة');
          }
        } else {
          throw FormatException('صيغة JSON غير صالحة للحقل ' + key);
        }
      } else if (value is Map || value is List) {
        throw FormatException('الحقل ' + key + ' لا يقبل كائناً أو قائمة');
      } else if (value != null && value is! num) {
        result[key] = value.toString();
      }
      if (choices.containsKey(key)) {
        final valueText = result[key].toString().trim().toUpperCase();
        if (!choices[key]!.contains(valueText)) {
          throw FormatException(
              'قيمة غير معتمدة للحقل ' + key + ': ' + result[key].toString());
        }
        result[key] = valueText;
      }
    }
    return result;
  }

  /// A pasted document is handled by the same streaming parser as a picked
  /// file, so preview and save cannot disagree on supported columns.
  Future<ImportDryRunResult> dryRunImport({
    required String source,
    required String format,
    Map<String, String> mapping = const {},
  }) async {
    final dir = await Directory.systemTemp.createTemp('pharmacy-import-');
    try {
      final file = File(dir.path + '/preview.' + format.toLowerCase());
      await file.writeAsString(source, encoding: utf8, flush: true);
      return await dryRunImportFile(
          file: file, format: format, mapping: mapping);
    } finally {
      await dir.delete(recursive: true);
    }
  }

  Future<List<DrugImportColumnPreview>> inspectImportSource({
    required String source,
    required String format,
    Map<String, String> mapping = const {},
  }) async {
    final dir = await Directory.systemTemp.createTemp('pharmacy-inspect-');
    try {
      final file = File(dir.path + '/sample.' + format.toLowerCase());
      await file.writeAsString(source, encoding: utf8, flush: true);
      return await inspectImportFile(
          file: file, format: format, mapping: mapping);
    } finally {
      await dir.delete(recursive: true);
    }
  }

  /// Pasted JSON/CSV uses the same scoped, validated batch transactions
  /// as disk import, without overwriting absent fields with model defaults.
  Future<ImportExecutionResult> executeImport({
    required String source,
    required String format,
    Map<String, String> mapping = const {},
    String conflictPolicy = 'SKIP',
    String? fileName,
    int branchId = 1,
    int batchSize = 100,
    void Function(int done, int total)? onProgress,
  }) async {
    final dir = await Directory.systemTemp.createTemp('pharmacy-import-');
    try {
      final file = File(dir.path + '/input.' + format.toLowerCase());
      await file.writeAsString(source, encoding: utf8, flush: true);
      return await executeImportFile(
        file: file,
        format: format,
        mapping: mapping,
        conflictPolicy: conflictPolicy,
        fileName: fileName,
        branchId: branchId,
        batchSize: batchSize,
        onProgress: onProgress,
      );
    } finally {
      await dir.delete(recursive: true);
    }
  }

  Future<void> _refreshFts(DatabaseExecutor db) async {
    final exists = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='drugs_fts'");
    if (exists.isEmpty) return;
    final cols = await db.rawQuery('PRAGMA table_info(drugs_fts)');
    final names = cols.map((e) => e['name'] as String).toSet();
    if (names.contains('rowid')) return;
    await db.execute('INSERT INTO drugs_fts(drugs_fts) VALUES(\'rebuild\')');
  }

  Future<List<OpenFdaDrugResult>> searchOpenFda(String query,
      {int limit = 20}) async {
    if (query.trim().isEmpty) throw ArgumentError('أدخل اسم الدواء للبحث');
    final uri = Uri.https('api.fda.gov', '/drug/label.json', {
      'search':
          'openfda.brand_name:"${query.trim()}" OR openfda.generic_name:"${query.trim()}"',
      'limit': '${limit.clamp(1, 100)}'
    });
    final response =
        await _client.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode == 404) return [];
    if (response.statusCode != 200)
      throw HttpException('OpenFDA HTTP ${response.statusCode}');
    final decoded = jsonDecode(response.body) as Map<String, Object?>;
    final results = (decoded['results'] as List? ?? const []);
    return results
        .whereType<Map>()
        .map((e) => OpenFdaDrugResult.fromMap(Map<String, Object?>.from(e)))
        .toList();
  }

  DrugModel openFdaToDrug(OpenFdaDrugResult result) {
    String field(String key) => result.fields[key] ?? '';
    return DrugModel(
        isActive: false,
        tradeNameAr: result.brandName,
        tradeNameEn: result.brandName,
        scientificName: result.genericName,
        indications: field('indications_and_usage'),
        dosageAdministration: field('dosage_and_administration'),
        contraindications: field('contraindications'),
        warningsPrecautions: field('warnings'),
        interactionsSummary: field('drug_interactions'),
        sideEffectsCommon: field('adverse_reactions'),
        pregnancyNotes: field('pregnancy'),
        pediatricNotes: field('pediatric_use'),
        geriatricNotes: field('geriatric_use'),
        storageConditions: field('storage_and_handling'),
        pregnancyCategory: 'UNKNOWN');
  }

  Future<File> exportDrugs(
      {required String format,
      bool hideCostPrices = true,
      int? categoryId,
      int branchId = 1,
      Directory? outputDirectory}) async {
    final db = await _helper.database;
    final rows = await db.query('drugs',
        where: categoryId == null
            ? 'is_deleted=0 AND branch_id=?'
            : 'is_deleted=0 AND branch_id=? AND category_id=?',
        whereArgs: categoryId == null ? [branchId] : [branchId, categoryId],
        orderBy: 'trade_name_ar');
    final fields = rows.map((r) {
      final m = Map<String, Object?>.from(r);
      if (hideCostPrices) {
        m.remove('cost_price_pack');
        m.remove('last_purchase_cost_pack');
      }
      return m;
    }).toList();
    final normalized = format.toUpperCase();
    late String data, extension, sourceType;
    if (normalized == 'CSV') {
      final headers = fields.isEmpty ? <String>[] : fields.first.keys.toList();
      data = '\uFEFF' +
          const ListToCsvConverter().convert([
            headers,
            ...fields.map((m) => headers.map((h) => m[h] ?? '').toList())
          ]);
      extension = 'csv';
      sourceType = 'EXPORT_CSV';
    } else if (normalized == 'JSON') {
      data = jsonEncode(fields);
      extension = 'json';
      sourceType = 'EXPORT_JSON';
    } else {
      throw ArgumentError('صيغة التصدير يجب أن تكون CSV أو JSON');
    }
    final directory = outputDirectory ?? await getTemporaryDirectory();
    final file = File(
        '${directory.path}/drug_export_${DateTime.now().millisecondsSinceEpoch}.$extension');
    await file.writeAsString(data, encoding: utf8, flush: true);
    await db.insert('import_jobs', {
      'source_type': sourceType,
      'file_name': file.path,
      'total_rows': fields.length,
      'status': 'COMPLETED',
      'started_at': DateTime.now().toIso8601String(),
      'finished_at': DateTime.now().toIso8601String()
    });
    await AuditService(helper: _helper).record(
        action: 'EXPORT',
        entityType: 'drugs',
        entityLabel: file.path,
        newValues: {
          'format': normalized,
          'rows': fields.length,
          'hide_cost_prices': hideCostPrices
        });
    return file;
  }

  Future<List<ImportJobModel>> listJobs() async =>
      (await _helper.query('import_jobs', orderBy: 'id DESC'))
          .map(ImportJobModel.fromMap)
          .toList();
}
