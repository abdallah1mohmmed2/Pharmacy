import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/database_helper.dart';
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
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration13.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/seed_data.dart';
import 'package:global_enterprise_pharmacy_erp/data/models/drug_model.dart';
import 'package:global_enterprise_pharmacy_erp/data/models/erp_models.dart';
import 'package:global_enterprise_pharmacy_erp/data/models/clinical_and_rx_models.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/posting_and_sales_service.dart';

Future<Database> openSaleDatabase(String path) async {
  final db = await databaseFactoryFfi.openDatabase(path,
      options: OpenDatabaseOptions(onConfigure: (d) async {
    await d.execute('PRAGMA foreign_keys=ON');
  }));
  await SchemaBuilder.build(db);
  await SchemaIteration12.upgrade(db);
  await SeedData.run(db);
  await SchemaIteration2.upgrade(db);
  await SchemaIteration3.upgrade(db);
  await SchemaIteration4.upgrade(db);
  await SchemaIteration5.upgrade(db);
  await SchemaIteration6.upgrade(db);
  await SchemaIteration7.upgrade(db);
  await SchemaIteration8.upgrade(db);
  await SchemaIteration9.upgrade(db);
  await SchemaIteration10.upgrade(db);
  await SchemaIteration11.upgrade(db);
  await SchemaIteration12.upgrade(db);
  await SchemaIteration13.upgrade(db);
  return db;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('real postSale commits invoice, FEFO movement and journal only at source',
      () async {
    final dir = await Directory.systemTemp.createTemp('sale-two-db-');
    Database? source;
    Database? target;
    try {
      source = await openSaleDatabase('${dir.path}/source.db');
      target = await openSaleDatabase('${dir.path}/target.db');
      final drugId = await source.insert('drugs', {
        'uuid': '11111111-1111-4111-8111-111111111111',
        'branch_id': 1,
        'created_at': '2026-11-10',
        'updated_at': '2026-11-10',
        'internal_code': 'SALE-BOUNDARY-TEST',
        'trade_name_ar': 'اختبار البيع',
        'units_per_pack': 1,
        'sell_price_unit': 20.0,
        'sell_price_pack': 20.0,
      });
      final warehouseId = await source.insert('warehouses', {
        'branch_id': 1,
        'code': 'SALE-BOUNDARY',
        'name_ar': 'مخزن اختبار',
        'wh_type': 'MAIN_STORE',
        'created_at': '2026-11-10',
      });
      final batchId = await source.insert('batches_fefo', {
        'drug_id': drugId,
        'warehouse_id': warehouseId,
        'batch_no': 'SALE-BOUNDARY-BATCH',
        'expiry_date': '2030-12-31',
        'sealed_packs': 10,
        'loose_units': 0,
        'total_units': 10,
        'unit_cost': 5.0,
        'pack_cost': 5.0,
      });
      final cashId = (await source.query('cash_accounts',
          columns: ['id'], where: 'code=?', whereArgs: ['CASH-DRAWER']))
          .single['id'] as int;
      final posting = PostingAndSalesService(
          helper: DatabaseHelper.forTesting(source));
      final invoiceId = await posting.postSale(
        branchId: 1,
        cashierUserId: 1,
        items: [CartItemModel(
            drug: DrugModel(id: drugId, unitsPerPack: 1,
                sellPriceUnit: 20.0, sellPricePack: 20.0),
            sellUnit: 'UNIT', quantity: 2)],
        saleType: 'CASH',
        payments: [(cashAccountId: cashId, amount: 40.0,
            method: 'CASH', walletRef: null)],
        clinicalVerdict: ClinicalVerdict([]),
      );
      expect(await source.query('sales_invoices',
          where: 'id=?', whereArgs: [invoiceId]), hasLength(1));
      expect(await source.query('sales_invoice_items',
          where: 'invoice_id=?', whereArgs: [invoiceId]), hasLength(1));
      expect(await source.query('stock_movements',
          where: 'doc_type=? AND doc_id=?',
          whereArgs: ['SALE', invoiceId]), isNotEmpty);
      expect((await source.query('batches_fefo',
          where: 'id=?', whereArgs: [batchId])).single['total_units'], 8);
      expect(await source.query('journal_entries',
          where: 'source_type=? AND source_id=?',
          whereArgs: ['SALE', invoiceId]), hasLength(1));
      expect(await source.query('financial_operation_outbox'), isEmpty,
          reason: 'F10 sale transport must not be inferred from CASH vouchers');
      expect(await target.query('sales_invoices'), isEmpty);
      expect(await target.query('stock_movements'), isEmpty);
      expect(await source.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      expect(await target.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    } finally {
      if (source != null) await source.close();
      if (target != null) await target.close();
      await dir.delete(recursive: true);
    }
  });
}
