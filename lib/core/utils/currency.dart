import 'package:intl/intl.dart';

/// Common currency codes offered as presets in pickers. Free-text entry still
/// allows any other ISO 4217 code.
const List<String> kCommonCurrencyCodes = [
  'USD',
  'EUR',
  'GBP',
  'CHF',
  'AUD',
  'CAD',
  'NZD',
  'JPY',
  'SEK',
  'NOK',
  'DKK',
  'THB',
  'EGP',
  'MXN',
  'IDR',
  'PHP',
  'ZAR',
];

/// The symbol for [currencyCode] (e.g. 'EUR' -> '€'), falling back to the
/// upper-cased code itself for anything intl doesn't recognise (or an empty
/// string for a blank code).
String currencySymbol(String currencyCode) {
  final code = currencyCode.trim().toUpperCase();
  if (code.isEmpty) return '';
  try {
    return NumberFormat.simpleCurrency(name: code).currencySymbol;
  } catch (_) {
    return code;
  }
}

/// Formats [amount] in [currencyCode] using the currency's symbol, falling back
/// to "CODE 12.34" for unrecognised codes.
String formatMoney(double amount, String currencyCode) {
  final code = currencyCode.trim().toUpperCase();
  try {
    return NumberFormat.simpleCurrency(name: code).format(amount);
  } catch (_) {
    final prefix = code.isEmpty ? '' : '$code ';
    return '$prefix${amount.toStringAsFixed(2)}';
  }
}
