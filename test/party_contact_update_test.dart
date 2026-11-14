import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/database_helper.dart';
import 'package:global_enterprise_pharmacy_erp/providers/session_and_erp_provider.dart';

class _SessionWithoutFullRefresh extends SessionAndErpProvider {
  _SessionWithoutFullRefresh(superDb) : super(database: superDb);
  int refreshed = 0;
  @override
  Future<void> refresh() async {
    refreshed++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => sqfliteFfiInit());

  test('editing contact keeps UUID, balances, and other branches unchanged',
      () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    try {
      await db.execute('''CREATE TABLE parties (
        id INTEGER PRIMARY KEY, branch_id INTEGER NOT NULL, is_deleted INTEGER NOT NULL DEFAULT 0,
        uuid TEXT NOT NULL, name_ar TEXT NOT NULL, phone TEXT, opening_alayh REAL NOT NULL,
        opening_lah REAL NOT NULL, credit_limit REAL NOT NULL,
        sync_status TEXT NOT NULL, sync_version INTEGER NOT NULL, updated_at TEXT NOT NULL
      )''');
      await db.execute('''CREATE TABLE audit_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT, event_at TEXT, user_id INTEGER,
        branch_id INTEGER, device_id TEXT, action TEXT, entity_type TEXT,
        entity_id INTEGER, entity_label TEXT, old_values_json TEXT, new_values_json TEXT,
        reason TEXT, severity TEXT, prev_hash TEXT, row_hash TEXT
      )''');
      final old = {
        'uuid': 'unchanged-uuid',
        'name_ar': 'عميل قديم',
        'phone': '000000000',
        'opening_alayh': 100.0,
        'opening_lah': 0.0,
        'credit_limit': 500.0,
        'sync_status': 'SYNCED',
        'sync_version': 3,
        'updated_at': '2026-11-13T00:00:00Z',
      };
      await db.insert('parties', {...old, 'id': 1, 'branch_id': 1});
      await db.insert('parties', {...old, 'id': 2, 'branch_id': 2});
      final session = _SessionWithoutFullRefresh(DatabaseHelper.forTesting(db));
      session.branchId = 1;
      await session.updatePartyContact(
          partyId: 1, nameAr: 'اسم جديد', phone: '+967777123456');
      final changed =
          (await db.query('parties', where: 'id=?', whereArgs: [1])).single;
      final other =
          (await db.query('parties', where: 'id=?', whereArgs: [2])).single;
      expect(changed['name_ar'], 'اسم جديد');
      expect(changed['phone'], '+967777123456');
      expect(changed['uuid'], 'unchanged-uuid');
      expect(changed['opening_alayh'], 100);
      expect(changed['credit_limit'], 500);
      expect(changed['sync_version'], 4);
      expect(changed['sync_status'], 'LOCAL');
      expect(other['name_ar'], 'عميل قديم');
      expect(other['phone'], '000000000');
      expect(session.refreshed, 1);
      expect(await db.query('audit_logs'), hasLength(1));
      await expectLater(
        session.updatePartyContact(
          partyId: 2,
          nameAr: 'ممنوع',
          phone: '000',
        ),
        throwsStateError,
      );
      expect(
          (await db.query('parties', where: 'id=?', whereArgs: [2]))
              .single['name_ar'],
          'عميل قديم');
      expect(await db.query('audit_logs'), hasLength(1));
      session.dispose();
    } finally {
      await db.close();
    }
  });
}
