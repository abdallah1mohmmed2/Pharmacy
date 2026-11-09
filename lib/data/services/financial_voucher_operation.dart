import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../database/global_uuid.dart';
import 'cash_voucher_integrity_validator.dart';
import 'financial_minor_units.dart';

/// Strict local wire contract for a posted CASH receipt/payment voucher.
///
/// Capture runs in the original posting transaction. Replay runs in a single
/// destination transaction; local integer IDs NEVER cross the wire. A hash
/// guards idempotency/integrity, not the authenticity of a remote sender.
/// Only a trusted, authenticated financial relay may call [applyVerified].
abstract final class FinancialVoucherOperation {
  static const int schemaVersion = 2;
  static const _rootFields = <String>{
    'schema_version',
    'operation_uuid',
    'branch_uuid',
    'fraction_digits',
    'currency_code',
    'voucher',
    'journal',
    'lines',
    'ledger',
    'cash'
  };

  /// This must be invoked by the posting service BEFORE its transaction commits.
  /// Bad or unprovisioned master identities reject capture and roll back the
  /// complete business posting, instead of producing an incomplete outbox row.
  static Future<String> capturePostedCashVoucher(
    Transaction txn, {
    required int branchId,
    required int voucherId,
    required int fractionDigits,
  }) async {
    if (fractionDigits != FinancialMinorUnits.currencyFractionDigits) {
      throw const FinancialVoucherSyncException('CURRENCY_POLICY_MISMATCH');
    }
    final validated = await CashVoucherIntegrityValidator.validate(
        database: txn,
        branchId: branchId,
        voucherId: voucherId,
        fractionDigits: fractionDigits);
    final branch = _single(
        await txn.query('branches', where: 'id=?', whereArgs: [branchId]),
        'BRANCH_MISSING');
    final branchUuid = _uuid(branch['uuid']);
    final voucher = _single(
        await txn.query('vouchers',
            where: 'id=? AND branch_id=?', whereArgs: [voucherId, branchId]),
        'VOUCHER_MISSING');
    final journalId = voucher['journal_entry_id'] as int;
    final journal = _single(
        await txn.query('journal_entries',
            where: 'id=? AND branch_id=?', whereArgs: [journalId, branchId]),
        'JOURNAL_MISSING');
    final lines = await txn.query('journal_lines',
        where: 'journal_entry_id=? AND branch_id=?',
        whereArgs: [journalId, branchId]);
    final party = _single(
        await txn.query('parties',
            where: 'id=? AND branch_id=?',
            whereArgs: [voucher['party_id'], branchId]),
        'PARTY_MISSING');
    final cashAccount = _single(
        await txn.query('cash_accounts',
            where: 'id=? AND branch_id=?',
            whereArgs: [voucher['cash_account_id'], branchId]),
        'CASH_ACCOUNT_MISSING');
    final ledger = _single(
        await txn.query('lah_alayh_ledger',
            where: "branch_id=? AND doc_type='VOUCHER' AND doc_id=?",
            whereArgs: [branchId, voucherId]),
        'LEDGER_MISSING');
    final cashMovement = _single(
        await txn.query('cash_transactions',
            where: "branch_id=? AND doc_type='VOUCHER' AND doc_id=?",
            whereArgs: [branchId, voucherId]),
        'CASH_MOVEMENT_MISSING');
    final movementUuid = _uuid(cashMovement['uuid']);
    final partyUuid = _uuid(party['uuid']);
    final cashUuid = _uuid(cashAccount['uuid']);
    final resultLines = <Map<String, Object?>>[];
    for (final line in lines) {
      final account = _single(
          await txn.query('chart_of_accounts',
              where: 'id=? AND branch_id=?',
              whereArgs: [line['account_id'], branchId]),
          'GL_MISSING');
      final isDebit = (line['dr_amount'] as num) > 0;
      resultLines.add(<String, Object?>{
        'uuid': _uuid(line['uuid']),
        'account_uuid': _uuid(account['uuid']),
        'party_uuid': line['party_id'] == null ? null : partyUuid,
        'dr_minor': isDebit ? validated.amountMinor : 0,
        'cr_minor': isDebit ? 0 : validated.amountMinor,
      });
    }
    resultLines
        .sort((a, b) => (a['uuid'] as String).compareTo(b['uuid'] as String));
    final operationUuid = validated.voucherUuid;
    final envelope = <String, Object?>{
      'schema_version': schemaVersion,
      'operation_uuid': operationUuid,
      'branch_uuid': branchUuid,
      'fraction_digits': FinancialMinorUnits.currencyFractionDigits,
      'currency_code': FinancialMinorUnits.currencyCode,
      'voucher': <String, Object?>{
        'uuid': validated.voucherUuid,
        'type': voucher['voucher_type'],
        'date': voucher['voucher_date'],
        'party_uuid': partyUuid,
        'cash_uuid': cashUuid,
        'amount_minor': validated.amountMinor,
      },
      'journal': <String, Object?>{
        'uuid': validated.journalUuid,
        'date': journal['entry_date'],
      },
      'lines': resultLines,
      'ledger': <String, Object?>{'uuid': _uuid(ledger['uuid'])},
      'cash': <String, Object?>{'uuid': movementUuid},
    };
    final payload = canonicalJson(envelope);
    final hash = sha256.convert(utf8.encode(payload)).toString();
    await txn.insert('financial_operation_outbox', {
      'operation_uuid': operationUuid,
      'branch_id': branchId,
      'branch_uuid': branchUuid,
      'voucher_uuid': operationUuid,
      'payload_json': payload,
      'payload_hash': hash,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
    return operationUuid;
  }

  /// Applies a complete, verified operation exactly once.
  ///
  /// The caller MUST have verified both the remote sender and authorization
  /// for this branch outside this function. A SHA-256 hash is NOT an
  /// authentication signature. This is not called by the generic Firestore
  /// sync worker, which remains forbidden to process financial tables.
  static Future<FinancialVoucherApplyResult> applyVerified(
    Database database, {
    required int branchId,
    required String expectedBranchUuid,
    required Map<String, Object?> envelope,
    required String payloadHash,
    required bool trustedRelay,
  }) async {
    if (!trustedRelay) {
      throw const FinancialVoucherSyncException('UNTRUSTED_FINANCIAL_SOURCE');
    }
    if (branchId <= 0 || !GlobalUuid.isValid(expectedBranchUuid)) {
      throw const FinancialVoucherSyncException('INVALID_BRANCH_IDENTITY');
    }
    final canonical = canonicalJson(envelope);
    final computed = sha256.convert(utf8.encode(canonical)).toString();
    if (computed != payloadHash) {
      throw const FinancialVoucherSyncException('PAYLOAD_HASH_MISMATCH');
    }
    _requireFields(envelope, _rootFields);
    if (envelope['schema_version'] != schemaVersion ||
        envelope['branch_uuid'] != expectedBranchUuid) {
      throw const FinancialVoucherSyncException('WRONG_SCHEMA_OR_BRANCH');
    }
    final operationUuid = _uuid(envelope['operation_uuid']);
    final voucher = _map(envelope['voucher']);
    const voucherFields = <String>{
      'uuid',
      'type',
      'date',
      'party_uuid',
      'cash_uuid',
      'amount_minor'
    };
    _requireFields(voucher, voucherFields);
    if (_uuid(voucher['uuid']) != operationUuid) {
      throw const FinancialVoucherSyncException('OPERATION_ID_MISMATCH');
    }
    final isReceipt = voucher['type'] == 'RECEIPT';
    if (!isReceipt && voucher['type'] != 'PAYMENT') {
      throw const FinancialVoucherSyncException('UNSUPPORTED_FINANCIAL_TYPE');
    }
    if (envelope['currency_code'] != FinancialMinorUnits.currencyCode ||
        envelope['fraction_digits'] !=
            FinancialMinorUnits.currencyFractionDigits) {
      throw const FinancialVoucherSyncException('CURRENCY_POLICY_MISMATCH');
    }
    const digits = FinancialMinorUnits.currencyFractionDigits;
    const scale = 1;
    final amountMinor = _integer(voucher['amount_minor'], 1, 999999999999);
    final amount = amountMinor / scale;
    final voucherDate = _date(voucher['date']);
    final journal = _map(envelope['journal']);
    _requireFields(journal, {'uuid', 'date'});
    final journalUuid = _uuid(journal['uuid']);
    final journalDate = _date(journal['date']);
    final ledger = _map(envelope['ledger']);
    _requireFields(ledger, {'uuid'});
    final ledgerUuid = _uuid(ledger['uuid']);
    final cash = _map(envelope['cash']);
    _requireFields(cash, {'uuid'});
    final movementUuid = _uuid(cash['uuid']);
    final partyUuid = _uuid(voucher['party_uuid']);
    final cashUuid = _uuid(voucher['cash_uuid']);

    final rawLines = envelope['lines'];
    if (rawLines is! List || rawLines.length != 2) {
      throw const FinancialVoucherSyncException('INVALID_JOURNAL_MEMBER_COUNT');
    }
    final lines = <Map<String, Object?>>[];
    final memberUuids = <String>{
      operationUuid,
      journalUuid,
      ledgerUuid,
      movementUuid,
    };
    var debitSum = 0;
    var creditSum = 0;
    for (final lineRaw in rawLines) {
      final line = _map(lineRaw);
      _requireFields(
          line, {'uuid', 'account_uuid', 'party_uuid', 'dr_minor', 'cr_minor'});
      final uuid = _uuid(line['uuid']);
      if (!memberUuids.add(uuid)) {
        throw const FinancialVoucherSyncException('REPEATED_MEMBER_UUID');
      }
      _uuid(line['account_uuid']);
      if (line['party_uuid'] != null) _uuid(line['party_uuid']);
      final dr = _integer(line['dr_minor'], 0, 999999999999);
      final cr = _integer(line['cr_minor'], 0, 999999999999);
      if (!((dr == amountMinor && cr == 0) || (cr == amountMinor && dr == 0))) {
        throw const FinancialVoucherSyncException('UNBALANCED_FINANCIAL_LINE');
      }
      debitSum += dr;
      creditSum += cr;
      lines.add(line);
    }
    if (debitSum != amountMinor || creditSum != amountMinor) {
      throw const FinancialVoucherSyncException('JOURNAL_NOT_BALANCED');
    }

    return database.transaction((txn) async {
      final branch = _single(
          await txn.query('branches', where: 'id=?', whereArgs: [branchId]),
          'BRANCH_MISSING');
      if (branch['uuid'] != expectedBranchUuid) {
        throw const FinancialVoucherSyncException('LOCAL_BRANCH_MISMATCH');
      }
      final prior = await txn.query('financial_operation_inbox',
          where: 'operation_uuid=?', whereArgs: [operationUuid]);
      if (prior.isNotEmpty) {
        if (prior.single['branch_id'] != branchId ||
            prior.single['payload_hash'] != payloadHash ||
            prior.single['voucher_uuid'] != operationUuid) {
          throw const FinancialVoucherSyncException(
              'OPERATION_REPLAY_CONFLICT');
        }
        return const FinancialVoucherApplyResult.duplicate();
      }
      // Same-device echo is already committed locally; never post it twice.
      final local = await txn.query('financial_operation_outbox',
          where: 'operation_uuid=?', whereArgs: [operationUuid]);
      if (local.isNotEmpty) {
        if (local.single['branch_id'] != branchId ||
            local.single['payload_hash'] != payloadHash) {
          throw const FinancialVoucherSyncException('LOCAL_ECHO_CONFLICT');
        }
        return const FinancialVoucherApplyResult.duplicate();
      }
      // F04: every member identity must be unused before the first insert.
      // Historical rows with NULL UUID remain local and are never rewritten.
      for (final member in <(String, String)>[
        ('journal_entries', journalUuid),
        ('lah_alayh_ledger', ledgerUuid),
        ('cash_transactions', movementUuid),
        for (final line in lines) ('journal_lines', line['uuid'] as String),
      ]) {
        if ((await txn.query(member.$1,
                columns: ['id'],
                where: 'uuid=?',
                whereArgs: [member.$2],
                limit: 1))
            .isNotEmpty) {
          throw const FinancialVoucherSyncException('MEMBER_UUID_CONFLICT');
        }
      }
      if ((await txn
              .query('vouchers', where: 'uuid=?', whereArgs: [operationUuid]))
          .isNotEmpty) {
        throw const FinancialVoucherSyncException('VOUCHER_UUID_CONFLICT');
      }

      final party = _single(
          await txn.query('parties',
              where: 'uuid=? AND branch_id=? AND is_deleted=0',
              whereArgs: [partyUuid, branchId]),
          'PARTY_DEPENDENCY_MISSING');
      final cashAccount = _single(
          await txn.query('cash_accounts',
              where: 'uuid=? AND branch_id=? AND is_deleted=0',
              whereArgs: [cashUuid, branchId]),
          'CASH_DEPENDENCY_MISSING');
      if (!{'CASHIER_DRAWER', 'MAIN_SAFE'}
          .contains(cashAccount['account_kind'])) {
        throw const FinancialVoucherSyncException('CASH_ACCOUNT_KIND_INVALID');
      }
      final cashGl = _single(
          await txn.query('chart_of_accounts',
              where: 'id=? AND branch_id=? AND is_deleted=0',
              whereArgs: [cashAccount['gl_account_id'], branchId]),
          'CASH_GL_DEPENDENCY_MISSING');
      final partyGl = _single(
          await txn.query('chart_of_accounts',
              where: 'code=? AND branch_id=? AND is_deleted=0',
              whereArgs: [isReceipt ? '1201' : '2101', branchId]),
          'PARTY_GL_DEPENDENCY_MISSING');
      _uuid(partyGl['uuid']);
      _uuid(cashGl['uuid']);
      if (partyGl['id'] == cashGl['id']) {
        throw const FinancialVoucherSyncException('GL_ACCOUNT_COLLISION');
      }

      final cashLines = lines
          .where((line) =>
              line['account_uuid'] == cashGl['uuid'] &&
              line['party_uuid'] == null)
          .toList();
      final partyLines = lines
          .where((line) =>
              line['account_uuid'] == partyGl['uuid'] &&
              line['party_uuid'] == partyUuid)
          .toList();
      if (cashLines.length != 1 || partyLines.length != 1) {
        throw const FinancialVoucherSyncException('INVALID_JOURNAL_ACCOUNTS');
      }
      if (cashLines.single[isReceipt ? 'dr_minor' : 'cr_minor'] !=
              amountMinor ||
          partyLines.single[isReceipt ? 'cr_minor' : 'dr_minor'] !=
              amountMinor) {
        throw const FinancialVoucherSyncException('INVALID_JOURNAL_SIDES');
      }

      final now = DateTime.now().toUtc().toIso8601String();
      Map<String, Object?> base(String uuid) => {
            'uuid': uuid,
            'branch_id': branchId,
            'created_at': now,
            'updated_at': now,
            'is_deleted': 0,
            'sync_status': 'SYNCED',
            'sync_version': 1,
          };
      // Destination display numbers are unique and deterministic. Never copy
      // a source-local sequence number or regenerate an economic event.
      final suffix = operationUuid.replaceAll('-', '');
      final voucherId = await txn.insert('vouchers', {
        ...base(operationUuid),
        'voucher_no': 'FS-V-$suffix',
        'voucher_type': voucher['type'],
        'voucher_date': voucherDate,
        'party_id': party['id'],
        'cash_account_id': cashAccount['id'],
        'amount': amount,
        'method': 'CASH',
        'description': 'سند متزامن',
      });
      final journalId = await txn.insert('journal_entries', {
        ...base(journalUuid),
        'entry_no': 'FS-JE-$suffix',
        'entry_date': journalDate,
        'description': 'قيد سند متزامن',
        'source_type': 'VOUCHER',
        'source_id': voucherId,
        'is_posted': 1,
      });
      for (final line in lines) {
        final isCash = line['account_uuid'] == cashGl['uuid'];
        await txn.insert('journal_lines', {
          ...base(line['uuid'] as String),
          'journal_entry_id': journalId,
          'account_id': isCash ? cashGl['id'] : partyGl['id'],
          'party_id': isCash ? null : party['id'],
          'dr_amount': (line['dr_minor'] as int) / scale,
          'cr_amount': (line['cr_minor'] as int) / scale,
          'memo': 'سند متزامن',
        });
      }
      await txn.insert('lah_alayh_ledger', {
        ...base(ledgerUuid),
        'party_id': party['id'],
        'entry_date': voucherDate,
        'entry_type': voucher['type'],
        'alayh_amount': isReceipt ? 0.0 : amount,
        'lah_amount': isReceipt ? amount : 0.0,
        'doc_type': 'VOUCHER',
        'doc_id': voucherId,
        'statement_ar': 'سند متزامن',
      });
      final newBalance = (cashAccount['current_balance'] as num).toDouble() +
          (isReceipt ? amount : -amount);
      await txn.update(
          'cash_accounts', {'current_balance': newBalance, 'updated_at': now},
          where: 'id=? AND branch_id=?',
          whereArgs: [cashAccount['id'], branchId]);
      await txn.insert('cash_transactions', {
        'uuid': movementUuid,
        'cash_account_id': cashAccount['id'],
        'tx_date': voucherDate,
        'direction': isReceipt ? 'IN' : 'OUT',
        'amount': amount,
        'tx_type': isReceipt ? 'RECEIPT_VOUCHER' : 'PAYMENT_VOUCHER',
        'doc_type': 'VOUCHER',
        'doc_id': voucherId,
        'balance_after': newBalance,
        'note': 'سند متزامن',
        'branch_id': branchId,
      });
      await txn.update('vouchers', {'journal_entry_id': journalId},
          where: 'id=? AND branch_id=?', whereArgs: [voucherId, branchId]);

      // The same read-only accounting proof used for local postings
      // validates the COMPLETE imported document before the receipt commits.
      await CashVoucherIntegrityValidator.validate(
          database: txn,
          branchId: branchId,
          voucherId: voucherId,
          fractionDigits: digits);
      await txn.insert('financial_operation_inbox', {
        'operation_uuid': operationUuid,
        'branch_id': branchId,
        'voucher_uuid': operationUuid,
        'payload_hash': payloadHash,
        'applied_at': now,
      });
      return const FinancialVoucherApplyResult.applied();
    });
  }

  /// Read-only FIFO: payloads remain local until a trusted relay is provided.
  static Future<List<Map<String, Object?>>> pending(
      Database database, int branchId,
      {int limit = 50}) {
    if (branchId <= 0 || limit < 1 || limit > 100) {
      throw ArgumentError('Invalid financial outbox query');
    }
    return database.query('financial_operation_outbox',
        where: "branch_id=? AND status='PENDING'",
        whereArgs: [branchId],
        orderBy: 'created_at,operation_uuid',
        limit: limit);
  }

  /// Called only after trusted relay ACK of the SAME operation and hash.
  static Future<void> acknowledge(
    Database database, {
    required int branchId,
    required String operationUuid,
    required String payloadHash,
    required bool trustedRelay,
  }) async {
    if (!trustedRelay) {
      throw const FinancialVoucherSyncException('UNTRUSTED_FINANCIAL_SOURCE');
    }
    await database.transaction((txn) async {
      final rows = await txn.query('financial_operation_outbox',
          where: 'branch_id=? AND operation_uuid=?',
          whereArgs: [branchId, operationUuid]);
      final row = _single(rows, 'OUTBOX_RECORD_MISSING');
      if (row['payload_hash'] != payloadHash) {
        throw const FinancialVoucherSyncException('OUTBOX_ACK_CONFLICT');
      }
      await txn.update(
          'financial_operation_outbox',
          {
            'status': 'SENT',
            'sent_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'branch_id=? AND operation_uuid=?',
          whereArgs: [branchId, operationUuid]);
    });
  }

  static String canonicalJson(Object? value) => jsonEncode(_canonical(value));

  static Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is List) return value.map(_canonical).toList();
    return value;
  }

  static Map<String, Object?> _map(Object? raw) {
    if (raw is! Map || raw.keys.any((key) => key is! String)) {
      throw const FinancialVoucherSyncException('INVALID_ENVELOPE_OBJECT');
    }
    return Map<String, Object?>.from(raw);
  }

  static void _requireFields(Map<String, Object?> value, Set<String> expected) {
    if (value.keys.toSet().difference(expected).isNotEmpty ||
        expected.difference(value.keys.toSet()).isNotEmpty) {
      throw const FinancialVoucherSyncException('INVALID_ENVELOPE_FIELDS');
    }
  }

  static Map<String, Object?> _single(
      List<Map<String, Object?>> rows, String error) {
    if (rows.length != 1) throw FinancialVoucherSyncException(error);
    return rows.single;
  }

  static String _uuid(Object? raw) {
    if (raw is! String || !GlobalUuid.isValid(raw)) {
      throw const FinancialVoucherSyncException('GLOBAL_UUID_REQUIRED');
    }
    return raw;
  }

  static int _integer(Object? raw, int min, int max) {
    if (raw is! int || raw < min || raw > max) {
      throw const FinancialVoucherSyncException('INVALID_MINOR_AMOUNT');
    }
    return raw;
  }

  static String _date(Object? raw) {
    if (raw is! String || raw.length < 10 || DateTime.tryParse(raw) == null) {
      throw const FinancialVoucherSyncException('INVALID_FINANCIAL_DATE');
    }
    return raw;
  }
}

class FinancialVoucherApplyResult {
  const FinancialVoucherApplyResult.applied() : applied = true;
  const FinancialVoucherApplyResult.duplicate() : applied = false;
  final bool applied;
}

class FinancialVoucherSyncException implements Exception {
  const FinancialVoucherSyncException(this.code);
  final String code;
  @override
  String toString() => 'FinancialVoucherSyncException: $code';
}
