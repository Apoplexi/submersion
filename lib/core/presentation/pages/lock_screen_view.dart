import 'package:flutter/material.dart';

import 'package:submersion/core/presentation/widgets/ocean_background.dart';
import 'package:submersion/core/presentation/widgets/unlock_form.dart';

/// Full-screen startup lock: splash chrome around an UnlockForm plus the
/// escape-hatch links (recovery code / open a different database).
///
/// Rendered inside the pre-l10n splash MaterialApp, so strings are plain
/// English by the same precedent as the splash and migration UI.
class LockScreenView extends StatelessWidget {
  final Brightness brightness;
  final Future<bool> Function(String secret) onSubmitSecret;
  final Future<bool> Function()? onBiometric;
  final VoidCallback? onUseRecoveryCode;
  final VoidCallback? onStartFresh;

  const LockScreenView({
    super.key,
    required this.brightness,
    required this.onSubmitSecret,
    required this.onBiometric,
    this.onUseRecoveryCode,
    this.onStartFresh,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: OceanBackground(
        brightness: brightness,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.asset(
                      'assets/icon/icon.png',
                      width: 96,
                      height: 96,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Submersion is locked',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 32),
                  UnlockForm(
                    onSubmitSecret: onSubmitSecret,
                    onBiometric: onBiometric,
                    footer: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (onUseRecoveryCode != null)
                          TextButton(
                            onPressed: onUseRecoveryCode,
                            child: const Text('Forgot password?'),
                          ),
                        if (onStartFresh != null)
                          TextButton(
                            onPressed: onStartFresh,
                            child: const Text('Open a different database'),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
