// lib/providers/settings_and_system_provider.dart
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/constants/setting_keys.dart';
import '../data/database/database_helper.dart';
import '../data/models/settings_audit_sync_models.dart';
import '../data/services/settings_and_audit_service.dart';
import '../data/services/drug_import_export_service.dart';
import '../data/services/backup_and_sync_service.dart';
import '../data/services/firestore_sync_worker.dart';
import '../data/services/security_hash_service.dart';

class SettingsAndSystemProvider extends ChangeNotifier {
  SettingsAndSystemProvider(
      {required Future<bool> Function(String) verifyManagerPin,
      required Future<bool> Function(String) verifyOwnerPin,
      DatabaseHelper? helper,
      Future<String?> Function()? firebaseIdTokenProvider,
      int Function()? activeBranchId})
      : _helper = helper ?? DatabaseHelper.instance,
        settings = SettingsService(
            helper: helper,
            verifyManagerPin: verifyManagerPin,
            verifyOwnerPin: verifyOwnerPin),
        importer = DrugImportExportService(helper: helper),
        backup = BackupAndSyncService(helper: helper),
        firestoreSync = FirestoreSyncWorker(helper: helper),
        _firebaseIdTokenProvider = firebaseIdTokenProvider,
        _activeBranchId = activeBranchId ?? (() => 1),
        audit = AuditService(helper: helper),
        periods = PeriodGuard(helper: helper);
  final DatabaseHelper _helper;
  final SettingsService settings;
  final DrugImportExportService importer;
  final BackupAndSyncService backup;
  final FirestoreSyncWorker firestoreSync;
  final Future<String?> Function()? _firebaseIdTokenProvider;
  final int Function() _activeBranchId;
  final AuditService audit;
  final PeriodGuard periods;
  bool loading = false, busy = false;
  String? error;
  List<Map<String, Object?>> userRows = [], drugCategories = [];
  List<ImportJobModel> importJobs = [];
  List<AuditLogModel> auditLogs = [];
  List<Map<String, Object?>> backupLogs = [],
      syncSummary = [],
      roleRows = [],
      periodRows = [];
  ChainVerificationResult? chainResult;
  ImportDryRunResult? dryRunResult;
  ImportExecutionResult? importResult;
  int importProgress = 0, importTotal = 0;
  Timer? _cloudSyncTimer;
  bool cloudSyncRunning = false;
  String? cloudSyncStatus;

