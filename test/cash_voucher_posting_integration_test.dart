import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:global_enterprise_pharmacy_erp/data/database/database_helper.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/global_uuid.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_builder.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration2.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration3.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration4.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration5.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration6.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration7.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration8.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration9.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration10.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration11.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration12.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/seed_data.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/posting_and_sales_service.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/cash_voucher_integrity_validator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database database;
  late PostingAndSalesService posting;
  late int partyId;
  late int cashId;

  Future<void> provisionReferenceUuids() async {
    // Test-only assignments for master records with legacy seed placeholders.
    // Production identity migration MUST NOT randomize historic UUIDs.
    final accountCodes = <String, String>{
      '1102': '11111111-1111-4111-8111-111111111111',
      '1201': '22222222-2222-4222-8222-222222222222',
      '2101': '33333333-3333-4333-8333-333333333333',
    };
    for (final entry in accountCodes.entries) {
      await database.update('chart_of_accounts', {'uuid': entry.value},
          where: 'code=?', whereArgs: [entry.key]);
    }
    await database.update(
        'cash_accounts', {'uuid': '44444444-4444-4444-8444-444444444444'},
        where: 'code=?', whereArgs: ['CASH-DRAWER']);
  }

  Future<int> post(String type) => posting.postVoucher(
      branchId: 1,
      voucherNo: 'ignored-by-sequence',
      voucherType: type,
      partyId: partyId,
      cashAccountId: cashId,
      amount: 125.25,
      method: 'CASH',
      description: 'real-schema test voucher');

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys=ON');
        },
      ),
    );
    await SchemaBuilder.build(database);
    await SchemaIteration12.upgrade(database);
    await SeedData.run(database);
    await SchemaIteration2.upgrade(database);
    await SchemaIteration3.upgrade(database);
    await SchemaIteration4.upgrade(database);
    await SchemaIteration5.upgrade(database);
    await SchemaIteration6.upgrade(database);
    await SchemaIteration7.upgrade(database);
    await SchemaIteration8.upgrade(database);
    await SchemaIteration9.upgrade(database);
    await SchemaIteration10.upgrade(database);
    await SchemaIteration11.upgrade(database);
    await SchemaIteration12.upgrade(database);

    partyId = await database.insert('parties', {
      'uuid': '55555555-5555-4555-8555-555555555555',
      'branch_id': 1,
      'created_at': '2026-11-09T00:00:00',
      'updated_at': '2026-11-09T00:00:00',
      'sync_status': 'LOCAL',
      'sync_version': 1,
      'party_type': 'CUSTOMER',
      'code': 'VOUCHER-INTEGRATION-TEST',
      'name_ar': 'اختبار سند',
    });
    cashId = (await database.query('cash_accounts',
            columns: ['id'], where: 'code=?', whereArgs: ['CASH-DRAWER']))
        .single['id'] as int;
    posting =
        PostingAndSalesService(helper: DatabaseHelper.forTesting(database));
  });

  tearDown(() => database.close());

  for (final type in ['RECEIPT', 'PAYMENT']) {
    test('actual $type voucher posts a complete balanced document', () async {
      await provisionReferenceUuids();
      final id = await post(type);
      final result = await CashVoucherIntegrityValidator.validate(
          database: database, branchId: 1, voucherId: id, fractionDigits: 2);
      expect(result.amountMinor, 12525);
      expect(GlobalUuid.isValid(result.voucherUuid), isTrue);
      expect(GlobalUuid.isValid(result.journalUuid), isTrue);
      final rows = await database.query('journal_lines',
          where:
              'journal_entry_id=(SELECT journal_entry_id FROM vouchers WHERE id=?)',
          whereArgs: [id]);
      expect(rows, hasLength(2));
      for (final row in rows) {
        expect(GlobalUuid.isValid(row['uuid'] as String), isTrue);
      }
      expect(await database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    });
  }

  test('legacy seed reference UUIDs block financial readiness', () async {
    final id = await post('RECEIPT');
    await expectLater(
      CashVoucherIntegrityValidator.validate(
          database: database, branchId: 1, voucherId: id, fractionDigits: 2),
      throwsA(isA<CashVoucherIntegrityException>()),
    );
  });

  test('posting failure rolls back voucher and cash movements', () async {
    await database.update('chart_of_accounts', {'code': 'X1201'},
        where: 'code=?', whereArgs: ['1201']);
    await expectLater(post('RECEIPT'), throwsA(isA<StateError>()));
    expect(await database.query('vouchers'), isEmpty);
    expect(await database.query('journal_entries'), isEmpty);
    expect(await database.query('cash_transactions'), isEmpty);
    final drawer = (await database
            .query('cash_accounts', where: 'id=?', whereArgs: [cashId]))
        .single;
    expect((drawer['current_balance'] as num).toDouble(), 0);
    final seq = (await database.query('number_sequences',
            where: 'doc_type=?', whereArgs: ['VOUCHER']))
        .single;
    expect(seq['last_no'], 0);
  });
}
