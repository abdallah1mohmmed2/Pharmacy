import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';

import 'backup_and_sync_service.dart';

typedef BackupSavePicker = Future<String?> Function(
    String fileName, Uint8List bytes);

/// Only the display name is user-controlled. It never becomes a path into the
/// private backup directory, or the live database.
abstract final class BackupFileName {
  static String baseName(String value) {
    var base = value.trim();
    if (base.toLowerCase().endsWith('.db.gz')) {
      base = base.substring(0, base.length - 6);
    } else if (base.toLowerCase().endsWith('.db')) {
      base = base.substring(0, base.length - 3);
    }
    base = base.trim();
    if (base.isEmpty ||
        base == '.' ||
        base == '..' ||
        base.length > 100 ||
        RegExp(r'[<>:"/\\|?*\x00-\x1f]').hasMatch(base) ||
        base.endsWith('.') ||
        base.endsWith(' ') ||
        RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$', caseSensitive: false)
            .hasMatch(base)) {
      throw const FormatException(
          'اسم النسخة غير صالح؛ تجنب علامات المسارات والرموز المحجوزة.');
    }
    return base;
  }

  static String fileName(String requested, {required bool compressed}) =>
      '${baseName(requested)}${compressed ? '.db.gz' : '.db'}';
}

/// Keeps the original verified private backup unchanged and copies its exact
/// bytes via the platform native Save As chooser. Android SAF destination
/// cannot be written to with dart:io File(path).
class ManualBackupFileService {
  ManualBackupFileService({BackupSavePicker? savePicker})
      : _savePicker = savePicker ?? _nativeSave;
  final BackupSavePicker _savePicker;

  static Future<String?> _nativeSave(String name, Uint8List bytes) =>
      FilePicker.platform.saveFile(
        dialogTitle: 'اختيار اسم ومكان حفظ النسخة الاحتياطية',
        fileName: name,
        type: FileType.any,
        bytes: bytes,
      );

  Future<String?> saveVerifiedCopy({
    required BackupResult source,
    required String requestedName,
  }) async {
    final name = BackupFileName.fileName(
      requestedName,
      compressed: source.compressed,
    );
    final data = await source.file.readAsBytes();
    final calculated = sha256.convert(data).toString();
    if (data.isEmpty ||
        calculated != source.sha256 ||
        data.length != source.sizeBytes) {
      throw StateError(
          'فشل التحقق من سلامة النسخة الداخلية؛ لم يتم تصدير ملف غير موثوق.');
    }
    return _savePicker(name, Uint8List.fromList(data));
  }
}
