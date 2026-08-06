import 'dart:io';

import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// Thin, non-throwing wrapper over local_auth. Platform support: iOS,
/// Android, macOS (Touch ID), Windows (Hello). Linux has no local_auth
/// backend — password-only there, and [isAvailable] says so.
class BiometricService {
  final LocalAuthentication _auth;

  BiometricService({LocalAuthentication? auth})
    : _auth = auth ?? LocalAuthentication();

  Future<bool> isAvailable() async {
    if (Platform.isLinux) return false;
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> authenticate({required String reason}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        // Retry after the OS backgrounds the app mid-prompt (the 3.x
        // replacement for stickyAuth) instead of failing the unlock.
        persistAcrossBackgrounding: true,
      );
    } on PlatformException {
      return false;
    }
  }
}
