import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/branch_identity_provisioning_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late KeyPair keyPair;
  late String publicPem;
  late Uint8List manifest;

  const tenantUuid = '2d91c5e0-8a42-4c10-9b33-5f4a7c8d9012';
  const branchUuid = '6a52f3a1-1e47-4a6d-9c10-5f8b2d3e4a70';
  const issuanceId = '7b63f4a2-2f58-4b7e-8d21-6a9c3e4f5b81';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    final algorithm = Ed25519();
    keyPair = await algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey() as SimplePublicKey;
    const spkiPrefix = <int>[
      0x30,
      0x2a,
      0x30,
      0x05,
      0x06,
      0x03,
      0x2b,
      0x65,
      0x70,
      0x03,
      0x21,
      0x00
    ];
    final der = <int>[...spkiPrefix, ...publicKey.bytes];
    final encoded = base64Encode(der);
    publicPem =
        '-----BEGIN PUBLIC KEY-----\n$encoded\n-----END PUBLIC KEY-----';
    final payload = <String, Object?>{
      'schema_version': 1,
      'tenant_uuid': tenantUuid,
      'tenant_code': 'MAIN',
      'tenant_name_ar': 'المؤسسة التجريبية',
      'branch_uuid': branchUuid,
      'branch_code': 'MAIN',
      'branch_name_ar': 'الصيدلية الرئيسية',
      'issued_at': '2026-11-08T00:00:00.000Z',
      'issuance_id': issuanceId,
    };
    final canonical = jsonEncode(payload);
    final signature = await algorithm.sign(
      utf8.encode(canonical),
      keyPair: keyPair,
    );
    manifest = Uint8List.fromList(utf8.encode(jsonEncode({
      'payload': payload,
      'signature': base64Encode(signature.bytes),
      'signature_algorithm': 'Ed25519',
    })));
  });

  Future<Database> createLegacyDatabase() async {
    // Each simulated device must own a physically separate SQLite database.
    // Reusing the literal ':memory:' path can make independent opens collide.
    final directory =
        await Directory.systemTemp.createTemp('pharmacy-branch-identity-');
    final db = await databaseFactoryFfi.openDatabase(
      '${directory.path}/identity.db',
    );
    await db.execute('PRAGMA foreign_keys = ON');
    await db.execute('''
      CREATE TABLE tenants (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        code TEXT NOT NULL UNIQUE,
        name_ar TEXT NOT NULL,
        name_en TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE branches (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        tenant_uuid TEXT REFERENCES tenants(uuid),
        code TEXT NOT NULL UNIQUE,
        name_ar TEXT NOT NULL,
        is_main INTEGER NOT NULL DEFAULT 0,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.insert('tenants', {
      'uuid': 'tenant-main',
      'code': 'MAIN',
      'name_ar': 'المؤسسة الرئيسية',
      'created_at': '2026-11-08',
      'updated_at': '2026-11-08',
    });
    await db.insert('branches', {
      'uuid': 'branch-main',
      'tenant_uuid': 'tenant-main',
      'code': 'MAIN',
      'name_ar': 'الفرع الرئيسي',
      'is_main': 1,
      'updated_at': '2026-11-08',
    });
    return db;
  }

  Future<void> disposeDatabase(Database db) async {
    final path = db.path;
    await db.close();
    await File(path).parent.delete(recursive: true);
  }

  test('same signed manifest installs identical IDs on two independent devices',
      () async {
    final service = BranchIdentityProvisioningService(
      trustedPublicKeyPem: publicPem,
    );
    final first = await createLegacyDatabase();
    final second = await createLegacyDatabase();
    try {
      await service.installManifest(database: first, manifestBytes: manifest);
      await service.installManifest(database: second, manifestBytes: manifest);
      for (final db in [first, second]) {
        final tenant = (await db.query('tenants')).single;
        final branch = (await db.query('branches')).single;
        expect(tenant['uuid'], tenantUuid);
        expect(branch['uuid'], branchUuid);
        expect(branch['tenant_uuid'], tenantUuid);
        final state = (await db.query('branch_identity_provisioning')).single;
        expect(state['issuance_id'], issuanceId);
        expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      }
    } finally {
      await disposeDatabase(first);
      await disposeDatabase(second);
    }
  });

  test('rejects modified manifest and a signature from an untrusted key',
      () async {
    final service = BranchIdentityProvisioningService(
      trustedPublicKeyPem: publicPem,
    );
    final decoded = jsonDecode(utf8.decode(manifest)) as Map<String, dynamic>;
    (decoded['payload'] as Map<String, dynamic>)['branch_name_ar'] = 'اسم معدل';
    await expectLater(
      service.verifyManifestBytes(
          Uint8List.fromList(utf8.encode(jsonEncode(decoded)))),
      throwsFormatException,
    );

    final otherPair = await Ed25519().newKeyPair();
    final otherPublic = await otherPair.extractPublicKey();
    final otherPem = '-----BEGIN PUBLIC KEY-----\n'
        '${base64Encode([
          ...<int>[
            0x30,
            0x2a,
            0x30,
            0x05,
            0x06,
            0x03,
            0x2b,
            0x65,
            0x70,
            0x03,
            0x21,
            0x00
          ],
          ...otherPublic.bytes
        ])}'
        '\n-----END PUBLIC KEY-----';
    await expectLater(
      BranchIdentityProvisioningService(trustedPublicKeyPem: otherPem)
          .verifyManifestBytes(manifest),
      throwsFormatException,
    );

    final withExtraEnvelopeField =
        jsonDecode(utf8.decode(manifest)) as Map<String, dynamic>;
    withExtraEnvelopeField['untrusted_note'] = 'unsigned';
    await expectLater(
      service.verifyManifestBytes(
        Uint8List.fromList(utf8.encode(jsonEncode(withExtraEnvelopeField))),
      ),
      throwsFormatException,
    );
  });

  test('rejects reapplication and database-level identity mutation', () async {
    final service = BranchIdentityProvisioningService(
      trustedPublicKeyPem: publicPem,
    );
    final db = await createLegacyDatabase();
    try {
      await service.installManifest(database: db, manifestBytes: manifest);
      await expectLater(
        service.installManifest(database: db, manifestBytes: manifest),
        throwsStateError,
      );
      await expectLater(
        db.update('branches', {'uuid': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'}),
        throwsA(anything),
      );
      await expectLater(
        db.delete('branch_identity_provisioning'),
        throwsA(anything),
      );
      await expectLater(db.delete('tenants'), throwsA(anything));
      await expectLater(db.delete('branches'), throwsA(anything));
    } finally {
      await disposeDatabase(db);
    }
  });

  test('refuses identity replacement after a completed cloud sync', () async {
    final service = BranchIdentityProvisioningService(
      trustedPublicKeyPem: publicPem,
    );
    final db = await createLegacyDatabase();
    try {
      await db.execute('''
        CREATE TABLE sync_queue (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          status TEXT NOT NULL
        )
      ''');
      await db.insert('sync_queue', {'status': 'DONE'});

      await expectLater(
        service.installManifest(database: db, manifestBytes: manifest),
        throwsStateError,
      );
      expect((await db.query('tenants')).single['uuid'], 'tenant-main');
      expect((await db.query('branches')).single['uuid'], 'branch-main');
      expect(
        await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='branch_identity_provisioning'",
        ),
        isEmpty,
      );
    } finally {
      await disposeDatabase(db);
    }
  });

  test('rejects a multi-branch database without partial changes', () async {
    final service = BranchIdentityProvisioningService(
      trustedPublicKeyPem: publicPem,
    );
    final db = await createLegacyDatabase();
    try {
      await db.insert('branches', {
        'uuid': 'branch-secondary',
        'tenant_uuid': 'tenant-main',
        'code': 'SECONDARY',
        'name_ar': 'فرع إضافي',
        'is_main': 0,
        'updated_at': '2026-11-08',
      });
      await expectLater(
        service.installManifest(database: db, manifestBytes: manifest),
        throwsStateError,
      );
      expect((await db.query('tenants')).single['uuid'], 'tenant-main');
      expect(await db.query('branches'), hasLength(2));
      expect(
        await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='branch_identity_provisioning'",
        ),
        isEmpty,
      );
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    } finally {
      await disposeDatabase(db);
    }
  });

  test('reads cloud sync setting from a legacy setting_value column', () async {
    final service = BranchIdentityProvisioningService(
      trustedPublicKeyPem: publicPem,
    );
    final db = await createLegacyDatabase();
    try {
      await db.execute(
        'CREATE TABLE system_settings (setting_no INTEGER, setting_value TEXT)',
      );
      await db.insert('system_settings', {
        'setting_no': 35,
        'setting_value': '{"enabled":true}',
      });
      await expectLater(
        service.installManifest(database: db, manifestBytes: manifest),
        throwsStateError,
      );
      expect((await db.query('tenants')).single['uuid'], 'tenant-main');
      expect(
        await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='branch_identity_provisioning'",
        ),
        isEmpty,
      );
    } finally {
      await disposeDatabase(db);
    }
  });

  test('fails closed when cloud sync setting value cannot be inspected',
      () async {
    final service = BranchIdentityProvisioningService(
      trustedPublicKeyPem: publicPem,
    );
    final db = await createLegacyDatabase();
    try {
      await db.execute(
        'CREATE TABLE system_settings (setting_no INTEGER)',
      );
      await db.insert('system_settings', {'setting_no': 35});
      await expectLater(
        service.installManifest(database: db, manifestBytes: manifest),
        throwsStateError,
      );
      expect((await db.query('tenants')).single['uuid'], 'tenant-main');
      expect(
        await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='branch_identity_provisioning'",
        ),
        isEmpty,
      );
    } finally {
      await disposeDatabase(db);
    }
  });
}
