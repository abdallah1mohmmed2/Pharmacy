import 'package:flutter_test/flutter_test.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/financial_minor_units.dart';

void main() {
  group('F03 exact minor-unit decimal contract', () {
    test('YER policy rejects wrong currency, fraction and nonzero decimals',
        () {
      expect(FinancialMinorUnits.currencyCode, 'YER');
      expect(FinancialMinorUnits.currencyFractionDigits, 0);
      FinancialMinorUnits.requireYerPolicy(code: 'YER', fractionDigits: 0);
      expect(FinancialMinorUnits.parseYer('125'), 125);
      expect(FinancialMinorUnits.parseYer('125.000'), 125);
      expect(
          () => FinancialMinorUnits.parseYer('125.01'), throwsFormatException);
      expect(
          () => FinancialMinorUnits.requireYerPolicy(
              code: 'USD', fractionDigits: 0),
          throwsFormatException);
      expect(
          () => FinancialMinorUnits.requireYerPolicy(
              code: 'YER', fractionDigits: 2),
          throwsFormatException);
    });
    test('zero-decimal currency and canonical output', () {
      expect(FinancialMinorUnits.parseDecimal('123', fractionDigits: 0), 123);
      expect(
          FinancialMinorUnits.parseDecimal('123.000', fractionDigits: 0), 123);
      expect(FinancialMinorUnits.toDecimal(123, fractionDigits: 0), '123');
    });

    test('one, two, three digits round-trip without rounding', () {
      for (final digits in [1, 2, 3]) {
        for (final amount in [0, 1, 9, 10, 101, 999999999999]) {
          final value =
              FinancialMinorUnits.toDecimal(amount, fractionDigits: digits);
          expect(
              FinancialMinorUnits.parseDecimal(value, fractionDigits: digits),
              amount);
        }
      }
    });

    test('leading and trailing zeros are exact, no hidden rounding', () {
      expect(FinancialMinorUnits.parseDecimal('0.01', fractionDigits: 2), 1);
      expect(
          FinancialMinorUnits.parseDecimal('1.2300', fractionDigits: 2), 123);
      expect(FinancialMinorUnits.parseDecimal('1.000', fractionDigits: 0), 1);
      expect(
          () => FinancialMinorUnits.parseDecimal('1.2301', fractionDigits: 2),
          throwsFormatException);
      expect(() => FinancialMinorUnits.parseDecimal('0.001', fractionDigits: 2),
          throwsFormatException);
    });

    test('reject negative, exponential, locale, NaN, Infinity and whitespace',
        () {
      for (final raw in [
        '-1',
        '+1',
        '1e2',
        '1,20',
        'NaN',
        'Infinity',
        ' 1',
        '1 ',
        '01',
        '.1',
        '1.',
        ''
      ]) {
        expect(() => FinancialMinorUnits.parseDecimal(raw, fractionDigits: 2),
            throwsFormatException,
            reason: raw);
      }
    });

    test('reject overflow and invalid precision', () {
      expect(
          FinancialMinorUnits.parseDecimal('999999999999', fractionDigits: 0),
          FinancialMinorUnits.maxMinor);
      expect(
          () => FinancialMinorUnits.parseDecimal('1000000000000',
              fractionDigits: 0),
          throwsFormatException);
      for (final digits in [-1, 4]) {
        expect(
            () => FinancialMinorUnits.parseDecimal('1', fractionDigits: digits),
            throwsFormatException);
        expect(() => FinancialMinorUnits.toDecimal(1, fractionDigits: digits),
            throwsFormatException);
      }
    });

    test('wire minor amounts require integers within supported range', () {
      expect(FinancialMinorUnits.checkedMinor(0, fractionDigits: 2), 0);
      expect(FinancialMinorUnits.checkedMinor(999999999999, fractionDigits: 3),
          999999999999);
      for (final raw in [null, 1.0, '1', -1, 1000000000000]) {
        expect(() => FinancialMinorUnits.checkedMinor(raw, fractionDigits: 2),
            throwsFormatException);
      }
    });
  });
}