  Future<void> initialize() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await settings.load();
      await refreshSystemData();
      await _configureCloudSyncTimer();
    } catch (e) {
      error = e.toString();
    }
    loading = false;
    notifyListeners();
  }

  Future<void> refreshSystemData() async {
    importJobs = await importer.listJobs();
    auditLogs =
        (await _helper.query('audit_logs', orderBy: 'id DESC', limit: 500))
            .map(AuditLogModel.fromMap)
            .toList();
    backupLogs = await backup.backups();
    syncSummary = await backup.queueSummary();
    roleRows = await _helper.rawQuery(
        'SELECT rp.role_code,r.role_name_ar,rp.permission_code,rp.is_allowed FROM role_permissions rp JOIN roles r ON r.role_code=rp.role_code ORDER BY rp.role_code,rp.permission_code');
    userRows = await _helper.rawQuery(
        'SELECT id,username,full_name,COALESCE(system_role_code,role_code) AS role_code,is_active FROM users WHERE is_deleted=0 ORDER BY full_name');
    drugCategories = await _helper.rawQuery(
        'SELECT id,name_ar,name_en FROM drug_categories WHERE is_deleted=0 ORDER BY name_ar');
    periodRows =
        await _helper.query('fiscal_periods', orderBy: 'start_date DESC');
  }

  Future<void> changeSetting(SettingKey key, Object value,
      {String? managerPin,
      required int? userId,
      int branchId = 1,
      String? reason}) async {
    await settings.setSetting(key, value,
        managerPin: managerPin,
        userId: userId,
        branchId: branchId,
        reason: reason);
    if (key == SettingKey.cloudSync) await _configureCloudSyncTimer();
    notifyListeners();
  }

  Future<ImportDryRunResult> dryRun(
      {required String source,
      required String format,
      Map<String, String> mapping = const {}}) async {
    dryRunResult = await importer.dryRunImport(
        source: source, format: format, mapping: mapping);
    notifyListeners();
    return dryRunResult!;
  }

  Future<ImportExecutionResult> executeImport(
      {required String source,
      required String format,
      Map<String, String> mapping = const {},
      String conflictPolicy = 'SKIP',
      String? fileName}) async {
    busy = true;
    importProgress = 0;
    importTotal = 0;
    notifyListeners();
    try {
      final result = await importer.executeImport(
          source: source,
          format: format,
          mapping: mapping,
          conflictPolicy: conflictPolicy,
          fileName: fileName,
          onProgress: (done, total) {
            importProgress = done;
            importTotal = total;
            notifyListeners();
          });
      importResult = result;
      await refreshSystemData();
      return result;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<List<OpenFdaDrugResult>> searchOpenFda(String query) =>
      importer.searchOpenFda(query);
  Future<File> exportDrugs(
      {required String format,
      bool hideCostPrices = true,
      int? categoryId}) async {
    final file = await importer.exportDrugs(
        format: format, hideCostPrices: hideCostPrices, categoryId: categoryId);
    await refreshSystemData();
    return file;
  }

  Future<BackupResult> createBackup(
      {String triggerType = 'MANUAL', int? userId}) async {
    final result =
        await backup.createBackup(triggerType: triggerType, userId: userId);
    await refreshSystemData();
    return result;
  }

  Future<void> restoreBackup(File file, {int? userId}) async {
    await backup.restoreBackup(backup: file, userId: userId);
    await initialize();
  }

  Future<void> _configureCloudSyncTimer() async {
    _cloudSyncTimer?.cancel();
    _cloudSyncTimer = null;
    if (settings.getJson(SettingKey.cloudSync)['enabled'] != true) {
      cloudSyncStatus = 'المزامنة متوقفة';
      notifyListeners();
      return;
    }
    final tokenProvider = _firebaseIdTokenProvider;
    if (tokenProvider == null) {
      cloudSyncStatus = 'بانتظار ربط Firebase Authentication';
      notifyListeners();
      return;
    }
    try {
      final token = await tokenProvider();
      if (token == null || token.isEmpty) {
        cloudSyncStatus = 'بانتظار تسجيل الدخول إلى حساب Firebase الخاص بالفرع';
        notifyListeners();
        return;
      }
    } catch (error) {
      cloudSyncStatus = 'تعذر تهيئة Firebase Authentication: $error';
      notifyListeners();
      return;
    }
    _cloudSyncTimer = Timer.periodic(const Duration(minutes: 2), (_) async {
      if (cloudSyncRunning) return;
      try {
        await syncNow();
      } catch (error) {
        cloudSyncStatus = error.toString();
        notifyListeners();
      }
    });
    cloudSyncStatus = 'المزامنة التلقائية مفعّلة';
    notifyListeners();
  }

  Future<void> refreshCloudSyncSchedule() => _configureCloudSyncTimer();

  Future<bool> testCloudConnection() async {
    final cfg = settings.getJson(SettingKey.cloudSync);
    if ((cfg['project_id']?.toString().trim() ?? '').isEmpty) {
      cloudSyncStatus = 'أدخل Firebase project_id أولاً';
      notifyListeners();
      return false;
    }
    final tokenProvider = _firebaseIdTokenProvider;
    if (tokenProvider == null) {
      cloudSyncStatus = 'لم يتم ربط Firebase Authentication بعد';
      notifyListeners();
      return false;
    }
    final token = await tokenProvider();
    if (token == null || token.isEmpty) {
      cloudSyncStatus = 'لا يوجد Firebase ID token لحساب الفرع';
      notifyListeners();
      return false;
    }
    return true;
  }

  Future<int> syncNow() async {
    if (cloudSyncRunning) return 0;
    final cfg = settings.getJson(SettingKey.cloudSync);
    if (cfg['enabled'] != true) {
      throw StateError('فعّل المزامنة السحابية من الإعداد رقم 35 أولاً');
    }
    final tokenProvider = _firebaseIdTokenProvider;
    if (tokenProvider == null) {
      throw StateError(
          'الإعداد 35 محفوظ، لكن Firebase Authentication غير مربوط بالتطبيق. لا يمكن استخدام تسجيل الدخول المحلي كبديل عن Firebase.');
    }
    final idToken = await tokenProvider();
    if (idToken == null || idToken.isEmpty) {
      throw StateError('سجّل الدخول إلى حساب Firebase الخاص بهذا الفرع أولاً');
    }
    cloudSyncRunning = true;
    cloudSyncStatus = 'جارٍ رفع واستقبال التغييرات...';
    notifyListeners();
    try {
      final result = await firestoreSync.syncConfigured(
        branchId: _activeBranchId(),
        idToken: idToken,
      );
      await refreshSystemData();
      cloudSyncStatus =
          'اكتملت المزامنة: رفع ${result.uploadedEvents} واستقبال ${result.receivedEvents}';
      return result.uploadedEvents + result.receivedEvents;
    } catch (error) {
      cloudSyncStatus = 'فشلت المزامنة: $error';
      rethrow;
    } finally {
      cloudSyncRunning = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _cloudSyncTimer?.cancel();
    super.dispose();
  }

  Future<ChainVerificationResult> verifyAuditChain() async {
    chainResult = await audit.verifyChainIntegrity();
    notifyListeners();
    return chainResult!;
  }

  Future<int> closeFiscalPeriod(String code,
      {required int userId,
      required Future<void> Function() createPreCloseBackup}) async {
    final id = await periods.closePeriod(
        periodCode: code,
        userId: userId,
        createPreCloseBackup: createPreCloseBackup,
        hasOpenShiftsOrStocktakes: _hasOpenOperationalSessions);
    await refreshSystemData();
    notifyListeners();
    return id;
  }

  Future<bool> _hasOpenOperationalSessions() async {
    final tables = await _helper
        .rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
    for (final row in tables) {
      final name = row['name'] as String;
      if (!RegExp(r'(shift|stocktak|stock_taking)', caseSensitive: false)
          .hasMatch(name)) continue;
      final columns = await _helper.rawQuery('PRAGMA table_info(' + name + ')');
      final names = columns.map((e) => e['name'] as String).toSet();
      final statusColumn = names.contains('status')
          ? 'status'
          : names.contains('state')
              ? 'state'
              : null;
      if (statusColumn == null) continue;
      final open = await _helper.rawQuery('SELECT COUNT(*) AS n FROM ' +
          name +
          ' WHERE upper(' +
          statusColumn +
          ') IN (\'OPEN\',\'ACTIVE\',\'IN_PROGRESS\',\'COUNTING\',\'REVIEW\',\'PENDING\')');
      if ((open.first['n'] as num) > 0) return true;
    }
    return false;
  }

  Future<int> createUser(
      {required String username,
      required String fullName,
      required String password,
      required String roleCode,
      required int branchId,
      required int actorUserId,
      required String actorRole}) async {
    const roles = {
      'OWNER',
      'MANAGER',
      'PHARMACIST',
      'CASHIER',
      'STOREKEEPER',
      'ACCOUNTANT',
      'AUDITOR'
    };
    if (!roles.contains(roleCode)) throw ArgumentError('الدور غير معروف');
    if (roleCode == 'OWNER' && actorRole != 'OWNER')
      throw StateError('إنشاء حساب مالك يتطلب صلاحية المالك الحالي');
    if (username.trim().length < 3 ||
        fullName.trim().isEmpty ||
        password.length < 8)
      throw ArgumentError('اسم المستخدم والاسم وكلمة مرور من 8 خانات مطلوبة');
    final db = await _helper.database;
    final now = DateTime.now().toIso8601String();
    final legacyRole = {
      'OWNER',
      'MANAGER',
      'PHARMACIST',
      'CASHIER',
      'ACCOUNTANT'
    }.contains(roleCode)
        ? roleCode
        : 'PHARMACIST';
    final id = await db.insert('users', {
      'uuid': 'user-' + DateTime.now().microsecondsSinceEpoch.toString(),
      'branch_id': branchId,
      'created_at': now,
      'updated_at': now,
      'is_deleted': 0,
      'sync_status': 'LOCAL',
      'sync_version': 1,
      'username': username.trim(),
      'full_name': fullName.trim(),
      'role_code': legacyRole,
      'system_role_code': roleCode,
      'password_hash': SecurityHashService.hash(password),
      'is_active': 1
    });
    await audit.record(
        action: 'CREATE',
        userId: actorUserId,
        branchId: branchId,
        entityType: 'users',
        entityId: id,
        entityLabel: username.trim(),
        newValues: {'full_name': fullName.trim(), 'role_code': roleCode});
    await refreshSystemData();
    notifyListeners();
    return id;
  }

  Future<void> updateUserSecurity(
      {required int targetUserId,
      required int actorUserId,
      required String actorRole,
      String? newPassword,
      String? newManagerPin}) async {
    if ((newPassword == null || newPassword.isEmpty) &&
        (newManagerPin == null || newManagerPin.isEmpty))
      throw ArgumentError('أدخل كلمة مرور أو رمز مدير جديداً');
    if (newPassword != null && newPassword.isNotEmpty && newPassword.length < 8)
      throw ArgumentError('كلمة المرور لا تقل عن 8 خانات');
    if (newManagerPin != null &&
        newManagerPin.isNotEmpty &&
        (newManagerPin.length < 4 || newManagerPin.length > 8))
      throw ArgumentError('رمز المدير من 4 إلى 8 خانات');
    final target = await _helper.query('users',
        where: 'id=?', whereArgs: [targetUserId], limit: 1);
    if (target.isEmpty) throw StateError('المستخدم غير موجود');
    final targetRole =
        (target.first['system_role_code'] ?? target.first['role_code'])
            .toString();
    if (targetRole == 'OWNER' && actorRole != 'OWNER')
      throw StateError('تغيير بيانات حساب المالك يتطلب المالك');
    final values = <String, Object?>{
      'updated_at': DateTime.now().toIso8601String()
    };
    if (newPassword != null && newPassword.isNotEmpty)
      values['password_hash'] = SecurityHashService.hash(newPassword);
    if (newManagerPin != null && newManagerPin.isNotEmpty)
      values['manager_pin_hash'] = SecurityHashService.hash(newManagerPin);
    await _helper
        .update('users', values, where: 'id=?', whereArgs: [targetUserId]);
    await audit.record(
        action: 'UPDATE',
        userId: actorUserId,
        entityType: 'users',
        entityId: targetUserId,
        newValues: {
          'password_changed': newPassword != null && newPassword.isNotEmpty,
          'manager_pin_changed':
              newManagerPin != null && newManagerPin.isNotEmpty
        });
    await refreshSystemData();
    notifyListeners();
  }

  Future<void> updateUserRole(
      {required int targetUserId,
      required String roleCode,
      required int actorUserId,
      required String actorRole}) async {
    const roles = {
      'OWNER',
      'MANAGER',
      'PHARMACIST',
      'CASHIER',
      'STOREKEEPER',
      'ACCOUNTANT',
      'AUDITOR'
    };
    if (!roles.contains(roleCode)) throw ArgumentError('الدور غير معروف');
    final target = await _helper.query('users',
        where: 'id=?', whereArgs: [targetUserId], limit: 1);
    if (target.isEmpty) throw StateError('المستخدم غير موجود');
    final targetRole =
        (target.first['system_role_code'] ?? target.first['role_code'])
            .toString();
    if (actorRole != 'OWNER' && (roleCode == 'OWNER' || targetRole == 'OWNER'))
      throw StateError('إدارة حساب المالك تتطلب صلاحية المالك');
    final legacy = {'OWNER', 'MANAGER', 'PHARMACIST', 'CASHIER', 'ACCOUNTANT'}
            .contains(roleCode)
        ? roleCode
        : 'PHARMACIST';
    await _helper.update(
        'users',
        {
          'role_code': legacy,
          'system_role_code': roleCode,
          'updated_at': DateTime.now().toIso8601String()
        },
        where: 'id=?',
        whereArgs: [targetUserId]);
    await audit.record(
        action: 'UPDATE',
        userId: actorUserId,
        entityType: 'users',
        entityId: targetUserId,
        newValues: {'role_code': roleCode});
    await refreshSystemData();
    notifyListeners();
  }

  Future<void> setRolePermission(String role, String permission, bool allowed,
      {required String actorRole}) async {
    if (actorRole != 'OWNER' &&
        (role == 'OWNER' ||
            (allowed &&
                {'roles.manage', 'settings.manager_pin'}.contains(permission))))
      throw StateError('تغيير صلاحية المالك أو الصلاحيات الحساسة يتطلب المالك');
    final db = await _helper.database;
    final before = await db.query('role_permissions',
        where: 'role_code=? AND permission_code=?',
        whereArgs: [role, permission],
        limit: 1);
    await db.update('role_permissions', {'is_allowed': allowed ? 1 : 0},
        where: 'role_code=? AND permission_code=?',
        whereArgs: [role, permission]);
    await audit.record(
        action: 'UPDATE',
        entityType: 'role_permissions',
        entityLabel: '$role.$permission',
        oldValues: {
          'is_allowed': before.isNotEmpty ? before.first['is_allowed'] : null
        },
        newValues: {
          'is_allowed': allowed ? 1 : 0
        });
    await refreshSystemData();
    notifyListeners();
  }
}
