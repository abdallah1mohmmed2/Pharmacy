import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../database/global_uuid.dart';
import 'financial_minor_units.dart';

/// F10 source-side snapshot only. Never send this to the CASH voucher relay.
/// Capture is performed in the SAME SQLite transaction as postSale.
abstract final class FinancialSaleCapture {
  static const schemaVersion = 1;

  static Future<void> capture(Transaction txn,
      {required int branchId, required int invoiceId}) async {
    Map<String, Object?> one(String name, List<Map<String, Object?>> rows) {
      if (rows.length != 1) throw StateError('F10_${name}_MISSING');
      return rows.single;
    }

    String uuid(Object? value) {
      if (value is! String || !GlobalUuid.isValid(value)) {
        throw StateError('F10_REFERENCE_UUID_NOT_READY');
      }
      return value;
    }

    int money(Object? value) {
      if (value is! num) throw StateError('F10_INVALID_AMOUNT');
      return FinancialMinorUnits.parseYer(value.toString());
    }

    final branch = one('BRANCH',
        await txn.query('branches', where: 'id=?', whereArgs: [branchId]));
    final invoice = one(
        'INVOICE',
        await txn.query('sales_invoices',
            where: 'id=? AND branch_id=?', whereArgs: [invoiceId, branchId]));
    final journal = one(
        'JOURNAL',
        await txn.query('journal_entries',
            where: 'id=? AND branch_id=?',
            whereArgs: [invoice['journal_entry_id'], branchId]));
    if (journal['source_type'] != 'SALE' || journal['source_id'] != invoiceId) {
      throw StateError('F10_JOURNAL_SOURCE_MISMATCH');
    }
    final items = await txn.query('sales_invoice_items',
        where: 'invoice_id=?', whereArgs: [invoiceId]);
    if (items.isEmpty) throw StateError('F10_ITEMS_MISSING');
    final payments = await txn
        .query('sales_payments', where: 'invoice_id=?', whereArgs: [invoiceId]);
    final cash = await txn.query('cash_transactions',
        where: "doc_type='INVOICE' AND doc_id=? AND branch_id=?",
        whereArgs: [invoiceId, branchId]);
    final ledger = await txn.query('lah_alayh_ledger',
        where: "doc_type='INVOICE' AND doc_id=? AND branch_id=?",
        whereArgs: [invoiceId, branchId]);
    final lines = await txn.query('journal_lines',
        where: 'journal_entry_id=?', whereArgs: [journal['id']]);
    final movements = await txn.query('stock_movements',
        where: "doc_type='SALE' AND doc_id=?", whereArgs: [invoiceId]);
    final allocations = <Map<String, Object?>>[];
    for (final item in items) {
      final batchRows = await txn.query('sales_invoice_item_batches',
          where: 'invoice_item_id=?', whereArgs: [item['id']]);
      if (batchRows.isEmpty) throw StateError('F10_ALLOCATION_MISSING');
      allocations.addAll(batchRows);
    }
    final net = money(invoice['net_total']);
    final paid = money(invoice['paid_total']);
    final remaining = money(invoice['remaining_alayh']);
    if (paid + remaining != net ||
        items.fold<int>(0, (s, i) => s + money(i['line_total'])) -
                money(invoice['discount_amount']) !=
            net ||
        payments.fold<int>(0, (s, i) => s + money(i['amount'])) != paid) {
      throw StateError('F10_TOTAL_MISMATCH');
    }
    if (cash.length != payments.length ||
        movements.where((m) => m['movement_type'] == 'SALE_OUT').isEmpty) {
      throw StateError('F10_EFFECTS_INCOMPLETE');
    }
    final dr = lines.fold<int>(0, (s, l) => s + money(l['dr_amount']));
    final cr = lines.fold<int>(0, (s, l) => s + money(l['cr_amount']));
    if (dr != cr || dr == 0) throw StateError('F10_UNBALANCED');
    final invoiceUuid = uuid(invoice['uuid']);
    final envelope = <String, Object?>{
      'schema_version': schemaVersion,
      'operation_type': 'CASH_SALE',
      'operation_uuid': invoiceUuid,
      'branch_uuid': uuid(branch['uuid']),
      'currency_code': FinancialMinorUnits.currencyCode,
      'fraction_digits': FinancialMinorUnits.currencyFractionDigits,
      'invoice': invoice,
      'items': items,
      'allocations': allocations,
      'payments': payments,
      'cash': cash,
      'ledger': ledger,
      'journal': journal,
      'lines': lines,
      'movements': movements,
    };
    // This is an internal source snapshot, NOT a transport-ready envelope:
    // it contains local integer references requiring UUID mapping in F10 replay.
    final payload = jsonEncode(envelope);
    final hash = sha256.convert(utf8.encode(payload)).toString();
    await txn.insert('financial_sale_capture_outbox', {
      'operation_uuid': invoiceUuid,
      'branch_id': branchId,
      'payload_json': payload,
      'payload_hash': hash,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
