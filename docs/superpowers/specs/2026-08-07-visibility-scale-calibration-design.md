# Visibility Scale Calibration - Design

Date: 2026-08-07
Status: Approved
Schema version: v144

## Problem

`Visibility` (`lib/core/constants/enums.dart:31`) is a four-value enum whose
labels weld a judgment to a measurement:

| Value | Label |
| ------- | ------- |
| `excellent` | `Excellent (>30m / >100ft)` |
| `good` | `Good (15-30m / 50-100ft)` |
| `moderate` | `Moderate (5-15m / 15-50ft)` |
| `poor` | `Poor (<5m / <15ft)` |

Only the judgment is persisted. `dives.visibility` is a `TEXT` column holding
the enum `.name`, so a dive with 6 m of visibility is stored forever as the
string `moderate`.

The thresholds are calibrated for tropical diving. A 30 m "excellent" is a Red
Sea or Cozumel number. In Puget Sound, Monterey, the Great Lakes or UK coastal
water, 6 m is an exceptional day, and the app files it at the bottom of
`moderate` - the second-worst of four buckets. Cold-water and inland divers
cannot record a good day as a good day.

Discarding the measurement also corrupts data the app already receives:

- `uddf_import_service.dart:731` and `uddf_full_import_service.dart:1992` take a
  real measured distance from a UDDF file and collapse it into a bucket.
- `subsurface_xml_parser.dart:246` parses an integer and does the same.
- `uddf_export_service.dart:555` then invents a distance back out of the bucket
  (excellent -> 30, good -> 20, moderate -> 10, poor -> 5).

A number entered in another logbook does not survive a round trip through
Submersion.

The app is also internally inconsistent: dive **sites** already store
`typicalVisibility` as free text (`dive_site.dart:227`), so there are two
incompatible visibility models in the same codebase.

## Decisions

| Question | Decision |
| ---------- | ---------- |
| Fix shape | Store the measurement; derive the adjective from a per-diver calibration |
| Legacy data | Keep both columns, never fabricate a number for an existing dive |
| Calibration source | Preset picker plus custom override, per diver |
| Entry UX | Units-aware numeric field with the adjective shown live |

The decisive argument for storing the measurement is that recalibration must be
lossless. If the stored fact is `6.0`, changing presets only changes an
adjective. If the stored fact is `moderate`, changing presets silently
reinterprets every dive already logged.

## Data model

### `dives` (schema v144)

```dart
// NEW - canonical measurement, always metric, nullable.
RealColumn get visibilityMeters => real().nullable()();

// RETAINED - legacy bucket. Read-only from v144 onward. Never written by new
// code paths; cleared when a dive gains a numeric value.
TextColumn get visibility => text().nullable()();
```

The migration adds the column and performs **no backfill**. Existing rows keep
their bucket word and `visibilityMeters` stays `null`.

### Precedence and clearing

Numeric wins. Reads resolve in this order:

1. `visibilityMeters != null` -> format the distance, derive the adjective.
2. `visibility != null` -> render the legacy band (see Display).
3. Both null -> field is absent.

When a save supplies `visibilityMeters`, the write must also clear the legacy
bucket so a stale second answer cannot survive. The clear must be an explicit
`Value(null)`. `Value.absent()` preserves the existing value on a `toCompanion`
write and would leave both columns populated.

### `diver_settings` (schema v144)

```dart
TextColumn get visibilityScalePreset =>
    text().withDefault(const Constant('tropical'))();
// Used only when the preset is 'custom'.
RealColumn get visibilityScaleExcellentM => real().nullable()();
RealColumn get visibilityScaleGoodM => real().nullable()();
RealColumn get visibilityScaleModerateM => real().nullable()();
```

## Calibration

A pure value object with no I/O, so it is trivially testable and safe to call
from build methods.

```dart
enum VisibilityScalePreset { tropical, temperate, coldWater, custom }

class VisibilityScale {
  final double excellentAtOrAboveM;
  final double goodAtOrAboveM;
  final double moderateAtOrAboveM;
}
```

Three boundaries produce four bands. Boundaries are inclusive at the lower edge:
a value `>= excellentAtOrAboveM` is excellent.

| Preset | Excellent | Good | Moderate | Poor |
| -------- | ----------- | ------ | ---------- | ------ |
| Tropical | >= 30 m | 15-30 m | 5-15 m | < 5 m |
| Temperate | >= 20 m | 10-20 m | 4-10 m | < 4 m |
| Cold-water / Inland | >= 12 m | 6-12 m | 2-6 m | < 2 m |
| Custom | user-entered | | | |

Thresholds are canonical metric. The settings UI converts for display, so an
imperial diver sees approximately 40 ft / 20 ft / 6.5 ft on the cold-water
preset. Custom values are entered in the diver's own units and converted to
metric for storage.

Custom validation: the three values must be strictly descending and greater than
zero. A violated constraint blocks the save with an inline error rather than
silently reordering.

On the cold-water preset a 6 m day reads **Good** and a 12 m day reads
**Excellent**, which is the reported problem resolved.

