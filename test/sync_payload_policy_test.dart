import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/sync_payload_policy.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/sync_table_policy.dart';

void main() {
  test('every allowed production table has an explicit field contract', () {
    expect(SyncPayloadPolicy.fieldsByTable.keys.toSet(), SyncTablePolicy.outboundTables);
  });

  test('projects approved fields and leaves local sensitive data untouched', () {
    final source = <String, Object?>{
      'uuid': 'drug-uuid', 'internal_code': 'D1', 'trade_name_ar': 'دواء',
      'sell_price_pack': 120, 'units_per_pack': 20, 'id': 42,
      'password_hash': 'private', 'refresh_token': 'private',
      'patient_name': 'private', 'indications': 'unapproved clinical text',
      'ingredients_json': '[{"token":"private"}]',
      'future_field': {'secret': 'private'}, '__relations': {'users': 'private'},
    };
    final snapshot = jsonEncode(source);
    final result = SyncPayloadPolicy.project('drugs', source);
    expect(result, {
      'uuid': 'drug-uuid', 'internal_code': 'D1', 'trade_name_ar': 'دواء',
      'sell_price_pack': 120, 'units_per_pack': 20,
    });
    expect(jsonEncode(source), snapshot);
  });

  test('witness identity and free text are excluded from stock operations', () {
    expect(SyncPayloadPolicy.project('disposals', {
      'disposal_no': 'D1', 'witness_name': 'private', 'authority_ref': 'private',
    }), {'disposal_no': 'D1'});
    expect(SyncPayloadPolicy.project('stock_movements', {
      'qty_units': 3, 'note': 'patient information',
    }), {'qty_units': 3});
  });

  test('unknown tables and malformed root values fail closed', () {
    for (final value in [null, [], 'text', 1]) {
      expect(() => SyncPayloadPolicy.project('drugs', value), throwsFormatException);
    }
    expect(() => SyncPayloadPolicy.project('users', {'uuid': 'u'}), throwsFormatException);
  });

  test('nested objects and encoded JSON cannot hide inside approved fields', () {
    for (final value in [
      {'token': 'private'}, [{'password': 'private'}],
      '{"secret":"private"}', '[{"patient":"private"}]', double.nan,
    ]) {
      expect(() => SyncPayloadPolicy.project('drugs', {'trade_name_ar': value}), throwsFormatException);
    }
    expect(SyncPayloadPolicy.project('drugs', {'trade_name_ar': 'دواء 500', 'trade_name_en': null}),
      {'trade_name_ar': 'دواء 500', 'trade_name_en': null});
  });
}
