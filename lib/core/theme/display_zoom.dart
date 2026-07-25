import 'package:flutter/material.dart';

/// App-wide display zoom constants and value clamping.
///
/// Zoom is a pure scale factor: 1.0 is the design size, values below 1.0 fit
/// more content on screen, values above 1.0 make everything larger.
class DisplayZoom {
  DisplayZoom._();

  /// Smallest supported zoom factor.
  static const double min = 0.70;

  /// Largest supported zoom factor.
  static const double max = 1.40;

  /// Increment used by the slider and the keyboard shortcuts.
  static const double step = 0.05;

  /// The unzoomed design size.
  static const double defaultValue = 1.0;

  /// Slider divisions across [min]..[max] at [step] granularity.
  static const int divisions = 14;

  /// Clamps any stored or computed value into the supported range.
  ///
  /// Guards against a corrupt preference producing a zero or NaN scale, which
  /// would divide by zero in the layout and blank the app.
  static double clampValue(double value) {
    if (!value.isFinite) return defaultValue;
    return value.clamp(min, max).toDouble();
  }
}

/// Applies an app-wide zoom factor to everything below it.
///
/// Lays the child out in a logical space divided by [zoom], then scales that
/// space back up by [zoom] to fill the physical area. The result is true
/// browser-style zoom: text, icons, spacing, and custom painters all change
/// size together, and because [MediaQuery] is inherited, responsive
/// breakpoints below this widget see the zoomed logical width.
class DisplayZoomScope extends StatelessWidget {
  const DisplayZoomScope({super.key, required this.zoom, required this.child});

  final double zoom;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Exact identity at the default so users who never touch the setting get
    // the same widget tree as before, with no extra transform layer.
    if (zoom == DisplayZoom.defaultValue) return child;

    final mq = MediaQuery.of(context);
    final logical = mq.size / zoom;

    return MediaQuery(
      data: mq.copyWith(
        size: logical,
        // Insets are expressed in the outer coordinate space. Without dividing
        // them, content creeps under the notch and behind the keyboard.
        padding: mq.padding / zoom,
        viewPadding: mq.viewPadding / zoom,
        viewInsets: mq.viewInsets / zoom,
        // ImageConfiguration consults this to select asset resolution.
        devicePixelRatio: mq.devicePixelRatio * zoom,
      ),
      child: Transform.scale(
        scale: zoom,
        alignment: Alignment.topLeft,
        // OverflowBox, not SizedBox: MaterialApp.builder passes TIGHT
        // constraints equal to the physical window, which would force a
        // SizedBox back to the physical size. The child would then be scaled
        // below the window (unpainted band at zoom < 1) or past it (clipped
        // overflow at zoom > 1). OverflowBox lets the child take the enlarged
        // logical size regardless of the incoming constraints.
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: logical.width,
          maxWidth: logical.width,
          minHeight: logical.height,
          maxHeight: logical.height,
          child: child,
        ),
      ),
    );
  }
}
