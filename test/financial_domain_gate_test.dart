import 'package:flutter_test/flutter_test.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/financial_domain_gate.dart';

void main() {
  test('F10-F16 domain manifest inventory stays explicit and disabled', () {
    expect(FinancialDomainGate.productionTransportEnabled, isFalse);
    expect(FinancialDomainGate.requiredMembers, hasLength(14));
    for (final entry in FinancialDomainGate.requiredMembers.entries) {
      expect(entry.value, isNotEmpty, reason: entry.key);
      expect(() => FinancialDomainGate.requireTransportApproved(entry.key),
          throwsA(isA<StateError>()));
      FinancialDomainGate.validateMemberNames(entry.key, entry.value);
      expect(
          () => FinancialDomainGate.validateMemberNames(
              entry.key, entry.value.skip(1)),
          throwsA(isA<StateError>()),
          reason: entry.key);
      expect(
          () => FinancialDomainGate.validateMemberNames(
              entry.key, [...entry.value, 'unexpected']),
          throwsA(isA<StateError>()),
          reason: entry.key);
    }
  });

  test('F10-F16 rejects unknown types and repeated members', () {
    expect(() => FinancialDomainGate.requireTransportApproved('UNKNOWN'),
        throwsA(isA<StateError>()));
    expect(
        () => FinancialDomainGate.validateMemberNames('UNKNOWN', ['voucher']),
        throwsA(isA<StateError>()));
    final members = FinancialDomainGate.requiredMembers['CASH_SALE']!;
    expect(
        () => FinancialDomainGate.validateMemberNames(
            'CASH_SALE', [...members, members.first]),
        throwsA(isA<StateError>()));
  });
}
