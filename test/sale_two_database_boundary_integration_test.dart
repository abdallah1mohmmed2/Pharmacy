import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
import 'package:global_enterprise_pharmacy_erp/data/services/financial_domain_gate.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/financial_sale_two_database_replay.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/financial_sale_wire_operation.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/financial_relay_client.dart';

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

  test('F10 truly replays CASH sale from independent SQLite A into B once',
      () async {
    final dir = await Directory.systemTemp.createTemp('f10-actual-transfer-');
    Database? a;
    Database? b;
    Database? c;
    try {
      a = await openSaleDatabase(dir.path + '/a.db');
      b = await openSaleDatabase(dir.path + '/b.db');
      c = await openSaleDatabase(dir.path + '/c.db');
      for (final db in [a, b, c]) {
        await db.update(
            'branches', {'uuid': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'},
            where: 'id=?', whereArgs: [1]);
        await db.update(
            'users', {'uuid': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'},
            where: 'id=?', whereArgs: [1]);
        await db.update(
            'cash_accounts', {'uuid': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'},
            where: 'code=?', whereArgs: ['CASH-DRAWER']);
        for (final e in <String, String>{
          '1102': '11111111-1111-4111-8111-111111111111',
          '4101': '22222222-2222-4222-8222-222222222222',
          '5101': '33333333-3333-4333-8333-333333333333',
          '1301': '44444444-4444-4444-8444-444444444444',
        }.entries) {
          await db.update('chart_of_accounts', {'uuid': e.value},
              where: 'code=?', whereArgs: [e.key]);
        }
      }
      await b.insert('drugs', {
        'uuid': 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
        'branch_id': 1,
        'created_at': '2026-11-10',
        'updated_at': '2026-11-10',
        'internal_code': 'UNRELATED',
        'trade_name_ar': 'صنف آخر',
      });
      await b.insert('sales_invoices', {
        'uuid': 'ffffffff-ffff-4fff-8fff-ffffffffffff',
        'branch_id': 1,
        'created_at': '2026-11-10',
        'updated_at': '2026-11-10',
        'invoice_no': 'OTHER-LOCAL',
        'invoice_date': '2026-11-10',
        'cashier_user_id': 1,
        'sale_type': 'CASH',
        'status': 'HELD',
      });
      final ids = <int>[];
      final batches = <int>[];
      for (final db in [a, b, c]) {
        final drugId = await db.insert('drugs', {
          'uuid': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
          'branch_id': 1,
          'created_at': '2026-11-10',
          'updated_at': '2026-11-10',
          'internal_code': 'SHARED-DRUG',
          'trade_name_ar': 'صنف مشترك',
          'units_per_pack': 1,
          'sell_price_unit': 20.0,
          'sell_price_pack': 20.0,
          'stock_total_units': 10,
        });
        final wh = await db.insert('warehouses', {
          'uuid': '55555555-5555-4555-8555-555555555555',
          'branch_id': 1,
          'code': 'F10-WH',
          'name_ar': 'مخزن مشترك',
          'wh_type': 'MAIN_STORE',
          'created_at': '2026-11-10',
        });
        final batch = await db.insert('batches_fefo', {
          'uuid': '66666666-6666-4666-8666-666666666666',
          'drug_id': drugId,
          'warehouse_id': wh,
          'batch_no': 'F10-B',
          'expiry_date': '2030-12-31',
          'sealed_packs': 10,
          'loose_units': 0,
          'total_units': 10,
          'unit_cost': 5.0,
          'pack_cost': 5.0,
        });
        ids.add(drugId);
        batches.add(batch);
      }
      expect(ids[0], isNot(ids[1]));
      final cashId = (await a.query('cash_accounts',
              columns: ['id'], where: 'code=?', whereArgs: ['CASH-DRAWER']))
          .single['id'] as int;
      final posted = await PostingAndSalesService(
              helper: DatabaseHelper.forTesting(a), captureSaleForF10: true)
          .postSale(
        branchId: 1,
        cashierUserId: 1,
        items: [
          CartItemModel(
              drug: DrugModel(
                  id: ids[0],
                  unitsPerPack: 1,
                  sellPriceUnit: 20,
                  sellPricePack: 20),
              sellUnit: 'UNIT',
              quantity: 2)
        ],
        saleType: 'CASH',
        payments: [
          (cashAccountId: cashId, amount: 40.0, method: 'CASH', walletRef: null)
        ],
        clinicalVerdict: ClinicalVerdict([]),
      );
      final uuid =
          (await a.query('sales_invoices', where: 'id=?', whereArgs: [posted]))
              .single['uuid'] as String;
      expect(await b.query('stock_movements'), isEmpty);
      await expectLater(
          FinancialSaleTwoDatabaseReplay.applyFromTrustedLocalSource(
              source: a,
              destination: b,
              sourceBranchId: 1,
              destinationBranchId: 1,
              operationUuid: uuid,
              trustedLocalSource: false),
          throwsA(isA<StateError>()));
      expect(
          await FinancialSaleTwoDatabaseReplay.applyFromTrustedLocalSource(
              source: a,
              destination: b,
              sourceBranchId: 1,
              destinationBranchId: 1,
              operationUuid: uuid,
              trustedLocalSource: true),
          isTrue);
      final dest =
          (await b.query('sales_invoices', where: 'uuid=?', whereArgs: [uuid]))
              .single;
      expect(dest['id'], isNot(posted));
      expect(dest['net_total'], 40.0);
      expect(dest['paid_total'], 40.0);
      expect(dest['total_cost'], 10.0);
      expect(
          await b.query('sales_invoice_items',
              where: 'invoice_id=?', whereArgs: [dest['id']]),
          hasLength(1));
      expect(
          await b.query('sales_payments',
              where: 'invoice_id=?', whereArgs: [dest['id']]),
          hasLength(1));
      expect(
          await b.query('cash_transactions',
              where: 'doc_type=? AND doc_id=?',
              whereArgs: ['INVOICE', dest['id']]),
          hasLength(1));
      expect(
          await b.query('stock_movements',
              where: 'doc_type=? AND doc_id=? AND movement_type=?',
              whereArgs: ['SALE', dest['id'], 'SALE_OUT']),
          hasLength(1));
      expect(
          (await b.query('batches_fefo',
                  where: 'id=?', whereArgs: [batches[1]]))
              .single['total_units'],
          8);
      expect(
          (await b.query('drugs', where: 'id=?', whereArgs: [ids[1]]))
              .single['stock_total_units'],
          8);
      final journal = (await b.query('journal_entries',
              where: 'source_type=? AND source_id=?',
              whereArgs: ['SALE', dest['id']]))
          .single;
      final lines = await b.query('journal_lines',
          where: 'journal_entry_id=?', whereArgs: [journal['id']]);
      expect(lines, hasLength(4));
      expect(
          lines.fold<double>(
              0, (s, row) => s + (row['dr_amount'] as num).toDouble()),
          50.0);
      expect(
          lines.fold<double>(
              0, (s, row) => s + (row['cr_amount'] as num).toDouble()),
          50.0);
      expect(
          await FinancialSaleTwoDatabaseReplay.applyFromTrustedLocalSource(
              source: a,
              destination: b,
              sourceBranchId: 1,
              destinationBranchId: 1,
              operationUuid: uuid,
              trustedLocalSource: true),
          isFalse);
      expect(await b.query('sales_invoices'), hasLength(2));
      expect(
          await b.query('stock_movements',
              where: 'doc_type=? AND doc_id=? AND movement_type=?',
              whereArgs: ['SALE', dest['id'], 'SALE_OUT']),
          hasLength(1));
      expect(await b.rawQuery('PRAGMA foreign_key_check'), isEmpty);

      // F10 independent UUID-only wire: destination C has no source DB handle.
      final wire = await FinancialSaleWireOperation.export(a,
          branchId: 1, operationUuid: uuid);
      final encoded = jsonEncode(wire.envelope);
      expect(encoded.contains('"invoice_id"'), isFalse);
      expect(encoded.contains('"drug_id"'), isFalse);
      expect(encoded.contains('"batch_id"'), isFalse);
      await expectLater(
          FinancialSaleTwoDatabaseReplay.applyVerifiedWire(
              destination: c,
              destinationBranchId: 1,
              expectedBranchUuid: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
              envelope: wire.envelope,
              payloadHash: wire.hash,
              trustedRelay: false),
          throwsA(isA<StateError>()));
      final modified = Map<String, Object?>.from(
          jsonDecode(jsonEncode(wire.envelope)) as Map);
      (modified['invoice'] as Map)['net_minor'] = 41;
      await expectLater(
          FinancialSaleTwoDatabaseReplay.applyVerifiedWire(
              destination: c,
              destinationBranchId: 1,
              expectedBranchUuid: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
              envelope: modified,
              payloadHash: wire.hash,
              trustedRelay: true),
          throwsA(isA<StateError>()));
      expect(await c.query('sales_invoices'), isEmpty);
      // The Dart HTTP client must carry the UUID-only envelope through the
      // authenticated relay route; the destination still has no source handle.
      var postCalls = 0;
      var getCalls = 0;
      final client = FinancialRelayClient(
        endpoint: Uri.parse('https://relay.invalid/v1/operations'),
        idTokenProvider: () async => 'verified-id-token',
        saleTransportEnabled: true,
        client: MockClient((request) async {
          expect(request.headers['authorization'], 'Bearer verified-id-token');
          if (request.method == 'POST') {
            postCalls++;
            final sent = jsonDecode(request.body) as Map<String, dynamic>;
            expect(sent['payload_hash'], wire.hash);
            expect(sent['envelope'], wire.envelope);
            return http.Response(jsonEncode({
              'status': 'COMMITTED',
              'operation_uuid': uuid,
              'payload_hash': wire.hash
            }), 200);
          }
          getCalls++;
          expect(request.url.queryParameters['operation_type'], 'CASH_SALE');
          expect(request.url.queryParameters['after'], '0');
          return http.Response(jsonEncode({
            'operations': [{
              'operation_uuid': uuid,
              'payload_hash': wire.hash,
              'envelope': wire.envelope,
            }],
            'next_cursor': '1',
          }), 200);
        }),
      );
      await client.sendCapturedSale(a, branchId: 1, operationUuid: uuid);
      await client.sendCapturedSale(a, branchId: 1, operationUuid: uuid);
      expect(postCalls, 1);
      expect(await a.query('financial_sale_delivery_acks'), hasLength(1));
      final cursor = await client.receiveSalePage(c,
          branchId: 1, branchUuid: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          afterCursor: '0', limit: 20);
      expect(cursor, '1');
      expect(getCalls, 1);
      client.close();
      expect(
          (await c.query('sales_invoices', where: 'uuid=?', whereArgs: [uuid]))
              .single['net_total'],
          40.0);
      expect(
          (await c.query('batches_fefo',
                  where: 'id=?', whereArgs: [batches[2]]))
              .single['total_units'],
          8);
      expect(
          (await c.query('drugs', where: 'id=?', whereArgs: [ids[2]]))
              .single['stock_total_units'],
          8);
      expect(await c.query('journal_lines'), hasLength(4));
      expect(await c.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      expect(
          await FinancialSaleTwoDatabaseReplay.applyVerifiedWire(
              destination: c,
              destinationBranchId: 1,
              expectedBranchUuid: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
              envelope: wire.envelope,
              payloadHash: wire.hash,
              trustedRelay: true),
          isFalse);
      expect(
          await c.query('stock_movements',
              where: 'movement_type=?', whereArgs: ['SALE_OUT']),
          hasLength(1));
      // Sender receives its own branch event: exact matching echo is a no-op.
      expect(
          await FinancialSaleTwoDatabaseReplay.applyVerifiedWire(
              destination: a,
              destinationBranchId: 1,
              expectedBranchUuid: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
              envelope: wire.envelope,
              payloadHash: wire.hash,
              trustedRelay: true),
          isFalse);
    } finally {
      if (a != null) await a.close();
      if (b != null) await b.close();
      if (c != null) await c.close();
      await dir.delete(recursive: true);
    }
  });

  test('F10 opt-in captures immutable sale in posting transaction', () async {
    final dir = await Directory.systemTemp.createTemp('f10-capture-');
    Database? db;
    try {
      db = await openSaleDatabase('${dir.path}/capture.db');
      await db.update(
          'branches', {'uuid': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'},
          where: 'id=?', whereArgs: [1]);
      final drugId = await db.insert('drugs', {
        'uuid': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        'branch_id': 1,
        'created_at': '2026-11-10',
        'updated_at': '2026-11-10',
        'internal_code': 'F10-CAPTURE',
        'trade_name_ar': 'اختبار الالتقاط',
        'units_per_pack': 1,
        'sell_price_unit': 20.0,
        'sell_price_pack': 20.0,
        'stock_total_units': 10,
      });
      final wh = await db.insert('warehouses', {
        'branch_id': 1,
        'code': 'F10-WH',
        'name_ar': 'مخزن',
        'wh_type': 'MAIN_STORE',
        'created_at': '2026-11-10',
      });
      await db.insert('batches_fefo', {
        'drug_id': drugId,
        'warehouse_id': wh,
        'batch_no': 'F10-BATCH',
        'expiry_date': '2030-12-31',
        'sealed_packs': 10,
        'loose_units': 0,
        'total_units': 10,
        'unit_cost': 5.0,
      });
      final cashId = (await db.query('cash_accounts',
              columns: ['id'], where: 'code=?', whereArgs: ['CASH-DRAWER']))
          .single['id'] as int;
      final posting = PostingAndSalesService(
          helper: DatabaseHelper.forTesting(db), captureSaleForF10: true);
      final id = await posting.postSale(
        branchId: 1,
        cashierUserId: 1,
        items: [
          CartItemModel(
              drug: DrugModel(
                  id: drugId,
                  unitsPerPack: 1,
                  sellPriceUnit: 20,
                  sellPricePack: 20),
              sellUnit: 'UNIT',
              quantity: 2)
        ],
        saleType: 'CASH',
        payments: [
          (cashAccountId: cashId, amount: 40.0, method: 'CASH', walletRef: null)
        ],
        clinicalVerdict: ClinicalVerdict([]),
      );
      final snapshots = await db.query('financial_sale_capture_outbox');
      expect(snapshots, hasLength(1));
      expect(
          snapshots.single['operation_uuid'],
          (await db.query('sales_invoices', where: 'id=?', whereArgs: [id]))
              .single['uuid']);
      expect(await db.query('financial_operation_outbox'), isEmpty);
      await expectLater(db.delete('financial_sale_capture_outbox'),
          throwsA(isA<DatabaseException>()));
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    } finally {
      if (db != null) await db.close();
      await dir.delete(recursive: true);
    }
  });

  test(
      'real postSale commits invoice, FEFO movement and journal only at source',
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
        'stock_total_units': 10,
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
      final posting =
          PostingAndSalesService(helper: DatabaseHelper.forTesting(source));
      final invoiceId = await posting.postSale(
        branchId: 1,
        cashierUserId: 1,
        items: [
          CartItemModel(
              drug: DrugModel(
                  id: drugId,
                  unitsPerPack: 1,
                  sellPriceUnit: 20.0,
                  sellPricePack: 20.0),
              sellUnit: 'UNIT',
              quantity: 2)
        ],
        saleType: 'CASH',
        payments: [
          (cashAccountId: cashId, amount: 40.0, method: 'CASH', walletRef: null)
        ],
        clinicalVerdict: ClinicalVerdict([]),
      );
      expect(
          await source
              .query('sales_invoices', where: 'id=?', whereArgs: [invoiceId]),
          hasLength(1));
      expect(
          await source.query('sales_invoice_items',
              where: 'invoice_id=?', whereArgs: [invoiceId]),
          hasLength(1));
      expect(
          await source.query('stock_movements',
              where: 'doc_type=? AND doc_id=?', whereArgs: ['SALE', invoiceId]),
          isNotEmpty);
      expect(
          (await source
                  .query('batches_fefo', where: 'id=?', whereArgs: [batchId]))
              .single['total_units'],
          8);
      expect(
          await source.query('journal_entries',
              where: 'source_type=? AND source_id=?',
              whereArgs: ['SALE', invoiceId]),
          hasLength(1));
      // F10 preflight: a genuine sale spans more than its invoice and stock row.
      // This is a source-side completeness audit, NOT a transport envelope.
      final invoice = (await source
              .query('sales_invoices', where: 'id=?', whereArgs: [invoiceId]))
          .single;
      expect(invoice['net_total'], 40.0);
      expect(invoice['paid_total'], 40.0);
      expect(invoice['total_cost'], 10.0);
      expect(invoice['remaining_alayh'], 0.0);
      final item = (await source.query('sales_invoice_items',
              where: 'invoice_id=?', whereArgs: [invoiceId]))
          .single;
      expect(item['qty_units'], 2);
      expect(item['line_cost'], 10.0);
      final allocations = await source.query('sales_invoice_item_batches',
          where: 'invoice_item_id=?', whereArgs: [item['id']]);
      expect(allocations, hasLength(1));
      expect(allocations.single['batch_id'], batchId);
      expect(allocations.single['qty_units'], 2);
      final saleMovements = await source.query('stock_movements',
          where: 'doc_type=? AND doc_id=? AND movement_type=?',
          whereArgs: ['SALE', invoiceId, 'SALE_OUT']);
      expect(saleMovements, hasLength(1));
      expect(saleMovements.single['qty_units'], -2);
      expect(saleMovements.single['balance_after_units'], 8);
      expect(
          (await source.query('drugs', where: 'id=?', whereArgs: [drugId]))
              .single['stock_total_units'],
          8);
      final payments = await source.query('sales_payments',
          where: 'invoice_id=?', whereArgs: [invoiceId]);
      expect(payments, hasLength(1));
      expect(payments.single['amount'], 40.0);
      final cashMovements = await source.query('cash_transactions',
          where: 'doc_type=? AND doc_id=?', whereArgs: ['INVOICE', invoiceId]);
      expect(cashMovements, hasLength(1));
      expect(cashMovements.single['amount'], 40.0);
      final journal = (await source.query('journal_entries',
              where: 'source_type=? AND source_id=?',
              whereArgs: ['SALE', invoiceId]))
          .single;
      final journalLines = await source.query('journal_lines',
          where: 'journal_entry_id=?', whereArgs: [journal['id']]);
      expect(journalLines, hasLength(4));
      final debit = journalLines.fold<double>(
          0, (sum, row) => sum + (row['dr_amount'] as num).toDouble());
      final credit = journalLines.fold<double>(
          0, (sum, row) => sum + (row['cr_amount'] as num).toDouble());
      expect(debit, 50.0);
      expect(credit, debit);
      expect(
          await source.query('lah_alayh_ledger',
              where: 'doc_type=? AND doc_id=?',
              whereArgs: ['INVOICE', invoiceId]),
          isEmpty,
          reason: 'Fully paid cash sale must not create customer debt');
      expect(FinancialDomainGate.productionTransportEnabled, isFalse);
      expect(() => FinancialDomainGate.requireTransportApproved('CASH_SALE'),
          throwsA(isA<StateError>()));
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
