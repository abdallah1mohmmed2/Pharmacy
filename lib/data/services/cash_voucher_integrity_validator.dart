import 'package:sqflite/sqflite.dart';

import '../database/global_uuid.dart';

/// Read-only integrity gate for a posted CASH receipt/payment voucher.
///
/// Deliberately does not authorize financial sync. Callers must supply an
/// approved currency precision; the current schema has no currency contract.
/// The missing UUID on cash_transactions and local-only source_id/doc_id
/// references still prevent exporting this operation to another device.
abstract final class CashVoucherIntegrityValidator {
  static Future<CashVoucherIntegrityResult> validate({
    required DatabaseExecutor database,
    required int branchId,
    required int voucherId,
    required int fractionDigits,
  }) async {
    if (branchId <= 0 || voucherId <= 0) {
      throw const CashVoucherIntegrityException('INVALID_LOCAL_ID');
    }
    if (fractionDigits < 0 || fractionDigits > 3) {
      throw const CashVoucherIntegrityException('CURRENCY_PRECISION_UNAPPROVED');
    }

    final voucher = _one(
      await database.query('vouchers',
          where: 'id=? AND branch_id=?',
          whereArgs: [voucherId, branchId]),
      'VOUCHER_MISSING',
    );
    final voucherUuid = _uuid(voucher);
    final type = voucher['voucher_type'];
    if (voucher['is_deleted'] == 1 ||
        !{'RECEIPT', 'PAYMENT'}.contains(type) ||
        voucher['method'] != 'CASH') {
      throw const CashVoucherIntegrityException('VOUCHER_TYPE_UNSUPPORTED');
    }
    final amount = _minor(voucher['amount'], fractionDigits);
    if (amount <= 0) {
      throw const CashVoucherIntegrityException('VOUCHER_AMOUNT_INVALID');
    }

    final partyId = voucher['party_id'];
    final cashId = voucher['cash_account_id'];
    final entryId = voucher['journal_entry_id'];
    if (partyId is! int || cashId is! int || entryId is! int) {
      throw const CashVoucherIntegrityException('VOUCHER_RELATION_MISSING');
    }
    final party = _one(
      await database.query('parties',
          where: 'id=? AND branch_id=?',
          whereArgs: [partyId, branchId]),
      'PARTY_MISSING',
    );
    _uuid(party);
    final cash = _one(
      await database.query('cash_accounts',
          where: 'id=? AND branch_id=?',
          whereArgs: [cashId, branchId]),
      'CASH_ACCOUNT_MISSING',
    );
    _uuid(cash);
    if (!{'CASHIER_DRAWER', 'MAIN_SAFE'}.contains(cash['account_kind'])) {
      throw const CashVoucherIntegrityException('CASH_ACCOUNT_TYPE_INVALID');
    }
    final glCashId = cash['gl_account_id'];
    if (glCashId is! int) {
      throw const CashVoucherIntegrityException('CASH_GL_MISSING');
    }
    final partyGlCode = type == 'RECEIPT' ? '1201' : '2101';
    final partyGl = _one(
      await database.query('chart_of_accounts',
          where: 'code=? AND branch_id=?',
          whereArgs: [partyGlCode, branchId]),
      'PARTY_GL_MISSING',
    );
    final glPartyId = partyGl['id'];
    _uuid(partyGl);
    final cashGl = _one(
      await database.query('chart_of_accounts',
          where: 'id=? AND branch_id=?',
          whereArgs: [glCashId, branchId]),
      'CASH_GL_MISSING',
    );
    _uuid(cashGl);
    if (glPartyId == glCashId) {
      throw const CashVoucherIntegrityException('GL_ACCOUNT_COLLISION');
    }

    final journal = _one(
      await database.query('journal_entries',
          where: 'id=? AND branch_id=?',
          whereArgs: [entryId, branchId]),
      'JOURNAL_MISSING',
    );
    final journalUuid = _uuid(journal);
    if (journal['source_type'] != 'VOUCHER' ||
        journal['source_id'] != voucherId ||
        journal['is_posted'] != 1 ||
        journal['is_deleted'] == 1) {
      throw const CashVoucherIntegrityException('JOURNAL_SOURCE_INVALID');
    }
    final lines = await database.query('journal_lines',
        where: 'journal_entry_id=? AND branch_id=?',
        whereArgs: [entryId, branchId]);
    if (lines.length != 2) {
      throw const CashVoucherIntegrityException('JOURNAL_MEMBER_COUNT_INVALID');
    }
    final isReceipt = type == 'RECEIPT';
    final cashLines = lines.where((line) =>
        line['account_id'] == glCashId && line['party_id'] == null);
    final partyLines = lines.where((line) =>
        line['account_id'] == glPartyId && line['party_id'] == partyId);
    if (cashLines.length != 1 || partyLines.length != 1) {
      throw const CashVoucherIntegrityException('JOURNAL_ACCOUNTS_INVALID');
    }
    for (final line in lines) {
      _uuid(line);
    }
    _checkSide(cashLines.single, amount, fractionDigits,
        debitSide: isReceipt);
    _checkSide(partyLines.single, amount, fractionDigits,
        debitSide: !isReceipt);

    // doc_id is a LOCAL SQLite ID, scoped to this branch, not an export ID.
    final ledgers = await database.query('lah_alayh_ledger',
        where: "doc_type='VOUCHER' AND doc_id=? AND branch_id=?",
        whereArgs: [voucherId, branchId]);
    final ledger = _one(ledgers, 'PARTY_LEDGER_MEMBER_COUNT_INVALID');
    _uuid(ledger);
    if (ledger['party_id'] != partyId ||
        ledger['entry_type'] != type ||
        ledger['is_deleted'] == 1) {
      throw const CashVoucherIntegrityException('PARTY_LEDGER_LINK_INVALID');
    }
    _checkAmount(ledger[isReceipt ? 'lah_amount' : 'alayh_amount'],
        amount, fractionDigits);
    _checkAmount(ledger[isReceipt ? 'alayh_amount' : 'lah_amount'],
        0, fractionDigits);

    final cashTxs = await database.query('cash_transactions',
        where: "doc_type='VOUCHER' AND doc_id=? AND branch_id=?",
        whereArgs: [voucherId, branchId]);
    final cashTx = _one(cashTxs, 'CASH_MEMBER_COUNT_INVALID');
    if (cashTx['cash_account_id'] != cashId ||
        cashTx['direction'] != (isReceipt ? 'IN' : 'OUT') ||
        cashTx['tx_type'] !=
            (isReceipt ? 'RECEIPT_VOUCHER' : 'PAYMENT_VOUCHER')) {
      throw const CashVoucherIntegrityException('CASH_MOVEMENT_LINK_INVALID');
    }
    _checkAmount(cashTx['amount'], amount, fractionDigits);
    return CashVoucherIntegrityResult(
      voucherUuid: voucherUuid,
      journalUuid: journalUuid,
      amountMinor: amount,
      fractionDigits: fractionDigits,
    );
  }

