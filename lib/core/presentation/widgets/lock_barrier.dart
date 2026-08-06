import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:submersion/core/presentation/providers/app_lock_provider.dart';
import 'package:submersion/core/presentation/widgets/unlock_form.dart';

/// Full-screen opaque overlay while the app is re-locked after a background
/// timeout. Mirrors RestoreBarrier's placement in the MaterialApp builder,
/// wrapped OUTSIDE it so the lock covers restore UI too. The database stays
/// open behind the overlay — App Lock is a UI gate, not a DB close.
class LockBarrier extends ConsumerWidget {
  final Widget child;

  const LockBarrier({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locked = ref.watch(appLockNotifierProvider);
    return Stack(
      children: [
        child,
        if (locked)
          Positioned.fill(
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              child: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock_outline, size: 48),
                        const SizedBox(height: 16),
                        Text(
                          'Submersion is locked',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 24),
                        UnlockForm(
                          onSubmitSecret: (s) => ref
                              .read(appLockNotifierProvider.notifier)
                              .unlockWithSecret(s),
                          onBiometric: () => ref
                              .read(appLockNotifierProvider.notifier)
                              .unlockWithBiometric(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
