// lib/data/models/finance_hr_partner_models.dart
import 'dart:convert';

double _number(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
int _integer(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
String _string(Object? value, [String fallback = '']) =>
    value?.toString() ?? fallback;
Map<String, int> _denominations(Object? value) {
  if (value is Map)
    return value.map((k, v) => MapEntry(k.toString(), _integer(v)));
  if (value is String && value.isNotEmpty) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map)
        return decoded.map((k, v) => MapEntry(k.toString(), _integer(v)));
    } catch (_) {}
  }
  return <String, int>{};
}

class CashTransactionModel {
  const CashTransactionModel(
      {this.id,
      required this.cashAccountId,
      required this.txDate,
      required this.direction,
      required this.amount,
      required this.txType,
      this.docType,
      this.docId,
      this.walletRefNo,
      this.cashierShiftId,
      this.balanceAfter = 0,
      this.note});
  final int? id, cashAccountId, docId, cashierShiftId;
  final String txDate, direction, txType;
  final double amount, balanceAfter;
  final String? docType, walletRefNo, note;
  factory CashTransactionModel.fromMap(Map<String, Object?> m) =>
      CashTransactionModel(
          id: m['id'] as int?,
          cashAccountId: _integer(m['cash_account_id']),
          txDate: _string(m['tx_date']),
          direction: _string(m['direction']),
          amount: _number(m['amount']),
          txType: _string(m['tx_type']),
          docType: m['doc_type'] as String?,
          docId: m['doc_id'] as int?,
          walletRefNo: m['wallet_ref_no'] as String?,
          cashierShiftId: m['cashier_shift_id'] as int?,
          balanceAfter: _number(m['balance_after']),
          note: m['note'] as String?);
  Map<String, Object?> toMap() => {
        'cash_account_id': cashAccountId,
        'tx_date': txDate,
        'direction': direction,
        'amount': amount,
        'tx_type': txType,
        'doc_type': docType,
        'doc_id': docId,
        'wallet_ref_no': walletRefNo,
        'cashier_shift_id': cashierShiftId,
        'balance_after': balanceAfter,
        'note': note
      };
}

class WorkShiftModel {
  const WorkShiftModel(
      {this.id,
      required this.nameAr,
      required this.startTime,
      required this.endTime,
      this.crossesMidnight = false});
  final int? id;
  final String nameAr, startTime, endTime;
  final bool crossesMidnight;
  Map<String, Object?> toMap() => {
        'name_ar': nameAr,
        'start_time': startTime,
        'end_time': endTime,
        'crosses_midnight': crossesMidnight ? 1 : 0
      };
  factory WorkShiftModel.fromMap(Map<String, Object?> m) => WorkShiftModel(
      id: m['id'] as int?,
      nameAr: _string(m['name_ar']),
      startTime: _string(m['start_time']),
      endTime: _string(m['end_time']),
      crossesMidnight: _integer(m['crosses_midnight']) == 1);
}

class CashierShiftModel {
  const CashierShiftModel(
      {this.id,
      required this.shiftNo,
      required this.userId,
      this.cashierPartyId,
      this.drawerAccountId,
      this.workShiftId,
      required this.openedAt,
      required this.openingCash,
      this.closedAt,
      this.expectedCash,
      this.countedCash,
      this.diffAmount,
      this.expectedWallets = const <String, double>{},
      this.countedWallets = const <String, double>{},
      this.diffHandling = 'NONE',
      this.countedDenominations = const <String, int>{},
      this.handoverToUserId,
      this.status = 'OPEN'});
  final int? id,
      userId,
      cashierPartyId,
      drawerAccountId,
      workShiftId,
      handoverToUserId;
  final String shiftNo, openedAt, diffHandling, status;
  final double openingCash;
  final String? closedAt;
  final double? expectedCash, countedCash, diffAmount;
  final Map<String, double> expectedWallets, countedWallets;
  final Map<String, int> countedDenominations;
  double get denominationTotal => countedDenominations.entries
      .fold(0, (sum, e) => sum + (_number(e.key) * e.value));
  Map<String, Object?> toMap() => {
        'shift_no': shiftNo,
        'user_id': userId,
        'cashier_party_id': cashierPartyId,
        'drawer_account_id': drawerAccountId,
        'work_shift_id': workShiftId,
        'opened_at': openedAt,
        'opening_cash': openingCash,
        'closed_at': closedAt,
        'expected_cash': expectedCash,
        'counted_cash': countedCash,
        'diff_amount': diffAmount,
        'expected_wallets_json': jsonEncode(expectedWallets),
        'counted_wallets_json': jsonEncode(countedWallets),
        'diff_handling': diffHandling,
        'counted_denominations_json': jsonEncode(countedDenominations),
        'handover_to_user_id': handoverToUserId,
        'status': status
      };
  factory CashierShiftModel.fromMap(Map<String, Object?> m) =>
      CashierShiftModel(
          id: m['id'] as int?,
          shiftNo: _string(m['shift_no']),
          userId: _integer(m['user_id']),
          cashierPartyId: m['cashier_party_id'] as int?,
          drawerAccountId: m['drawer_account_id'] as int?,
          workShiftId: m['work_shift_id'] as int?,
          openedAt: _string(m['opened_at']),
          openingCash: _number(m['opening_cash']),
          closedAt: m['closed_at'] as String?,
          expectedCash:
              m['expected_cash'] == null ? null : _number(m['expected_cash']),
          countedCash:
              m['counted_cash'] == null ? null : _number(m['counted_cash']),
          diffAmount:
              m['diff_amount'] == null ? null : _number(m['diff_amount']),
          expectedWallets: _doubleMap(m['expected_wallets_json']),
          countedWallets: _doubleMap(m['counted_wallets_json']),
          diffHandling: _string(m['diff_handling'], 'NONE'),
          countedDenominations: _denominations(m['counted_denominations_json']),
          handoverToUserId: m['handover_to_user_id'] as int?,
          status: _string(m['status'], 'OPEN'));
}

