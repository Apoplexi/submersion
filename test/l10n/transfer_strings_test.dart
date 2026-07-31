import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';

/// Every locale must carry the Transfer / dive-computer strings added for
/// #152: gen-l10n falls back to English silently, so an untranslated locale
/// would ship unnoticed.
void main() {
  test('every supported locale translates the transfer computer strings', () {
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = lookupAppLocalizations(locale);
      final strings = <String>[
        l10n.transfer_computers_knownComputersHeader,
        l10n.transfer_computers_diveCount(3),
        l10n.transfer_computers_downloadTooltip,
        l10n.transfer_computers_lastDownloadNever,
        l10n.transfer_computers_lastDownloadMinutesAgo(5),
        l10n.transfer_computers_lastDownloadHoursAgo(3),
        l10n.transfer_computers_lastDownloadYesterday,
        l10n.transfer_computers_lastDownloadDaysAgo(3),
      ];
      for (final value in strings) {
        expect(value, isNotEmpty, reason: 'locale $locale');
      }
    }
  });

  test('the last-download strings are actually translated in German', () {
    final de = lookupAppLocalizations(const Locale('de'));
    expect(de.transfer_computers_lastDownloadNever, 'Nie');
    expect(de.transfer_computers_lastDownloadYesterday, 'Gestern');
  });
}
