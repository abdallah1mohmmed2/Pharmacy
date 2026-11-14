import 'package:flutter_test/flutter_test.dart';
import 'package:global_enterprise_pharmacy_erp/data/models/purchase_input_parser.dart';

void main() {
  test('Arabic and Persian digits and decimal separators are accepted', () {
    expect(parsePurchaseNumber('١٬٢٥٠٫٥٠'), 1250.5);
    expect(parsePurchaseNumber('۱۲۵۰٫۵۰'), 1250.5);
    expect(parsePurchaseNumber('1,250.50'), 1250.5);
    expect(parsePurchaseNumber('1250,50'), 1250.5);
    expect(parsePurchaseNumber('١،٢٥'), 1.25);
    expect(parsePurchaseNumber('\u200f١٢٫٥\u061c'), 12.5);
  });
  test('blank, malformed and nonfinite prices remain invalid', () {
    for (final value in ['', 'NaN', 'Infinity', '١٢abc', '1.2.3', '1,2,3', '1e999']) {
      expect(parsePurchaseNumber(value), isNull, reason: value);
    }
  });
  test('pack quantities accept Arabic integers but never round fractions', () {
    expect(parsePurchaseCount('٢'), 2);
    expect(parsePurchaseCount('١٬٠٠٠'), 1000);
    expect(parsePurchaseCount('٢٫٠'), 2);
    expect(parsePurchaseCount('٢٫٥'), isNull);
    expect(parsePurchaseCount('NaN'), isNull);
    expect(parsePurchaseCount('-١'), -1);
  });
  test('full expiry formats normalize to the same strict database date', () {
    for (final value in ['2028-12-31', '٣١/١٢/٢٠٢٨', '2028/12/31', '31.12.2028', ' ٣١ / ١٢ / ٢٠٢٨ ']) {
      expect(purchaseExpiryIso(parsePurchaseExpiry(value)!), '2028-12-31');
    }
  });
  test('month and year use the last actual day including leap years', () {
    expect(purchaseExpiryIso(parsePurchaseExpiry('٠٢/٢٠٢٨')!), '2028-02-29');
    expect(purchaseExpiryIso(parsePurchaseExpiry('2027-02')!), '2027-02-28');
    expect(purchaseExpiryIso(parsePurchaseExpiry('١٢/٢٠٢٨')!), '2028-12-31');
  });
  test('invalid calendar dates are rejected rather than rolled into next month', () {
    for (final value in ['2027-02-29', '٣١/٠٢/٢٠٢٨', '2028-13-01', '12/00/2028', '31/12/28', 'abc', '']) {
      expect(parsePurchaseExpiry(value), isNull, reason: value);
    }
  });
}