Map<String, double> _doubleMap(Object? value) {
  if (value is Map)
    return value.map((k, v) => MapEntry(k.toString(), _number(v)));
  if (value is String && value.isNotEmpty) {
    try {
      final d = jsonDecode(value);
      if (d is Map) return d.map((k, v) => MapEntry(k.toString(), _number(v)));
    } catch (_) {}
  }
  return <String, double>{};
}

class ExpenseCategoryModel {
  const ExpenseCategoryModel(
      {this.id,
      required this.nameAr,
      this.recurrence = 'NONE',
      this.monthlyBudgetLimit = 0,
      this.glAccountId});
  final int? id, glAccountId;
  final String nameAr, recurrence;
  final double monthlyBudgetLimit;
  Map<String, Object?> toMap() => {
        'name_ar': nameAr,
        'recurrence': recurrence,
        'monthly_budget_limit': monthlyBudgetLimit,
        'gl_account_id': glAccountId
      };
  factory ExpenseCategoryModel.fromMap(Map<String, Object?> m) =>
      ExpenseCategoryModel(
          id: m['id'] as int?,
          nameAr: _string(m['name_ar']),
          recurrence: _string(m['recurrence'], 'NONE'),
          monthlyBudgetLimit: _number(m['monthly_budget_limit']),
          glAccountId: m['gl_account_id'] as int?);
}

class ExpenseModel {
  const ExpenseModel(
      {this.id,
      required this.expenseNo,
      required this.categoryId,
      required this.expenseDate,
      required this.amount,
      required this.cashAccountId,
      this.paidTo,
      this.description,
      this.attachmentPath,
      this.isRecurringInstance = false,
      this.cashierShiftId,
      this.journalEntryId});
  final int? id, categoryId, cashAccountId, cashierShiftId, journalEntryId;
  final String expenseNo, expenseDate;
  final double amount;
  final String? paidTo, description, attachmentPath;
  final bool isRecurringInstance;
  Map<String, Object?> toMap() => {
        'expense_no': expenseNo,
        'category_id': categoryId,
        'expense_date': expenseDate,
        'amount': amount,
        'cash_account_id': cashAccountId,
        'paid_to': paidTo,
        'description': description,
        'attachment_path': attachmentPath,
        'is_recurring_instance': isRecurringInstance ? 1 : 0,
        'cashier_shift_id': cashierShiftId,
        'journal_entry_id': journalEntryId
      };
  factory ExpenseModel.fromMap(Map<String, Object?> m) => ExpenseModel(
      id: m['id'] as int?,
      expenseNo: _string(m['expense_no']),
      categoryId: _integer(m['category_id']),
      expenseDate: _string(m['expense_date']),
      amount: _number(m['amount']),
      cashAccountId: _integer(m['cash_account_id']),
      paidTo: m['paid_to'] as String?,
      description: m['description'] as String?,
      attachmentPath: m['attachment_path'] as String?,
      isRecurringInstance: _integer(m['is_recurring_instance']) == 1,
      cashierShiftId: m['cashier_shift_id'] as int?,
      journalEntryId: m['journal_entry_id'] as int?);
}

