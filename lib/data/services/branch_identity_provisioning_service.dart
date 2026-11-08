import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:sqflite/sqflite.dart';

/// Verifies and atomically installs the operator-signed pharmacy identity.
class BranchIdentityProvisioningService {
  BranchIdentityProvisioningService({
    required String trustedPublicKeyPem,
  }) : _trustedPublicKeyPem = trustedPublicKeyPem;

  static const _uuidPattern =
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$';

  static const _payloadFields = <String>{
    'schema_version',
    'tenant_uuid',
    'tenant_code',
    'tenant_name_ar',
    'branch_uuid',
    'branch_code',
    'branch_name_ar',
    'issued_at',
    'issuance_id',
  };

  final String _trustedPublicKeyPem;

  Future<ProvisioningIdentity> verifyManifestBytes(Uint8List bytes) async {
    if (_trustedPublicKeyPem.trim().isEmpty) {
      throw const FormatException(
        'مفتاح التحقق الموثوق غير مضبوط في إصدار التطبيق.',
      );
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('ملف التأسيس غير صالح.');
    }
    final payload = decoded['payload'];
    if (payload is! Map<String, dynamic>) {
      throw const FormatException('بيانات الهوية غير موجودة.');
    }
    if (decoded['signature_algorithm'] != 'Ed25519' ||
        decoded['signature'] is! String) {
      throw const FormatException('خوارزمية أو توقيع الملف غير مدعوم.');
    }
    if (payload.keys.toSet().difference(_payloadFields).isNotEmpty ||
        _payloadFields.difference(payload.keys.toSet()).isNotEmpty) {
      throw const FormatException('حقول ملف التأسيس لا تطابق الإصدار المعتمد.');
    }
    if (payload['schema_version'] != 1) {
      throw const FormatException('إصدار ملف التأسيس غير مدعوم.');
    }

    for (final field in ['tenant_uuid', 'branch_uuid', 'issuance_id']) {
      final value = payload[field];
      if (value is! String || !RegExp(_uuidPattern).hasMatch(value)) {
        throw FormatException('معرف UUID غير صالح: $field');
      }
    }
    for (final field in [
      'tenant_code',
      'tenant_name_ar',
      'branch_code',
      'branch_name_ar',
      'issued_at',
    ]) {
      if (payload[field] is! String ||
          (payload[field] as String).trim().isEmpty) {
        throw FormatException('حقل إلزامي غير صالح: $field');
      }
    }

    final signatureBytes = base64Decode(decoded['signature'] as String);
    if (signatureBytes.length != 64) {
      throw const FormatException('طول التوقيع غير صالح.');
    }
    final publicKeyBytes = _decodeEd25519PublicKey(_trustedPublicKeyPem);
    final canonicalPayload = jsonEncode(<String, Object?>{
      'schema_version': payload['schema_version'],
      'tenant_uuid': payload['tenant_uuid'],
      'tenant_code': payload['tenant_code'],
      'tenant_name_ar': payload['tenant_name_ar'],
      'branch_uuid': payload['branch_uuid'],
      'branch_code': payload['branch_code'],
      'branch_name_ar': payload['branch_name_ar'],
      'issued_at': payload['issued_at'],
      'issuance_id': payload['issuance_id'],
    });
    final publicKey = SimplePublicKey(
      publicKeyBytes,
      type: KeyPairType.ed25519,
    );
    final valid = await Ed25519().verify(
      utf8.encode(canonicalPayload),
      signature: Signature(signatureBytes, publicKey: publicKey),
    );
    if (!valid) {
      throw const FormatException('توقيع ملف التأسيس غير صحيح أو تم تعديل الملف.');
    }

    return ProvisioningIdentity(
      tenantUuid: payload['tenant_uuid'] as String,
      tenantCode: payload['tenant_code'] as String,
      tenantNameAr: payload['tenant_name_ar'] as String,
      branchUuid: payload['branch_uuid'] as String,
      branchCode: payload['branch_code'] as String,
      branchNameAr: payload['branch_name_ar'] as String,
      issuanceId: payload['issuance_id'] as String,
      issuedAt: payload['issued_at'] as String,
    );
  }

