// test/algorithms_and_invariants_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:global_enterprise_pharmacy_erp/data/models/clinical_and_rx_models.dart';
import 'package:global_enterprise_pharmacy_erp/data/models/drug_model.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/clinical_guard_service.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/fefo_allocator_service.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/partner_distribution_service.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/purchase_and_bonus_service.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/posting_and_sales_service.dart';

void main() {
  group('FEFO and pack-unit invariants', () {
    test('loose units are always normalized into 0 <= loose < units per pack',
        () {
      for (final total in [0, 1, 29, 30, 31, 59, 60, 61, 999]) {
        final split = FefoAllocator.splitUnits(total, 30);
        expect(split.looseUnits, greaterThanOrEqualTo(0));
        expect(split.looseUnits, lessThan(30));
        expect(split.sealedPacks * 30 + split.looseUnits, total);
      }
      expect(() => FefoAllocator.splitUnits(-1, 30), throwsArgumentError);
      expect(() => FefoAllocator.splitUnits(10, 0), throwsArgumentError);
    });
  });
  group('Clinical reference invariants', () {
    test(
        'Cockcroft-Gault applies the female factor and uses a supplied eGFR override',
        () {
      final birth = DateTime(DateTime.now().year - 50, 1, 1);
      final male = PatientClinicalModel(
          fullName: 'M',
          birthDate: birth,
          sex: 'M',
          weightKg: 72,
          serumCreatinine: 1);
      final female = PatientClinicalModel(
          fullName: 'F',
          birthDate: birth,
          sex: 'F',
          weightKg: 72,
          serumCreatinine: 1);
      final expected = ((140 - male.ageYears!) * 72) / 72;
      expect(male.crcl, closeTo(expected, 0.0001));
      expect(female.crcl, closeTo(expected * .85, 0.0001));
      final override = PatientClinicalModel(
          fullName: 'O',
          birthDate: birth,
          sex: 'M',
          weightKg: 72,
          serumCreatinine: 1,
          egfrMlMin: 41);
      expect(override.crcl, 41);
    });
    test('Child-Pugh B rule maps to its recorded dose adjustment', () {
      final rule = HepaticRuleModel.fromMap({
        'drug_id': 7,
        'child_pugh_class': 'B',
        'action': 'REDUCE_DOSE',
        'dose_factor': 0.5,
        'max_daily_mg': 250
      });
      expect(rule.childPughClass, 'B');
      expect(rule.action, 'REDUCE_DOSE');
      expect(rule.doseFactor, 0.5);
      expect(ClinicalGuardService.hepaticRuleMatches('B', rule), isTrue);
      expect(ClinicalGuardService.hepaticRuleMatches('A', rule), isFalse);
    });
    test(
        'pregnancy category X is blocked only for a confirmed pregnant patient',
        () {
      const drug =
          DrugModel(tradeNameAr: 'دواء اختباري', pregnancyCategory: 'X');
      const pregnant = PatientClinicalModel(
          fullName: 'حالة',
          sex: 'F',
          isPregnant: true,
          pregnancyStatusKnown: true);
      const notPregnant = PatientClinicalModel(
          fullName: 'حالة أخرى',
          sex: 'F',
          isPregnant: false,
          pregnancyStatusKnown: true);
      expect(ClinicalGuardService.blocksPregnancyX(drug, pregnant), isTrue);
      expect(ClinicalGuardService.blocksPregnancyX(drug, notPregnant), isFalse);
    });
  });
  group('Accounting and inventory costing invariants', () {
    test('weighted average cost incorporates old stock and incoming total cost',
        () {
      final value = PurchaseAndBonusService.calculateWeightedAverage(
          currentPacks: 10,
          currentAverage: 100,
          incomingPacks: 5,
          incomingTotalCost: 600);
      expect(value, closeTo(106.6666667, 0.0001));
      expect(
          PurchaseAndBonusService.calculateEffectivePackCost(
              paidPacks: 10,
              bonusPacks: 2,
              packPrice: 120,
              discountPct: 0,
              includeBonus: true),
          100);
      expect(
          PurchaseAndBonusService.calculateEffectivePackCost(
              paidPacks: 10,
              bonusPacks: 2,
              packPrice: 120,
              discountPct: 0,
              includeBonus: false),
          120);
      expect(
          PurchaseAndBonusService.calculateWeightedAverage(
              currentPacks: 0,
              currentAverage: 0,
              incomingPacks: 0,
              incomingTotalCost: 0),
          0);
    });
    test('rounded partner shares sum to distributable profit exactly', () {
      final amounts = PartnerDistributionService.allocateProfitExactly(
          profit: 100, basis: [1, 1, 1]);
      expect(amounts.fold<double>(0, (a, b) => a + b), 100);
      expect(amounts, [33.34, 33.33, 33.33]);
    });
    test('hidden journal entries must balance before posting', () {
      expect(PostingAndSalesService.isBalancedAmounts(1250, 1250), isTrue);
      expect(PostingAndSalesService.isBalancedAmounts(1250, 1240), isFalse);
      expect(PostingAndSalesService.isBalancedAmounts(0, 0), isFalse);
    });
    test('partner distribution mode enforces mutually exclusive inputs', () {
      const shares = PartnerPolicy('shares');
      const percentage = PartnerPolicy('percentage');
      expect(() => shares.validate(sharesCount: 10, percentage: 20),
          throwsA(isA<PolicyViolation>()));
      expect(() => percentage.validate(sharesCount: 10, percentage: 20),
          throwsA(isA<PolicyViolation>()));
      expect(() => shares.validate(sharesCount: 10), returnsNormally);
      expect(() => percentage.validate(percentage: 100), returnsNormally);
    });
  });
}