### Default preset

The default is `tropical`, which reproduces today's exact thresholds. Upgrading
to v144 therefore re-labels nobody's logbook. The fix is that the scale becomes
changeable, not that it silently changes. Discoverability is handled by placing
the setting next to the existing unit preferences.

## Display

A single pure function is the only place the mapping lives:

```dart
VisibilityBand? bandFor(double meters, VisibilityScale scale);
```

Consumers: dive detail, compact and dense dive list tiles, the dive table
column, `DiveFieldExtractor` (`dive_field_extractor.dart:50`), and the CSV and
Excel exporters.

Rendered form for a numeric dive, in the diver's units:

```
Visibility   20 ft . Excellent
```

### Legacy rows

Legacy rows render as the distance band they actually mean, never as a
calibrated adjective:

```
Visibility   15-50 ft
```

We know only that the dive fell somewhere in that band; asserting an adjective
would be a guess. This requires the band string to be unit-aware, so the
hardcoded English in `enums.dart` is replaced by ARB messages with numeric
placeholders.

The `Visibility` enum itself is **retained** - it is still needed to decode the
legacy column, and UDDF and Subsurface importers still reference it for files
that carry a bucket rather than a number. What is removed is
`Visibility.displayName`, replaced by metric band bounds on each value plus a
localized, unit-aware renderer that formats those bounds. Statistics legacy
segment labels use the same renderer, so they are unit-aware too.

## Statistics

`getVisibilityDistribution` (`statistics_repository.dart:971`) currently does
`GROUP BY visibility` on the text column. SQL cannot see the diver's
calibration, so binning moves into Dart: the query selects both `visibility` and
`visibility_meters` (retaining the existing `DiveFilterSql` predicate), and the
repository bins the rows.

- Numeric dives bin by calibrated adjective.
- Legacy-only dives form their own segments, labelled with their band
  (for example `5-15 m (legacy)`).

This is the one place the dual model stays visible to users. It is honest -
legacy dives genuinely are a coarser measurement - and the legacy segments
shrink naturally as dives are edited.

## Import and export

| Path | Change |
| ------ | -------- |
| UDDF import | Store the parsed distance in `visibilityMeters` instead of bucketing it |
| UDDF full import | Same |
| Subsurface XML import | Route the parsed integer to `visibilityMeters` |
| CSV import | Map a `visibility` header to the numeric column, parsing a unit suffix when present |
| UDDF export | Emit the true value for numeric dives; fall back to today's representative mapping only for legacy dives |
| CSV / Excel export | Replace the single `Visibility` column with `Visibility` (numeric, diver's units) and `Visibility Rating` (adjective) |

The existing single `Visibility` column currently emits `displayName`, so its
content changes either way. Splitting it keeps the numeric column
machine-readable for spreadsheet use while preserving the human-readable rating.
Legacy dives emit an empty numeric cell and their band text in the rating
column.

The UDDF changes are a strict improvement: they remove an existing lossy
round trip rather than adding behaviour.

## Settings UI

A new section beside the existing unit preferences: a preset selector, and, when
`custom` is selected, three numeric fields in the diver's units. A live preview
row shows how a sample distance is labelled under the current selection.

## Sync

`sync_data_serializer.dart` wraps Drift's generated `toJson` / `fromJson` rather
than a hand-maintained column list, so the new columns propagate automatically
once codegen runs. Required work is the schema version bump to v144 and
confirming that a peer on an older schema hydrates the new columns to their
defaults rather than erroring.

`visibilityScalePreset` is a `diver_settings` column and therefore syncs with the
diver's other preferences, so the calibration follows the diver across devices.

## Testing

Written test-first, per CLAUDE.md.

- `VisibilityScale` band boundaries, explicitly covering the inclusive lower
  edge of each band and the exact preset threshold values.
- Custom scale validation: rejects non-descending and non-positive values.
- Migration v143 -> v144: existing rows keep their legacy text untouched and
  `visibilityMeters` is null; no rows are backfilled.
- Precedence: a dive with both columns populated renders the numeric value; a
  save carrying a number clears the legacy bucket via `Value(null)`.
- Widget test: entering a number updates the adjective live, and switching units
  reformats without changing the stored metric value.
- Statistics binning across a mixed legacy and numeric dataset.
- UDDF round trip: a measured distance survives export and re-import. This is
  the regression test for the data loss that exists today.

## Out of scope

- Dive site `typicalVisibility` stays free text. Unifying it with the numeric
  model is a real follow-up, but a separate change.
- No per-region or per-site automatic calibration.
- No range entry (`visibilityMeters` is a single value, not a min/max pair).

## Accepted trade-offs

1. **Default preset is tropical.** No existing logbook re-labels on upgrade, but
   cold-water divers must set the preference once; they are not fixed by
   default.
2. **Legacy dives render as a band, never an adjective.** Honest, but old and
   new dives look different in the same list until the old ones are edited.
3. **Single value, not a range.** A diver who thinks in ranges ("15 to 20 feet")
   must pick one number.
