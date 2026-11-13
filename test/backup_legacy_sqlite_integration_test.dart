import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/database_helper.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/backup_and_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory root;
  late DatabaseHelper helper;
  late BackupAndSyncService service;
  late Directory backupDirectory;

  Future<Database> snapshotDb(File file) =>
      openDatabase(file.path, readOnly: true, singleInstance: false);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('pharmacy_backup_test_');
    backupDirectory = Directory('${root.path}/backups');
    final source = await openDatabase('${root.path}/pharmacy.db',
        singleInstance: false);
    await source.execute('PRAGMA journal_mode=WAL');
    await source.execute(
        'CREATE TABLE system_settings (setting_no INTEGER PRIMARY KEY, setting_value TEXT)');
    await source.execute('''
CREATE TABLE backup_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT, backup_at TEXT, trigger_type TEXT,
  file_path TEXT, size_bytes INTEGER, sha256 TEXT, encrypted INTEGER,
  result TEXT, user_id INTEGER
)''');
    await source.execute('''
CREATE TABLE audit_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT, event_at TEXT, user_id INTEGER,
  branch_id INTEGER, device_id TEXT, action TEXT, entity_type TEXT,
  entity_id INTEGER, entity_label TEXT, old_values_json TEXT,
  new_values_json TEXT, reason TEXT, severity TEXT, prev_hash TEXT, row_hash TEXT
)''');
    await source.execute(
        'CREATE TABLE test_data (id INTEGER PRIMARY KEY, payload TEXT NOT NULL)');
    await source.insert('test_data', {'id': 1, 'payload': 'كميات الصيدلية'});
    helper = DatabaseHelper.forTesting(source);
    service = BackupAndSyncService(
      helper: helper,
      backupDirectoryForTesting: backupDirectory,
      forceLegacyCopyForTesting: true,
    );
  });

  tearDown(() async {
    await helper.close();
    await root.delete(recursive: true);
  });

  test('legacy Android SQLite path copies a consistent WAL snapshot', () async {
    final result = await service.createBackup(compress: false);
    expect(await result.file.exists(), isTrue);
    expect(result.compressed, isFalse);

    final snapshot = await snapshotDb(result.file);
    try {
      final data = await snapshot.query('test_data');
      expect(data.single['payload'], 'كميات الصيدلية');
      expect((await snapshot.rawQuery('PRAGMA quick_check')).single.values.single,
          'ok');
    } finally {
      await snapshot.close();
    }
    expect((await (await helper.database).query('test_data')).length, 1);
    final rows = await (await helper.database).query('backup_log');
    expect(rows.single['sha256'],
        sha256.convert(await result.file.readAsBytes()).toString());
  });

  test('legacy fallback supports gzip and never damages the live database',
      () async {
    final result = await service.createBackup(compress: true);
    expect(result.compressed, isTrue);
    expect(result.file.path.endsWith('.db.gz'), isTrue);
    expect(await result.file.exists(), isTrue);
    expect(await (await helper.database).query('test_data'), hasLength(1));
    final log = await (await helper.database).query('backup_log');
    expect(log.single['result'], 'SUCCESS');
    expect(log.single['size_bytes'], result.sizeBytes);
  });

  test('modern SQLite continues to use VACUUM INTO when supported', () async {
    final modern = BackupAndSyncService(
      helper: helper,
      backupDirectoryForTesting: backupDirectory,
    );
    final sqliteVersion = (await (await helper.database)
            .rawQuery('SELECT sqlite_version() AS version'))
        .single['version']
        .toString();
    final bits = sqliteVersion.split('.');
    final modernAvailable = int.parse(bits[0]) > 3 ||
        (int.parse(bits[0]) == 3 && int.parse(bits[1]) >= 27);
    if (!modernAvailable) return;
    final result = await modern.createBackup(compress: false);
    final snapshot = await snapshotDb(result.file);
    try {
      expect((await snapshot.query('test_data')).single['payload'],
          'كميات الصيدلية');
    } finally {
      await snapshot.close();
    }
  });
}
