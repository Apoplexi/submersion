# GPS Track Mapping Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render, import, export, and edit recorded GPS surface tracks, which Submersion has stored since schema v101 but has never drawn.

**Architecture:** A pure-Dart geometry core (Douglas–Peucker simplification, time windowing, speed derivation, bucketed colorization runs) feeds four thin map surfaces through Riverpod providers backed by a level-of-detail cache in the local (unsynced) database. Import and export attach at the repository layer, never at the view. Trim is non-destructive metadata; split writes both children before tombstoning the parent.

**Tech Stack:** Flutter 3.x, Drift ORM, Riverpod 3, go_router, flutter_map 8.3, flutter_map_tile_caching, latlong2, the `xml` package, `compute()` isolates.

**Spec:** `docs/superpowers/specs/2026-08-07-gps-track-mapping-design.md`

## Global Constraints

Every task's requirements implicitly include this section.

- **Timestamps are wall-clock-as-UTC.** Track points are epoch **seconds**; track `startTime`/`endTime` are epoch **milliseconds**. Both are the recording device's local wall clock reinterpreted as UTC. Never call `toLocal()` when formatting. Reference implementation: `lib/features/gps_log/presentation/pages/gps_logger_page.dart:239-246`.
- **Units follow diver settings.** Anything displaying a unit goes through `UnitFormatter`, driven by `settingsProvider`. Never hard-code m/ft/kt.
- **No emojis** in code, comments, or documentation.
- **Immutability.** Never mutate a list or object in place; return new instances.
- **`dart format .`** must produce no changes before any commit.
- **`flutter analyze`** must be clean. Never pipe it to `tail` — that masks the exit code.
- **Commit message style:** imperative sentence case, no `feat:`/`fix:` prefix, no `Co-Authored-By` trailer, no Claude Code attribution. Match the existing log ("Add customizable home screen design spec").
- **l10n:** every user-visible string goes in `lib/l10n/arb/app_en.arb` and is translated to **all** supported locales (ar, de, es, fr, he, hu, it, nl, pt, zh).
- **Schema versions:** main DB target is **v144** — re-grep `origin/main` for `currentSchemaVersion` immediately before pushing, because this ladder has had parallel-branch collisions. Local cache DB target is **v9**.
- **Worktree:** this work runs in its own git worktree. After creating it, run `git submodule update --init --recursive` then `flutter pub get` before anything else.

## File Structure

**Created:**

| Path | Responsibility |
|---|---|
| `lib/features/gps_log/domain/track_geometry.dart` | Pure geometry: local projection, Douglas–Peucker, windowing, bounds, speed |
| `lib/features/gps_log/domain/track_colorization.dart` | `TrackColorMode`, `TrackRun`, bucketing into contiguous runs |
| `lib/features/gps_log/data/repositories/track_geometry_cache_repository.dart` | Read/write simplified geometry in the local cache DB |
| `lib/features/gps_log/presentation/providers/gps_track_map_providers.dart` | Hydration, simplification, dive-association providers |
| `lib/features/gps_log/presentation/widgets/gps_track_polyline_layer.dart` | Runs to `PolylineLayer` |
| `lib/features/gps_log/presentation/widgets/track_color_legend.dart` | Legend for the active colorization mode |
| `lib/features/gps_log/presentation/widgets/track_shape_painter.dart` | Tile-less shape fallback for thumbnails |
| `lib/features/gps_log/presentation/widgets/gps_track_thumbnail.dart` | 88x64 non-interactive mini-map per list row |
| `lib/features/gps_log/presentation/pages/gps_track_detail_page.dart` | `/gps-log/:id` |
| `lib/features/gps_log/presentation/pages/gps_track_map_page.dart` | `/gps-log/map` overview |
| `lib/features/gps_log/data/services/track_import/*.dart` | Orchestrator plus GPX, KML, CSV parsers |
| `lib/features/dive_import/data/services/fit/fit_track_extractor.dart` | Harvest the FIT position stream |
| `lib/core/services/export/gpx/gpx_export_service.dart` | GPX document builder plus share/save entry points |

**Modified:**

| Path | Change |
|---|---|
| `lib/core/database/database.dart` | `gps_tracks` +5 columns, `currentSchemaVersion` 142 to 144, migration step |
| `lib/core/database/local_cache_database.dart` | `gps_track_geometry_cache` table, v8 to v9, self-heal |
| `lib/core/utils/unit_formatter.dart` | `formatSpeed` |
| `lib/core/services/export/shared/file_export_utils.dart` | `saveTextToFile` |
| `lib/core/services/export/kml/kml_export_service.dart` | `<gx:Track>` output |
| `lib/core/services/sync/sync_data_serializer.dart` | Serialize the 5 new columns |
| `lib/core/router/app_router.dart` | `/gps-log/map` before `/gps-log/:id` |
| `lib/features/gps_log/data/repositories/gps_track_repository.dart` | `effectivePoints`, trim writes, ordered split |
| `lib/features/gps_log/presentation/pages/gps_logger_page.dart` | Thumbnails, row navigation, map-mode action |
| `lib/features/dive_log/presentation/widgets/dive_locations_map.dart` | Optional `trackRuns` / `trackBounds` |
| `lib/features/dive_log/presentation/widgets/surface_gps_section.dart` | Windowed track, full-track chip, track row |

---

## Phase 1: Schema and Core

No UI. Everything here is unit-testable without pumping a widget.

---

### Task 1: Local projection and Douglas–Peucker simplification

**Files:**
- Create: `lib/features/gps_log/domain/track_geometry.dart`
- Test: `test/features/gps_log/track_geometry_test.dart`

**Interfaces:**
- Consumes: `GpsTrackPoint` from `lib/features/gps_log/domain/entities/gps_track.dart`
- Produces:
  - `({double east, double north}) projectLocal(GpsTrackPoint origin, GpsTrackPoint p)`
  - `List<GpsTrackPoint> simplifyTrack(List<GpsTrackPoint> points, double toleranceMeters)`

Douglas–Peucker needs perpendicular point-to-segment distance, which is awkward on a sphere. Because a dive-day track spans kilometres, not continents, we project to a local flat east/north plane anchored at the track's first point and do the math in metres there. Error over that span is far below the 2 m tightest tolerance.

- [ ] **Step 1: Write the failing test**

Create `test/features/gps_log/track_geometry_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/gps_log/domain/entities/gps_track.dart';
import 'package:submersion/features/gps_log/domain/track_geometry.dart';

GpsTrackPoint p(double lat, double lon, {int t = 0}) =>
    GpsTrackPoint(timestamp: t, latitude: lat, longitude: lon);

void main() {
  group('projectLocal', () {
    test('projects a degree offset at the equator to known metres', () {
      // 0.001 deg longitude at the equator = 0.001 * 111320.0 = 111.32 m
      // 0.001 deg latitude anywhere       = 0.001 * 111194.93 = 111.19 m
      final origin = p(0.0, 0.0);
      final offset = projectLocal(origin, p(0.001, 0.001));
      expect(offset.east, closeTo(111.32, 0.01));
      expect(offset.north, closeTo(111.19, 0.01));
    });

    test('is zero for the origin itself', () {
      final origin = p(20.5, -87.3);
      final offset = projectLocal(origin, origin);
      expect(offset.east, 0.0);
      expect(offset.north, 0.0);
    });
  });

  group('simplifyTrack', () {
    test('drops a collinear midpoint', () {
      // All three on the equator: the midpoint lies exactly on the chord,
      // so its perpendicular distance is 0 and any tolerance removes it.
      final points = [p(0.0, 0.0), p(0.0, 0.001), p(0.0, 0.002)];
      final result = simplifyTrack(points, 1.0);
      expect(result.length, 2);
      expect(result.first.longitude, 0.0);
      expect(result.last.longitude, 0.002);
    });

    test('keeps a midpoint deviating more than the tolerance', () {
      // Chord runs along the equator from lon 0 to lon 0.002. The midpoint
      // sits 0.001 deg north of it = 111.19 m perpendicular deviation.
      final points = [p(0.0, 0.0), p(0.001, 0.001), p(0.0, 0.002)];
      final result = simplifyTrack(points, 50.0);
      expect(result.length, 3);
    });

    test('drops a midpoint deviating less than the tolerance', () {
      // Same 111.19 m deviation, but now under a 200 m tolerance.
      final points = [p(0.0, 0.0), p(0.001, 0.001), p(0.0, 0.002)];
      final result = simplifyTrack(points, 200.0);
      expect(result.length, 2);
    });

    test('always preserves first and last points', () {
      final points = List.generate(
        100,
        (i) => p(0.0, i * 0.00001, t: i),
      );
      final result = simplifyTrack(points, 1000.0);
      expect(result.length, 2);
      expect(result.first.timestamp, 0);
      expect(result.last.timestamp, 99);
    });

    test('returns the input unchanged for fewer than three points', () {
      expect(simplifyTrack(const [], 10.0), isEmpty);
      expect(simplifyTrack([p(1, 1)], 10.0).length, 1);
      expect(simplifyTrack([p(1, 1), p(2, 2)], 10.0).length, 2);
    });

    test('preserves the original timestamps of surviving points', () {
      final points = [
        p(0.0, 0.0, t: 100),
        p(0.001, 0.001, t: 200),
        p(0.0, 0.002, t: 300),
      ];
      final result = simplifyTrack(points, 50.0);
      expect(result.map((e) => e.timestamp).toList(), [100, 200, 300]);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/gps_log/track_geometry_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'track_geometry.dart'` / `projectLocal` isn't defined.

- [ ] **Step 3: Write the implementation**

Create `lib/features/gps_log/domain/track_geometry.dart`:

