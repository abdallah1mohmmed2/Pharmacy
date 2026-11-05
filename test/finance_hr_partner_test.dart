// test/finance_hr_partner_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/partner_distribution_service.dart';

void main() {
  test('shares mode locks percentage input and preserves shares editing', () {
    const policy = PartnerPolicy('shares');
    expect(policy.sharesEditable, isTrue);
    expect(policy.percentageEditable, isFalse);
    expect(() => policy.validate(sharesCount: 20, percentage: 25),
        throwsA(isA<PolicyViolation>()));
    expect(() => policy.validate(sharesCount: 20), returnsNormally);
  });

  test('percentage mode locks shares input and preserves percentage editing', () {
    const policy = PartnerPolicy('percentage');
    expect(policy.percentageEditable, isTrue);
    expect(policy.sharesEditable, isFalse);
    expect(() => policy.validate(sharesCount: 20, percentage: 25),
        throwsA(isA<PolicyViolation>()));
    expect(() => policy.validate(percentage: 25), returnsNormally);
  });

  test('partner percentage must remain within zero and one hundred', () {
    const policy = PartnerPolicy('percentage');
    expect(() => policy.validate(percentage: 100), returnsNormally);
    expect(() => policy.validate(percentage: 100.1), throwsArgumentError);
    expect(() => policy.validate(percentage: -0.1), throwsArgumentError);
  });
}
