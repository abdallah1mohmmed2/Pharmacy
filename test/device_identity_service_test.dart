import 'package:flutter_test/flutter_test.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/device_identity_service.dart';

void main() {
  test('keeps one device UUID stable across service instances', () async {
    final storage = _MemoryDeviceIdentityStorage();
    final first = DeviceIdentityService(storage: storage);
    final second = DeviceIdentityService(storage: storage);

    final id = await first.getOrCreateDeviceId();
    expect(DeviceIdentityService.isValidDeviceId(id), isTrue);
    expect(await second.getOrCreateDeviceId(), id);
  });

  test('two independent devices receive different UUIDs', () async {
    final first = DeviceIdentityService(
      storage: _MemoryDeviceIdentityStorage(),
    );
    final second = DeviceIdentityService(
      storage: _MemoryDeviceIdentityStorage(),
    );

    final firstId = await first.getOrCreateDeviceId();
    final secondId = await second.getOrCreateDeviceId();

    expect(DeviceIdentityService.isValidDeviceId(firstId), isTrue);
    expect(DeviceIdentityService.isValidDeviceId(secondId), isTrue);
    expect(firstId, isNot(secondId));
  });

  test('concurrent requests share one stable UUID', () async {
    final storage = _MemoryDeviceIdentityStorage();
    final service = DeviceIdentityService(storage: storage);

    final ids = await Future.wait(List.generate(
      8,
      (_) => service.getOrCreateDeviceId(),
    ));

    expect(ids.toSet(), hasLength(1));
    expect(storage.values, hasLength(1));
  });

  test('replaces malformed persisted value with a valid UUID', () async {
    final storage = _MemoryDeviceIdentityStorage()
      ..values['pharmacy_device_uuid_v1'] = 'not-a-uuid';
    final service = DeviceIdentityService(storage: storage);

    final id = await service.getOrCreateDeviceId();

    expect(DeviceIdentityService.isValidDeviceId(id), isTrue);
    expect(storage.values['pharmacy_device_uuid_v1'], id);
  });
}

class _MemoryDeviceIdentityStorage implements DeviceIdentityStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
