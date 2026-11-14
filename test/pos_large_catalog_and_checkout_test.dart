import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/database_helper.dart';
import 'package:global_enterprise_pharmacy_erp/data/models/drug_model.dart';
import 'package:global_enterprise_pharmacy_erp/data/models/erp_models.dart';
import 'package:global_enterprise_pharmacy_erp/data/models/clinical_and_rx_models.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/posting_and_sales_service.dart';
import 'package:global_enterprise_pharmacy_erp/providers/pos_and_drugs_provider.dart';

class _DelayedPosting extends PostingAndSalesService {
  final done = Completer<int>();
  int calls = 0;

  @override
  Future<int> postSale({
    required int branchId,
    required int cashierUserId,
    required List<CartItemModel> items,
    required String saleType,
    required List<
            ({
              int cashAccountId,
              double amount,
              String method,
              String? walletRef
            })>
        payments,
    int customerPartyId = 0,
    double discountAmount = 0,
    required ClinicalVerdict clinicalVerdict,
  }) {
    calls++;
    return done.future;
  }
}

class _DelayedSearchDb implements Database {
  final result = Completer<List<Map<String, Object?>>>();
  @override
  String get path => ':memory:';
  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql,
          [List<Object?>? arguments]) =>
      result.future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<Database> createDb() => databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE drugs (
                id INTEGER PRIMARY KEY,
                branch_id INTEGER NOT NULL,
                is_deleted INTEGER NOT NULL DEFAULT 0,
                is_active INTEGER NOT NULL DEFAULT 1,
                internal_code TEXT,
                trade_name_ar TEXT,
                trade_name_en TEXT,
                scientific_name TEXT,
                barcode_local TEXT,
                barcode_international TEXT
              )
            ''');
          },
        ),
      );

  test('typing invalidates old search before debounce starts next query',
      () async {
    final db = _DelayedSearchDb();
    final provider =
        PosAndDrugsProvider(database: DatabaseHelper.forTesting(db));
    final old = provider.searchDrugs('old');
    provider.invalidateSearch('new');
    db.result.complete([
      {'id': 1, 'trade_name_ar': 'old result'}
    ]);
    await old;
    expect(provider.search, 'new');
    expect(provider.drugs, isEmpty);
    expect(provider.loading, isFalse);
  });

  test('initial POS catalog stays bounded with 27,000 medicines', () async {
    final db = await createDb();
    try {
      for (var offset = 0; offset < 27000; offset += 900) {
        await db.rawInsert('''
          WITH RECURSIVE seq(n) AS (
            SELECT 1 UNION ALL SELECT n+1 FROM seq WHERE n<900
          )
          INSERT INTO drugs (id, branch_id, internal_code, trade_name_ar)
          SELECT n+?, 1, 'CODE-'||(n+?), 'علاج '||(n+?) FROM seq
        ''', [offset, offset, offset]);
      }
      await db.insert('drugs', {
        'id': 27001,
        'branch_id': 1,
        'internal_code': 'ONLY-ONE',
        'trade_name_ar': 'دواء نادر فريد'
      });
      final provider =
          PosAndDrugsProvider(database: DatabaseHelper.forTesting(db));
      await provider.loadDrugs();
      expect(provider.drugs.length, lessThanOrEqualTo(100));
      await provider.searchDrugs('نادر فريد');
      expect(provider.drugs.map((d) => d.id).toList(), [27001]);
      await provider.loadDrugs();
      expect(provider.drugs.length, lessThanOrEqualTo(100));
    } finally {
      await db.close();
    }
  });

  test('checkout rejects the second attempt while first sale is pending',
      () async {
    final db = await createDb();
    try {
      final posting = _DelayedPosting();
      final provider = PosAndDrugsProvider(
          database: DatabaseHelper.forTesting(db), posting: posting);
      provider.addDrug(const DrugModel(id: 51, tradeNameAr: 'دواء اختبار'));
      Future<int> checkout() => provider.checkout(
            cashierId: 1,
            saleType: 'CASH',
            payments: [
              (
                cashAccountId: 1,
                amount: 0.0,
                method: 'CASH',
                walletRef: null,
              )
            ],
            clinicalVerdict: ClinicalVerdict([]),
          );
      final first = checkout();
      expect(provider.checkoutPending, isTrue);
      await expectLater(checkout(), throwsA(isA<StateError>()));
      expect(posting.calls, 1);
      posting.done.complete(27);
      expect(await first, 27);
      expect(provider.checkoutPending, isFalse);
      expect(provider.cart, isEmpty);
    } finally {
      await db.close();
    }
  });
}
