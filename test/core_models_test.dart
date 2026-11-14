import 'package:flutter_test/flutter_test.dart';
import 'package:global_enterprise_pharmacy_erp/data/models/drug_model.dart';
import 'package:global_enterprise_pharmacy_erp/data/models/inventory_and_purchase_models.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/security_hash_service.dart';

void main() {
  group('DrugModel', () {
    test('converts pack, strip and unit quantities to base units', () {
      const drug = DrugModel(stripsPerPack: 3, unitsPerStrip: 10);
      expect(drug.toBaseUnits('PACK', 2), 60);
      expect(drug.toBaseUnits('STRIP', 2), 20);
      expect(drug.toBaseUnits('UNIT', 2), 2);
    });
    test('rejects non-positive sale quantities', () {
      const drug = DrugModel();
      expect(() => drug.toBaseUnits('UNIT', 0), throwsArgumentError);
    });
    test('completeness is bounded from zero to one hundred', () {
      const drug = DrugModel();
      expect(drug.calculateCompletenessPct(), inInclusiveRange(0, 100));
    });
  });
  group('BatchFefoModel', () {
    test('calculates expiry status from calendar dates', () {
      final today = DateTime.now();
      final future = today.add(const Duration(days: 40));
      final expiry = future.toIso8601String().substring(0, 10);
      final batch = BatchFefoModel(
          id: 1,
          drugId: 1,
          warehouseId: 1,
          batchNo: 'B-1',
          expiryDate: expiry,
          totalUnits: 20);
      expect(batch.daysUntilExpiry, 40);
      expect(batch.expiryState, 'WARNING');
      expect(batch.isExpired, isFalse);
    });
    test('marks expired batches as unavailable for sale', () {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final expiry = yesterday.toIso8601String().substring(0, 10);
      final batch = BatchFefoModel(
          id: 2,
          drugId: 1,
          warehouseId: 1,
          batchNo: 'B-2',
          expiryDate: expiry,
          totalUnits: 10);
      expect(batch.isExpired, isTrue);
      expect(batch.isSellable, isFalse);
      expect(batch.expiryState, 'EXPIRED');
    });
  });
  group('SecurityHashService', () {
    test('hashes secrets with a unique salt and verifies the original value',
        () {
      final first = SecurityHashService.hash('123456');
      final second = SecurityHashService.hash('123456');
      expect(first, isNot(second));
      expect(SecurityHashService.verify('123456', first), isTrue);
      expect(SecurityHashService.verify('wrong', first), isFalse);
      expect(SecurityHashService.verify('123456', second), isTrue);
    });
  });
}
