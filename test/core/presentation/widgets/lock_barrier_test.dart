import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:submersion/core/presentation/providers/app_lock_provider.dart';
import 'package:submersion/core/presentation/widgets/lock_barrier.dart';
import 'package:submersion/core/presentation/widgets/unlock_form.dart';
import 'package:submersion/core/services/security/database_security_key_store.dart';
import 'package:submersion/core/services/security/database_security_service.dart';

import '../../../support/fake_keychain_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    DatabaseSecurityService.instance.resetForTesting();
  });

  testWidgets('passes the child through when unlocked, overlays when locked', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'app_lock_enabled': true,
      'app_lock_timeout_minutes': 0,
      // Biometric hardware is absent in tests; keep the auto-fire path off.
      'app_lock_biometrics_enabled': false,
    });
    final prefs = await SharedPreferences.getInstance();
    DatabaseSecurityService.instance.resetForTesting();
    await DatabaseSecurityService.instance.configure(
      prefs: prefs,
      keyStore: DatabaseSecurityKeyStore(storage: InMemoryKeychain()),
    );

    late WidgetRef capturedRef;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              capturedRef = ref;
              return const LockBarrier(child: Text('APP'));
            },
          ),
        ),
      ),
    );
    expect(find.text('APP'), findsOneWidget);
    expect(find.byType(UnlockForm), findsNothing);

    // Timeout 0: any background/resume cycle locks immediately.
    final notifier = capturedRef.read(appLockNotifierProvider.notifier);
    notifier.noteBackgrounded();
    notifier.noteResumed();
    await tester.pump();

    expect(find.byType(UnlockForm), findsOneWidget);
  });
}
