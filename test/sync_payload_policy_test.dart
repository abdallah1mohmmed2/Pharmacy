import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/sync_payload_policy.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/sync_table_policy.dart';

void main() {
  test('all production projections match the inbound contract', () {
    expect(SyncTablePolicy.inboundTables, SyncTablePolicy.outboundTables);
    for (final table in SyncTablePolicy.outboundTables) {
      final source = <String, Object?>{
        for (final field in SyncPayloadPolicy.fieldsByTable[table]!)
          field: null,
        'uuid': 'example',
        'password_hash': 'PRIVATE_SENTINEL',
      };
      final projected = SyncPayloadPolicy.project(table, source);
      expect(SyncPayloadPolicy.validateIncoming(table, projected), projected);
      expect(() => SyncPayloadPolicy.validateIncoming(table, source),
          throwsFormatException);
    }
  });

  test('every allowed production table has an explicit field contract', () {
    expect(SyncPayloadPolicy.fieldsByTable.keys.toSet(),
        SyncTablePolicy.outboundTables);
  });

  test('projects approved fields and leaves local sensitive data untouched',
      () {
    final source = <String, Object?>{
      'uuid': 'drug-uuid',
      'internal_code': 'D1',
      'trade_name_ar': 'دواء',
      'sell_price_pack': 120,
      'units_per_pack': 20,
      'id': 42,
      'password_hash': 'private',
      'refresh_token': 'private',
      'patient_name': 'private',
      'indications': 'unapproved clinical text',
      'ingredients_json': '[{"token":"private"}]',
      'future_field': {'secret': 'private'},
      '__relations': {'users': 'private'},
    };
    final snapshot = jsonEncode(source);
    final result = SyncPayloadPolicy.project('drugs', source);
    expect(result, {
      'uuid': 'drug-uuid',
      'internal_code': 'D1',
      'trade_name_ar': 'دواء',
      'sell_price_pack': 120,
      'units_per_pack': 20,
    });
    expect(jsonEncode(source), snapshot);
  });

  test('witness identity and free text are excluded from stock operations', () {
    expect(
        SyncPayloadPolicy.project('disposals', {
          'disposal_no': 'D1',
          'witness_name': 'private',
          'authority_ref': 'private',
        }),
        {'disposal_no': 'D1'});
    expect(() => SyncPayloadPolicy.project('stock_movements', {
      'qty_units': 3,
      'note': 'patient information',
    }), throwsFormatException);
  });

  test('F10 generic row sync cannot copy stock balances or sale effects', () {
    expect(SyncTablePolicy.allowsInbound('stock_movements'), isFalse);
    expect(SyncTablePolicy.allowsOutbound('sales_invoice_item_batches'),
        isFalse);
    expect(() => SyncPayloadPolicy.validateIncoming('stock_movements', {
      'doc_type': 'SALE',
      'qty_units': -2,
    }), throwsFormatException);
    expect(() => SyncPayloadPolicy.validateIncoming(
        'sales_invoice_item_batches', {
      'invoice_item_id': 12, 'batch_id': 20, 'qty_units': 2,
    }), throwsFormatException);
    final drug = SyncPayloadPolicy.project('drugs', {
      'uuid': 'global-drug', 'trade_name_ar': 'صنف',
      'stock_total_units': 8, 'sell_price_unit': 20,
    });
    expect(drug, {'uuid':'global-drug', 'trade_name_ar':'صنف',
      'sell_price_unit':20});
    final batch = SyncPayloadPolicy.project('batches_fefo', {
      'uuid': 'global-batch', 'batch_no':'B', 'total_units': 8,
      'sealed_packs': 8, 'loose_units':0, 'status':'ACTIVE',
      'unit_cost':5,
    });
    expect(batch, {'uuid':'global-batch', 'batch_no':'B',
      'unit_cost':5});
    expect(() => SyncPayloadPolicy.validateIncoming('drugs', {
      'uuid': 'global-drug', 'stock_total_units': 8,
    }), throwsFormatException);
    expect(() => SyncPayloadPolicy.validateIncoming('batches_fefo', {
      'uuid': 'global-batch', 'total_units': 8,
    }), throwsFormatException);
  });

  test('unknown tables and malformed root values fail closed', () {
    for (final value in [null, [], 'text', 1]) {
      expect(() => SyncPayloadPolicy.project('drugs', value),
          throwsFormatException);
    }
    expect(() => SyncPayloadPolicy.project('users', {'uuid': 'u'}),
        throwsFormatException);
  });

  test('nested objects and encoded JSON cannot hide inside approved fields',
      () {
    for (final value in [
      {'token': 'private'},
      [
        {'password': 'private'}
      ],
      '{"secret":"private"}',
      '[{"patient":"private"}]',
      double.nan,
    ]) {
      expect(() => SyncPayloadPolicy.project('drugs', {'trade_name_ar': value}),
          throwsFormatException);
    }
    expect(
        SyncPayloadPolicy.project(
            'drugs', {'trade_name_ar': 'دواء 500', 'trade_name_en': null}),
        {'trade_name_ar': 'دواء 500', 'trade_name_en': null});
  });
}
