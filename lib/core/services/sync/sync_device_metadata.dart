import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import 'package:submersion/core/data/repositories/sync_repository.dart';

/// The identity resolved by [SyncDeviceMetadata.resolve].
typedef DeviceIdentity = ({String id, String? name, String? appVersion});

/// Resolves an identity without touching the platform. Lets callers that own
/// the identity (and tests) supply one directly.
typedef DeviceIdentityResolver = Future<DeviceIdentity> Function();

/// Who this device is, for anything that stamps an identity into the cloud:
/// library epoch markers, library moved markers, and per-device sync
/// manifests. One resolver so the three cannot drift apart.
class SyncDeviceMetadata {
  const SyncDeviceMetadata(this._syncRepository);

  final SyncRepository _syncRepository;

  /// Hostnames that identify nothing. Android routinely reports 'localhost',
  /// which would make every Android peer display under the same name; an
  /// absent name falls back to the device id, which is at least unique.
  static const _uselessNames = {'localhost'};

  /// Normalises a raw hostname, returning null when it identifies nothing.
  static String? sanitizeDeviceName(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (_uselessNames.contains(trimmed.toLowerCase())) return null;
    return trimmed;
  }

  /// Each piece degrades independently to a safe default: markers are shown
  /// in banners and dialogs, so the origin must always be displayable.
  Future<DeviceIdentity> resolve() async {
    String id;
    try {
      id = await _syncRepository.getDeviceId();
    } catch (_) {
      // Non-empty sentinel: the marker's origin is rendered, so it must never
      // be blank.
      id = 'unknown';
    }
    String? name;
    try {
      name = sanitizeDeviceName(Platform.localHostname);
    } catch (_) {
      name = null;
    }
    String? appVersion;
    try {
      appVersion = (await PackageInfo.fromPlatform()).version;
    } catch (_) {
      appVersion = null;
    }
    return (id: id, name: name, appVersion: appVersion);
  }
}