```dart
import 'dart:math' as math;

import 'package:submersion/core/utils/geo_math.dart';
import 'package:submersion/features/dive_sites/domain/entities/dive_site.dart';
import 'package:submersion/features/gps_log/domain/entities/gps_track.dart';

/// Metres per degree of latitude (constant everywhere on a sphere).
const double _metersPerDegreeLatitude = 111194.93;

/// Projects [p] into a local flat east/north plane in metres, anchored at
/// [origin].
///
/// A dive-day track spans kilometres, so the flat-earth error over that span
/// is far below the tightest simplification tolerance (2 m). Working in this
/// plane makes perpendicular point-to-segment distance trivial, which is what
/// Douglas-Peucker needs.
({double east, double north}) projectLocal(
  GpsTrackPoint origin,
  GpsTrackPoint p,
) {
  final metersPerLon = metersPerDegreeLongitude(origin.latitude);
  return (
    east: (p.longitude - origin.longitude) * metersPerLon,
    north: (p.latitude - origin.latitude) * _metersPerDegreeLatitude,
  );
}

/// Perpendicular distance in metres from [point] to the segment [a]-[b].
double _perpendicularDistance(
  ({double east, double north}) point,
  ({double east, double north}) a,
  ({double east, double north}) b,
) {
  final dx = b.east - a.east;
  final dy = b.north - a.north;
  final lengthSquared = dx * dx + dy * dy;

  // Degenerate segment: fall back to straight point-to-point distance.
  if (lengthSquared == 0) {
    final px = point.east - a.east;
    final py = point.north - a.north;
    return math.sqrt(px * px + py * py);
  }

  // Project onto the segment, clamped to its extent.
  var t = ((point.east - a.east) * dx + (point.north - a.north) * dy) /
      lengthSquared;
  t = t.clamp(0.0, 1.0);

  final projectedX = a.east + t * dx;
  final projectedY = a.north + t * dy;
  final ex = point.east - projectedX;
  final ey = point.north - projectedY;
  return math.sqrt(ex * ex + ey * ey);
}

/// Reduces [points] to the subset whose maximum perpendicular deviation from
/// the retained polyline stays within [toleranceMeters] (Douglas-Peucker).
///
/// First and last points are always retained. Surviving points keep their
/// original timestamps and accuracy - this decimates, it never interpolates.
List<GpsTrackPoint> simplifyTrack(
  List<GpsTrackPoint> points,
  double toleranceMeters,
) {
  if (points.length < 3) return List.unmodifiable(points);

  final origin = points.first;
  final projected = [for (final p in points) projectLocal(origin, p)];
  final keep = List<bool>.filled(points.length, false);
  keep[0] = true;
  keep[points.length - 1] = true;

  // Iterative rather than recursive: a 21k-point track would risk a deep
  // recursion on pathological input.
  final stack = <({int start, int end})>[
    (start: 0, end: points.length - 1),
  ];

  while (stack.isNotEmpty) {
    final segment = stack.removeLast();
    var maxDistance = 0.0;
    var maxIndex = -1;

    for (var i = segment.start + 1; i < segment.end; i++) {
      final distance = _perpendicularDistance(
        projected[i],
        projected[segment.start],
        projected[segment.end],
      );
      if (distance > maxDistance) {
        maxDistance = distance;
        maxIndex = i;
      }
    }

    if (maxIndex != -1 && maxDistance > toleranceMeters) {
      keep[maxIndex] = true;
      stack.add((start: segment.start, end: maxIndex));
      stack.add((start: maxIndex, end: segment.end));
    }
  }

  return List.unmodifiable([
    for (var i = 0; i < points.length; i++)
      if (keep[i]) points[i],
  ]);
}

/// Converts a track point to the [GeoPoint] the shared geo helpers take.
GeoPoint toGeoPoint(GpsTrackPoint p) => GeoPoint(p.latitude, p.longitude);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/gps_log/track_geometry_test.dart`
Expected: PASS, 8 tests.

- [ ] **Step 5: Format, analyze, commit**

```bash
dart format .
flutter analyze
git add lib/features/gps_log/domain/track_geometry.dart test/features/gps_log/track_geometry_test.dart
git commit -m "Add local projection and Douglas-Peucker track simplification"
```

---

### Task 2: Time windowing, bounds, and speed

**Files:**
- Modify: `lib/features/gps_log/domain/track_geometry.dart`
- Test: `test/features/gps_log/track_geometry_test.dart` (append groups)

**Interfaces:**
- Consumes: `projectLocal`, `toGeoPoint` from Task 1
- Produces:
  - `List<GpsTrackPoint> windowTrack(List<GpsTrackPoint> points, {required int fromEpochSeconds, required int toEpochSeconds})`
  - `({double minLat, double maxLat, double minLon, double maxLon})? trackBounds(List<GpsTrackPoint> points)`
  - `double speedMpsBetween(GpsTrackPoint a, GpsTrackPoint b)`
  - `double trackDistanceMeters(List<GpsTrackPoint> points)`

`trackBounds` normalizes longitude for antimeridian crossings. A Pacific track running from +179.9 to -179.9 is 0.2 degrees wide, but a naive min/max reports 359.8 degrees and fits the camera to the whole planet.

- [ ] **Step 1: Write the failing test**

Append to `test/features/gps_log/track_geometry_test.dart`, inside `main()`:

```dart
  group('windowTrack', () {
    final points = [
      p(0.0, 0.0, t: 100),
      p(0.0, 0.001, t: 200),
      p(0.0, 0.002, t: 300),
      p(0.0, 0.003, t: 400),
    ];

    test('includes points inside the window inclusively', () {
      final result =
          windowTrack(points, fromEpochSeconds: 200, toEpochSeconds: 300);
      expect(result.map((e) => e.timestamp).toList(), [200, 300]);
    });

    test('returns everything when the window spans the track', () {
      final result =
          windowTrack(points, fromEpochSeconds: 0, toEpochSeconds: 1000);
      expect(result.length, 4);
    });

    test('returns empty when the window misses the track entirely', () {
      final result =
          windowTrack(points, fromEpochSeconds: 500, toEpochSeconds: 600);
      expect(result, isEmpty);
    });

    test('handles an inverted window by returning empty', () {
      final result =
          windowTrack(points, fromEpochSeconds: 300, toEpochSeconds: 200);
      expect(result, isEmpty);
    });
  });

  group('trackBounds', () {
    test('returns null for an empty track', () {
      expect(trackBounds(const []), isNull);
    });

    test('computes a simple bounding box', () {
      final bounds = trackBounds([p(10.0, 20.0), p(12.0, 25.0), p(11.0, 22.0)]);
      expect(bounds!.minLat, 10.0);
      expect(bounds.maxLat, 12.0);
      expect(bounds.minLon, 20.0);
      expect(bounds.maxLon, 25.0);
    });

    test('collapses to a point for a single fix', () {
      final bounds = trackBounds([p(5.0, -3.0)]);
      expect(bounds!.minLat, 5.0);
      expect(bounds.maxLat, 5.0);
      expect(bounds.minLon, -3.0);
      expect(bounds.maxLon, -3.0);
    });

    test('normalizes an antimeridian crossing to a narrow span', () {
      // 179.9 E to 179.9 W is 0.2 deg wide, not 359.8. The unwrapped
      // maxLon exceeds 180, which is what the camera fit expects.
      final bounds = trackBounds([p(0.0, 179.9), p(0.0, -179.9)]);
      expect(bounds!.maxLon - bounds.minLon, closeTo(0.2, 1e-9));
      expect(bounds.minLon, closeTo(179.9, 1e-9));
      expect(bounds.maxLon, closeTo(180.1, 1e-9));
    });

    test('does not unwrap a track that merely spans a wide longitude range', () {
      // A genuine 60 deg span must stay 60 deg, not get folded.
      final bounds = trackBounds([p(0.0, -30.0), p(0.0, 30.0)]);
      expect(bounds!.minLon, -30.0);
      expect(bounds.maxLon, 30.0);
    });
  });

  group('speedMpsBetween', () {
    test('computes metres per second over the elapsed time', () {
      // 0.001 deg latitude = 111.19 m, over 10 s = 11.119 m/s
      final a = p(0.0, 0.0, t: 0);
      final b = p(0.001, 0.0, t: 10);
      expect(speedMpsBetween(a, b), closeTo(11.12, 0.02));
    });

    test('returns zero when no time elapsed', () {
      final a = p(0.0, 0.0, t: 50);
      final b = p(0.001, 0.0, t: 50);
      expect(speedMpsBetween(a, b), 0.0);
    });

    test('returns zero for a backwards timestamp rather than a negative speed', () {
      final a = p(0.0, 0.0, t: 100);
      final b = p(0.001, 0.0, t: 50);
      expect(speedMpsBetween(a, b), 0.0);
    });
  });

  group('trackDistanceMeters', () {
    test('sums consecutive leg distances', () {
      // Two legs of 0.001 deg latitude each = 2 * 111.19 m
      final points = [p(0.0, 0.0), p(0.001, 0.0), p(0.002, 0.0)];
      expect(trackDistanceMeters(points), closeTo(222.39, 0.1));
    });

    test('is zero for fewer than two points', () {
      expect(trackDistanceMeters(const []), 0.0);
      expect(trackDistanceMeters([p(1, 1)]), 0.0);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/gps_log/track_geometry_test.dart`
Expected: FAIL — `windowTrack` isn't defined.

- [ ] **Step 3: Write the implementation**

Append to `lib/features/gps_log/domain/track_geometry.dart`:

```dart
/// Points whose timestamp falls within [fromEpochSeconds]..[toEpochSeconds]
/// inclusive. Both bounds are wall-clock-as-UTC epoch SECONDS.
List<GpsTrackPoint> windowTrack(
  List<GpsTrackPoint> points, {
  required int fromEpochSeconds,
  required int toEpochSeconds,
}) {
  if (fromEpochSeconds > toEpochSeconds) return const [];
  return List.unmodifiable([
    for (final p in points)
      if (p.timestamp >= fromEpochSeconds && p.timestamp <= toEpochSeconds) p,
  ]);
}

/// Bounding box of [points], or null when empty.
///
/// Longitudes are unwrapped across the antimeridian: a track running from
/// 179.9 E to 179.9 W reports minLon 179.9 and maxLon 180.1 (a 0.2 deg span)
/// rather than the 359.8 deg span a naive min/max would produce, which would
/// fit the camera to the entire globe.
({double minLat, double maxLat, double minLon, double maxLon})? trackBounds(
  List<GpsTrackPoint> points,
) {
  if (points.isEmpty) return null;

  var minLat = points.first.latitude;
  var maxLat = points.first.latitude;
  for (final p in points) {
    if (p.latitude < minLat) minLat = p.latitude;
    if (p.latitude > maxLat) maxLat = p.latitude;
  }

  var minLon = points.first.longitude;
  var maxLon = points.first.longitude;
  for (final p in points) {
    if (p.longitude < minLon) minLon = p.longitude;
    if (p.longitude > maxLon) maxLon = p.longitude;
  }

  // A raw span wider than half the globe means the track almost certainly
  // wraps the antimeridian rather than genuinely circling the planet. Re-run
  // the extent with western longitudes shifted into a continuous frame.
  if (maxLon - minLon > 180.0) {
    var shiftedMin = double.infinity;
    var shiftedMax = double.negativeInfinity;
    for (final p in points) {
      final lon = p.longitude < 0 ? p.longitude + 360.0 : p.longitude;
      if (lon < shiftedMin) shiftedMin = lon;
      if (lon > shiftedMax) shiftedMax = lon;
    }
    minLon = shiftedMin;
    maxLon = shiftedMax;
  }

  return (minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon);
}

/// Ground speed in metres per second between two consecutive fixes.
///
/// Returns 0 for zero or negative elapsed time. GPS logs do occasionally
/// carry out-of-order or duplicated timestamps, and a negative speed would
/// poison bucketing and the max-speed statistic.
double speedMpsBetween(GpsTrackPoint a, GpsTrackPoint b) {
  final elapsed = b.timestamp - a.timestamp;
  if (elapsed <= 0) return 0.0;
  return distanceMeters(toGeoPoint(a), toGeoPoint(b)) / elapsed;
}

/// Total along-track distance in metres.
double trackDistanceMeters(List<GpsTrackPoint> points) {
  if (points.length < 2) return 0.0;
  var total = 0.0;
  for (var i = 1; i < points.length; i++) {
    total += distanceMeters(toGeoPoint(points[i - 1]), toGeoPoint(points[i]));
  }
  return total;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/gps_log/track_geometry_test.dart`
