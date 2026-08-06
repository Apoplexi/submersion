import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:submersion/core/services/database_service.dart';
import 'package:submersion/core/services/security/database_security_key_store.dart';
import 'package:submersion/core/services/security/database_security_service.dart';
import 'package:submersion/features/settings/presentation/pages/security_settings_page.dart';
import 'package:submersion/features/settings/presentation/widgets/security_setup_dialog.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';

import '../../../../support/fake_keychain_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late String dbPath;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('security_page_test');
    dbPath = p.join(tmp.path, 'submersion.db');
    DatabaseSecurityService.instance.resetForTesting();
    DatabaseService.instance.resetForTesting();
    DatabaseService.instance.setCurrentPathForTesting(dbPath);
  });

  tearDown(() async {
    DatabaseSecurityService.instance.resetForTesting();
    DatabaseService.instance.resetForTesting();
    await tmp.delete(recursive: true);
  });

  Future<void> configure(Map<String, Object> prefsValues) async {
    SharedPreferences.setMockInitialValues(prefsValues);
    final prefs = await SharedPreferences.getInstance();
    await DatabaseSecurityService.instance.configure(
      prefs: prefs,
      keyStore: DatabaseSecurityKeyStore(storage: InMemoryKeychain()),
    );
  }

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('en'),
        home: Scaffold(body: SecuritySettingsPage()),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows both toggles off by default', (tester) async {
    await configure({});
    await pumpPage(tester);
    expect(find.text('App Lock'), findsOneWidget);
    expect(find.text('Encrypt database'), findsOneWidget);
    final switches = tester
        .widgetList<SwitchListTile>(find.byType(SwitchListTile))
        .toList();
    expect(switches, hasLength(2));
    expect(switches.every((s) => s.value == false), true);
  });

  testWidgets('enabling app lock opens the setup dialog', (tester) async {
    await configure({});
    await pumpPage(tester);
    await tester.tap(find.text('App Lock'));
    await tester.pump();
    expect(find.byType(SecuritySetupDialog), findsOneWidget);
    expect(find.text('Set app password'), findsOneWidget);
  });

  testWidgets('with app lock on, shows management tiles', (tester) async {
    await configure({'app_lock_enabled': true});
    await pumpPage(tester);
    expect(find.text('Auto-lock'), findsOneWidget);
    expect(find.text('Change password'), findsOneWidget);
    expect(find.text('New recovery code'), findsOneWidget);
  });

  testWidgets('encryption toggle with app lock off launches setup first', (
    tester,
  ) async {
    await configure({});
    await pumpPage(tester);
    await tester.tap(find.text('Encrypt database'));
    await tester.pump();
    // The password setup dialog appears before any encryption confirm.
    expect(find.byType(SecuritySetupDialog), findsOneWidget);
  });

  testWidgets('disable app lock is blocked while encryption is on', (
    tester,
  ) async {
    await configure({'app_lock_enabled': true, 'db_encryption_enabled': true});
    await pumpPage(tester);
    await tester.tap(find.text('App Lock'));
    await tester.pump();
    expect(find.text('Encryption is on'), findsOneWidget);
  });
}
