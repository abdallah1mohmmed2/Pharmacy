part of 'drug_import_export_service.dart';

/// Resolves an import-only name without trusting foreign database IDs.
/// Preview never writes; execution calls this inside the drug row savepoint.
Future<int?> _manufacturerReference(
    DatabaseExecutor db, Map<String, Object?> row, int branchId,
    {required bool create}) async {
  final name = (row['manufacturer_name'] ?? '').toString().trim();
  if (name.isEmpty) return row['manufacturer_id'] as int?;
  if (name.length > 300) {
    throw const FormatException('اسم الشركة أطول من 300 حرف');
  }
  final key = name.toLowerCase();
  final id = row['manufacturer_id'];
  final matches = await db.query('manufacturers',
      where: 'branch_id=? AND is_deleted=0 AND '
          '(LOWER(TRIM(name_ar))=? OR LOWER(TRIM(name_en))=?)',
      whereArgs: [branchId, key, key],
      limit: 2);
  if (matches.length > 1) {
    throw const FormatException('اسم الشركة ملتبس؛ حدد الشركة برقمها');
  }
  if (id != null && (matches.isEmpty || matches.single['id'] != id)) {
    throw const FormatException('اسم الشركة لا يطابق رقمها في الفرع الحالي');
  }
  if (matches.isNotEmpty) return matches.single['id'] as int;
  if (!create) return null;
  final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
  final uuid = '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  final now = DateTime.now().toIso8601String();
  return db.insert('manufacturers', {
    'uuid': uuid,
    'branch_id': branchId,
    'created_at': now,
    'updated_at': now,
    'name_ar': name,
    'name_en': name,
  });
}
