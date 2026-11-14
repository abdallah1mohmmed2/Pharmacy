import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../database/global_uuid.dart';
import 'financial_minor_units.dart';
import 'financial_voucher_operation.dart';

/// F10 versioned transport DTO. No SQLite integer IDs cross the wire.
/// The existing sale posting snapshot remains a local-only audit source.
/// Export requires independently provisioned UUIDs for all master references.
abstract final class FinancialSaleWireOperation {
  static const int schemaVersion = 1;

  static Map<String, Object?> _map(Object? value) {
    if (value is! Map || value.keys.any((x) => x is! String)) {
      throw StateError('F10_WIRE_OBJECT_INVALID');
    }
    return Map<String, Object?>.from(value);
  }

  static List<Map<String, Object?>> _list(Object? value, int limit) {
    if (value is! List || value.isEmpty || value.length > limit) {
      throw StateError('F10_WIRE_LIST_INVALID');
    }
    return value.map(_map).toList();
  }

  static void _fields(Map<String, Object?> value, Set<String> fields) {
    if (value.keys.toSet().length != fields.length ||
        !value.keys.toSet().containsAll(fields)) {
      throw StateError('F10_WIRE_FIELDS_INVALID');
    }
  }

  static String _uuid(Object? value) {
    if (value is! String || !GlobalUuid.isValid(value)) {
      throw StateError('F10_UUID_NOT_PROVISIONED');
    }
    return value;
  }

  static int _minor(Object? value) {
    if (value is! num) throw StateError('F10_AMOUNT_INVALID');
    return FinancialMinorUnits.parseYer(value.toString());
  }

  static int _int(Object? value, {int min = 0, int max = 1000000}) {
    if (value is! int || value < min || value > max) {
      throw StateError('F10_INTEGER_INVALID');
    }
    return value;
  }

