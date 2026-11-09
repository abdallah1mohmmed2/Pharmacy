import 'dart:math';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/erp_models.dart';
import '../models/clinical_and_rx_models.dart';
import 'fefo_allocator_service.dart';
import 'financial_voucher_operation.dart';

class PostingAndSalesService {
  PostingAndSalesService(
      {DatabaseHelper? helper, int? financialSyncFractionDigits})
      : _helper = helper ?? DatabaseHelper.instance,
        _financialSyncFractionDigits = financialSyncFractionDigits;
  final DatabaseHelper _helper;
  // Null by default: no financial capture until a trusted currency/identity
  // configuration is approved by the caller. The normal posting is unchanged.
  final int? _financialSyncFractionDigits;
  final FefoAllocator _fefo = FefoAllocator();
  // RFC 4122 v4 identifiers for NEW postings only. Historical local IDs
  // remain untouched until a reviewed identity-mapping migration exists.
  final Random _uuidRandom = Random.secure();

  String _uuid() {
    final bytes = List<int>.generate(16, (_) => _uuidRandom.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex =
        bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Map<String, Object?> _base(int branchId) => {
        'uuid': _uuid(),
        'branch_id': branchId,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'is_deleted': 0,
        'sync_status': 'LOCAL',
        'sync_version': 1
      };

  static bool isBalancedAmounts(double debit, double credit) =>
      debit > 0 && (debit - credit).abs() <= 0.005;

  Future<int> postBalancedEntry(Transaction txn,
      {required int branchId,
      required String description,
      required String sourceType,
      required int sourceId,
      required List<
              ({
                int accountId,
                double debit,
                double credit,
                int? partyId,
                String memo
              })>
          lines}) async {
    final debit = lines.fold<double>(0, (s, l) => s + l.debit);
    final credit = lines.fold<double>(0, (s, l) => s + l.credit);
    if (!isBalancedAmounts(debit, credit))
      throw StateError('القيد المحاسبي غير متوازن');
    final no = 'JE-' + DateTime.now().microsecondsSinceEpoch.toString();
    final entryId = await txn.insert('journal_entries', {
      ..._base(branchId),
      'entry_no': no,
      'entry_date': DateTime.now().toIso8601String(),
      'description': description,
      'source_type': sourceType,
      'source_id': sourceId,
      'is_posted': 1
    });
    for (final line in lines) {
      await txn.insert('journal_lines', {
        ..._base(branchId),
        'journal_entry_id': entryId,
        'account_id': line.accountId,
        'party_id': line.partyId,
        'dr_amount': line.debit,
        'cr_amount': line.credit,
        'memo': line.memo
      });
    }
    return entryId;
  }

  Future<int> postSale(
      {required int branchId,
      required int cashierUserId,
      required List<CartItemModel> items,
      required String saleType,
      required List<
              ({
                int cashAccountId,
                double amount,
                String method,
                String? walletRef
              })>
          payments,
      int customerPartyId = 0,
      double discountAmount = 0,
      required ClinicalVerdict clinicalVerdict}) async {
    if (items.isEmpty) throw ArgumentError('لا يمكن حفظ فاتورة فارغة');
    if (clinicalVerdict.hasUnresolvedCritical)
      throw StateError(
          'لا يمكن ترحيل الفاتورة قبل توثيق قرارات التنبيهات السريرية الحرجة');
    return (await _helper.database).transaction((txn) async {
      final subtotal = items.fold<double>(0, (s, i) => s + i.lineTotal);
      final net =
          (subtotal - discountAmount).clamp(0, double.infinity).toDouble();
      final paid = payments.fold<double>(0, (s, p) => s + p.amount);
      if (paid - net > 0.005)
        throw StateError('إجمالي المدفوع أكبر من صافي الفاتورة');
      final remaining = (net - paid).clamp(0, double.infinity).toDouble();
      if (remaining > 0 && customerPartyId <= 0)
        throw StateError('اختر العميل لتسجيل المبلغ المتبقي');
      final activeShiftRows = await txn.query('cashier_shifts',
          columns: ['id'],
          where: "branch_id=? AND user_id=? AND status='OPEN'",
          whereArgs: [branchId, cashierUserId],
          orderBy: 'id DESC',
          limit: 1);
      final int? activeShiftId =
          activeShiftRows.isEmpty ? null : activeShiftRows.first['id'] as int;
      final invoiceNo = await _nextNumber(txn, branchId, 'INVOICE');
      final invoiceId = await txn.insert('sales_invoices', {
        ..._base(branchId),
        'invoice_no': invoiceNo,
        'invoice_date': DateTime.now().toIso8601String(),
        'cashier_user_id': cashierUserId,
        'customer_party_id': customerPartyId <= 0 ? null : customerPartyId,
        'sale_type': saleType,
        'status': 'COMPLETED',
        'subtotal': subtotal,
        'discount_amount': discountAmount,
        'net_total': net,
        'paid_total': paid,
        'remaining_alayh': remaining,
        'total_cost': 0
      });
      double actualTotalCost = 0;
      for (final item in items) {
        final int drugId =
            item.drug.id ?? (throw StateError('معرّف الدواء غير محفوظ'));
        final drugRows = await txn.query('drugs',
            columns: ['units_per_pack', 'is_controlled'],
            where: 'id=? AND is_deleted=0',
            whereArgs: [drugId]);
        if (drugRows.isEmpty) throw StateError('الصنف غير موجود');
        if ((drugRows.first['is_controlled'] as num? ?? 0) == 1)
          throw StateError(
              'الأدوية المراقبة تُصرف من شاشة الوصفات مع توثيق بيانات المريض والمستلم فقط');
        final unitsValue = drugRows.first['units_per_pack'];
        final int units = unitsValue is num
            ? unitsValue.toInt()
            : item.drug.effectiveUnitsPerPack;
        final invoiceItemId = await txn.insert('sales_invoice_items', {
          ..._base(branchId),
          'invoice_id': invoiceId,
          'drug_id': drugId,
          'sell_unit': item.sellUnit,
          'qty_in_sell_unit': item.quantity,
          'qty_units': item.baseUnits,
          'unit_price_sell_unit': item.unitPrice,
          'line_discount_amount': item.discount,
          'line_total': item.lineTotal,
          'line_cost': 0,
          'is_substitute': item.isSubstitute ? 1 : 0,
          'substituted_for_drug_id': item.substitutedForDrugId
        });
        final allocations = await _fefo.allocateAndApply(
            txn: txn,
            drugId: drugId,
            needUnits: item.baseUnits,
            unitsPerPack: units,
            invoiceItemId: invoiceItemId,
            warehouseId: null,
            unitPrice: item.unitPrice,
            docType: 'SALE',
            docId: invoiceId);
        final lineCost = allocations.fold<double>(
            0, (sum, a) => sum + a.qtyUnits * a.unitCost);
        actualTotalCost += lineCost;
        await txn.update('sales_invoice_items', {'line_cost': lineCost},
            where: 'id=?', whereArgs: [invoiceItemId]);
      }
      await txn.update('sales_invoices', {'total_cost': actualTotalCost},
          where: 'id=?', whereArgs: [invoiceId]);
      final journalLines = <({
        int accountId,
        double debit,
        double credit,
        int? partyId,
        String memo
      })>[];
      for (final payment in payments) {
        if (payment.method == 'WALLET' &&
            (payment.walletRef == null || payment.walletRef!.trim().length < 6))
          throw StateError('رقم إشعار المحفظة إلزامي');
        await txn.insert('sales_payments', {
          ..._base(branchId),
          'invoice_id': invoiceId,
          'cash_account_id': payment.cashAccountId,
          'method': payment.method,
          'amount': payment.amount,
          'wallet_ref_no': payment.walletRef
        });
        await txn.rawUpdate(
            'UPDATE cash_accounts SET current_balance=current_balance+?,updated_at=? WHERE id=?',
            [
              payment.amount,
              DateTime.now().toIso8601String(),
              payment.cashAccountId
            ]);
        final cashBalanceRows = await txn.query('cash_accounts',
            columns: ['current_balance'],
            where: 'id=?',
            whereArgs: [payment.cashAccountId],
            limit: 1);
        await txn.insert('cash_transactions', {
          'cash_account_id': payment.cashAccountId,
          'tx_date': DateTime.now().toIso8601String(),
          'direction': 'IN',
          'amount': payment.amount,
          'tx_type': 'SALE',
          'doc_type': 'INVOICE',
          'doc_id': invoiceId,
          'wallet_ref_no': payment.walletRef,
          'cashier_shift_id': activeShiftId,
          'balance_after':
              (cashBalanceRows.first['current_balance'] as num).toDouble(),
          'note': 'تحصيل فاتورة بيع',
          'branch_id': branchId
        });
        final cashAccount = await txn.query('cash_accounts',
            columns: ['gl_account_id', 'account_kind'],
            where: 'id=?',
            whereArgs: [payment.cashAccountId]);
        if (cashAccount.isEmpty) throw StateError('حساب التحصيل غير موجود');
        final kind = cashAccount.first['account_kind'] as String;
        if (payment.method == 'WALLET' && kind != 'WALLET')
          throw StateError('اختر محفظة إلكترونية لطريقة الدفع هذه');
        if (payment.method == 'CASH' && kind == 'WALLET')
          throw StateError('اختر الصندوق النقدي أو غيّر وسيلة الدفع إلى محفظة');
        if (payment.method == 'BANK' && kind != 'BANK')
          throw StateError('اختر الحساب البنكي لطريقة الدفع هذه');
        final glValue = cashAccount.first['gl_account_id'];
        if (glValue == null)
          throw StateError('اربط حساب الصندوق بدليل الحسابات أولاً');
        final int gl = int.parse(glValue.toString());
        journalLines.add((
          accountId: gl,
          debit: payment.amount,
          credit: 0,
          partyId: null,
          memo: 'تحصيل فاتورة'
        ));
      }
      final revenue = await _accountId(txn, '4101');
      if (remaining > 0 && customerPartyId > 0) {
        final creditRows = await txn.rawQuery(
            'SELECT p.credit_limit, COALESCE(v.net,0) AS net FROM parties p LEFT JOIN v_party_balance v ON v.party_id=p.id WHERE p.id=?',
            [customerPartyId]);
        if (creditRows.isEmpty) throw StateError('العميل غير موجود');
        final limit = (creditRows.first['credit_limit'] as num).toDouble();
        final existing = (creditRows.first['net'] as num).toDouble();
        if (limit > 0 && existing + remaining > limit)
          throw StateError('تجاوز الحد الائتماني للعميل');
        await txn.insert('lah_alayh_ledger', {
          ..._base(branchId),
          'party_id': customerPartyId,
          'entry_date': DateTime.now().toIso8601String(),
          'entry_type': 'SALE',
          'alayh_amount': remaining,
          'lah_amount': 0,
          'doc_type': 'INVOICE',
          'doc_id': invoiceId,
          'statement_ar': 'الجزء المتبقي من الفاتورة ' + invoiceNo
        });
        final receivable = await _accountId(txn, '1201');
        journalLines.add((
          accountId: receivable,
          debit: remaining,
          credit: 0,
          partyId: customerPartyId,
          memo: 'ذمم فاتورة'
        ));
      }
      journalLines.add((
        accountId: revenue,
        debit: 0,
        credit: net,
        partyId: null,
        memo: 'إيراد المبيعات'
      ));
      final cost = actualTotalCost;
      if (cost > 0) {
        final inventory = await _accountId(txn, '1301');
        final cogs = await _accountId(txn, '5101');
        journalLines.add((
          accountId: cogs,
          debit: cost,
          credit: 0,
          partyId: null,
          memo: 'تكلفة المبيعات'
        ));
        journalLines.add((
          accountId: inventory,
          debit: 0,
          credit: cost,
          partyId: null,
          memo: 'تخفيض المخزون'
        ));
      }
      final entryId = await postBalancedEntry(txn,
          branchId: branchId,
          description: 'فاتورة بيع ' + invoiceNo,
          sourceType: 'SALE',
          sourceId: invoiceId,
          lines: journalLines);
      await txn.update('sales_invoices', {'journal_entry_id': entryId},
          where: 'id=?', whereArgs: [invoiceId]);
      return invoiceId;
    });
  }

  Future<int> postVoucher(
      {required int branchId,
      required String voucherNo,
      required String voucherType,
      required int partyId,
      int cashAccountId = -1,
      required double amount,
      required String method,
      required String description,
      String? walletRefNo}) async {
    if (amount <= 0) throw ArgumentError('المبلغ يجب أن يكون أكبر من صفر');
    if (method == 'WALLET' &&
        (walletRefNo == null || walletRefNo.trim().length < 6))
      throw ArgumentError('رقم إشعار المحفظة مطلوب');
    if (method == 'OFFSET' && voucherType != 'SETTLEMENT')
      throw ArgumentError('وسيلة التسوية بدون نقد مخصصة لسند التسوية فقط');
    if (!['RECEIPT', 'PAYMENT', 'SETTLEMENT'].contains(voucherType))
      throw ArgumentError('نوع سند غير صالح');
    return (await _helper.database).transaction((txn) async {
      final generatedVoucherNo = await _nextNumber(txn, branchId, 'VOUCHER');
      final isOffset = method == 'OFFSET';
      final int cashId = cashAccountId;
      Map<String, Object?>? cashRow;
      if (!isOffset) {
        if (cashId < 0) throw StateError('حساب الصندوق غير موجود');
        final cashRows = await txn
            .query('cash_accounts', where: 'id=?', whereArgs: [cashId]);
        if (cashRows.isEmpty) throw StateError('حساب الصندوق غير موجود');
        cashRow = cashRows.first;
        final kind = cashRow['account_kind'] as String;
        if (method == 'WALLET' && kind != 'WALLET')
          throw StateError('اختر محفظة إلكترونية');
        if (method == 'CASH' && kind == 'WALLET')
          throw StateError('اختر الصندوق النقدي');
        if (method == 'BANK' && kind != 'BANK')
          throw StateError('اختر الحساب البنكي');
      }
      final party =
          await txn.query('parties', where: 'id=?', whereArgs: [partyId]);
      if (party.isEmpty) throw StateError('الطرف غير موجود');
      final now = DateTime.now().toIso8601String();
      final voucherId = await txn.insert('vouchers', {
        ..._base(branchId),
        'voucher_no': generatedVoucherNo,
        'voucher_type': voucherType,
        'voucher_date': now,
        'party_id': partyId,
        'cash_account_id': isOffset ? null : cashId,
        'amount': amount,
        'method': method,
        'wallet_ref_no': walletRefNo,
        'description': description
      });
      final shiftRows = !isOffset
          ? await txn.query('cashier_shifts',
              columns: ['id'],
              where: "branch_id=? AND status='OPEN'",
              whereArgs: [branchId],
              orderBy: 'id DESC',
              limit: 1)
          : <Map<String, Object?>>[];
      final int? voucherShiftId =
          shiftRows.isEmpty ? null : shiftRows.first['id'] as int;
      final isReceipt = voucherType == 'RECEIPT';
      if (!isOffset) {
        await txn.insert('lah_alayh_ledger', {
          ..._base(branchId),
          'party_id': partyId,
          'entry_date': now,
          'entry_type': voucherType,
          'alayh_amount': isReceipt ? 0.0 : amount,
          'lah_amount': isReceipt ? amount : 0.0,
          'doc_type': 'VOUCHER',
          'doc_id': voucherId,
          'statement_ar':
              description.isEmpty ? 'سند ' + generatedVoucherNo : description
        });
      }
      final partyGl = await _accountId(txn, isReceipt ? '1201' : '2101');
      final lines = <({
        int accountId,
        double debit,
        double credit,
        int? partyId,
        String memo
      })>[];
      if (isOffset) {
        final balanceRows = await txn.rawQuery(
            'SELECT net FROM v_party_balance WHERE party_id=?', [partyId]);
        final net = balanceRows.isEmpty
            ? 0.0
            : (balanceRows.first['net'] as num).toDouble();
        if (net.abs() < 0.005)
          throw StateError('لا يوجد رصيد قائم لإجراء التسوية');
        if (amount > net.abs() + 0.005)
          throw StateError('مبلغ التسوية يتجاوز الرصيد القائم');
        final adjustment = await _accountId(txn, '5304');
        final offsetPartyGl = await _accountId(txn, net > 0 ? '1201' : '2101');
        if (net > 0) {
          await txn.insert('lah_alayh_ledger', {
            ..._base(branchId),
            'party_id': partyId,
            'entry_date': now,
            'entry_type': 'SETTLEMENT',
            'alayh_amount': 0,
            'lah_amount': amount,
            'doc_type': 'VOUCHER',
            'doc_id': voucherId,
            'statement_ar': 'تسوية رصيد'
          });
          lines.add((
            accountId: adjustment,
            debit: amount,
            credit: 0,
            partyId: null,
            memo: 'تسوية رصيد مستحق'
          ));
          lines.add((
            accountId: offsetPartyGl,
            debit: 0,
            credit: amount,
            partyId: partyId,
            memo: 'تخفيض رصيد الطرف'
          ));
        } else {
          await txn.insert('lah_alayh_ledger', {
            ..._base(branchId),
            'party_id': partyId,
            'entry_date': now,
            'entry_type': 'SETTLEMENT',
            'alayh_amount': amount,
            'lah_amount': 0,
            'doc_type': 'VOUCHER',
            'doc_id': voucherId,
            'statement_ar': 'تسوية رصيد'
          });
          lines.add((
            accountId: offsetPartyGl,
            debit: amount,
            credit: 0,
            partyId: partyId,
            memo: 'تخفيض التزام الطرف'
          ));
          lines.add((
            accountId: adjustment,
            debit: 0,
            credit: amount,
            partyId: null,
            memo: 'تسوية رصيد مستحق'
          ));
        }
      } else {
        final row = cashRow!;
        final cashGlValue = row['gl_account_id'];
        if (cashGlValue is! int)
          throw StateError('اربط حساب الصندوق بدليل الحسابات أولاً');
        final int cashGl = int.parse(cashGlValue.toString());
        await txn.rawUpdate(
            'UPDATE cash_accounts SET current_balance=current_balance+?,updated_at=? WHERE id=?',
            [isReceipt ? amount : -amount, now, cashId]);
        final afterRows = await txn.query('cash_accounts',
            columns: ['current_balance'],
            where: 'id=?',
            whereArgs: [cashId],
            limit: 1);
        await txn.insert('cash_transactions', {
          'uuid': _uuid(),
          'cash_account_id': cashId,
          'tx_date': now,
          'direction': isReceipt ? 'IN' : 'OUT',
          'amount': amount,
          'tx_type': isReceipt ? 'RECEIPT_VOUCHER' : 'PAYMENT_VOUCHER',
          'doc_type': 'VOUCHER',
          'doc_id': voucherId,
          'wallet_ref_no': walletRefNo,
          'cashier_shift_id': voucherShiftId,
          'balance_after':
              (afterRows.first['current_balance'] as num).toDouble(),
          'note': description,
          'branch_id': branchId
        });
        if (isReceipt) {
          lines.add((
            accountId: cashGl,
            debit: amount,
            credit: 0,
            partyId: null,
            memo: 'استلام نقدية'
          ));
          lines.add((
            accountId: partyGl,
            debit: 0,
            credit: amount,
            partyId: partyId,
            memo: 'تخفيض رصيد الطرف'
          ));
        } else {
          lines.add((
            accountId: partyGl,
            debit: amount,
            credit: 0,
            partyId: partyId,
            memo: 'تسديد للطرف'
          ));
          lines.add((
            accountId: cashGl,
            debit: 0,
            credit: amount,
            partyId: null,
            memo: 'صرف نقدية'
          ));
        }
      }
      final entryId = await postBalancedEntry(txn,
          branchId: branchId,
          description: description,
          sourceType: 'VOUCHER',
          sourceId: voucherId,
          lines: lines);
      await txn.update('vouchers', {'journal_entry_id': entryId},
          where: 'id=?', whereArgs: [voucherId]);
      // P0-06: only explicitly configured CASH vouchers emit the complete
      // immutable outbox envelope inside the SAME business transaction.
      // Invalid provisioned identities or unbalanced docs abort the posting.
      if (_financialSyncFractionDigits != null && method == 'CASH') {
        await FinancialVoucherOperation.capturePostedCashVoucher(
          txn,
          branchId: branchId,
          voucherId: voucherId,
          fractionDigits: _financialSyncFractionDigits!,
        );
      }
      return voucherId;
    });
  }

  Future<String> _nextNumber(
      Transaction txn, int branchId, String docType) async {
    final year = DateTime.now().year;
    final rows = await txn.query('number_sequences',
        where: 'branch_id=? AND doc_type=? AND year=?',
        whereArgs: [branchId, docType, year],
        limit: 1);
    if (rows.isEmpty) throw StateError('تسلسل المستند غير مهيأ: ' + docType);
    final row = rows.first;
    final next = (row['last_no'] as int) + 1;
    final id = row['id'] as int;
    final prefix = row['prefix'] as String;
    final pad = row['pad_length'] as int;
    await txn.update('number_sequences',
        {'last_no': next, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id=?', whereArgs: [id]);
    return prefix +
        '-' +
        year.toString() +
        '-' +
        next.toString().padLeft(pad, '0');
  }

  Future<int> _accountId(Transaction txn, String code) async {
    final rows = await txn.query('chart_of_accounts',
        columns: ['id'], where: 'code=?', whereArgs: [code], limit: 1);
    if (rows.isEmpty)
      throw StateError('الحساب غير موجود في دليل الحسابات: ' + code);
    return rows.first['id'] as int;
  }
}