  /// Installs a previously verified identity in one SQLite transaction.
  /// The database-level triggers installed here make the identity immutable.
  Future<void> installManifest({
    required Database database,
    required Uint8List manifestBytes,
  }) async {
    final identity = await verifyManifestBytes(manifestBytes);
    await database.transaction((txn) async {
      // Defer tenant foreign-key validation until both parent and branch references are updated.
      await txn.execute('PRAGMA defer_foreign_keys = ON');
      await txn.execute('''
        CREATE TABLE IF NOT EXISTS branch_identity_provisioning (
          id INTEGER PRIMARY KEY CHECK(id = 1),
          tenant_uuid TEXT NOT NULL UNIQUE,
          branch_uuid TEXT NOT NULL UNIQUE,
          issuance_id TEXT NOT NULL UNIQUE,
          issued_at TEXT NOT NULL,
          installed_at TEXT NOT NULL
        )
      ''');

      final installed = await txn.query(
        'branch_identity_provisioning',
        where: 'id = 1',
        limit: 1,
      );
      if (installed.isNotEmpty) {
        throw StateError('تم تأسيس هوية هذا الجهاز مسبقاً ولا يمكن تغييرها أو إعادة تطبيقها.');
      }

      final tenants = await txn.query('tenants', limit: 2);
      if (tenants.length != 1) {
        throw StateError('يجب وجود مؤسسة محلية واحدة قبل تثبيت الهوية.');
      }
      final tenant = tenants.single;
      final oldTenantUuid = tenant['uuid'] as String;
      if (oldTenantUuid != 'tenant-main') {
        throw StateError('هوية المؤسسة الحالية ليست مؤقتة؛ رُفض استبدالها.');
      }
      final existingTenant = await txn.query(
        'tenants',
        where: 'uuid = ?',
        whereArgs: [identity.tenantUuid],
        limit: 1,
      );
      if (existingTenant.isNotEmpty) {
        throw StateError('UUID المؤسسة المطلوب مستخدم مسبقاً.');
      }

      // This release intentionally provisions one pharmacy branch only.
      // Do not migrate a partially multi-branch database under a single-branch manifest.
      final branches = await txn.query('branches', limit: 2);
      if (branches.length != 1 ||
          branches.single['is_main'] != 1 ||
          branches.single['is_deleted'] != 0) {
        throw StateError(
          'هذا الملف مخصص حالياً لمؤسسة ذات فرع واحد؛ لم يتم تغيير أي بيانات.',
        );
      }
      final branch = branches.single;
      if (branch['uuid'] != 'branch-main' ||
          branch['tenant_uuid'] != oldTenantUuid) {
        throw StateError('هوية الفرع الحالية ليست مؤقتة أو غير مرتبطة بالمؤسسة المؤقتة.');
      }
      final existingBranch = await txn.query(
        'branches',
        where: 'uuid = ?',
        whereArgs: [identity.branchUuid],
        limit: 1,
      );
      if (existingBranch.isNotEmpty) {
        throw StateError('UUID الفرع المطلوب مستخدم مسبقاً.');
      }

      final now = DateTime.now().toUtc().toIso8601String();
      await txn.update(
        'tenants',
        {
          'uuid': identity.tenantUuid,
          'code': identity.tenantCode,
          'name_ar': identity.tenantNameAr,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [tenant['id']],
      );
      await txn.update(
        'branches',
        {
          'uuid': identity.branchUuid,
          'tenant_uuid': identity.tenantUuid,
          'code': identity.branchCode,
          'name_ar': identity.branchNameAr,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [branch['id']],
      );
      await txn.insert('branch_identity_provisioning', {
        'id': 1,
        'tenant_uuid': identity.tenantUuid,
        'branch_uuid': identity.branchUuid,
        'issuance_id': identity.issuanceId,
        'issued_at': identity.issuedAt,
        'installed_at': now,
      });

      // Protect identity columns at the SQLite boundary, not only in UI code.
      await txn.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_tenant_identity_immutable
        BEFORE UPDATE OF uuid ON tenants
        WHEN EXISTS (SELECT 1 FROM branch_identity_provisioning WHERE id = 1)
        BEGIN
          SELECT RAISE(ABORT, 'tenant identity is immutable after provisioning');
        END
      ''');
      await txn.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_branch_identity_immutable
        BEFORE UPDATE OF uuid, tenant_uuid ON branches
        WHEN EXISTS (SELECT 1 FROM branch_identity_provisioning WHERE id = 1)
        BEGIN
          SELECT RAISE(ABORT, 'branch identity is immutable after provisioning');
        END
      ''');
      await txn.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_provisioning_record_immutable_update
        BEFORE UPDATE ON branch_identity_provisioning
        BEGIN
          SELECT RAISE(ABORT, 'provisioning record is immutable');
        END
      ''');
      await txn.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_tenant_identity_immutable_delete
        BEFORE DELETE ON tenants
        WHEN EXISTS (SELECT 1 FROM branch_identity_provisioning WHERE id = 1)
        BEGIN
          SELECT RAISE(ABORT, 'tenant identity cannot be deleted after provisioning');
        END
      ''');
      await txn.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_branch_identity_immutable_delete
        BEFORE DELETE ON branches
        WHEN EXISTS (SELECT 1 FROM branch_identity_provisioning WHERE id = 1)
        BEGIN
          SELECT RAISE(ABORT, 'branch identity cannot be deleted after provisioning');
        END
      ''');
      await txn.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_provisioning_record_immutable_delete
        BEFORE DELETE ON branch_identity_provisioning
        BEGIN
          SELECT RAISE(ABORT, 'provisioning record is immutable');
        END
      ''');
    });
  }

  List<int> _decodeEd25519PublicKey(String pem) {
    final body = pem
        .replaceAll('-----BEGIN PUBLIC KEY-----', '')
        .replaceAll('-----END PUBLIC KEY-----', '')
        .replaceAll(RegExp(r'\s'), '');
    final der = base64Decode(body);
    // SubjectPublicKeyInfo prefix for Ed25519 (RFC 8410), followed by 32 bytes.
    const prefix = <int>[
      0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00
    ];
    if (der.length != prefix.length + 32) {
      throw const FormatException('مفتاح Ed25519 العام غير صالح.');
    }
    for (var i = 0; i < prefix.length; i++) {
      if (der[i] != prefix[i]) {
        throw const FormatException('صيغة مفتاح Ed25519 العام غير مدعومة.');
      }
    }
    return Uint8List.fromList(der.sublist(prefix.length));
  }
}

class ProvisioningIdentity {
  const ProvisioningIdentity({
    required this.tenantUuid,
    required this.tenantCode,
    required this.tenantNameAr,
    required this.branchUuid,
    required this.branchCode,
    required this.branchNameAr,
    required this.issuanceId,
    required this.issuedAt,
  });

  final String tenantUuid;
  final String tenantCode;
  final String tenantNameAr;
  final String branchUuid;
  final String branchCode;
  final String branchNameAr;
  final String issuanceId;
  final String issuedAt;
}