class EmployeeModel {
  const EmployeeModel(
      {this.id,
      required this.partyId,
      required this.jobTitle,
      this.pharmacistLicenseNo,
      this.hireDate,
      this.terminationDate,
      this.payType = 'MONTHLY',
      this.payRate = 0,
      this.maxAdvancePct = 50,
      this.nameAr = ''});
  final int? id, partyId;
  final String jobTitle, payType, nameAr;
  final String? pharmacistLicenseNo, hireDate, terminationDate;
  final double payRate, maxAdvancePct;
  Map<String, Object?> toMap() => {
        'party_id': partyId,
        'job_title': jobTitle,
        'pharmacist_license_no': pharmacistLicenseNo,
        'hire_date': hireDate,
        'termination_date': terminationDate,
        'pay_type': payType,
        'pay_rate': payRate,
        'max_advance_pct': maxAdvancePct
      };
  factory EmployeeModel.fromMap(Map<String, Object?> m) => EmployeeModel(
      id: m['id'] as int?,
      partyId: _integer(m['party_id']),
      jobTitle: _string(m['job_title'], 'OTHER'),
      pharmacistLicenseNo: m['pharmacist_license_no'] as String?,
      hireDate: m['hire_date'] as String?,
      terminationDate: m['termination_date'] as String?,
      payType: _string(m['pay_type'], 'MONTHLY'),
      payRate: _number(m['pay_rate']),
      maxAdvancePct: _number(m['max_advance_pct'] ?? 50),
      nameAr: _string(m['name_ar']));
}

class AttendanceModel {
  const AttendanceModel(
      {this.id,
      required this.employeeId,
      required this.workDate,
      this.workShiftId,
      this.checkIn,
      this.checkOut,
      this.status = 'PRESENT',
      this.overtimeHours = 0,
      this.wageEarned = 0});
  final int? id, employeeId, workShiftId;
  final String workDate, status;
  final String? checkIn, checkOut;
  final double overtimeHours, wageEarned;
  Map<String, Object?> toMap() => {
        'employee_id': employeeId,
        'work_date': workDate,
        'work_shift_id': workShiftId,
        'check_in': checkIn,
        'check_out': checkOut,
        'status': status,
        'overtime_hours': overtimeHours,
        'wage_earned': wageEarned
      };
  factory AttendanceModel.fromMap(Map<String, Object?> m) => AttendanceModel(
      id: m['id'] as int?,
      employeeId: _integer(m['employee_id']),
      workDate: _string(m['work_date']),
      workShiftId: m['work_shift_id'] as int?,
      checkIn: m['check_in'] as String?,
      checkOut: m['check_out'] as String?,
      status: _string(m['status'], 'PRESENT'),
      overtimeHours: _number(m['overtime_hours']),
      wageEarned: _number(m['wage_earned']));
}

class PayrollRunModel {
  const PayrollRunModel(
      {this.id,
      required this.employeeId,
      required this.periodCode,
      this.grossLah = 0,
      this.bonusesLah = 0,
      this.advancesAlayh = 0,
      this.deductionsAlayh = 0,
      this.status = 'DRAFT',
      this.paidVoucherId});
  final int? id, employeeId, paidVoucherId;
  final String periodCode, status;
  final double grossLah, bonusesLah, advancesAlayh, deductionsAlayh;
  double get netAmount =>
      grossLah + bonusesLah - advancesAlayh - deductionsAlayh;
  Map<String, Object?> toMap() => {
        'employee_id': employeeId,
        'period_code': periodCode,
        'gross_lah': grossLah,
        'bonuses_lah': bonusesLah,
        'advances_alayh': advancesAlayh,
        'deductions_alayh': deductionsAlayh,
        'net_amount': netAmount,
        'status': status,
        'paid_voucher_id': paidVoucherId
      };
  factory PayrollRunModel.fromMap(Map<String, Object?> m) => PayrollRunModel(
      id: m['id'] as int?,
      employeeId: _integer(m['employee_id']),
      periodCode: _string(m['period_code']),
      grossLah: _number(m['gross_lah']),
      bonusesLah: _number(m['bonuses_lah']),
      advancesAlayh: _number(m['advances_alayh']),
      deductionsAlayh: _number(m['deductions_alayh']),
      status: _string(m['status'], 'DRAFT'),
      paidVoucherId: m['paid_voucher_id'] as int?);
}

