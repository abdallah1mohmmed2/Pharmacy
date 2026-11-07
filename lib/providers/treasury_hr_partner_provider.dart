// lib/providers/treasury_hr_partner_provider.dart
import 'package:flutter/foundation.dart';
import '../data/database/database_helper.dart';
import '../data/models/finance_hr_partner_models.dart';
import '../data/services/shift_and_treasury_service.dart';
import '../data/services/hr_and_payroll_service.dart';
import '../data/services/partner_distribution_service.dart';

class TreasuryHrPartnerProvider extends ChangeNotifier {
  TreasuryHrPartnerProvider(
      {DatabaseHelper? database,
      ShiftAndTreasuryService? treasury,
      HrAndPayrollService? hr,
      PartnerDistributionService? partners})
      : _db = database ?? DatabaseHelper.instance,
        _treasury = treasury ?? ShiftAndTreasuryService(helper: database),
        _hr = hr ?? HrAndPayrollService(helper: database),
        _partners = partners ?? PartnerDistributionService(helper: database);
  final DatabaseHelper _db;
  final ShiftAndTreasuryService _treasury;
  final HrAndPayrollService _hr;
  final PartnerDistributionService _partners;
  int branchId = 1;
  int? userId;
  bool loading = false;
  String? error;
  List<Map<String, Object?>> cashAccounts = [],
      transactions = [],
      expenses = [],
      categories = [],
      shifts = [],
      workShifts = [],
      employees = [],
      partners = [],
      distributions = [];
  CashierShiftModel? activeShift;
  PartnerPolicy partnerPolicy = const PartnerPolicy('shares');
  List<Map<String, Object?>> distributionPreview = [];
  Map<String, double> profitSummary = {};