  static String _date(Object? value) {
    if (value is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})?$')
            .hasMatch(value) ||
        DateTime.tryParse(value) == null) {
      throw StateError('F10_DATE_INVALID');
    }
    return value;
  }

  static Future<Map<String, Object?>> _byId(
      Database db, String table, Object? id) async {
    if (id is! int) throw StateError('F10_SOURCE_REFERENCE_INVALID');
    final rows = await db.query(table, where: 'id=?', whereArgs: [id]);
    if (rows.length != 1) throw StateError('F10_SOURCE_REFERENCE_MISSING');
    return rows.single;
  }

  // Synthetic member UUIDs are derived from an immutable ordered snapshot,
  // not from local SQLite IDs. Source movement/allocations lack UUID columns.
  static String _memberUuid(String operationUuid, String kind, int ordinal) {
    final digest = sha256
        .convert(
            utf8.encode(operationUuid + ':' + kind + ':' + ordinal.toString()))
        .toString();
    final raw = digest.substring(0, 32).split('');
    raw[12] = '5';
    raw[16] = '8';
    final h = raw.join();
    return h.substring(0, 8) +
        '-' +
        h.substring(8, 12) +
        '-' +
        h.substring(12, 16) +
        '-' +
        h.substring(16, 20) +
        '-' +
        h.substring(20, 32);
  }

  /// Materialize a tightly scoped UUID-only wire envelope from the immutable
  /// source snapshot. The returned hash uses the existing canonical JSON rule.
  /// Nothing from the snapshot is directly sent over HTTP.
  static Future<({Map<String, Object?> envelope, String hash})> export(
    Database db, {
    required int branchId,
    required String operationUuid,
  }) async {
    _uuid(operationUuid);
    final captures = await db.query('financial_sale_capture_outbox',
        where: 'branch_id=? AND operation_uuid=?',
        whereArgs: [branchId, operationUuid]);
    if (captures.length != 1) throw StateError('F10_CAPTURE_NOT_FOUND');
    final raw = captures.single['payload_json'];
    if (raw is! String ||
        sha256.convert(utf8.encode(raw)).toString() !=
            captures.single['payload_hash']) {
      throw StateError('F10_CAPTURE_TAMPERED');
    }
    final captured = _map(jsonDecode(raw));
    if (captured['schema_version'] != 1 ||
        captured['operation_type'] != 'CASH_SALE' ||
        captured['operation_uuid'] != operationUuid ||
        captured['currency_code'] != 'YER' ||
        captured['fraction_digits'] != 0) {
      throw StateError('F10_CAPTURE_CONTRACT_INVALID');
    }
    final branch = await _byId(db, 'branches', branchId);
    final branchUuid = _uuid(branch['uuid']);
    if (captured['branch_uuid'] != branchUuid) {
      throw StateError('F10_BRANCH_MISMATCH');
    }
    final invoice = _map(captured['invoice']);
    final journal = _map(captured['journal']);
    if (_uuid(invoice['uuid']) != operationUuid ||
        invoice['branch_id'] != branchId ||
        invoice['sale_type'] != 'CASH' ||
        invoice['status'] != 'COMPLETED' ||
        invoice['customer_party_id'] != null ||
        _minor(invoice['remaining_alayh']) != 0 ||
        journal['source_type'] != 'SALE' ||
        journal['source_id'] != invoice['id']) {
      throw StateError('F10_CASH_SALE_REQUIRED');
    }
    final cashier = await _byId(db, 'users', invoice['cashier_user_id']);
    final invoiceWire = <String, Object?>{
      'uuid': operationUuid,
      'date': _date(invoice['invoice_date']),
      'cashier_uuid': _uuid(cashier['uuid']),
      'subtotal_minor': _minor(invoice['subtotal']),
      'discount_minor': _minor(invoice['discount_amount']),
      'net_minor': _minor(invoice['net_total']),
      'paid_minor': _minor(invoice['paid_total']),
      'cost_minor': _minor(invoice['total_cost']),
    };

    final itemSource = _list(captured['items'], 100);
    final itemWires = <Map<String, Object?>>[];
    final itemUuid = <int, String>{};
    for (final item in itemSource) {
      if (item['invoice_id'] != invoice['id'] ||
          item['is_substitute'] == 1 ||
          item['substituted_for_drug_id'] != null) {
        throw StateError('F10_UNSUPPORTED_SALE_ITEM');
      }
      final drug = await _byId(db, 'drugs', item['drug_id']);
      final id = _uuid(item['uuid']);
      itemUuid[_int(item['id'], min: 1)] = id;
      final quantity = item['qty_in_sell_unit'];
      if (quantity is! num || quantity.toInt() != quantity) {
        throw StateError('F10_FRACTIONAL_SELL_QUANTITY_NOT_SUPPORTED');
      }
      itemWires.add({
        'uuid': id,
        'drug_uuid': _uuid(drug['uuid']),
        'sell_unit': item['sell_unit'],
        'qty_in_sell_unit': quantity.toInt(),
        'qty_units': _int(item['qty_units'], min: 1),
        'unit_price_minor': _minor(item['unit_price_sell_unit']),
        'line_discount_minor': _minor(item['line_discount_amount']),
        'line_total_minor': _minor(item['line_total']),
        'line_cost_minor': _minor(item['line_cost']),
      });
    }

    final allocationSource = _list(captured['allocations'], 300);
    final batchWires = <String, Map<String, Object?>>{};
    final sourceBatchUuids = <int, String>{};
    Future<String> batchUuid(Object? id) async {
      if (id is! int) throw StateError('F10_BATCH_ID_INVALID');
      if (sourceBatchUuids.containsKey(id)) return sourceBatchUuids[id]!;
      final batch = await _byId(db, 'batches_fefo', id);
      final drug = await _byId(db, 'drugs', batch['drug_id']);
      final warehouse = await _byId(db, 'warehouses', batch['warehouse_id']);
      final batchId = _uuid(batch['uuid']);
      batchWires[batchId] = {
        'uuid': batchId,
        'drug_uuid': _uuid(drug['uuid']),
        'warehouse_uuid': _uuid(warehouse['uuid']),
      };
      sourceBatchUuids[id] = batchId;
      return batchId;
    }

    final allocationWires = <Map<String, Object?>>[];
    for (var index = 0; index < allocationSource.length; index++) {
      final a = allocationSource[index];
      final itemId = a['invoice_item_id'];
      if (itemId is! int ||
          !itemUuid.containsKey(itemId) ||
          a['returned_qty_units'] != 0) {
        throw StateError('F10_ALLOCATION_INVALID');
      }
      allocationWires.add({
        'uuid': _memberUuid(operationUuid, 'allocation', index),
        'item_uuid': itemUuid[itemId],
        'batch_uuid': await batchUuid(a['batch_id']),
        'qty_units': _int(a['qty_units'], min: 1),
        'unit_cost_minor': _minor(a['unit_cost']),
      });
    }

    final movementSource = _list(captured['movements'], 600);
    final movementWires = <Map<String, Object?>>[];
    for (var index = 0; index < movementSource.length; index++) {
      final m = movementSource[index];
      if (m['doc_type'] != 'SALE' || m['doc_id'] != invoice['id']) {
        throw StateError('F10_MOVEMENT_SOURCE_INVALID');
      }
      movementWires.add({
        'uuid': _memberUuid(operationUuid, 'movement', index),
        'batch_uuid': await batchUuid(m['batch_id']),
        'movement_type': m['movement_type'],
        'qty_units': m['qty_units'],
        'unit_cost_minor': _minor(m['unit_cost']),
        'unit_price_minor': _minor(m['unit_price']),
        'occurred_at': _date(m['movement_at']),
      });
    }

    final paymentSource = _list(captured['payments'], 100);
    final cashSource = _list(captured['cash'], 100);
    final paymentWires = <Map<String, Object?>>[];
    final cashWires = <Map<String, Object?>>[];
    for (final payment in paymentSource) {
      if (payment['invoice_id'] != invoice['id'] ||
          payment['method'] != 'CASH') {
        throw StateError('F10_UNSUPPORTED_PAYMENT');
      }
      final account =
          await _byId(db, 'cash_accounts', payment['cash_account_id']);
      final cashUuid = _uuid(account['uuid']);
      paymentWires.add({
        'uuid': _uuid(payment['uuid']),
        'cash_uuid': cashUuid,
        'amount_minor': _minor(payment['amount']),
      });
      final matches = cashSource
          .where((c) =>
              c['cash_account_id'] == payment['cash_account_id'] &&
              c['amount'] == payment['amount'] &&
              c['direction'] == 'IN' &&
              c['tx_type'] == 'SALE' &&
              c['doc_type'] == 'INVOICE' &&
              c['doc_id'] == invoice['id'])
          .toList();
      if (matches.length != 1) throw StateError('F10_CASH_MOVEMENT_INVALID');
      final c = matches.single;
      cashWires.add({
        'uuid': _uuid(c['uuid']),
        'cash_uuid': cashUuid,
        'amount_minor': _minor(c['amount']),
        'date': _date(c['tx_date']),
      });
    }
    if (cashSource.length != paymentSource.length ||
        _map(captured['journal'])['uuid'] == null ||
        captured['ledger'] is! List ||
        (captured['ledger'] as List).isNotEmpty) {
      throw StateError('F10_UNSUPPORTED_SALE_EFFECTS');
    }
    final lineSource = _list(captured['lines'], 100);
    final lineWires = <Map<String, Object?>>[];
    for (final line in lineSource) {
      if (line['journal_entry_id'] != journal['id'] ||
          line['party_id'] != null) {
        throw StateError('F10_JOURNAL_SOURCE_INVALID');
      }
      final account = await _byId(db, 'chart_of_accounts', line['account_id']);
      lineWires.add({
        'uuid': _uuid(line['uuid']),
        'account_uuid': _uuid(account['uuid']),
        'dr_minor': _minor(line['dr_amount']),
        'cr_minor': _minor(line['cr_amount']),
      });
    }

    final envelope = <String, Object?>{
      'schema_version': schemaVersion,
      'operation_type': 'CASH_SALE',
      'operation_uuid': operationUuid,
      'branch_uuid': branchUuid,
      'currency_code': 'YER',
      'fraction_digits': 0,
      'invoice': invoiceWire,
      'items': itemWires,
      'batches': batchWires.values.toList(),
      'allocations': allocationWires,
      'movements': movementWires,
      'payments': paymentWires,
      'cash': cashWires,
      'journal': {
        'uuid': _uuid(journal['uuid']),
        'date': _date(journal['entry_date']),
      },
      'lines': lineWires,
    };
    final hash = sha256
        .convert(utf8.encode(FinancialVoucherOperation.canonicalJson(envelope)))
        .toString();
    // Validate the same strict envelope locally before any network request.
    prepare(envelope, hash: hash);
    return (envelope: envelope, hash: hash);
  }

  static SaleWirePrepared prepare(
    Map<String, Object?> e, {
    required String hash,
    String? expectedBranchUuid,
  }) {
    final actual = sha256
        .convert(utf8.encode(FinancialVoucherOperation.canonicalJson(e)))
        .toString();
    if (hash != actual ||
        e['schema_version'] != schemaVersion ||
        e['operation_type'] != 'CASH_SALE' ||
        e['currency_code'] != 'YER' ||
        e['fraction_digits'] != 0) {
      throw StateError('F10_WIRE_HASH_OR_VERSION_INVALID');
    }
    _fields(e, {
      'schema_version',
      'operation_type',
      'operation_uuid',
      'branch_uuid',
      'currency_code',
      'fraction_digits',
      'invoice',
      'items',
      'batches',
      'allocations',
      'movements',
      'payments',
      'cash',
      'journal',
      'lines'
    });
    final branchUuid = _uuid(e['branch_uuid']);
    if (expectedBranchUuid != null && expectedBranchUuid != branchUuid) {
      throw StateError('F10_WIRE_BRANCH_INVALID');
    }
    final operationUuid = _uuid(e['operation_uuid']);
    final inv = _map(e['invoice']);
    _fields(inv, {
      'uuid',
      'date',
      'cashier_uuid',
      'subtotal_minor',
      'discount_minor',
      'net_minor',
      'paid_minor',
      'cost_minor'
    });
    if (_uuid(inv['uuid']) != operationUuid)
      throw StateError('F10_INVOICE_MISMATCH');
    final subtotal =
        _int(inv['subtotal_minor'], min: 1, max: FinancialMinorUnits.maxMinor);
    final discount =
        _int(inv['discount_minor'], max: FinancialMinorUnits.maxMinor);
    final net =
        _int(inv['net_minor'], min: 1, max: FinancialMinorUnits.maxMinor);
    final paid =
        _int(inv['paid_minor'], min: 1, max: FinancialMinorUnits.maxMinor);
    final cost = _int(inv['cost_minor'], max: FinancialMinorUnits.maxMinor);
    if (subtotal - discount != net || net != paid)
      throw StateError('F10_TOTAL_INVALID');
    final invoice = <String, Object?>{
      'id': 1,
      'uuid': operationUuid,
      'invoice_date': _date(inv['date']),
      'total_cost': cost.toDouble(),
    };
    final itemRows = <Map<String, Object?>>[];
    final itemIds = <String, int>{};
    final itemDrugUuids = <int, String>{};
    var lineTotal = 0, lineCost = 0;
    for (final x in _list(e['items'], 100)) {
      _fields(x, {
        'uuid',
        'drug_uuid',
        'sell_unit',
        'qty_in_sell_unit',
        'qty_units',
        'unit_price_minor',
        'line_discount_minor',
        'line_total_minor',
        'line_cost_minor'
      });
      final id = itemRows.length + 1;
      final uuid = _uuid(x['uuid']);
      if (itemIds.containsKey(uuid)) throw StateError('F10_ITEM_DUPLICATE');
      itemIds[uuid] = id;
      itemDrugUuids[id] = _uuid(x['drug_uuid']);
      final qty = _int(x['qty_units'], min: 1);
      final sellQty = _int(x['qty_in_sell_unit'], min: 1);
      final unitPrice =
          _int(x['unit_price_minor'], max: FinancialMinorUnits.maxMinor);
      final off =
          _int(x['line_discount_minor'], max: FinancialMinorUnits.maxMinor);
      final total =
          _int(x['line_total_minor'], max: FinancialMinorUnits.maxMinor);
      final itemCost =
          _int(x['line_cost_minor'], max: FinancialMinorUnits.maxMinor);
      if (!['UNIT', 'PACK'].contains(x['sell_unit']) ||
          unitPrice * sellQty - off != total) {
        throw StateError('F10_ITEM_AMOUNT_INVALID');
      }
      lineTotal += total;
      lineCost += itemCost;
      itemRows.add({
        'id': id,
        'uuid': uuid,
        'sell_unit': x['sell_unit'],
        'qty_in_sell_unit': sellQty,
        'qty_units': qty,
        'unit_price_sell_unit': unitPrice.toDouble(),
        'line_discount_amount': off.toDouble(),
        'line_total': total.toDouble(),
        'line_cost': itemCost.toDouble(),
      });
    }
    if (lineTotal != subtotal || lineCost != cost) {
      throw StateError('F10_ITEMS_NOT_BALANCED');
    }

    final batchKeys = <int, (String, String, String, String)>{};
    final batchUuids = <int, (String, String)>{};
    final batchIds = <String, int>{};
    for (final b in _list(e['batches'], 100)) {
      _fields(b, {'uuid', 'drug_uuid', 'warehouse_uuid'});
      final uuid = _uuid(b['uuid']);
      if (batchIds.containsKey(uuid)) throw StateError('F10_BATCH_DUPLICATE');
      final id = batchIds.length + 1;
      batchIds[uuid] = id;
      final drugUuid = _uuid(b['drug_uuid']);
      batchKeys[id] = (drugUuid, '', '', '');
      batchUuids[id] = (_uuid(b['warehouse_uuid']), uuid);
    }
    final allocations = <Map<String, Object?>>[];
    final allocated = <int, int>{};
    final allocatedCost = <int, int>{};
    final perBatch = <int, int>{};
    final seen = <String>{operationUuid};
    void member(Object? value) {
      if (!seen.add(_uuid(value)))
        throw StateError('F10_WIRE_MEMBER_DUPLICATE');
    }

    member(_map(e['journal'])['uuid']);
    for (final x in itemRows) {
      member(x['uuid']);
    }
    for (final a in _list(e['allocations'], 300)) {
      _fields(a,
          {'uuid', 'item_uuid', 'batch_uuid', 'qty_units', 'unit_cost_minor'});
      member(a['uuid']);
      final item = itemIds[_uuid(a['item_uuid'])];
      final batch = batchIds[_uuid(a['batch_uuid'])];
      if (item == null ||
          batch == null ||
          itemDrugUuids[item] != batchKeys[batch]!.$1) {
        throw StateError('F10_WIRE_ALLOCATION_REFERENCE');
      }
      final qty = _int(a['qty_units'], min: 1);
      final unitCost =
          _int(a['unit_cost_minor'], max: FinancialMinorUnits.maxMinor);
      allocated[item] = (allocated[item] ?? 0) + qty;
      allocatedCost[item] = (allocatedCost[item] ?? 0) + qty * unitCost;
      perBatch[batch] = (perBatch[batch] ?? 0) + qty;
      allocations.add({
        'invoice_item_id': item,
        'batch_id': batch,
        'qty_units': qty,
        'unit_cost': unitCost.toDouble(),
      });
    }
    for (final i in itemRows) {
      final id = i['id'] as int;
      if (allocated[id] != i['qty_units'] ||
          allocatedCost[id] != (i['line_cost'] as num).toInt()) {
        throw StateError('F10_WIRE_ALLOCATION_TOTALS');
      }
    }
    final movements = <Map<String, Object?>>[];
    final moved = <int, int>{};
    for (final m in _list(e['movements'], 600)) {
      _fields(m, {
        'uuid',
        'batch_uuid',
        'movement_type',
        'qty_units',
        'unit_cost_minor',
        'unit_price_minor',
        'occurred_at'
      });
      member(m['uuid']);
      final batch = batchIds[_uuid(m['batch_uuid'])];
      if (batch == null) throw StateError('F10_WIRE_MOVEMENT_BATCH');
      final type = m['movement_type'];
      final qty = m['qty_units'];
      if (!['SALE_OUT', 'PACK_OPEN'].contains(type) ||
          qty is! int ||
          (type == 'PACK_OPEN' && qty != 0) ||
          (type == 'SALE_OUT' && qty >= 0)) {
        throw StateError('F10_WIRE_MOVEMENT_SIGN');
      }
      if (type == 'SALE_OUT') moved[batch] = (moved[batch] ?? 0) - qty;
      movements.add({
        'batch_id': batch,
        'doc_type': 'SALE',
        'doc_id': 1,
        'movement_type': type,
        'qty_units': qty,
        'unit_cost':
            _int(m['unit_cost_minor'], max: FinancialMinorUnits.maxMinor)
                .toDouble(),
        'unit_price':
            _int(m['unit_price_minor'], max: FinancialMinorUnits.maxMinor)
                .toDouble(),
        'movement_at': _date(m['occurred_at']),
        'note': null,
      });
    }
    if (moved.length != perBatch.length ||
        perBatch.keys.any((id) => perBatch[id] != moved[id])) {
      throw StateError('F10_WIRE_STOCK_TOTALS');
    }
    final cashAccountIds = <String, int>{};
    final cashAccountUuids = <int, String>{};
    final payments = <Map<String, Object?>>[];
    final paymentAmounts = <String, int>{};
    var paymentTotal = 0;
    for (final x in _list(e['payments'], 100)) {
      _fields(x, {'uuid', 'cash_uuid', 'amount_minor'});
      member(x['uuid']);
      final cashUuid = _uuid(x['cash_uuid']);
      if (cashAccountIds.containsKey(cashUuid))
        throw StateError('F10_CASH_ACCOUNT_DUPLICATE');
      final id = cashAccountIds.length + 1;
      cashAccountIds[cashUuid] = id;
      cashAccountUuids[id] = cashUuid;
      final value =
          _int(x['amount_minor'], min: 1, max: FinancialMinorUnits.maxMinor);
      paymentAmounts[cashUuid] = value;
      paymentTotal += value;
      payments.add({
        'uuid': x['uuid'],
        'cash_account_id': id,
        'amount': value.toDouble(),
        'method': 'CASH'
      });
    }
    final cash = <Map<String, Object?>>[];
    final cashSeen = <String>{};
    var cashTotal = 0;
    for (final x in _list(e['cash'], 100)) {
      _fields(x, {'uuid', 'cash_uuid', 'amount_minor', 'date'});
      member(x['uuid']);
      final cashUuid = _uuid(x['cash_uuid']);
      final value =
          _int(x['amount_minor'], min: 1, max: FinancialMinorUnits.maxMinor);
      if (!cashSeen.add(cashUuid) || paymentAmounts[cashUuid] != value) {
        throw StateError('F10_WIRE_CASH_MISMATCH');
      }
      cashTotal += value;
      cash.add({
        'uuid': x['uuid'],
        'cash_account_id': cashAccountIds[cashUuid],
        'amount': value.toDouble(),
        'tx_date': _date(x['date'])
      });
    }
    if (cash.length != payments.length ||
        paymentTotal != net ||
        cashTotal != net) {
      throw StateError('F10_WIRE_PAYMENTS_NOT_BALANCED');
    }
    final accounts = <String, int>{};
    final accountUuids = <int, String>{};
    final lines = <Map<String, Object?>>[];
    var dr = 0, cr = 0;
    final journal = _map(e['journal']);
    _fields(journal, {'uuid', 'date'});
    for (final l in _list(e['lines'], 100)) {
      _fields(l, {'uuid', 'account_uuid', 'dr_minor', 'cr_minor'});
      member(l['uuid']);
      final account = _uuid(l['account_uuid']);
      final accId = accounts.putIfAbsent(account, () {
        final id = accounts.length + 1;
        accountUuids[id] = account;
        return id;
      });
      final debit = _int(l['dr_minor'], max: FinancialMinorUnits.maxMinor);
      final credit = _int(l['cr_minor'], max: FinancialMinorUnits.maxMinor);
      if ((debit == 0) == (credit == 0)) {
        throw StateError('F10_WIRE_JOURNAL_SIDE');
      }
      dr += debit;
      cr += credit;
      lines.add({
        'uuid': l['uuid'],
        'account_id': accId,
        'dr_amount': debit.toDouble(),
        'cr_amount': credit.toDouble(),
        'memo': null
      });
    }
    if (dr != cr || dr != net + cost)
      throw StateError('F10_WIRE_JOURNAL_TOTALS');
    return SaleWirePrepared(
      operationUuid: operationUuid,
      branchUuid: branchUuid,
      hash: hash,
      invoice: invoice,
      items: itemRows,
      allocations: allocations,
      movements: movements,
      payments: payments,
      cash: cash,
      journal: {
        'id': 1,
        'uuid': journal['uuid'],
        'entry_date': _date(journal['date'])
      },
      lines: lines,
      net: net,
      paid: paid,
      subtotal: subtotal,
      discount: discount,
      cashierUuid: _uuid(inv['cashier_uuid']),
      itemDrugUuids: itemDrugUuids,
      batchKeys: batchKeys,
      batchUuids: batchUuids,
      accountUuids: accountUuids,
      cashAccountUuids: cashAccountUuids,
    );
  }
}

class SaleWirePrepared {
  const SaleWirePrepared({
    required this.operationUuid,
    required this.branchUuid,
    required this.hash,
    required this.invoice,
    required this.items,
    required this.allocations,
    required this.movements,
    required this.payments,
    required this.cash,
    required this.journal,
    required this.lines,
    required this.net,
    required this.paid,
    required this.subtotal,
    required this.discount,
    required this.cashierUuid,
    required this.itemDrugUuids,
    required this.batchKeys,
    required this.batchUuids,
    required this.accountUuids,
    required this.cashAccountUuids,
  });
  final String operationUuid, branchUuid, hash, cashierUuid;
  final Map<String, Object?> invoice, journal;
  final List<Map<String, Object?>> items,
      allocations,
      movements,
      payments,
      cash,
      lines;
  final int net, paid, subtotal, discount;
  final Map<int, String> itemDrugUuids, accountUuids, cashAccountUuids;
  final Map<int, (String, String, String, String)> batchKeys;
  final Map<int, (String, String)> batchUuids;
}
