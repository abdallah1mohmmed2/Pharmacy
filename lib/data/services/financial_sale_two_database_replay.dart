import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../database/global_uuid.dart';
import 'financial_minor_units.dart';

/// F10 integration-only replay between two independently opened SQLite DBs.
///
/// This is NOT a network protocol. The source-local snapshot contains integer
/// IDs and must never be published to Firebase/HTTP. A trusted caller must own
/// both database handles. Production financial transport remains disabled.
///
/// Only completed, fully paid CASH sales are supported; credit/mixed sales,
/// unsettled dependencies and uncertain legacy identities fail closed.
abstract final class FinancialSaleTwoDatabaseReplay {
  static Map<String, Object?> _map(Object? value) {
    if (value is! Map) throw StateError('F10_INVALID_ENVELOPE');
    return Map<String, Object?>.from(value);
  }

  static List<Map<String, Object?>> _rows(Object? value) {
    if (value is! List) throw StateError('F10_INVALID_MEMBERS');
    return value.map(_map).toList();
  }

  static int _positive(Object? value) {
    if (value is! int || value <= 0) throw StateError('F10_INVALID_QUANTITY');
    return value;
  }

  static int _money(Object? value) {
    if (value is! num) throw StateError('F10_INVALID_AMOUNT');
    return FinancialMinorUnits.parseYer(value.toString());
  }

  static String _uuid(Object? value) {
    if (value is! String || !GlobalUuid.isValid(value)) {
      throw StateError('F10_REFERENCE_UUID_NOT_PROVISIONED');
    }
    return value;
  }

  static Map<String, Object?> _one(List<Map<String, Object?>> rows) {
    if (rows.length != 1) throw StateError('F10_REFERENCE_MISSING_OR_AMBIGUOUS');
    return rows.single;
  }

  static Future<Map<String, Object?>> _source(
      Database db, String table, Object? id) async {
    if (id is! int) throw StateError('F10_SOURCE_ID_INVALID');
    return _one(await db.query(table, where: 'id=?', whereArgs: [id]));
  }

  static Future<Map<String, Object?>> _target(
      Transaction txn, String table, String uuid, int branchId) =>
      txn.query(table,
          where: 'uuid=? AND branch_id=? AND is_deleted=0',
          whereArgs: [uuid, branchId]).then(_one);

