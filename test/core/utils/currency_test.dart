import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/utils/currency.dart';

void main() {
  group('currencySymbol', () {
    test('maps common codes to their symbols', () {
      expect(currencySymbol('USD'), r'$');
      expect(currencySymbol('EUR'), '€');
      expect(currencySymbol('GBP'), '£');
    });

    test('is case-insensitive and trims whitespace', () {
      expect(currencySymbol(' eur '), '€');
    });

    test('blank code yields an empty symbol', () {
      expect(currencySymbol(''), '');
      expect(currencySymbol('   '), '');
    });

    test('unrecognised code falls back to the code itself', () {
      expect(currencySymbol('ZZZ'), 'ZZZ');
    });
  });

  group('formatMoney', () {
    test('includes the currency symbol', () {
      expect(formatMoney(12.5, 'EUR'), contains('€'));
      expect(formatMoney(12.5, 'USD'), contains(r'$'));
    });

    test('unrecognised code still shows the code and amount', () {
      final formatted = formatMoney(12.5, 'ZZZ');
      expect(formatted, contains('ZZZ'));
      expect(formatted, contains('12.5'));
    });
  });

  test('kCommonCurrencyCodes covers the major currencies', () {
    expect(kCommonCurrencyCodes, containsAll(['USD', 'EUR', 'GBP', 'CHF']));
  });
}
