import 'package:flutter/services.dart';

import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/settings/presentation/providers/display_zoom_provider.dart';

const _channel = MethodChannel('app.submersion/display');

/// Registers a method channel handler so the macOS View menu can drive the
/// app-wide display zoom.
void registerDisplayZoomMenuChannel(WidgetRef ref) {
  _channel.setMethodCallHandler((call) async {
    final notifier = ref.read(displayZoomNotifierProvider.notifier);
    switch (call.method) {
      case 'zoomIn':
        await notifier.stepBy(1);
      case 'zoomOut':
        await notifier.stepBy(-1);
      case 'actualSize':
        await notifier.reset();
    }
  });
}