  Future<void> loadAll({required int branchId, required int userId}) async {
    this.branchId = branchId;
    this.userId = userId;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final db = await _db.database;
      cashAccounts = await _treasury.cashAccounts(branchId);
      transactions = await _treasury.transactions(branchId);
      expenses = await db.rawQuery(
          'SELECT e.*,c.name_ar category_name,a.name_ar cash_account_name FROM expenses e JOIN expense_categories c ON c.id=e.category_id JOIN cash_accounts a ON a.id=e.cash_account_id WHERE e.branch_id=? ORDER BY e.expense_date DESC,e.id DESC',
          [branchId]);
      categories = await db.query('expense_categories',
          where: 'branch_id=?', whereArgs: [branchId], orderBy: 'name_ar');
      shifts = await db.query('cashier_shifts',
          where: 'branch_id=?',
          whereArgs: [branchId],
          orderBy: 'id DESC',
          limit: 30);
      workShifts = await db.query('work_shifts', orderBy: 'id');
      final active = await db.query('cashier_shifts',
          where: "branch_id=? AND status='OPEN'",
          whereArgs: [branchId],
          orderBy: 'id DESC',
          limit: 1);
      activeShift =
          active.isEmpty ? null : CashierShiftModel.fromMap(active.first);
      employees = await _hr.employees(branchId);
      partners = await db.rawQuery(
          'SELECT p.*,t.name_ar,t.phone,COALESCE(b.total_lah,0) total_lah,COALESCE(b.total_alayh,0) total_alayh FROM partners p JOIN parties t ON t.id=p.party_id LEFT JOIN v_party_balance b ON b.party_id=p.party_id WHERE p.branch_id=? ORDER BY t.name_ar',
          [branchId]);
      distributions = await db.query('partner_distributions',
          where: 'branch_id=?',
          whereArgs: [branchId],
          orderBy: 'id DESC',
          limit: 30);
      partnerPolicy = await _partners.policy();
    } catch (e) {
      error = e.toString();
    }
    loading = false;
    notifyListeners();
  }

  Future<void> refresh() async {
    final b = branchId, u = userId;
    if (u != null) await loadAll(branchId: b, userId: u);
  }

  Future<int> recordExpense(
      {required int categoryId,
      required int cashAccountId,
      required double amount,
      required String description,
      String paidTo = ''}) async {
    final id = await _treasury.recordExpense(
        branchId: branchId,
        categoryId: categoryId,
        cashAccountId: cashAccountId,
        amount: amount,
        description: description,
        paidTo: paidTo,
        cashierShiftId: activeShift?.id);
    await refresh();
    return id;
  }

  Future<int> transfer(
      {required int fromAccountId,
      required int toAccountId,
      required double amount,
      double fee = 0,
      String? reference,
      String note = ''}) async {
    await _treasury.transfer(
        branchId: branchId,
        fromAccountId: fromAccountId,
        toAccountId: toAccountId,
        amount: amount,
        fee: fee,
        walletRefNo: reference,
        note: note);
    await refresh();
    return 1;
  }

  Future<double> reconcileWallet(
      {required int accountId,
      required double actual,
      String? reference}) async {
    final d = await _treasury.reconcileWallet(
        branchId: branchId,
        accountId: accountId,
        actualBalance: actual,
        walletRefNo: reference);
    await refresh();
    return d;
  }

  Future<int> openShift(
      {required int drawerAccountId,
      double openingCash = 0,
      int? partyId,
      int? workShiftId}) async {
    if (userId == null) throw StateError('لا يوجد مستخدم مسجل');
    final id = await _treasury.openShift(
        branchId: branchId,
        userId: userId!,
        drawerAccountId: drawerAccountId,
        openingCash: openingCash,
        cashierPartyId: partyId,
        workShiftId: workShiftId);
    await refresh();
    return id;
  }

  Future<double> expectedCash(int shiftId) => _treasury.expectedCash(shiftId);
  Future<double> closeShift(
      {required int shiftId,
      required Map<String, int> denominations,
      required String handling,
      Map<String, double> wallets = const {},
      int? nextUserId}) async {
    final d = await _treasury.closeShiftBlind(
        shiftId: shiftId,
        denominations: denominations,
        diffHandling: handling,
        countedWallets: wallets,
        handoverToUserId: nextUserId);
    await refresh();
    return d;
  }

  Future<int> registerAttendance(
      {required int employeeId,
      required String date,
      required String status,
      int? shiftId}) async {
    final id = await _hr.registerAttendance(
        employeeId: employeeId,
        workDate: date,
        status: status,
        workShiftId: shiftId);
    await refresh();
    return id;
  }

  Future<int> advance(
      {required int employeeId,
      required int cashAccountId,
      required double amount,
      int? managerUserId}) async {
    final id = await _hr.postEmployeeAdvance(
        employeeId: employeeId,
        cashAccountId: cashAccountId,
        amount: amount,
        managerUserId: managerUserId);
    await refresh();
    return id;
  }

  Future<int> adjustment(
      {required int employeeId,
      required double amount,
      required bool bonus,
      required String reason}) async {
    final id = await _hr.recordAdjustment(
        employeeId: employeeId, amount: amount, isBonus: bonus, reason: reason);
    await refresh();
    return id;
  }

  Future<int> generatePayroll(
          {required int employeeId, required String period}) =>
      _hr.generatePayroll(employeeId: employeeId, periodCode: period);
  Future<void> approvePayroll(int id) => _hr.approvePayroll(id);
  Future<int> payPayroll({required int id, required int cashAccountId}) async {
    final v = await _hr.payPayroll(payrollId: id, cashAccountId: cashAccountId);
    await refresh();
    return v;
  }

  Future<Map<String, double>> calculateProfit(String period) async {
    profitSummary = await _partners.calculatePeriodNetProfit(
        branchId: branchId, periodCode: period);
    notifyListeners();
    return profitSummary;
  }

  Future<int> createDistribution(
      {required String period, required double reservePct}) async {
    profitSummary = await _partners.calculatePeriodNetProfit(
        branchId: branchId, periodCode: period);
    final id = await _partners.createDistribution(
        branchId: branchId, periodCode: period, reservePct: reservePct);
    final distributable =
        (profitSummary['net_profit'] ?? 0) * (1 - reservePct / 100);
    distributionPreview = await _partners.planDistribution(
        branchId: branchId,
        periodCode: period,
        distributableProfit: distributable);
    await refresh();
    return id;
  }

  Future<void> postDistribution(int id) async {
    await _partners.postPartnerDistribution(distributionId: id);
    await refresh();
  }

  Future<void> switchDistributionMode(String mode,
      {required int managerUserId}) async {
    await _partners.switchDistributionMode(
        branchId: branchId, newMode: mode, managerUserId: managerUserId);
    await refresh();
  }

  Future<void> validatePartnerFields({int? shares, double? percentage}) =>
      _partners.validatePartnerFields(
          sharesCount: shares, percentage: percentage);
}
