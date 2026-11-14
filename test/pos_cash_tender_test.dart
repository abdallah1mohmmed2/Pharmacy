import 'package:flutter_test/flutter_test.dart';
import 'package:global_enterprise_pharmacy_erp/data/models/pos_cash_tender.dart';

void main() {
  test('cash change uses the discounted net without increasing collected cash',
      () {
    expect(posCashChange(netTotal: 900, receivedText: '1000'), 100);
    expect(posCashChange(netTotal: 900, receivedText: '900'), 0);
    expect(posCashChange(netTotal: 900, receivedText: '  '), 0);
    expect(posCashChange(netTotal: 75.5, receivedText: '100'), 24.5);
  });
  test('underpayment, malformed and non-finite cash tender are rejected', () {
    for (final input in ['899', '-1', 'abc', 'NaN', 'Infinity']) {
      expect(() => posCashChange(netTotal: 900, receivedText: input),
          throwsStateError);
    }
    expect(() => posCashChange(netTotal: double.nan, receivedText: '1000'),
        throwsStateError);
  });
}