  /// Returns true if applied; false for a byte-identical replay. Any exception
  /// rolls back the complete destination transaction, including the receipt.
  static Future<bool> applyFromTrustedLocalSource({
    required Database source,
    required Database destination,
    required int sourceBranchId,
    required int destinationBranchId,
    required String operationUuid,
    required bool trustedLocalSource,
  }) async {
    if (!trustedLocalSource) throw StateError('F10_UNTRUSTED_SOURCE');
    _uuid(operationUuid);
    final capture = _one(await source.query('financial_sale_capture_outbox',
        where: 'operation_uuid=? AND branch_id=?',
        whereArgs: [operationUuid, sourceBranchId]));
    final payload = capture['payload_json'];
    final hash = capture['payload_hash'];
    if (payload is! String || hash is! String ||
        sha256.convert(utf8.encode(payload)).toString() != hash) {
      throw StateError('F10_CAPTURE_HASH_MISMATCH');
    }
    final envelope = _map(jsonDecode(payload));
    if (envelope['schema_version'] != 1 ||
        envelope['operation_type'] != 'CASH_SALE' ||
        envelope['operation_uuid'] != operationUuid ||
        envelope['currency_code'] != FinancialMinorUnits.currencyCode ||
        envelope['fraction_digits'] != 0) {
      throw StateError('F10_CONTRACT_MISMATCH');
    }
    final sourceBranch = _one(await source.query('branches',
        where: 'id=?', whereArgs: [sourceBranchId]));
    final branchUuid = _uuid(sourceBranch['uuid']);
    if (envelope['branch_uuid'] != branchUuid) {
      throw StateError('F10_SOURCE_BRANCH_MISMATCH');
    }
    final invoice = _map(envelope['invoice']);
    if (_uuid(invoice['uuid']) != operationUuid ||
        invoice['branch_id'] != sourceBranchId ||
        invoice['sale_type'] != 'CASH' ||
        invoice['status'] != 'COMPLETED' ||
        invoice['customer_party_id'] != null ||
        _money(invoice['remaining_alayh']) != 0) {
      throw StateError('F10_NOT_FULLY_PAID_CASH_SALE');
    }
    final items = _rows(envelope['items']);
    final allocations = _rows(envelope['allocations']);
    final movements = _rows(envelope['movements']);
    final payments = _rows(envelope['payments']);
    final cash = _rows(envelope['cash']);
    final ledger = _rows(envelope['ledger']);
    final journal = _map(envelope['journal']);
    final lines = _rows(envelope['lines']);
    if (items.isEmpty || allocations.isEmpty || payments.isEmpty ||
        payments.length != cash.length || ledger.isNotEmpty ||
        lines.isEmpty || _uuid(journal['uuid']).isEmpty ||
        journal['source_type'] != 'SALE' ||
        journal['source_id'] != invoice['id']) {
      throw StateError('F10_INCOMPLETE_OPERATION');
    }
    final net = _money(invoice['net_total']);
    final paid = _money(invoice['paid_total']);
    final subtotal = _money(invoice['subtotal']);
    final discount = _money(invoice['discount_amount']);
    if (net == 0 || net != paid || subtotal - discount != net ||
        items.fold<int>(0, (s, i) => s + _money(i['line_total'])) != subtotal ||
        payments.fold<int>(0, (s, i) => s + _money(i['amount'])) != paid ||
        cash.fold<int>(0, (s, i) => s + _money(i['amount'])) != paid ||
        lines.fold<int>(0, (s, i) => s + _money(i['dr_amount'])) !=
            lines.fold<int>(0, (s, i) => s + _money(i['cr_amount'])) ||
        lines.fold<int>(0, (s, i) => s + _money(i['dr_amount'])) == 0) {
      throw StateError('F10_FINANCIAL_TOTALS_INVALID');
    }
    for (final payment in payments) {
      if (payment['method'] != 'CASH' ||
          payment['invoice_id'] != invoice['id']) {
        throw StateError('F10_UNSUPPORTED_PAYMENT');
      }
      _uuid(payment['uuid']);
      final matches = cash.where((c) =>
          c['cash_account_id'] == payment['cash_account_id'] &&
          c['amount'] == payment['amount'] &&
          c['direction'] == 'IN' &&
          c['tx_type'] == 'SALE' &&
          c['doc_type'] == 'INVOICE' &&
          c['doc_id'] == invoice['id']);
      if (matches.length != 1) throw StateError('F10_CASH_EFFECT_MISMATCH');
      _uuid(matches.single['uuid']);
    }

    // Source IDs are used only to inspect trusted source dependencies. They
    // are never inserted into the destination as foreign keys.
    final cashier = await _source(source, 'users', invoice['cashier_user_id']);
    final cashierUuid = _uuid(cashier['uuid']);
    final itemDrugUuids = <int, String>{};
    final batchKeys = <int, (String, String, String, String)>{};
    final accountUuids = <int, String>{};
    final cashAccountUuids = <int, String>{};
    final itemIds = <int>{};
    final allocationsPerItem = <int, int>{};
    final quantitiesPerBatch = <int, int>{};
    final memberUuids = <String>{operationUuid, _uuid(journal['uuid'])};

    for (final item in items) {
      final id = _positive(item['id']);
      if (!itemIds.add(id) ||
          item['invoice_id'] != invoice['id'] ||
          item['is_substitute'] == 1 ||
          item['substituted_for_drug_id'] != null ||
          _positive(item['qty_units']) == 0 ||
          !memberUuids.add(_uuid(item['uuid']))) {
        throw StateError('F10_ITEM_INTEGRITY');
      }
      final drug = await _source(source, 'drugs', item['drug_id']);
      itemDrugUuids[id] = _uuid(drug['uuid']);
    }
    for (final allocation in allocations) {
      final itemId = _positive(allocation['invoice_item_id']);
      if (!itemIds.contains(itemId) ||
          allocation['returned_qty_units'] != 0) {
        throw StateError('F10_ALLOCATION_INTEGRITY');
      }
      final units = _positive(allocation['qty_units']);
      allocationsPerItem[itemId] = (allocationsPerItem[itemId] ?? 0) + units;
      final batchId = _positive(allocation['batch_id']);
      quantitiesPerBatch[batchId] = (quantitiesPerBatch[batchId] ?? 0) + units;
      final batch = await _source(source, 'batches_fefo', batchId);
      final drug = await _source(source, 'drugs', batch['drug_id']);
      final warehouse = await _source(source, 'warehouses', batch['warehouse_id']);
      final key = (_uuid(drug['uuid']), warehouse['code'] as String,
          batch['batch_no'] as String, batch['expiry_date'] as String);
      if (key.$1 != itemDrugUuids[itemId]) {
        throw StateError('F10_BATCH_DRUG_MISMATCH');
      }
      batchKeys[batchId] = key;
    }
    for (final item in items) {
      if (allocationsPerItem[item['id']] != item['qty_units']) {
        throw StateError('F10_ALLOCATION_QUANTITY_MISMATCH');
      }
    }
    final movementUnits = <int, int>{};
    for (final m in movements) {
      if (m['doc_type'] != 'SALE' || m['doc_id'] != invoice['id'] ||
          !batchKeys.containsKey(m['batch_id']) ||
          !{'SALE_OUT', 'PACK_OPEN'}.contains(m['movement_type'])) {
        throw StateError('F10_STOCK_MOVEMENT_INVALID');
      }
      if (m['movement_type'] == 'SALE_OUT') {
        final qty = m['qty_units'];
        if (qty is! int || qty >= 0) throw StateError('F10_STOCK_SIGN_INVALID');
        final id = m['batch_id'] as int;
        movementUnits[id] = (movementUnits[id] ?? 0) - qty;
      } else if (m['qty_units'] != 0) {
        throw StateError('F10_PACK_OPEN_INVALID');
      }
    }
    if (movementUnits.length != quantitiesPerBatch.length ||
        quantitiesPerBatch.keys.any(
            (id) => movementUnits[id] != quantitiesPerBatch[id])) {
      throw StateError('F10_STOCK_ALLOCATION_MISMATCH');
    }
    for (final payment in payments) {
      final acc = await _source(source, 'cash_accounts',
          payment['cash_account_id']);
      cashAccountUuids[acc['id'] as int] = _uuid(acc['uuid']);
      if (!memberUuids.add(_uuid(payment['uuid']))) {
        throw StateError('F10_REPEATED_MEMBER');
      }
    }
    for (final c in cash) {
      if (!memberUuids.add(_uuid(c['uuid']))) {
        throw StateError('F10_REPEATED_MEMBER');
      }
    }
    for (final line in lines) {
      if (line['journal_entry_id'] != journal['id'] ||
          line['party_id'] != null ||
          !memberUuids.add(_uuid(line['uuid']))) {
        throw StateError('F10_JOURNAL_LINE_INVALID');
      }
      final account = await _source(source, 'chart_of_accounts',
          line['account_id']);
      accountUuids[account['id'] as int] = _uuid(account['uuid']);
    }

    return destination.transaction((txn) async {
      final branch = _one(await txn.query('branches',
          where: 'id=?', whereArgs: [destinationBranchId]));
      if (branch['uuid'] != branchUuid) throw StateError('F10_DEST_BRANCH_MISMATCH');
      final prior = await txn.query('financial_operation_inbox',
          where: 'operation_uuid=?', whereArgs: [operationUuid]);
      if (prior.isNotEmpty) {
        if (prior.single['branch_id'] != destinationBranchId ||
            prior.single['payload_hash'] != hash) {
          throw StateError('F10_REPLAY_CONFLICT');
        }
        return false;
      }
      if ((await txn.query('sales_invoices',
          where: 'uuid=?', whereArgs: [operationUuid])).isNotEmpty ||
          (await txn.query('financial_sale_capture_outbox',
          where: 'operation_uuid=?', whereArgs: [operationUuid])).isNotEmpty) {
        throw StateError('F10_INVOICE_OR_LOCAL_ECHO_CONFLICT');
      }
      final dstCashier = await _target(txn, 'users', cashierUuid,
          destinationBranchId);
      final now = DateTime.now().toUtc().toIso8601String();
      Map<String, Object?> base(String uuid) => {
        'uuid': uuid, 'branch_id': destinationBranchId,
        'created_at': now, 'updated_at': now, 'is_deleted': 0,
        'sync_status': 'SYNCED', 'sync_version': 1,
      };
      final suffix = operationUuid.replaceAll('-', '');
      final invoiceId = await txn.insert('sales_invoices', {
        ...base(operationUuid),
        'invoice_no': 'F10-I-' + suffix,
        'invoice_date': invoice['invoice_date'],
        'cashier_user_id': dstCashier['id'],
        'sale_type': 'CASH', 'status': 'COMPLETED',
        'subtotal': subtotal.toDouble(),
        'discount_amount': discount.toDouble(),
        'net_total': net.toDouble(),
        'paid_total': paid.toDouble(),
        'remaining_alayh': 0, 'total_cost': invoice['total_cost'],
      });

      // Use stable drug UUID and a unique warehouse/batch business key.
      // These provisional natural keys are why this importer is not released
      // as production transport until the missing stock UUIDs are migrated.
      final dstDrugs = <String, Map<String, Object?>>{};
      for (final uuid in itemDrugUuids.values.toSet()) {
        dstDrugs[uuid] = await _target(txn, 'drugs', uuid, destinationBranchId);
      }
      final dstBatches = <int, Map<String, Object?>>{};
      for (final entry in batchKeys.entries) {
        final k = entry.value;
        final wh = _one(await txn.query('warehouses',
            where: 'code=? AND branch_id=?', whereArgs: [k.$2, destinationBranchId]));
        final d = dstDrugs[k.$1]!;
        dstBatches[entry.key] = _one(await txn.query('batches_fefo',
            where: 'drug_id=? AND warehouse_id=? AND batch_no=? AND expiry_date=?',
            whereArgs: [d['id'], wh['id'], k.$3, k.$4]));
      }
      final dstItems = <int, int>{};
      for (final item in items) {
        final drug = dstDrugs[itemDrugUuids[item['id']]!]!;
        final id = await txn.insert('sales_invoice_items', {
          ...base(_uuid(item['uuid'])),
          'invoice_id': invoiceId, 'drug_id': drug['id'],
          'sell_unit': item['sell_unit'],
          'qty_in_sell_unit': item['qty_in_sell_unit'],
          'qty_units': item['qty_units'],
          'unit_price_sell_unit': item['unit_price_sell_unit'],
          'line_discount_amount': item['line_discount_amount'],
          'line_total': item['line_total'], 'line_cost': item['line_cost'],
        });
        dstItems[item['id'] as int] = id;
        final changed = await txn.rawUpdate(
            'UPDATE drugs SET stock_total_units=stock_total_units-?, updated_at=? '
            'WHERE id=? AND stock_total_units>=?',
            [item['qty_units'], now, drug['id'], item['qty_units']]);
        if (changed != 1) throw StateError('F10_INSUFFICIENT_DRUG_STOCK');
      }
      for (final a in allocations) {
        await txn.insert('sales_invoice_item_batches', {
          'invoice_item_id': dstItems[a['invoice_item_id']]!,
          'batch_id': dstBatches[a['batch_id']]!['id'],
          'qty_units': a['qty_units'],
          'unit_cost': a['unit_cost'],
        });
      }
      final remainingByBatch = <int, int>{};
      for (final m in movements) {
        final sourceBatchId = m['batch_id'] as int;
        final targetBatch = dstBatches[sourceBatchId]!;
        final targetDrug = dstDrugs[batchKeys[sourceBatchId]!.$1]!;
        final current = remainingByBatch[sourceBatchId] ??
            (targetBatch['total_units'] as int);
        final qty = m['qty_units'] as int;
        final next = current + qty;
        if (next < 0) throw StateError('F10_INSUFFICIENT_BATCH_STOCK');
        if (m['movement_type'] == 'SALE_OUT') {
          final size = (targetDrug['units_per_pack'] as int);
          final changed = await txn.update('batches_fefo', {
            'total_units': next,
            'sealed_packs': next ~/ size,
            'loose_units': next % size,
            'status': next == 0 ? 'DEPLETED' : 'ACTIVE',
          }, where: 'id=? AND total_units=?',
             whereArgs: [targetBatch['id'], current]);
          if (changed != 1) throw StateError('F10_BATCH_CONFLICT');
        }
        await txn.insert('stock_movements', {
          'drug_id': targetDrug['id'],
          'batch_id': targetBatch['id'],
          'warehouse_id': targetBatch['warehouse_id'],
          'movement_type': m['movement_type'],
          'qty_units': qty,
          'unit_cost': m['unit_cost'],
          'unit_price': m['unit_price'],
          'balance_after_units': next,
          'doc_type': 'SALE', 'doc_id': invoiceId,
          'movement_at': m['movement_at'],
          'note': m['note'],
        });
        remainingByBatch[sourceBatchId] = next;
      }
      for (final p in payments) {
        final dstCash = await _target(txn, 'cash_accounts',
            cashAccountUuids[p['cash_account_id']]!, destinationBranchId);
        if (!{'CASHIER_DRAWER', 'MAIN_SAFE'}.contains(dstCash['account_kind'])) {
          throw StateError('F10_CASH_KIND_INVALID');
        }
        await txn.insert('sales_payments', {
          ...base(_uuid(p['uuid'])),
          'invoice_id': invoiceId, 'cash_account_id': dstCash['id'],
          'method': 'CASH', 'amount': p['amount'],
        });
        final changed = await txn.rawUpdate(
            'UPDATE cash_accounts SET current_balance=current_balance+?,updated_at=? '
            'WHERE id=?', [p['amount'], now, dstCash['id']]);
        if (changed != 1) throw StateError('F10_CASH_ACCOUNT_MISSING');
        final balance = _one(await txn.query('cash_accounts',
            where: 'id=?', whereArgs: [dstCash['id']]))['current_balance'];
        final cashRow = cash.singleWhere((c) =>
            c['cash_account_id'] == p['cash_account_id'] &&
            c['amount'] == p['amount']);
        await txn.insert('cash_transactions', {
          'uuid': _uuid(cashRow['uuid']),
          'branch_id': destinationBranchId,
          'cash_account_id': dstCash['id'],
          'tx_date': cashRow['tx_date'], 'direction': 'IN',
          'amount': p['amount'], 'tx_type': 'SALE',
          'doc_type': 'INVOICE', 'doc_id': invoiceId,
          'balance_after': balance,
          'note': 'تحصيل فاتورة متزامنة',
        });
      }
      final journalId = await txn.insert('journal_entries', {
        ...base(_uuid(journal['uuid'])),
        'entry_no': 'F10-J-' + suffix,
        'entry_date': journal['entry_date'],
        'description': 'قيد فاتورة متزامنة',
        'source_type': 'SALE', 'source_id': invoiceId,
        'is_posted': 1,
      });
      for (final line in lines) {
        final dstAccount = await _target(txn, 'chart_of_accounts',
            accountUuids[line['account_id']]!, destinationBranchId);
        await txn.insert('journal_lines', {
          ...base(_uuid(line['uuid'])),
          'journal_entry_id': journalId,
          'account_id': dstAccount['id'],
          'dr_amount': line['dr_amount'],
          'cr_amount': line['cr_amount'],
          'memo': line['memo'],
        });
      }
      await txn.update('sales_invoices', {'journal_entry_id': journalId},
          where: 'id=?', whereArgs: [invoiceId]);
      // Existing v13 receipt table also guards duplicate F10 operation UUIDs.
      // The legacy voucher_uuid column is set to the operation UUID.
      await txn.insert('financial_operation_inbox', {
        'operation_uuid': operationUuid, 'branch_id': destinationBranchId,
        'voucher_uuid': operationUuid, 'payload_hash': hash,
        'applied_at': now,
      });
      return true;
    });
  }
}
