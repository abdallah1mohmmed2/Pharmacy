import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/database_helper.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/shift_and_treasury_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('transactions filters by transaction branch without ambiguous columns',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('pharmacy-treasury-test-');
    final db = await databaseFactory.openDatabase(
      '${directory.path}/treasury.db',
    );
    final helper = DatabaseHelper.forTesting(db);
    final service = ShiftAndTreasuryService(helper: helper);

    try {
      await db.execute('''
        CREATE TABLE cash_accounts (
          id INTEGER PRIMARY KEY,
          branch_id INTEGER NOT NULL,
          name_ar TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE cash_transactions (
          id INTEGER PRIMARY KEY,
          branch_id INTEGER NOT NULL,
          cash_account_id INTEGER NOT NULL,
          tx_date TEXT NOT NULL,
          direction TEXT NOT NULL,
          amount REAL NOT NULL
        )
      ''');
      await db.insert('cash_accounts', {
        'id': 10,
        'branch_id': 1,
        'name_ar': 'خزينة الفرع الأول',
      });
      await db.insert('cash_accounts', {
        'id': 20,
        'branch_id': 2,
        'name_ar': 'خزينة الفرع الثاني',
      });
      await db.insert('cash_transactions', {
        'id': 100,
        'branch_id': 1,
        'cash_account_id': 10,
        'tx_date': '2026-11-08T10:00:00',
        'direction': 'IN',
        'amount': 150,
      });
      await db.insert('cash_transactions', {
        'id': 200,
        'branch_id': 2,
        'cash_account_id': 20,
        'tx_date': '2026-11-08T11:00:00',
        'direction': 'IN',
        'amount': 250,
      });

      final branchOne = await service.transactions(1);
      expect(branchOne, hasLength(1));
      expect(branchOne.single['id'], 100);
      expect(branchOne.single['account_name'], 'خزينة الفرع الأول');

      final branchTwo = await service.transactions(2, accountId: 20);
      expect(branchTwo, hasLength(1));
      expect(branchTwo.single['id'], 200);
      expect(branchTwo.single['account_name'], 'خزينة الفرع الثاني');
    } finally {
      await helper.close();
      await directory.delete(recursive: true);
    }
  });
}