Expected: PASS, 20 tests total.

- [ ] **Step 5: Format, analyze, commit**

```bash
dart format .
flutter analyze
git add lib/features/gps_log/domain/track_geometry.dart test/features/gps_log/track_geometry_test.dart
git commit -m "Add track windowing, antimeridian-safe bounds, and speed math"
```

---

### Task 3: Colorization buckets and contiguous runs

**Files:**
- Create: `lib/features/gps_log/domain/track_colorization.dart`
- Test: `test/features/gps_log/track_colorization_test.dart`

**Interfaces:**
- Consumes: `speedMpsBetween` from Task 2
- Produces:
  - `enum TrackColorMode { uniform, speed, elapsed }`
  - `class TrackRun { final List<GpsTrackPoint> points; final int bucket; }`
  - `const int kTrackColorBuckets = 8;`
  - `List<TrackRun> bucketizeTrack(List<GpsTrackPoint> points, TrackColorMode mode, {int buckets = kTrackColorBuckets})`
  - `({double min, double max})? speedRange(List<GpsTrackPoint> points)`

Runs must **share a boundary point** with their neighbour, or the rendered polyline shows a one-segment gap at every bucket change.

- [ ] **Step 1: Write the failing test**

Create `test/features/gps_log/track_colorization_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/gps_log/domain/entities/gps_track.dart';
import 'package:submersion/features/gps_log/domain/track_colorization.dart';

GpsTrackPoint p(double lat, double lon, {int t = 0}) =>
    GpsTrackPoint(timestamp: t, latitude: lat, longitude: lon);

void main() {
  group('uniform mode', () {
    test('produces exactly one run covering every point', () {
      final points = [
        p(0.0, 0.0, t: 0),
        p(0.001, 0.0, t: 10),
        p(0.002, 0.0, t: 20),
      ];
      final runs = bucketizeTrack(points, TrackColorMode.uniform);
      expect(runs.length, 1);
      expect(runs.first.bucket, 0);
      expect(runs.first.points.length, 3);
    });
  });

  group('elapsed mode', () {
    test('assigns increasing buckets across the track', () {
      final points = List.generate(
        9,
        (i) => p(0.0, i * 0.001, t: i * 100),
      );
      final runs = bucketizeTrack(points, TrackColorMode.elapsed, buckets: 3);
      expect(runs.length, greaterThan(1));
      expect(runs.first.bucket, lessThan(runs.last.bucket));
    });

    test('runs share a boundary point so the line has no gaps', () {
      final points = List.generate(
        9,
        (i) => p(0.0, i * 0.001, t: i * 100),
      );
      final runs = bucketizeTrack(points, TrackColorMode.elapsed, buckets: 3);
      for (var i = 1; i < runs.length; i++) {
        expect(
          runs[i].points.first.timestamp,
          runs[i - 1].points.last.timestamp,
          reason: 'run $i must start where run ${i - 1} ended',
        );
      }
    });
  });

  group('speed mode', () {
    test('separates a slow leg from a fast leg into different buckets', () {
      // Leg 1: 0.0001 deg lat (11.1 m) over 10 s  = 1.11 m/s
      // Leg 2: 0.0100 deg lat (1112 m) over 10 s  = 111 m/s
      final points = [
        p(0.0, 0.0, t: 0),
        p(0.0001, 0.0, t: 10),
        p(0.0101, 0.0, t: 20),
      ];
      final runs = bucketizeTrack(points, TrackColorMode.speed, buckets: 4);
      expect(runs.length, 2);
      expect(runs.first.bucket, isNot(equals(runs.last.bucket)));
    });

    test('merges consecutive legs at the same speed into one run', () {
      final points = [
        p(0.0, 0.0, t: 0),
        p(0.001, 0.0, t: 10),
        p(0.002, 0.0, t: 20),
        p(0.003, 0.0, t: 30),
      ];
      final runs = bucketizeTrack(points, TrackColorMode.speed, buckets: 4);
      expect(runs.length, 1);
      expect(runs.first.points.length, 4);
    });
  });

  group('degenerate input', () {
    test('returns empty for an empty track', () {
      expect(bucketizeTrack(const [], TrackColorMode.speed), isEmpty);
    });

    test('returns empty for a single point (nothing to draw)', () {
      expect(bucketizeTrack([p(1, 1)], TrackColorMode.speed), isEmpty);
    });

    test('handles a two-point track as one run', () {
      final runs = bucketizeTrack(
        [p(0.0, 0.0, t: 0), p(0.001, 0.0, t: 10)],
        TrackColorMode.speed,
      );
      expect(runs.length, 1);
      expect(runs.first.points.length, 2);
    });
  });

  group('speedRange', () {
    test('returns null when there are no legs', () {
      expect(speedRange(const []), isNull);
      expect(speedRange([p(1, 1)]), isNull);
    });

    test('reports min and max leg speed', () {
      final points = [
        p(0.0, 0.0, t: 0),
        p(0.0001, 0.0, t: 10),
        p(0.0101, 0.0, t: 20),
      ];
      final range = speedRange(points);
      expect(range!.min, closeTo(1.11, 0.05));
      expect(range.max, closeTo(111.2, 1.0));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/gps_log/track_colorization_test.dart`
Expected: FAIL — `bucketizeTrack` isn't defined.

- [ ] **Step 3: Write the implementation**

Create `lib/features/gps_log/domain/track_colorization.dart`:

```dart
import 'package:submersion/features/gps_log/domain/entities/gps_track.dart';
import 'package:submersion/features/gps_log/domain/track_geometry.dart';

/// How a track polyline is colorized.
enum TrackColorMode { uniform, speed, elapsed }

/// Default number of quantization buckets.
///
/// flutter_map's Polyline.gradientColors cannot express a colour ramp along
/// arc length (it paints a straight screen-space gradient between the first
/// and last point), so colorization is done by quantizing into buckets and
/// emitting one Polyline per contiguous same-bucket run. Discrete bands also
/// map one-to-one onto legend rows.
const int kTrackColorBuckets = 8;

/// A contiguous span of track points sharing one quantization bucket.
class TrackRun {
  final List<GpsTrackPoint> points;
  final int bucket;

  const TrackRun({required this.points, required this.bucket});
}

/// Minimum and maximum leg speed in metres per second, or null when the
/// track has fewer than two points.
({double min, double max})? speedRange(List<GpsTrackPoint> points) {
  if (points.length < 2) return null;
  var min = double.infinity;
  var max = double.negativeInfinity;
  for (var i = 1; i < points.length; i++) {
    final speed = speedMpsBetween(points[i - 1], points[i]);
    if (speed < min) min = speed;
    if (speed > max) max = speed;
  }
  return (min: min, max: max);
}

/// Bucket index for [value] within [min]..[max], clamped to 0..buckets-1.
int _bucketFor(double value, double min, double max, int buckets) {
  if (max <= min) return 0;
  final normalized = (value - min) / (max - min);
  return (normalized * buckets).floor().clamp(0, buckets - 1);
}

/// Splits [points] into contiguous runs sharing a quantization bucket.
///
/// Consecutive runs SHARE their boundary point: run N ends on the same point
/// run N+1 begins on. Without that overlap the rendered polyline shows a
/// one-segment gap at every bucket change.
List<TrackRun> bucketizeTrack(
  List<GpsTrackPoint> points,
  TrackColorMode mode, {
  int buckets = kTrackColorBuckets,
}) {
  // A single point has no segment to draw.
  if (points.length < 2) return const [];

  if (mode == TrackColorMode.uniform) {
    return [TrackRun(points: List.unmodifiable(points), bucket: 0)];
  }

  // One bucket per LEG (there are points.length - 1 legs).
  final legBuckets = <int>[];
  if (mode == TrackColorMode.speed) {
    final range = speedRange(points);
    final min = range?.min ?? 0.0;
    final max = range?.max ?? 0.0;
    for (var i = 1; i < points.length; i++) {
      legBuckets.add(
        _bucketFor(speedMpsBetween(points[i - 1], points[i]), min, max, buckets),
      );
    }
  } else {
    final start = points.first.timestamp;
    final end = points.last.timestamp;
    for (var i = 1; i < points.length; i++) {
      legBuckets.add(
        _bucketFor(
          points[i].timestamp.toDouble(),
          start.toDouble(),
          end.toDouble(),
          buckets,
        ),
      );
    }
  }

  final runs = <TrackRun>[];
  var runStart = 0;
  for (var leg = 1; leg <= legBuckets.length; leg++) {
    final atEnd = leg == legBuckets.length;
    final bucketChanged = !atEnd && legBuckets[leg] != legBuckets[leg - 1];
    if (atEnd || bucketChanged) {
      runs.add(
        TrackRun(
          // leg L spans points[L] .. points[L+1], so a run covering legs
          // runStart..leg-1 spans points runStart .. leg inclusive.
          points: List.unmodifiable(points.sublist(runStart, leg + 1)),
          bucket: legBuckets[runStart],
        ),
      );
      runStart = leg;
    }
  }

  return List.unmodifiable(runs);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/gps_log/track_colorization_test.dart`
Expected: PASS, 10 tests.

- [ ] **Step 5: Format, analyze, commit**

```bash
dart format .
flutter analyze
git add lib/features/gps_log/domain/track_colorization.dart test/features/gps_log/track_colorization_test.dart
git commit -m "Add track colorization buckets and contiguous runs"
```

---

### Task 4: Speed formatting in UnitFormatter

**Files:**
- Modify: `lib/core/utils/unit_formatter.dart`
- Modify: `lib/l10n/arb/app_en.arb` and all locale ARBs
- Test: `test/core/utils/unit_formatter_speed_test.dart`

**Interfaces:**
- Produces: `String UnitFormatter.formatSpeed(double metersPerSecond, {int decimals = 1})`

Speed derives from the existing distance-unit preference: metric shows km/h, imperial shows mph. Knots are offered as an explicit third option because divers on boats routinely think in knots regardless of their depth units.

- [ ] **Step 1: Inspect the existing formatter to match its conventions**

Run: `sed -n '1,80p' lib/core/utils/unit_formatter.dart`

Note how `formatDistance` reads the unit off settings and which l10n keys it uses. `formatSpeed` must follow the identical shape.

- [ ] **Step 2: Write the failing test**

Create `test/core/utils/unit_formatter_speed_test.dart`. Build the `Settings` instance the same way the existing `test/core/utils/unit_formatter_test.dart` does — open that file first and copy its construction helper rather than inventing one:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/utils/unit_formatter.dart';

// Reuse the Settings builder from the sibling unit_formatter_test.dart.
// If that file defines a local helper, lift it into a shared test helper
// under test/helpers/ and import it from both.
import '../../helpers/settings_test_helper.dart';

