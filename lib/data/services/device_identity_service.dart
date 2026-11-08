import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A stable, random identifier for this app installation.
///
/// This identifier is stored outside the SQLite database so restoring a
/// database backup onto another device does not clone the source device ID.
/// It is diagnostic metadata, never an authentication credential.
abstract interface class DeviceIdentityStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class _SecureDeviceIdentityStorage implements DeviceIdentityStorage {
  _SecureDeviceIdentityStorage()
      : _storage = const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

class DeviceIdentityService {
  DeviceIdentityService({DeviceIdentityStorage? storage})
      : _storage = storage ?? _SecureDeviceIdentityStorage();

  static final DeviceIdentityService instance = DeviceIdentityService();
  static const _storageKey = 'pharmacy_device_uuid_v1';
  static final _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  final DeviceIdentityStorage _storage;
  Future<String>? _pending;

  /// Returns the same UUID for this app installation across restarts.
  /// Concurrent callers share one creation operation.
  Future<String> getOrCreateDeviceId() {
    final pending = _pending;
    if (pending != null) return pending;

    late final Future<String> operation;
    operation = _loadOrCreate().whenComplete(() {
      if (identical(_pending, operation)) _pending = null;
    });
    _pending = operation;
    return operation;
  }

  Future<String> _loadOrCreate() async {
    final existing = await _storage.read(_storageKey);
    if (existing != null && _uuidPattern.hasMatch(existing)) {
      return existing;
    }

    final generated = _newUuidV4();
    await _storage.write(_storageKey, generated);
    final persisted = await _storage.read(_storageKey);
    if (persisted != generated) {
      throw StateError('تعذر تثبيت معرّف هذا الجهاز في التخزين الآمن.');
    }
    return generated;
  }

  String _newUuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }

  static bool isValidDeviceId(String value) =>
      _uuidPattern.hasMatch(value);
}
