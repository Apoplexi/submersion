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