void main() {
  group('formatSpeed', () {
    test('metric renders km/h', () {
      final units = UnitFormatter(metricSettings());
      // 10 m/s = 36 km/h
      expect(units.formatSpeed(10.0), '36.0 km/h');
    });

    test('imperial renders mph', () {
      final units = UnitFormatter(imperialSettings());
      // 10 m/s = 22.369 mph
      expect(units.formatSpeed(10.0), '22.4 mph');
    });

    test('zero speed renders without a sign or NaN', () {
      final units = UnitFormatter(metricSettings());
      expect(units.formatSpeed(0.0), '0.0 km/h');
    });

    test('honours the decimals argument', () {
      final units = UnitFormatter(metricSettings());
      expect(units.formatSpeed(10.0, decimals: 0), '36 km/h');
    });
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/core/utils/unit_formatter_speed_test.dart`
Expected: FAIL — `formatSpeed` isn't defined on `UnitFormatter`.

- [ ] **Step 4: Implement `formatSpeed`**

Add to `lib/core/utils/unit_formatter.dart`, immediately after `formatDistance` so related formatters stay adjacent:

```dart
  /// Formats a speed in metres per second using the diver's distance-unit
  /// preference: metric renders km/h, imperial renders mph.
  String formatSpeed(double metersPerSecond, {int decimals = 1}) {
    final isMetric = _settings.depthUnit == DepthUnit.meters;
    final value = isMetric
        ? metersPerSecond * 3.6
        : metersPerSecond * 2.236936;
    final suffix = isMetric ? 'km/h' : 'mph';
    return '${value.toStringAsFixed(decimals)} $suffix';
  }
```

Adjust the settings field name and `DepthUnit` reference to match what `formatDistance` actually reads — copy its exact expression rather than assuming.

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/core/utils/unit_formatter_speed_test.dart`
Expected: PASS, 4 tests.

- [ ] **Step 6: Verify no existing formatter tests regressed**

Run: `flutter test test/core/utils/`
Expected: PASS, all tests.

- [ ] **Step 7: Format, analyze, commit**

```bash
dart format .
flutter analyze
git add lib/core/utils/unit_formatter.dart test/core/utils/unit_formatter_speed_test.dart
git commit -m "Add speed formatting to UnitFormatter"
```

---

### Task 5: Main database migration to v144

**Files:**
- Modify: `lib/core/database/database.dart`
- Modify: `lib/core/services/sync/sync_data_serializer.dart`
- Test: `test/core/database/migration_v144_gps_track_columns_test.dart`

**Interfaces:**
- Produces: `gps_tracks` columns `source` (TEXT, default `'phone'`), `sourceRef` (TEXT?), `name` (TEXT?), `trimStartTime` (INT?), `trimEndTime` (INT?)

All five columns land in one migration even though `source` is not read until Phase 6 and the trim bounds are not written until Phase 7. One migration on a collision-prone ladder is materially safer than three.

- [ ] **Step 1: Confirm the version is still free**

```bash
git fetch origin
git show origin/main:lib/core/database/database.dart | grep -n "currentSchemaVersion ="
```

Expected: `142`. If it is not 142, stop and pick the next free version, updating every reference in this task.

- [ ] **Step 2: Read an existing migration step to copy its shape**

Run: `grep -n "from < 14[0-2]" lib/core/database/database.dart`

Open the most recent step and match its structure exactly — the guard style, `m.addColumn` usage, and comment convention.

- [ ] **Step 3: Write the failing migration test**

Create `test/core/database/migration_v144_gps_track_columns_test.dart`. Note the setup convention: this repo has **no `AppDatabase.forTesting` constructor** — main-database tests go through `setUpTestDatabase()` from `test/helpers/test_database.dart`, which installs an in-memory `AppDatabase` into `DatabaseService.instance`.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/database/database.dart';

import '../../helpers/test_database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = await setUpTestDatabase();
  });

  tearDown(tearDownTestDatabase);

  test('gps_tracks carries the v144 columns', () async {
    final columns = await db
        .customSelect('PRAGMA table_info(gps_tracks)')
        .get();
    final names = columns.map((r) => r.data['name'] as String).toSet();

    expect(names, contains('source'));
    expect(names, contains('source_ref'));
    expect(names, contains('name'));
    expect(names, contains('trim_start_time'));
    expect(names, contains('trim_end_time'));
  });

  test('source defaults to phone for a row inserted without it', () async {
    await db.into(db.gpsTracks).insert(
          GpsTracksCompanion.insert(
            id: 'track-1',
            startTime: 1700000000000,
            createdAt: 1700000000000,
            updatedAt: 1700000000000,
          ),
        );
    final row = await (db.select(db.gpsTracks)
          ..where((t) => t.id.equals('track-1')))
        .getSingle();
    expect(row.source, 'phone');
    expect(row.trimStartTime, isNull);
    expect(row.trimEndTime, isNull);
  });

  test('schema version is 144', () {
    expect(db.schemaVersion, 144);
  });
}
```

- [ ] **Step 4: Run test to verify it fails**

Run: `flutter test test/core/database/migration_v144_gps_track_columns_test.dart`
Expected: FAIL — no such column `source`.

- [ ] **Step 5: Add the columns to the table definition**

In `lib/core/database/database.dart`, inside `class GpsTracks extends Table`, after `pointCount` (around line 380):

```dart
  /// Provenance: 'phone' | 'gpx' | 'fit' | 'kml' | 'csv'. Rendering code
  /// treats this as opaque - no view logic branches on it.
  TextColumn get source => text().withDefault(const Constant('phone'))();

  /// Originating filename or device, for imported tracks.
  TextColumn get sourceRef => text().nullable()();

  /// User-editable label.
  TextColumn get name => text().nullable()();

  /// Non-destructive trim bounds, wall-clock-as-UTC epoch MILLISECONDS.
  /// The points blob is never rewritten by a trim, so trimming is fully
  /// reversible and cannot lose a fix.
  IntColumn get trimStartTime => integer().nullable()();
  IntColumn get trimEndTime => integer().nullable()();
```

- [ ] **Step 6: Bump the version and add the migration step**

Change `currentSchemaVersion` from `142` to `144`, then add to the migration chain, matching the surrounding style:

```dart
      if (from < 144) {
        await m.addColumn(gpsTracks, gpsTracks.source);
        await m.addColumn(gpsTracks, gpsTracks.sourceRef);
        await m.addColumn(gpsTracks, gpsTracks.name);
        await m.addColumn(gpsTracks, gpsTracks.trimStartTime);
        await m.addColumn(gpsTracks, gpsTracks.trimEndTime);
      }
```

- [ ] **Step 7: Regenerate Drift code**

```bash
dart run build_runner build --delete-conflicting-outputs
```

- [ ] **Step 8: Run test to verify it passes**

Run: `flutter test test/core/database/migration_v144_gps_track_columns_test.dart`
Expected: PASS, 3 tests.

- [ ] **Step 9: Thread the columns through sync serialization**

Open `lib/core/services/sync/sync_data_serializer.dart`, find the `gps_tracks` entity handling, and add all five columns to both the serialize and deserialize paths. Defaulted columns need hydration on read so a peer on an older schema cannot push a null back over `source`: when the incoming payload omits `source`, write `'phone'` rather than `Value.absent()`.

- [ ] **Step 10: Extend the sync round-trip test**

Add to `test/core/services/sync/sync_gps_tracks_test.dart`. That file already has a `seedTrack()` helper and a `SyncDataSerializer serializer` / `GpsTrackRepository repo` pair in scope:

```dart
  test('v144 columns survive a serialize round trip', () async {
    final id = await seedTrack();
    final db = DatabaseService.instance.database;
    await (db.update(db.gpsTracks)..where((t) => t.id.equals(id))).write(
      const GpsTracksCompanion(
        source: Value('gpx'),
        sourceRef: Value('cozumel-day-3.gpx'),
        name: Value('Palancar morning'),
        trimStartTime: Value(1700000600000),
        trimEndTime: Value(1700003000000),
      ),
    );

    final fetched = await serializer.fetchRecord('gpsTracks', id);
    expect(fetched!['source'], 'gpx');
    expect(fetched['sourceRef'], 'cozumel-day-3.gpx');
    expect(fetched['name'], 'Palancar morning');
    expect(fetched['trimStartTime'], 1700000600000);
    expect(fetched['trimEndTime'], 1700003000000);
  });

  test('an incoming payload without source hydrates the phone default',
      () async {
    // A peer on a pre-v144 schema omits the column entirely. It must land as
    // 'phone', never as null, or effectivePoints and the import dedupe rule
    // both see a source they cannot match.
    await serializer.upsertRecord('gpsTracks', {
      'id': 'peer-track',
      'startTime': 1700000000000,
      'endTime': 1700003600000,
      'tzOffsetMinutes': -300,
      'pointCount': 0,
      'createdAt': 1700000000000,
      'updatedAt': 1700000000000,
    });

    final db = DatabaseService.instance.database;
    final row = await (db.select(db.gpsTracks)
          ..where((t) => t.id.equals('peer-track')))
        .getSingle();
    expect(row.source, 'phone');
  });
```

Add `import 'package:drift/drift.dart';` and `import 'package:submersion/core/services/database_service.dart';` to the file's imports.

- [ ] **Step 11: Run the sync tests**

Run: `flutter test test/core/services/sync/sync_gps_tracks_test.dart`
Expected: PASS.

- [ ] **Step 12: Format, analyze, commit**

```bash
dart format .
flutter analyze
git add lib/core/database/database.dart lib/core/database/database.g.dart lib/core/services/sync/sync_data_serializer.dart test/core/database/migration_v144_gps_track_columns_test.dart test/core/services/sync/sync_gps_tracks_test.dart
git commit -m "Add GPS track source, name, and trim-bound columns at schema v144"
```

---

### Task 6: effectivePoints accessor on the repository

**Files:**
- Modify: `lib/features/gps_log/data/repositories/gps_track_repository.dart`
- Modify: `lib/features/gps_log/domain/entities/gps_track.dart`
- Test: `test/features/gps_log/gps_track_effective_points_test.dart`

**Interfaces:**
- Consumes: `windowTrack` from Task 2, trim columns from Task 5
- Produces:
  - `GpsTrack` gains `final String source; final String? sourceRef; final String? name; final int? trimStartTime; final int? trimEndTime;` plus `copyWith` coverage
  - `List<GpsTrackPoint> GpsTrack.effectivePoints`

This lands in Phase 1 even though nothing writes trim bounds until Phase 7. Every consumer reads through it from the start, so Phase 7 changes one accessor instead of auditing every call site.

- [ ] **Step 1: Write the failing test**

Create `test/features/gps_log/gps_track_effective_points_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/gps_log/domain/entities/gps_track.dart';

GpsTrackPoint p(int t) =>
    GpsTrackPoint(timestamp: t, latitude: 0.0, longitude: t * 0.001);

GpsTrack trackWith({int? trimStart, int? trimEnd}) => GpsTrack(
      id: 'track-1',
      // Points are epoch SECONDS; trim bounds are epoch MILLISECONDS.
      startTime: 100000,
      endTime: 400000,
      points: [p(100), p(200), p(300), p(400)],
      trimStartTime: trimStart,
      trimEndTime: trimEnd,
    );

