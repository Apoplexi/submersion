import 'dart:convert';

import 'package:equatable/equatable.dart';

/// How contour levels are chosen: nice unit-aware steps, or a user list.
enum SeascapeContourMode { auto, custom }

/// One user-defined contour level. Depth is stored in METERS regardless of
/// the display unit; [colorArgb] null means the standard contour ink.
class SeascapeContourLevel extends Equatable {
  final double depthMeters;
  final int? colorArgb;

  const SeascapeContourLevel({required this.depthMeters, this.colorArgb});

  Map<String, dynamic> toJson() => {
    'depthMeters': depthMeters,
    if (colorArgb != null) 'colorArgb': colorArgb,
  };

  static SeascapeContourLevel? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final depth = json['depthMeters'];
    if (depth is! num || !depth.isFinite || depth <= 0) return null;
    final color = json['colorArgb'];
    return SeascapeContourLevel(
      depthMeters: depth.toDouble(),
      colorArgb: color is int ? color : null,
    );
  }

  @override
  List<Object?> get props => [depthMeters, colorArgb];
}

/// The seascape terrain-appearance knobs (issue #1065): device-local view
/// preferences carried on AppSettings and threaded into the geometry
/// builders as plain data (crosses compute() isolates).
class SeascapeAppearance extends Equatable {
  /// Null = ramp spans the terrain's own depth range (legacy behavior).
  final double? rampMaxDepthMeters;
  final bool rampBanded;
  final SeascapeContourMode contourMode;
  final List<SeascapeContourLevel> customLevels;

  /// Cells steeper than this highlight as walls, slider range 5 to 90.
  final double wallAngleDeg;

  const SeascapeAppearance({
    this.rampMaxDepthMeters,
    this.rampBanded = false,
    this.contourMode = SeascapeContourMode.auto,
    this.customLevels = const [],
    this.wallAngleDeg = 22.0,
  });

  SeascapeAppearance copyWith({
    double? rampMaxDepthMeters,
    bool clearRampMax = false,
    bool? rampBanded,
    SeascapeContourMode? contourMode,
    List<SeascapeContourLevel>? customLevels,
    double? wallAngleDeg,
  }) => SeascapeAppearance(
    rampMaxDepthMeters: clearRampMax
        ? null
        : (rampMaxDepthMeters ?? this.rampMaxDepthMeters),
    rampBanded: rampBanded ?? this.rampBanded,
    contourMode: contourMode ?? this.contourMode,
    customLevels: customLevels ?? this.customLevels,
    wallAngleDeg: wallAngleDeg ?? this.wallAngleDeg,
  );

  String encode() => jsonEncode({
    if (rampMaxDepthMeters != null) 'rampMaxDepthMeters': rampMaxDepthMeters,
    'rampBanded': rampBanded,
    'contourMode': contourMode.name,
    'customLevels': [for (final l in customLevels) l.toJson()],
    'wallAngleDeg': wallAngleDeg,
  });

  /// Defensive decode: any missing or malformed field falls back to its
  /// default so a corrupt pref can never break the seascape.
  factory SeascapeAppearance.decode(String? raw) {
    if (raw == null || raw.isEmpty) return const SeascapeAppearance();
    Object? parsed;
    try {
      parsed = jsonDecode(raw);
    } on FormatException {
      return const SeascapeAppearance();
    }
    if (parsed is! Map<String, dynamic>) return const SeascapeAppearance();
    const defaults = SeascapeAppearance();
    final ramp = parsed['rampMaxDepthMeters'];
    final banded = parsed['rampBanded'];
    final mode = parsed['contourMode'];
    final levels = parsed['customLevels'];
    final wall = parsed['wallAngleDeg'];
    return SeascapeAppearance(
      rampMaxDepthMeters: (ramp is num && ramp.isFinite && ramp > 0)
          ? ramp.toDouble()
          : null,
      rampBanded: banded is bool ? banded : defaults.rampBanded,
      contourMode: mode == SeascapeContourMode.custom.name
          ? SeascapeContourMode.custom
          : SeascapeContourMode.auto,
      customLevels: levels is List
          ? [for (final e in levels) ?SeascapeContourLevel.fromJson(e)]
          : defaults.customLevels,
      wallAngleDeg: (wall is num && wall.isFinite)
          ? wall.toDouble().clamp(5.0, 90.0)
          : defaults.wallAngleDeg,
    );
  }

  @override
  List<Object?> get props => [
    rampMaxDepthMeters,
    rampBanded,
    contourMode,
    customLevels,
    wallAngleDeg,
  ];
}