  static Map<String, Object?> _one(
      List<Map<String, Object?>> rows, String code) {
    if (rows.length != 1) throw CashVoucherIntegrityException(code);
    return rows.single;
  }

  static String _uuid(Map<String, Object?> row) {
    final value = row['uuid'];
    if (value is! String || !GlobalUuid.isValid(value)) {
      throw const CashVoucherIntegrityException('GLOBAL_UUID_REQUIRED');
    }
    return value;
  }

  /// Never round a financial value to make a malformed document look valid.
  /// SQLite REAL is legacy storage; P0-06 must establish a canonical decimal
  /// representation before transport. Here we accept only exactly
  /// representable values at the explicitly selected precision.
  static int _minor(Object? raw, int fractionDigits) {
    if (raw is! num || !raw.isFinite || raw < 0) {
      throw const CashVoucherIntegrityException('AMOUNT_INVALID');
    }
    final value = raw.toString();
    if (!RegExp(r'^\\d+(?:\\.\\d+)?$').hasMatch(value)) {
      throw const CashVoucherIntegrityException('AMOUNT_NOT_DECIMAL');
    }
    final parts = value.split('.');
    final fractional = parts.length == 2
        ? parts[1].replaceFirst(RegExp(r'0+$'), '')
        : '';
    if (fractional.length > fractionDigits) {
      throw const CashVoucherIntegrityException('AMOUNT_PRECISION_INVALID');
    }
    final whole = BigInt.parse(parts[0]);
    final scale = BigInt.from(10).pow(fractionDigits);
    final minor = whole * scale +
        BigInt.parse(fractional.padRight(fractionDigits, '0').isEmpty
            ? '0'
            : fractional.padRight(fractionDigits, '0'));
    if (minor > BigInt.from(0x7fffffffffffffff)) {
      throw const CashVoucherIntegrityException('AMOUNT_OVERFLOW');
    }
    return minor.toInt();
  }

  static void _checkAmount(Object? value, int expected, int fractionDigits) {
    if (_minor(value, fractionDigits) != expected) {
      throw const CashVoucherIntegrityException('AMOUNT_MISMATCH');
    }
  }

  static void _checkSide(
      Map<String, Object?> line, int expected, int fractionDigits,
      {required bool debitSide}) {
    _checkAmount(
        line[debitSide ? 'dr_amount' : 'cr_amount'], expected, fractionDigits);
    _checkAmount(
        line[debitSide ? 'cr_amount' : 'dr_amount'], 0, fractionDigits);
  }
}

class CashVoucherIntegrityResult {
  const CashVoucherIntegrityResult({
    required this.voucherUuid,
    required this.journalUuid,
    required this.amountMinor,
    required this.fractionDigits,
  });

  final String voucherUuid;
  final String journalUuid;
  final int amountMinor;
  final int fractionDigits;
}

class CashVoucherIntegrityException implements Exception {
  const CashVoucherIntegrityException(this.code);

  final String code;

  @override
  String toString() => 'CashVoucherIntegrityException: $code';
}