void main() {
  group('effectivePoints', () {
    test('returns every point when no trim is set', () {
      expect(trackWith().effectivePoints.length, 4);
    });

    test('drops points before the trim start', () {
      final track = trackWith(trimStart: 200000);
      expect(track.effectivePoints.map((e) => e.timestamp).toList(),
          [200, 300, 400]);
    });

    test('drops points after the trim end', () {
      final track = trackWith(trimEnd: 300000);
      expect(track.effectivePoints.map((e) => e.timestamp).toList(),
          [100, 200, 300]);
    });

    test('applies both bounds together', () {
      final track = trackWith(trimStart: 200000, trimEnd: 300000);
      expect(track.effectivePoints.map((e) => e.timestamp).toList(),
          [200, 300]);
    });

    test('never mutates the underlying points list', () {
      final track = trackWith(trimStart: 200000);
      track.effectivePoints;
      expect(track.points.length, 4);
    });

    test('returns empty when the trim window excludes everything', () {
      final track = trackWith(trimStart: 500000);
      expect(track.effectivePoints, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/gps_log/gps_track_effective_points_test.dart`
Expected: FAIL — `GpsTrack` has no named parameter `trimStartTime`.

- [ ] **Step 3: Extend the entity**

In `lib/features/gps_log/domain/entities/gps_track.dart`, add the five fields to `GpsTrack`, its constructor (with `this.source = 'phone'` and the rest nullable), and `copyWith`. Then add:

```dart
  /// The points this track actually represents, honouring non-destructive
  /// trim bounds.
  ///
  /// Every consumer - rendering, statistics, export, dive matching - reads
  /// through this rather than [points], so trimming cannot be silently
  /// ignored by one call site. Trim bounds are epoch MILLISECONDS while
  /// point timestamps are epoch SECONDS, hence the division.
  List<GpsTrackPoint> get effectivePoints {
    final start = trimStartTime;
    final end = trimEndTime;
    if (start == null && end == null) return points;
    return List.unmodifiable([
      for (final p in points)
        if ((start == null || p.timestamp >= start ~/ 1000) &&
            (end == null || p.timestamp <= end ~/ 1000))
          p,
    ]);
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/gps_log/gps_track_effective_points_test.dart`
Expected: PASS, 6 tests.

- [ ] **Step 5: Map the new columns in the repository**

In `gps_track_repository.dart`, update `_toDomain` to populate `source`, `sourceRef`, `name`, `trimStartTime`, and `trimEndTime` from the Drift row.

- [ ] **Step 6: Run the existing repository tests**

Run: `flutter test test/features/gps_log/`
Expected: PASS, no regressions.

- [ ] **Step 7: Format, analyze, commit**

```bash
dart format .
flutter analyze
git add lib/features/gps_log/domain/entities/gps_track.dart lib/features/gps_log/data/repositories/gps_track_repository.dart test/features/gps_log/gps_track_effective_points_test.dart
git commit -m "Add effectivePoints accessor honouring track trim bounds"
```

---

### Task 7: Geometry cache table in the local database

**Files:**
- Modify: `lib/core/database/local_cache_database.dart`
- Test: `test/core/database/local_cache_gps_geometry_test.dart`

**Interfaces:**
- Produces: `gps_track_geometry_cache` table `(trackId TEXT, lodLevel TEXT, points BLOB?, status TEXT, createdAt INT)`, primary key `(trackId, lodLevel)`; local cache `schemaVersion` 8 to 9

This goes in the local cache DB, not the synced one: simplified geometry is fully re-derivable from the stored blob, so the main DB would charge a schema bump, HLC timestamps, tombstones, merge rules, and backup weight for nothing.

- [ ] **Step 1: Read the existing pattern**

Run: `sed -n '85,200p' lib/core/database/local_cache_database.dart`

`ReefDataCache` is the closest model — copy its table shape, its status column convention, and its `beforeOpen` self-heal.

- [ ] **Step 2: Write the failing test**

Create `test/core/database/local_cache_gps_geometry_test.dart`:

Follow `test/core/database/local_cache_migration_v7_bathymetry_test.dart`: the local cache database is constructed **directly** with `LocalCacheDatabase(NativeDatabase.memory())` and torn down with `addTearDown(db.close)`. There is no `forTesting` constructor.

```dart
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/database/local_cache_database.dart';

void main() {
  late LocalCacheDatabase db;

  setUp(() {
    db = LocalCacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
  });

  test('schema version is 9', () {
    expect(db.schemaVersion, 9);
  });

  test('stores and reads back simplified geometry', () async {
    await db.into(db.gpsTrackGeometryCache).insert(
          GpsTrackGeometryCacheCompanion.insert(
            trackId: 'track-1',
            lodLevel: 'thumbnail',
            status: 'ok',
            createdAt: 1700000000,
            points: Value(Uint8List.fromList([1, 2, 3])),
          ),
        );
    final row = await (db.select(db.gpsTrackGeometryCache)
          ..where((t) => t.trackId.equals('track-1')))
        .getSingle();
    expect(row.status, 'ok');
    expect(row.points, [1, 2, 3]);
  });

  test('caches a definitive empty result without a blob', () async {
    await db.into(db.gpsTrackGeometryCache).insert(
          GpsTrackGeometryCacheCompanion.insert(
            trackId: 'track-2',
            lodLevel: 'detail',
            status: 'empty',
            createdAt: 1700000000,
          ),
        );
    final row = await (db.select(db.gpsTrackGeometryCache)
          ..where((t) => t.trackId.equals('track-2')))
        .getSingle();
    expect(row.status, 'empty');
    expect(row.points, isNull);
  });

  test('keys separate LOD levels for the same track independently', () async {
    for (final lod in ['thumbnail', 'overview', 'detail']) {
      await db.into(db.gpsTrackGeometryCache).insert(
            GpsTrackGeometryCacheCompanion.insert(
              trackId: 'track-3',
              lodLevel: lod,
              status: 'ok',
              createdAt: 1700000000,
            ),
          );
    }
    final rows = await (db.select(db.gpsTrackGeometryCache)
          ..where((t) => t.trackId.equals('track-3')))
        .get();
    expect(rows.length, 3);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/core/database/local_cache_gps_geometry_test.dart`
Expected: FAIL — `gpsTrackGeometryCache` isn't defined.

- [ ] **Step 4: Add the table**

In `lib/core/database/local_cache_database.dart`, after `ReefDataCache`:

```dart
/// Simplified track geometry, cached per level of detail.
///
/// NOT synced and never backed up: every device can re-derive this from the
/// gps_tracks points blob in milliseconds, so paying the main database's
/// schema-bump, HLC, tombstone, and backup costs would buy nothing.
class GpsTrackGeometryCache extends Table {
  TextColumn get trackId => text()();

  /// 'thumbnail' (50 m tolerance) | 'overview' (10 m) | 'detail' (2 m)
  TextColumn get lodLevel => text()();

  /// Gzipped JSON in the same format as gps_tracks.points. Null when
  /// [status] is not 'ok'.
  BlobColumn get points => blob().nullable()();

  /// 'ok' | 'empty' | 'unavailable'. An explicit negative is cached so a
  /// genuinely empty track is not re-derived on every scroll.
  TextColumn get status => text()();

  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {trackId, lodLevel};
}
```

Register it in the `@DriftDatabase(tables: [...])` list, bump `schemaVersion` from 8 to 9, add the migration step, and add the `beforeOpen` self-heal alongside the bathymetry and reef ones:

```dart
        CREATE TABLE IF NOT EXISTS gps_track_geometry_cache (
          track_id TEXT NOT NULL,
          lod_level TEXT NOT NULL,
          points BLOB,
          status TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          PRIMARY KEY (track_id, lod_level)
        )
```

- [ ] **Step 5: Regenerate Drift code**

```bash
dart run build_runner build --delete-conflicting-outputs
```

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/core/database/local_cache_gps_geometry_test.dart`
Expected: PASS, 4 tests.

- [ ] **Step 7: Format, analyze, commit**

```bash
dart format .
flutter analyze
git add lib/core/database/local_cache_database.dart lib/core/database/local_cache_database.g.dart test/core/database/local_cache_gps_geometry_test.dart
git commit -m "Add GPS track geometry cache table to the local database"
```

---

### Task 8: Geometry cache repository and map providers

**Files:**
- Create: `lib/features/gps_log/data/repositories/track_geometry_cache_repository.dart`
- Create: `lib/features/gps_log/presentation/providers/gps_track_map_providers.dart`
- Test: `test/features/gps_log/track_geometry_cache_repository_test.dart`
- Test: `test/features/gps_log/gps_track_map_providers_test.dart`

**Interfaces:**
- Consumes: `simplifyTrack` (Task 1), `effectivePoints` (Task 6), the cache table (Task 7), `encodeTrackPoints`/`decodeTrackPoints` from `track_point_codec.dart`
- Produces:
  - `enum TrackLod { thumbnail, overview, detail }` with `double get toleranceMeters`
  - `TrackGeometryCacheRepository.read(String trackId, TrackLod lod)` returning `List<GpsTrackPoint>?`
  - `TrackGeometryCacheRepository.write(String trackId, TrackLod lod, List<GpsTrackPoint> points)`
  - `TrackGeometryCacheRepository.invalidate(String trackId)`
  - `gpsTrackDetailProvider(String trackId)` → `FutureProvider.family<GpsTrack?, String>`
  - `gpsTrackGeometryProvider((String trackId, TrackLod lod))` → `FutureProvider.family<List<GpsTrackPoint>, (String, TrackLod)>`

`divesOnTrackProvider` and `trackForDiveProvider` are added in Task 12, with the dive-marker feature that first consumes them.

Simplification runs inside `compute()`. Follow the existing isolate pattern in `lib/core/tide/tide_calculator.dart` — top-level function, single serializable argument.

- [ ] **Step 1: Write the failing repository test**

Create `test/features/gps_log/track_geometry_cache_repository_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/database/local_cache_database.dart';
import 'package:submersion/core/services/local_cache_database_service.dart';
import 'package:submersion/features/gps_log/data/repositories/track_geometry_cache_repository.dart';
import 'package:submersion/features/gps_log/domain/entities/gps_track.dart';

GpsTrackPoint p(int t) =>
    GpsTrackPoint(timestamp: t, latitude: t * 0.001, longitude: 0.0);

void main() {
  late LocalCacheDatabase db;
  late TrackGeometryCacheRepository repo;

  setUp(() {
    db = LocalCacheDatabase(NativeDatabase.memory());
    LocalCacheDatabaseService.instance.setTestDatabase(db);
    repo = TrackGeometryCacheRepository();
  });

  tearDown(() async {
    await db.close();
    LocalCacheDatabaseService.instance.resetForTesting();
  });

  test('returns null for an uncached track', () async {
    expect(await repo.read('missing', TrackLod.thumbnail), isNull);
  });

  test('round-trips written geometry', () async {
    final points = [p(1), p(2), p(3)];
    await repo.write('track-1', TrackLod.detail, points);
    final read = await repo.read('track-1', TrackLod.detail);
    expect(read, isNotNull);
    expect(read!.length, 3);
    expect(read.first.timestamp, 1);
  });

  test('keeps LOD levels independent', () async {
    await repo.write('track-1', TrackLod.thumbnail, [p(1), p(2)]);
    await repo.write('track-1', TrackLod.detail, [p(1), p(2), p(3)]);
    expect((await repo.read('track-1', TrackLod.thumbnail))!.length, 2);
    expect((await repo.read('track-1', TrackLod.detail))!.length, 3);
  });

  test('caches an empty result as a definitive answer, not a miss', () async {
    await repo.write('track-empty', TrackLod.overview, const []);
    final read = await repo.read('track-empty', TrackLod.overview);
    expect(read, isNotNull);
    expect(read, isEmpty);
  });

  test('invalidate clears every LOD for a track', () async {
    await repo.write('track-1', TrackLod.thumbnail, [p(1), p(2)]);
    await repo.write('track-1', TrackLod.detail, [p(1), p(2), p(3)]);
    await repo.invalidate('track-1');
    expect(await repo.read('track-1', TrackLod.thumbnail), isNull);
    expect(await repo.read('track-1', TrackLod.detail), isNull);
  });

  test('invalidate leaves other tracks untouched', () async {
    await repo.write('track-1', TrackLod.detail, [p(1)]);
    await repo.write('track-2', TrackLod.detail, [p(1)]);
    await repo.invalidate('track-1');
    expect(await repo.read('track-2', TrackLod.detail), isNotNull);
  });

  test('rewriting the same key replaces rather than duplicates', () async {
    await repo.write('track-1', TrackLod.detail, [p(1), p(2)]);
    await repo.write('track-1', TrackLod.detail, [p(1)]);
    expect((await repo.read('track-1', TrackLod.detail))!.length, 1);
  });

  group('TrackLod tolerances', () {
    test('match the spec', () {
      expect(TrackLod.thumbnail.toleranceMeters, 50.0);
      expect(TrackLod.overview.toleranceMeters, 10.0);
      expect(TrackLod.detail.toleranceMeters, 2.0);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/gps_log/track_geometry_cache_repository_test.dart`
Expected: FAIL — `TrackGeometryCacheRepository` isn't defined.

- [ ] **Step 3: Implement the repository**

Create `lib/features/gps_log/data/repositories/track_geometry_cache_repository.dart`:

```dart
import 'package:drift/drift.dart';

import 'package:submersion/core/database/local_cache_database.dart';
import 'package:submersion/core/services/local_cache_database_service.dart';
import 'package:submersion/features/gps_log/domain/entities/gps_track.dart';
import 'package:submersion/features/gps_log/domain/track_point_codec.dart';

/// Level of detail for simplified track geometry.
enum TrackLod {
  /// Row thumbnails and unselected tracks on the overview map.
  thumbnail,

  /// Selected track on the overview map, detail page zoomed out.
  overview,

  /// Detail page at zoom >= 14.
  detail;

  /// Douglas-Peucker tolerance in metres. Expressed in metres rather than
  /// pixels so simplification is independent of screen density.
  double get toleranceMeters => switch (this) {
        TrackLod.thumbnail => 50.0,
        TrackLod.overview => 10.0,
        TrackLod.detail => 2.0,
      };
}

/// Reads and writes simplified geometry in the local (unsynced) cache.
///
/// Constructed with no arguments and resolving the database through
/// [LocalCacheDatabaseService.instance], matching [GpsTrackRepository]'s
/// convention of `AppDatabase get _db => DatabaseService.instance.database`.
class TrackGeometryCacheRepository {
  LocalCacheDatabase get _db => LocalCacheDatabaseService.instance.database;

  /// Cached geometry, or null on a cache miss.
  ///
  /// An empty list is a real answer (the track has no drawable points) and
  /// is distinct from null (nothing cached yet).
  Future<List<GpsTrackPoint>?> read(String trackId, TrackLod lod) async {
    final row = await (_db.select(_db.gpsTrackGeometryCache)
          ..where((t) => t.trackId.equals(trackId))
          ..where((t) => t.lodLevel.equals(lod.name)))
        .getSingleOrNull();
    if (row == null) return null;
    if (row.status != 'ok') return const [];
    final blob = row.points;
    if (blob == null) return const [];
    return decodeTrackPoints(blob);
  }

  Future<void> write(
    String trackId,
    TrackLod lod,
    List<GpsTrackPoint> points,
  ) async {
    await _db.into(_db.gpsTrackGeometryCache).insertOnConflictUpdate(
          GpsTrackGeometryCacheCompanion.insert(
            trackId: trackId,
            lodLevel: lod.name,
            status: points.isEmpty ? 'empty' : 'ok',
            createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            points: points.isEmpty
                ? const Value.absent()
                : Value(encodeTrackPoints(points)),
          ),
        );
  }

  /// Drops every cached LOD for [trackId]. Called after a trim or split
  /// changes which points the track represents.
  Future<void> invalidate(String trackId) async {
    await (_db.delete(_db.gpsTrackGeometryCache)
          ..where((t) => t.trackId.equals(trackId)))
        .go();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/gps_log/track_geometry_cache_repository_test.dart`
Expected: PASS, 8 tests.

- [ ] **Step 5: Write the failing provider test**

Create `test/features/gps_log/gps_track_map_providers_test.dart`. Both databases need seeding: `setUpTestDatabase()` for the main one (the track lives there) and a direct `LocalCacheDatabase` for the cache.

```dart
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/database/local_cache_database.dart';
import 'package:submersion/core/services/local_cache_database_service.dart';
import 'package:submersion/features/gps_log/data/repositories/gps_track_repository.dart';
import 'package:submersion/features/gps_log/data/repositories/track_geometry_cache_repository.dart';
import 'package:submersion/features/gps_log/domain/entities/gps_track.dart';
import 'package:submersion/features/gps_log/presentation/providers/gps_track_map_providers.dart';

import '../../helpers/test_database.dart';

void main() {
  late LocalCacheDatabase cacheDb;
  late GpsTrackRepository repo;

  setUp(() async {
    await setUpTestDatabase();
    cacheDb = LocalCacheDatabase(NativeDatabase.memory());
    LocalCacheDatabaseService.instance.setTestDatabase(cacheDb);
    repo = GpsTrackRepository();
  });

  tearDown(() async {
    await cacheDb.close();
    LocalCacheDatabaseService.instance.resetForTesting();
    await tearDownTestDatabase();
  });

  /// Seeds a track of 100 near-collinear fixes: a straight run east with a
  /// sub-metre north wobble, so aggressive simplification should collapse it
  /// to a handful of points.
  Future<String> seedWobblyTrack() async {
    final id = await repo.startTrack(
      startTimeMs: 1700000000000,
      tzOffsetMinutes: 0,
    );
    for (var i = 0; i < 100; i++) {
      await repo.appendBufferPoint(
        id,
        GpsTrackPoint(
          timestamp: 1700000000 + i,
          // 1e-8 deg is ~1 mm of wobble - far below any tolerance.
          latitude: (i.isEven ? 1e-8 : -1e-8),
          longitude: i * 0.0001,
        ),
      );
    }
    await repo.finalizeTrack(id, endTimeMs: 1700000099000);
    return id;
  }

  test('simplifies on first read and writes the result to cache', () async {
    final id = await seedWobblyTrack();
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final simplified = await container
        .read(gpsTrackGeometryProvider((id, TrackLod.thumbnail)).future);

    expect(simplified.length, lessThan(100));
    expect(simplified.length, greaterThanOrEqualTo(2));

    // The cache now holds it, so a cold provider would not re-simplify.
    final cached =
        await TrackGeometryCacheRepository().read(id, TrackLod.thumbnail);
    expect(cached, isNotNull);
    expect(cached!.length, simplified.length);
  });

  test('a second read returns the cached geometry unchanged', () async {
    final id = await seedWobblyTrack();
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final first = await container
        .read(gpsTrackGeometryProvider((id, TrackLod.thumbnail)).future);
    container.invalidate(gpsTrackGeometryProvider((id, TrackLod.thumbnail)));
    final second = await container
        .read(gpsTrackGeometryProvider((id, TrackLod.thumbnail)).future);

    expect(second.length, first.length);
    expect(second.first.timestamp, first.first.timestamp);
    expect(second.last.timestamp, first.last.timestamp);
  });

  test('different LOD levels produce independently cached results', () async {
    final id = await seedWobblyTrack();
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container
        .read(gpsTrackGeometryProvider((id, TrackLod.thumbnail)).future);
    await container
        .read(gpsTrackGeometryProvider((id, TrackLod.detail)).future);

    final cache = TrackGeometryCacheRepository();
    expect(await cache.read(id, TrackLod.thumbnail), isNotNull);
    expect(await cache.read(id, TrackLod.detail), isNotNull);
  });

  test('returns empty for a track id that does not exist', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final result = await container
        .read(gpsTrackGeometryProvider(('nope', TrackLod.detail)).future);
    expect(result, isEmpty);
  });
}
```

Tests for `divesOnTrackProvider` and `trackForDiveProvider` are written in Task 12, alongside the dive-marker feature that consumes them — keeping the provider and its first consumer in one reviewable unit.

- [ ] **Step 6: Implement the providers**

Create `lib/features/gps_log/presentation/providers/gps_track_map_providers.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:submersion/features/gps_log/data/repositories/track_geometry_cache_repository.dart';
import 'package:submersion/features/gps_log/domain/entities/gps_track.dart';
import 'package:submersion/features/gps_log/domain/track_geometry.dart';
import 'package:submersion/features/gps_log/presentation/providers/gps_log_providers.dart';

/// Argument bundle for the isolate. compute() takes exactly one argument,
/// and it must be sendable.
class _SimplifyRequest {
  final List<GpsTrackPoint> points;
  final double toleranceMeters;

  const _SimplifyRequest(this.points, this.toleranceMeters);
}

/// Top-level so it can run in an isolate.
List<GpsTrackPoint> _simplifyInIsolate(_SimplifyRequest request) =>
    simplifyTrack(request.points, request.toleranceMeters);

final trackGeometryCacheRepositoryProvider =
    Provider<TrackGeometryCacheRepository>(
  (ref) => TrackGeometryCacheRepository(),
);

/// A single hydrated track, points blob decoded. This is the expensive step
/// and it happens once per track.
final gpsTrackDetailProvider =
    FutureProvider.family<GpsTrack?, String>((ref, trackId) async {
  return ref
      .watch(gpsTrackRepositoryProvider)
      .getTrack(trackId, includePoints: true);
});

/// Simplified geometry at a given level of detail, cached across launches.
final gpsTrackGeometryProvider =
    FutureProvider.family<List<GpsTrackPoint>, (String, TrackLod)>(
        (ref, key) async {
  final (trackId, lod) = key;
  final cache = ref.watch(trackGeometryCacheRepositoryProvider);

  final cached = await cache.read(trackId, lod);
  if (cached != null) return cached;

  final track = await ref.watch(gpsTrackDetailProvider(trackId).future);
  if (track == null) return const [];

  // Read through effectivePoints so trim bounds are honoured before
  // simplification rather than after.
  final simplified = await compute(
    _simplifyInIsolate,
    _SimplifyRequest(track.effectivePoints, lod.toleranceMeters),
  );
  await cache.write(trackId, lod, simplified);
  return simplified;
});
```

Note the import of `gps_log_providers.dart` for `gpsTrackRepositoryProvider`, and drop the unused `Dive` import — `divesOnTrackProvider` arrives in Task 12.

- [ ] **Step 7: Run tests to verify they pass**

Run: `flutter test test/features/gps_log/`
Expected: PASS, all tests.

- [ ] **Step 8: Format, analyze, commit**

```bash
dart format .
flutter analyze
git add lib/features/gps_log/data/repositories/track_geometry_cache_repository.dart lib/features/gps_log/presentation/providers/gps_track_map_providers.dart test/features/gps_log/track_geometry_cache_repository_test.dart test/features/gps_log/gps_track_map_providers_test.dart
git commit -m "Add track geometry cache repository and map providers"
```

---

**Phase 1 complete.** The geometry core, both schema changes, and the provider layer are in place and fully unit-tested. Nothing is visible in the app yet.

Run the full suite before moving on:

```bash
flutter test
flutter analyze
```

---

## Phase 2: Track Detail Page

First user-visible value. At the end of this phase a diver can tap a track and see where the boat went.

---

### Task 9: Polyline layer from colorization runs

**Files:**
- Create: `lib/features/gps_log/presentation/widgets/gps_track_polyline_layer.dart`
- Test: `test/features/gps_log/gps_track_polyline_layer_test.dart`

**Interfaces:**
- Consumes: `TrackRun`, `TrackColorMode`, `kTrackColorBuckets` (Task 3)
- Produces:
  - `List<Color> trackBucketColors(ColorScheme scheme, TrackColorMode mode, int buckets)`
  - `List<Polyline> buildTrackPolylines({required List<TrackRun> runs, required TrackColorMode mode, required ColorScheme scheme, double strokeWidth = 4.0, Color? uniformColor})`
  - `class GpsTrackPolylineLayer extends StatelessWidget` wrapping `PolylineLayer`

Each `Polyline` carries its run index as `hitValue`, which is how Task 13 resolves a tap back to a point. The colour ramp is generated from the theme rather than hard-coded so it reads correctly in both light and dark.

- [ ] **Step 1: Write the failing test**

Create `test/features/gps_log/gps_track_polyline_layer_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/gps_log/domain/entities/gps_track.dart';
import 'package:submersion/features/gps_log/domain/track_colorization.dart';
import 'package:submersion/features/gps_log/presentation/widgets/gps_track_polyline_layer.dart';

GpsTrackPoint p(int t) =>
    GpsTrackPoint(timestamp: t, latitude: t * 0.001, longitude: 0.0);

TrackRun run(int bucket, int count) => TrackRun(
      points: List.generate(count, (i) => p(bucket * 100 + i)),
      bucket: bucket,
    );

void main() {
  final scheme = ColorScheme.fromSeed(seedColor: Colors.blue);

  group('trackBucketColors', () {
    test('returns one colour per bucket', () {
      final colors = trackBucketColors(scheme, TrackColorMode.speed, 8);
      expect(colors.length, 8);
    });

    test('produces visually distinct endpoints', () {
      final colors = trackBucketColors(scheme, TrackColorMode.speed, 8);
      expect(colors.first, isNot(equals(colors.last)));
    });

    test('uniform mode returns a single colour', () {
      final colors = trackBucketColors(scheme, TrackColorMode.uniform, 8);
      expect(colors.length, 1);
    });
  });

  group('buildTrackPolylines', () {
    test('emits one polyline per run', () {
      final runs = [run(0, 3), run(3, 4), run(7, 2)];
      final lines = buildTrackPolylines(
        runs: runs,
        mode: TrackColorMode.speed,
        scheme: scheme,
      );
      expect(lines.length, 3);
    });

    test('carries the run index as hitValue for tap resolution', () {
      final runs = [run(0, 3), run(3, 4)];
      final lines = buildTrackPolylines(
        runs: runs,
        mode: TrackColorMode.speed,
        scheme: scheme,
      );
      expect(lines[0].hitValue, 0);
      expect(lines[1].hitValue, 1);
    });

    test('maps each run to the colour for its bucket', () {
      final colors = trackBucketColors(scheme, TrackColorMode.speed, 8);
      final runs = [run(0, 2), run(7, 2)];
      final lines = buildTrackPolylines(
        runs: runs,
        mode: TrackColorMode.speed,
        scheme: scheme,
      );
      expect(lines[0].color, colors[0]);
      expect(lines[1].color, colors[7]);
    });

    test('uniform mode honours an explicit uniformColor override', () {
      final runs = [run(0, 3)];
      final lines = buildTrackPolylines(
        runs: runs,
        mode: TrackColorMode.uniform,
        scheme: scheme,
        uniformColor: const Color(0xFF123456),
      );
      expect(lines.single.color, const Color(0xFF123456));
    });

    test('converts every point to a LatLng in order', () {
      final runs = [run(0, 3)];
      final lines = buildTrackPolylines(
        runs: runs,
        mode: TrackColorMode.uniform,
        scheme: scheme,
      );
      expect(lines.single.points.length, 3);
      expect(lines.single.points.first.latitude, closeTo(0.0, 1e-9));
    });

    test('returns empty for no runs', () {
      final lines = buildTrackPolylines(
        runs: const [],
        mode: TrackColorMode.speed,
        scheme: scheme,
      );
      expect(lines, isEmpty);
    });

    test('clamps an out-of-range bucket rather than throwing', () {
      final lines = buildTrackPolylines(
        runs: [run(99, 2)],
        mode: TrackColorMode.speed,
        scheme: scheme,
      );
      expect(lines.length, 1);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/gps_log/gps_track_polyline_layer_test.dart`
Expected: FAIL — `trackBucketColors` isn't defined.

- [ ] **Step 3: Write the implementation**

Create `lib/features/gps_log/presentation/widgets/gps_track_polyline_layer.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:submersion/features/gps_log/domain/track_colorization.dart';

/// Sequential ramp endpoints for each colorization mode.
///
/// Speed runs cool (slow) to warm (fast); elapsed time runs light to dark in
/// the theme's primary hue. Both are generated from the active [ColorScheme]
/// rather than hard-coded so they hold up in light and dark themes.
List<Color> trackBucketColors(
  ColorScheme scheme,
  TrackColorMode mode,
  int buckets,
) {
  if (mode == TrackColorMode.uniform) return [scheme.primary];

  final (Color from, Color to) = switch (mode) {
    TrackColorMode.speed => (scheme.tertiary, scheme.error),
    TrackColorMode.elapsed => (scheme.primaryContainer, scheme.primary),
    TrackColorMode.uniform => (scheme.primary, scheme.primary),
  };

  if (buckets <= 1) return [to];
  return [
    for (var i = 0; i < buckets; i++)
      Color.lerp(from, to, i / (buckets - 1))!,
  ];
}

/// Converts colorization runs into one [Polyline] per run.
///
/// Each polyline carries its run index as [Polyline.hitValue] so a tap can be
/// resolved back to a specific span of the track.
List<Polyline<int>> buildTrackPolylines({
  required List<TrackRun> runs,
  required TrackColorMode mode,
  required ColorScheme scheme,
  double strokeWidth = 4.0,
  Color? uniformColor,
}) {
  if (runs.isEmpty) return const [];

  final colors = trackBucketColors(scheme, mode, kTrackColorBuckets);

  return [
    for (var i = 0; i < runs.length; i++)
      Polyline<int>(
        points: [
          for (final p in runs[i].points) LatLng(p.latitude, p.longitude),
        ],
        color: mode == TrackColorMode.uniform
            ? (uniformColor ?? colors.first)
            : colors[runs[i].bucket.clamp(0, colors.length - 1)],
        strokeWidth: strokeWidth,
        strokeCap: StrokeCap.round,
        strokeJoin: StrokeJoin.round,
        hitValue: i,
      ),
  ];
}

/// Draws a colorized track as a flutter_map layer.
class GpsTrackPolylineLayer extends StatelessWidget {
  const GpsTrackPolylineLayer({
    super.key,
    required this.runs,
    required this.mode,
    this.strokeWidth = 4.0,
    this.uniformColor,
    this.hitNotifier,
  });

  final List<TrackRun> runs;
  final TrackColorMode mode;
  final double strokeWidth;
  final Color? uniformColor;
  final LayerHitNotifier<int>? hitNotifier;

  @override
  Widget build(BuildContext context) {
    return PolylineLayer<int>(
      hitNotifier: hitNotifier,
      polylines: buildTrackPolylines(
        runs: runs,
        mode: mode,
        scheme: Theme.of(context).colorScheme,
        strokeWidth: strokeWidth,
        uniformColor: uniformColor,
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/gps_log/gps_track_polyline_layer_test.dart`
Expected: PASS, 11 tests.

- [ ] **Step 5: Format, analyze, commit**

```bash
dart format .
flutter analyze
git add lib/features/gps_log/presentation/widgets/gps_track_polyline_layer.dart test/features/gps_log/gps_track_polyline_layer_test.dart
git commit -m "Add polyline layer builder for colorized GPS tracks"
```

---

### Task 10: Track detail route and page skeleton

**Files:**
- Create: `lib/features/gps_log/presentation/pages/gps_track_detail_page.dart`
- Modify: `lib/core/router/app_router.dart`
- Modify: `lib/features/gps_log/presentation/pages/gps_logger_page.dart`
- Modify: `lib/l10n/arb/app_en.arb` plus all locale ARBs
- Test: `test/features/gps_log/gps_track_detail_page_test.dart`
- Test: `test/core/router/app_router_gps_track_test.dart`

**Interfaces:**
- Consumes: `gpsTrackDetailProvider`, `gpsTrackGeometryProvider`, `TrackLod` (Task 8); `GpsTrackPolylineLayer` (Task 9)
- Produces: route `/gps-log/:id` named `gpsTrackDetail`; `GpsTrackDetailPage({required String trackId})`

The static `/gps-log/map` route is added in Task 19, but its ordering constraint is established here: any static child of `/gps-log` must be declared **before** `:id` or the parameter route swallows it.

- [ ] **Step 1: Write the failing router test**

Create `test/core/router/app_router_gps_track_test.dart`, following the structure-assertion style used by the `dive planner back-navigation` group in `test/core/router/app_router_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:submersion/core/router/app_router.dart';

/// Recursively collects every path in the route tree.
List<String> _allPaths(List<RouteBase> routes) => [
      for (final r in routes) ...[
        if (r is GoRoute) r.path,
        ..._allPaths(r.routes),
      ],
    ];

void main() {
  test('/gps-log has a :id child route', () {
    final paths = _allPaths(appRouter.configuration.routes);
    expect(paths, contains(':id'));
  });

  test('static gps-log children are declared before the :id route', () {
    // A static sibling declared after :id would never match - go_router
    // takes the first matching route, and :id matches any single segment.
    final gpsLog = _findRoute(appRouter.configuration.routes, '/gps-log');
    final childPaths = [
      for (final r in gpsLog.routes.whereType<GoRoute>()) r.path,
    ];
    final idIndex = childPaths.indexOf(':id');
    expect(idIndex, isNot(-1), reason: ':id child must exist');
    for (var i = 0; i < childPaths.length; i++) {
      if (childPaths[i] == ':id') continue;
      expect(
        i,
        lessThan(idIndex),
        reason: 'static child "${childPaths[i]}" must precede :id',
      );
    }
  });
}

GoRoute _findRoute(List<RouteBase> routes, String path) {
  for (final r in routes) {
    if (r is GoRoute && r.path == path) return r;
    try {
      return _findRoute(r.routes, path);
    } catch (_) {
      // keep searching siblings
    }
  }
  throw StateError('route $path not found');
}
```

Adjust `appRouter` to whatever the router instance or provider is actually named in `app_router.dart` — grep for the `GoRouter(` construction and match it.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/router/app_router_gps_track_test.dart`
Expected: FAIL — `:id` is not in the route tree.

- [ ] **Step 3: Add l10n strings**

Add to `lib/l10n/arb/app_en.arb`:

```json
  "gpsTrack_detail_title": "GPS Track",
  "@gpsTrack_detail_title": {
    "description": "App bar title for a single recorded GPS surface track"
  },
  "gpsTrack_detail_notFound": "This track is no longer available.",
  "@gpsTrack_detail_notFound": {
    "description": "Shown when a track id in the URL does not resolve"
  },
  "gpsTrack_detail_unreadable": "Track data could not be read.",
  "@gpsTrack_detail_unreadable": {
    "description": "Shown when a track's stored points blob fails to decode"
  },
  "gpsTrack_detail_noPoints": "This track has no recorded positions.",
  "@gpsTrack_detail_noPoints": {
    "description": "Shown when a track exists but contains zero fixes"
  }
```

Then translate all four into every locale ARB: ar, de, es, fr, he, hu, it, nl, pt, zh. Do not leave English strings in the other files.

- [ ] **Step 4: Regenerate localizations**

```bash
flutter gen-l10n
```

- [ ] **Step 5: Write the failing page test**

Create `test/features/gps_log/gps_track_detail_page_test.dart`. Copy the pump harness shape from `test/features/dive_log/presentation/widgets/surface_gps_section_test.dart` — `getBaseOverrides()` from `test/helpers/mock_providers.dart`, an explicit surface size, and `AppLocalizations.localizationsDelegates`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/gps_log/domain/entities/gps_track.dart';
import 'package:submersion/features/gps_log/presentation/pages/gps_track_detail_page.dart';
import 'package:submersion/features/gps_log/presentation/providers/gps_track_map_providers.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';

import '../../helpers/mock_providers.dart';

GpsTrackPoint p(int t) =>
    GpsTrackPoint(timestamp: t, latitude: 20.0 + t * 0.001, longitude: -87.0);

GpsTrack _track() => GpsTrack(
      id: 'track-1',
      startTime: 1700000000000,
      endTime: 1700003600000,
      pointCount: 4,
      points: [p(0), p(1), p(2), p(3)],
    );

Future<void> _pump(
  WidgetTester tester, {
  required List<Override> overrides,
}) async {
  final base = await getBaseOverrides();
  await tester.binding.setSurfaceSize(const Size(800, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [...base, ...overrides],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const GpsTrackDetailPage(trackId: 'track-1'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders a map with the track drawn', (tester) async {
    await _pump(tester, overrides: [
      gpsTrackDetailProvider('track-1').overrideWith((ref) async => _track()),
      gpsTrackGeometryProvider(('track-1', TrackLod.detail))
          .overrideWith((ref) async => _track().points),
    ]);

    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byType(PolylineLayer<int>), findsOneWidget);
  });

  testWidgets('shows a not-found message for a missing track',
      (tester) async {
    await _pump(tester, overrides: [
      gpsTrackDetailProvider('track-1').overrideWith((ref) async => null),
      gpsTrackGeometryProvider(('track-1', TrackLod.detail))
          .overrideWith((ref) async => const <GpsTrackPoint>[]),
    ]);

    expect(find.text('This track is no longer available.'), findsOneWidget);
    expect(find.byType(FlutterMap), findsNothing);
  });

  testWidgets('shows an unreadable message when decoding throws',
      (tester) async {
    await _pump(tester, overrides: [
      gpsTrackDetailProvider('track-1')
          .overrideWith((ref) async => throw const FormatException('bad gzip')),
      gpsTrackGeometryProvider(('track-1', TrackLod.detail))
          .overrideWith((ref) async => const <GpsTrackPoint>[]),
    ]);

    expect(find.text('Track data could not be read.'), findsOneWidget);
  });

  testWidgets('shows an empty message for a track with no fixes',
      (tester) async {
    await _pump(tester, overrides: [
      gpsTrackDetailProvider('track-1')
          .overrideWith((ref) async => const GpsTrack(
                id: 'track-1',
                startTime: 1700000000000,
                endTime: 1700003600000,
              )),
      gpsTrackGeometryProvider(('track-1', TrackLod.detail))
          .overrideWith((ref) async => const <GpsTrackPoint>[]),
    ]);

    expect(
      find.text('This track has no recorded positions.'),
      findsOneWidget,
    );
  });
}
```

- [ ] **Step 6: Run test to verify it fails**

Run: `flutter test test/features/gps_log/gps_track_detail_page_test.dart`
Expected: FAIL — `GpsTrackDetailPage` isn't defined.

- [ ] **Step 7: Write the page**

Create `lib/features/gps_log/presentation/pages/gps_track_detail_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import 'package:submersion/features/gps_log/domain/entities/gps_track.dart';
import 'package:submersion/features/gps_log/domain/track_colorization.dart';
import 'package:submersion/features/gps_log/domain/track_geometry.dart';
import 'package:submersion/features/gps_log/data/repositories/track_geometry_cache_repository.dart';
import 'package:submersion/features/gps_log/presentation/providers/gps_track_map_providers.dart';
import 'package:submersion/features/gps_log/presentation/widgets/gps_track_polyline_layer.dart';
import 'package:submersion/features/maps/presentation/providers/map_tile_providers.dart';
import 'package:submersion/features/maps/presentation/widgets/map_attribution.dart';
import 'package:submersion/features/maps/presentation/widgets/map_compass_button.dart';
import 'package:submersion/features/maps/presentation/widgets/trackpad_zoom_map.dart';
import 'package:submersion/l10n/l10n_extension.dart';

/// Full-screen map of one recorded GPS surface track.
class GpsTrackDetailPage extends ConsumerStatefulWidget {
  const GpsTrackDetailPage({super.key, required this.trackId});

  final String trackId;

  @override
  ConsumerState<GpsTrackDetailPage> createState() =>
      _GpsTrackDetailPageState();
}

class _GpsTrackDetailPageState extends ConsumerState<GpsTrackDetailPage> {
  final MapController _mapController = MapController();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final trackAsync = ref.watch(gpsTrackDetailProvider(widget.trackId));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.gpsTrack_detail_title)),
      body: trackAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        // A corrupt or undecodable blob must not crash the page. Surface it
        // as a readable message; deletion is offered from the list.
        error: (_, __) => Center(child: Text(l10n.gpsTrack_detail_unreadable)),
        data: (track) {
          if (track == null) {
            return Center(child: Text(l10n.gpsTrack_detail_notFound));
          }
          final points = track.effectivePoints;
          if (points.isEmpty) {
            return Center(child: Text(l10n.gpsTrack_detail_noPoints));
          }
          return _TrackMap(
            trackId: widget.trackId,
            fallbackPoints: points,
            controller: _mapController,
          );
        },
      ),
    );
  }
}

class _TrackMap extends ConsumerWidget {
  const _TrackMap({
    required this.trackId,
    required this.fallbackPoints,
    required this.controller,
  });

  final String trackId;
  final List<GpsTrackPoint> fallbackPoints;
  final MapController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Fall back to the unsimplified points while the isolate is working, so
    // the map draws immediately rather than flashing empty.
    final points = ref
            .watch(gpsTrackGeometryProvider((trackId, TrackLod.detail)))
            .value ??
        fallbackPoints;
    final runs = bucketizeTrack(points, TrackColorMode.uniform);
    final bounds = trackBounds(points)!;

    return TrackpadZoomMap(
      controller: controller,
      child: FlutterMap(
        mapController: controller,
        options: MapOptions(
          initialCameraFit: CameraFit.bounds(
            bounds: LatLngBounds(
              LatLng(bounds.minLat, bounds.minLon),
              LatLng(bounds.maxLat, bounds.maxLon),
            ),
            padding: const EdgeInsets.all(48),
          ),
        ),
        children: [
          ref.watch(mapTileLayerProvider),
          GpsTrackPolylineLayer(
            runs: runs,
            mode: TrackColorMode.uniform,
          ),
          const MapAttribution(),
          MapCompassButton(controller: controller),
        ],
      ),
    );
  }
}
```

Resolve `mapTileLayerProvider` and the exact `MapAttribution` / `MapCompassButton` constructor signatures against `dive_activity_map_page.dart`, which already composes all three — copy its usage rather than guessing.

- [ ] **Step 8: Register the route**

In `lib/core/router/app_router.dart`, add a child of the existing `/gps-log` route (around line 857). Declare it **last** among that route's children so future static siblings can be inserted before it:

```dart
            routes: [
              // Static children MUST precede ':id' - ':id' matches any single
              // segment and would otherwise swallow them.
              GoRoute(
                path: ':id',
                name: 'gpsTrackDetail',
                builder: (context, state) => GpsTrackDetailPage(
                  trackId: state.pathParameters['id']!,
                ),
              ),
            ],
```

- [ ] **Step 9: Make list rows navigate**

In `gps_logger_page.dart`, add `onTap: () => context.push('/gps-log/${track.id}')` to the track `ListTile` (around line 235) and a trailing chevron alongside the existing delete button.

- [ ] **Step 10: Run all the tests**

Run: `flutter test test/features/gps_log/ test/core/router/`
Expected: PASS.

- [ ] **Step 11: Format, analyze, commit**

```bash
dart format .
flutter analyze
git add lib/features/gps_log/presentation/pages/gps_track_detail_page.dart lib/core/router/app_router.dart lib/features/gps_log/presentation/pages/gps_logger_page.dart lib/l10n/ test/features/gps_log/gps_track_detail_page_test.dart test/core/router/app_router_gps_track_test.dart
git commit -m "Add GPS track detail page at /gps-log/:id"
```

---
