import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/backup_and_sync_service.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/manual_backup_file_service.dart';

void main() {
  test('user may edit Arabic name, while suffix always matches backup bytes',
      () {
    expect(BackupFileName.fileName('نسخة الصيدلية', compressed: true),
        'نسخة الصيدلية.db.gz');
    expect(BackupFileName.fileName('نسخة الأدوية.db.gz', compressed: true),
        'نسخة الأدوية.db.gz');
    expect(BackupFileName.fileName('my-backup.db', compressed: false),
        'my-backup.db');
    expect(BackupFileName.fileName('my-backup.db.gz', compressed: false),
        'my-backup.db');
  });

  test('invalid names and path injection are rejected before export', () {
    for (final invalid in ['', '  ', '..', '../pharmacy', r'C:\backup',
      'test/name', 'CON', 'A*B', 'hello?world', 'name.']) {
      expect(() => BackupFileName.baseName(invalid), throwsFormatException,
          reason: invalid);
    }
  });

  test('native Save As is passed exact verified bytes, name and extension',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('custom_backup_picker_');
    try {
      final original = File('${directory.path}/trusted.db.gz');
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      await original.writeAsBytes(bytes, flush: true);
      final checksum = sha256.convert(bytes).toString();
      var opened = 0;
      final service = ManualBackupFileService(
        savePicker: (name, payload) async {
          opened++;
          expect(name, 'نسخة تجريبية.db.gz');
          expect(payload, orderedEquals(bytes));
          return 'user-selected-destination';
        },
      );
      final result = await service.saveVerifiedCopy(
        source: BackupResult(
          file: original, sha256: checksum,
          sizeBytes: bytes.length, compressed: true,
        ),
        requestedName: 'نسخة تجريبية',
      );
      expect(result, 'user-selected-destination');
      expect(opened, 1);
      expect(await original.readAsBytes(), bytes,
          reason: 'Export must never modify the trusted original.');
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('wrong checksum prevents any export picker from opening', () async {
    final directory =
        await Directory.systemTemp.createTemp('unsafe_backup_export_');
    try {
      final original = File('${directory.path}/trusted.db');
      await original.writeAsBytes([1, 2, 3], flush: true);
      var invoked = false;
      final service = ManualBackupFileService(
        savePicker: (_, __) async {
          invoked = true;
          return 'must-not-run';
        },
      );
      await expectLater(
        service.saveVerifiedCopy(
          source: BackupResult(
            file: original, sha256: 'wrong',
            sizeBytes: 3, compressed: false,
          ),
          requestedName: 'test',
        ),
        throwsStateError,
      );
      expect(invoked, isFalse);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('picker cancellation does not touch the verified private backup',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('cancel_backup_picker_');
    try {
      final original = File('${directory.path}/trusted.db');
      final bytes = [10, 20, 30];
      await original.writeAsBytes(bytes, flush: true);
      final result = await ManualBackupFileService(
        savePicker: (_, __) async => null,
      ).saveVerifiedCopy(
        source: BackupResult(
          file: original,
          sha256: sha256.convert(bytes).toString(),
          sizeBytes: 3,
          compressed: false,
        ),
        requestedName: 'يومية',
      );
      expect(result, isNull);
      expect(await original.readAsBytes(), bytes);
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