class PartnerModel {
  const PartnerModel(
      {this.id,
      required this.partyId,
      this.capitalAmount = 0,
      this.sharesCount,
      this.percentage,
      this.needsInput = false,
      this.joinDate,
      this.isActive = true,
      this.nameAr = ''});
  final int? id, partyId;
  final double capitalAmount;
  final int? sharesCount;
  final double? percentage;
  final bool needsInput, isActive;
  final String? joinDate;
  final String nameAr;
  double derivedShareRatio(int totalActiveShares) => totalActiveShares <= 0
      ? 0
      : ((sharesCount ?? 0) / totalActiveShares) * 100;
  Map<String, Object?> toMap() => {
        'party_id': partyId,
        'capital_amount': capitalAmount,
        'shares_count': sharesCount,
        'percentage': percentage,
        'needs_input': needsInput ? 1 : 0,
        'join_date': joinDate,
        'is_active': isActive ? 1 : 0
      };
  factory PartnerModel.fromMap(Map<String, Object?> m) => PartnerModel(
      id: m['id'] as int?,
      partyId: _integer(m['party_id']),
      capitalAmount: _number(m['capital_amount']),
      sharesCount: m['shares_count'] as int?,
      percentage: m['percentage'] == null ? null : _number(m['percentage']),
      needsInput: _integer(m['needs_input']) == 1,
      joinDate: m['join_date'] as String?,
      isActive: _integer(m['is_active'] ?? 1) == 1,
      nameAr: _string(m['name_ar']));
}

class PartnerDistributionModel {
  const PartnerDistributionModel(
      {this.id,
      required this.distributionNo,
      required this.periodCode,
      required this.distributionMode,
      this.totalRevenue = 0,
      this.totalCogs = 0,
      this.totalExpensesAndLosses = 0,
      this.netProfit = 0,
      this.reservePct = 0,
      this.distributableProfit = 0,
      this.status = 'DRAFT',
      this.journalEntryId});
  final int? id, journalEntryId;
  final String distributionNo, periodCode, distributionMode, status;
  final double totalRevenue,
      totalCogs,
      totalExpensesAndLosses,
      netProfit,
      reservePct,
      distributableProfit;
  Map<String, Object?> toMap() => {
        'distribution_no': distributionNo,
        'period_code': periodCode,
        'distribution_mode': distributionMode,
        'total_revenue': totalRevenue,
        'total_cogs': totalCogs,
        'total_expenses_and_losses': totalExpensesAndLosses,
        'net_profit': netProfit,
        'reserve_pct': reservePct,
        'distributable_profit': distributableProfit,
        'status': status,
        'journal_entry_id': journalEntryId
      };
  factory PartnerDistributionModel.fromMap(Map<String, Object?> m) =>
      PartnerDistributionModel(
          id: m['id'] as int?,
          distributionNo: _string(m['distribution_no']),
          periodCode: _string(m['period_code']),
          distributionMode: _string(m['distribution_mode']),
          totalRevenue: _number(m['total_revenue']),
          totalCogs: _number(m['total_cogs']),
          totalExpensesAndLosses: _number(m['total_expenses_and_losses']),
          netProfit: _number(m['net_profit']),
          reservePct: _number(m['reserve_pct']),
          distributableProfit: _number(m['distributable_profit']),
          status: _string(m['status'], 'DRAFT'),
          journalEntryId: m['journal_entry_id'] as int?);
}

class PartnerDistributionLineModel {
  const PartnerDistributionLineModel(
      {this.id,
      required this.distributionId,
      required this.partnerId,
      required this.basisValue,
      this.shareAmountLah = 0,
      this.withdrawalsAlayh = 0});
  final int? id, distributionId, partnerId;
  final double basisValue, shareAmountLah, withdrawalsAlayh;
  double get netPayable => shareAmountLah - withdrawalsAlayh;
  Map<String, Object?> toMap() => {
        'distribution_id': distributionId,
        'partner_id': partnerId,
        'basis_value': basisValue,
        'share_amount_lah': shareAmountLah,
        'withdrawals_alayh': withdrawalsAlayh,
        'net_payable': netPayable
      };
  factory PartnerDistributionLineModel.fromMap(Map<String, Object?> m) =>
      PartnerDistributionLineModel(
          id: m['id'] as int?,
          distributionId: _integer(m['distribution_id']),
          partnerId: _integer(m['partner_id']),
          basisValue: _number(m['basis_value']),
          shareAmountLah: _number(m['share_amount_lah']),
          withdrawalsAlayh: _number(m['withdrawals_alayh']));
}
