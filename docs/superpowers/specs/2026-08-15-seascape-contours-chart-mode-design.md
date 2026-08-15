# Seascape Contours and Chart Mode - Design

**Date:** 2026-08-15
**Status:** Approved (design dialogue with Eric, 2026-08-15)
**Depends on:** the site bathymetry seascape
(`2026-07-28-site-bathymetry-seascape-design.md`, shipped in PR #763) and its
axes/extent addendum (`2026-07-28-seascape-axes-and-extent-design.md`).
**Part of:** the seascape usefulness program (slice 1 of 5, see Program
Context below).

## Problem

The 3D seascape renders real bathymetry but reads as scenery: a smooth
teal-to-navy ramp gives no precise depth structure, and there is no way to
get the classic "nautical chart" read of a site. Divers briefing a dive want
to see isobaths (where the 10 m line runs, where the wall drops), and they
want a north-up plan view they can read in ten seconds.

## Program Context

Brainstormed 2026-08-15. The seascape serves four jobs (pre-dive briefing,
post-dive story, site knowledge base, quick orientation), delivered as five
slices, each its own spec/plan/PR cycle:

1. **Terrain legibility: contour lines + chart mode (this spec).**
2. Site features: diver-placed annotations (wreck, mooring, entry/exit,
   swim-through, hazard, typical-current arrow), a new synced table.
   Currents are deliberately diver-annotated, not model-derived: no public
   model resolves flow at dive-site scale, and the seascape's honesty
   principle forbids fake precision.
3. Wreck suggestions: OSM seamarks (Overpass) + NOAA ENC wrecks as a
   keyless cached source layer, surfaced as suggestions the diver accepts
   into site features.
4. Briefing tools: two-point measure (distance, bearing, depth profile
   along the line) and depth-limit shading (cert depth or MOD of a chosen
   mix).
5. Dive coverage layer: aggregate path ribbons into a "where I've been"
   density trace.

## Decisions (Eric, 2026-08-15)

- Contour levels are unit-aware nice values in the diver's display unit.
- Contours render as occlusion-correct ribbon meshes, not chrome lines.
- Major contours get depth labels in the 3D orbit view as well as in chart
  mode.
- Chart mode lives on the site seascape page as a mode toggle: locked
  north-up top-down orthographic plan view.
- The depth legend shows in BOTH modes and on BOTH seascape pages (site and
  per-dive), not only in chart mode.
- The per-dive seascape page gets a "Contours" FilterChip (a chip row above
  the time scrub bar) instead of hardcoding contours on.
- No export/share button in this slice; no chart mode on the per-dive page.

## Design

### Contour generation

New pure-domain builder `lib/features/dive_3d/domain/spatial/contour_builder.dart`:

- Marching squares over `BathymetryGrid.depthsMeters`. Any cell whose four
  corners include a `null` (nodata) or land value is skipped entirely, so
  contours stop at the edge of known data instead of interpolating fiction.
- Per-cell segments are joined into polylines (shared-endpoint chaining) so
  ribbons are continuous and labels have a curve to anchor to.
- Polyline vertices map through the same ENU-to-scene projection as the
  terrain mesh (`enuBounds` + `spatial_projection.dart`), so contours lie
  exactly on the terrain surface.
- **Levels:** computed at nice values in the diver's display depth unit
  using the existing 1/2/5 x 10^n `niceStep` logic from
  `seascape_axes.dart`. Selection rule: the minor interval is the smallest
  nice step that yields at most 15 levels across the wet depth range
  (0 to `grid.maxDepthMeters` in display units). Every 5th level is a major
  contour. A feet diver gets 20/40/60 ft lines; a meters diver gets
  5/10/15 m lines. Levels convert to meters for marching; label text stays
  in display units.
- **Flat-site guard:** if fewer than 2 levels fit in the depth range, no
  contours are emitted.
- Output type `ContourSet`: per level, `levelMeters`, `isMajor`, `labelText`,
  and scene-space polylines.

The builder is a pure function (no IO, no throws by design) and runs inside
the existing geometry services, so it rides the current `compute()` isolate
path for grids above 4000 cells.

### Rendering: ribbon meshes under the contours overlay

Chrome-painted polylines were rejected: the chrome foreground has no
occlusion, so lines on the far side of a ridge would draw through it.
Instead each polyline becomes a thin triangle-strip ribbon (the dive-path
ribbon pattern), lifted a small epsilon above the terrain surface to avoid
z-fighting the mesh, and packaged as `SceneLayer`s gated by a new
`SceneOverlay.contours` value (default visible on both seascape scenes).
Ribbons participate in the painter's back-to-front triangle sort, so
occlusion is correct for free.

Styling: minor contours are fine, semi-transparent dark ink; major contours
are wider and more opaque. Colors are fixed constants beside the terrain
ramp constants in the builder.

### Contour labels

Major contours only, and only while the contours overlay is visible (no
separate toggle).

- **3D orbit view:** each major contour carries a small set of candidate
  anchor points sampled along its polyline. Per paint, `AxisChromePainter`
  projects the candidates and draws the label at the candidate nearest the
  camera (highest view-space z), which naturally sits on the visible front
  side of the terrain. Screen-aligned text with a subtle halo, one label per
  major contour.
- **Chart mode:** same machinery; top-down means no occlusion concerns, so
  labels are always legible.
- Anchor data rides a new nullable `contourLabels` field on the same result
  records that carry `axisInputs` (`SpatialSceneResult`,
  `SiteSeascapeReady`).

### Chart mode (site seascape page only)

A mode toggle in the site seascape page's app bar switches between 3D orbit
and chart:

- **Camera:** top-down orthographic, locked north-up. Rotation gestures are
  disabled; pan and pinch-zoom remain. Entering chart mode snaps
  zoom-to-fit on the terrain box. Because the projector is orthographic, the
  top-down view is a geometrically true plan view; the existing axes remain
  visible as the scale frame and the compass rose stays pinned north-up.
- **Engine trap:** positive pitch tips scene-north toward screen bottom at
  yaw 0, so the exact yaw/pitch pair for north-up is verified in a unit test
  via the existing `compassNeedleAngle` helper, never assumed.
- **Water plane:** hidden in chart mode. From above it only tints the map
  blue and muddies depth colors. The water layer gains a
  `SceneOverlay.water` gate: always on in 3D orbit, excluded from the chart
  mode visible set, never exposed as a user chip. (Visibility routes through
  the overlay gate because the scene is immutable data and the viewport a
  dumb renderer; rebuilding geometry to hide a plane, or a page-side special
  case in the viewport, would both be the wrong seam.)

Chart mode only exists on the site page, which only renders with a real
bathymetry grid, so it can never show synthesized terrain.

### Depth legend

New widget `seascape_depth_legend.dart`: a compact vertical ramp bar
(teal at 0 to navy at max depth) with tick marks at the major contour
levels, values in display units, plus the sand swatch labeled as land.
Shown top-right on BOTH seascape pages in BOTH modes, clear of the
provenance chip (top-left), compass (bottom-left), and overlay chips
(bottom center). Hidden on synthesized terrain.

### Integration

- `SceneOverlay` gains `contours` and `water`. The analytical dive scene's
  overlay menu (`dive_3d_page.dart`) does an exhaustive switch over this
  enum: both new values get labels there but are filtered out of that menu,
  the same way `paths` was handled when the seascape shipped.
- **Site seascape page:** adds a third FilterChip, "Contours", default on.
- **Per-dive seascape page:** gains a compact chip row above the
  `TimeScrubBar` with a single "Contours" chip (markers stay hardcoded; that
  scene has no markers today, and water stays internal).
- Both geometry services (`site_seascape_geometry_service.dart`,
  `spatial_geometry_service.dart`) invoke the contour builder only when the
  terrain is real bathymetry. The synthesized fallback gets no contours, no
  legend, and no chart mode: contours assert "this is the real isobath,"
  matching the precedent that hover inspection is disabled on invented
  terrain.
- Levels depend on the display unit, so the geometry providers gain a
  depth-unit dependency and rebuild when units change (a 20 ft contour is
  not a 6 m contour). Known trap: a new provider dependency breaks consumer
  widget tests that lack a settings override; all touched page tests get the
  `_TestSettingsNotifier` pattern.
- New l10n keys (contours chip label, chart mode toggle tooltip, legend land
  label, overlay menu labels) are translated in ALL supported locales, and
  `flutter gen-l10n` runs from the project root.

### Edge cases

- Nodata holes: marching squares skips cells touching null corners.
- Near-flat sites: fewer than 2 fitting levels means no contour lines; the
  legend still shows the ramp.
- Unit switch: levels, labels, and legend all recompute via the settings
  watch.
- Degenerate label placement: if every candidate anchor of a contour
  projects off-screen, its label is skipped that frame.

## Testing

TDD throughout:

- `contour_builder` unit tests with hand-computed marching-squares vectors:
  a tiny 3x3 grid with a known saddle, null-corner skipping, polyline
  joining, level selection in both unit systems, flat-site guard, label
  anchor sampling.
- Chart-mode camera preset unit test asserting north-up via
  `compassNeedleAngle`.
- Widget tests: contours chip toggles the layers on both pages, chart mode
  toggle swaps camera and chrome (legend present, water hidden, labels on),
  legend renders ticks in the active unit. Established patterns apply:
  settings-notifier override, bounded pumps on pages hosting maps or
  never-settling animations.
- `dart format .` and `flutter analyze` clean before push.

## Out of scope (this slice)

- Export/share chart as image (respect the existing share-vs-save duality
  when it comes).
- Chart mode on the per-dive seascape page.
- Depth-band (stepped/quantized) terrain coloring; the smooth ramp stays.
- Depth-ramp renormalization for drop-off sites (still a known trade-off
  from the axes spec).
- Slices 2 to 5 of the program (site features, wreck suggestions, measure +
  depth-limit shading, coverage layer).

## File plan

New:
- `lib/features/dive_3d/domain/spatial/contour_builder.dart` (+ tests)
- `lib/features/dive_3d/presentation/widgets/seascape_depth_legend.dart`
  (+ tests)

Touched:
- `lib/features/dive_3d/presentation/scene_overlay.dart` (two new values)
- `lib/features/dive_3d/domain/spatial/site_seascape_geometry_service.dart`
- `lib/features/dive_3d/domain/spatial/spatial_geometry_service.dart`
- `lib/features/dive_3d/application/site_seascape_providers.dart`
- `lib/features/dive_3d/application/spatial_providers.dart`
- `lib/features/dive_3d/presentation/renderer/tissue_chrome_painters.dart`
  (`AxisChromePainter`: contour labels)
- `lib/features/dive_3d/presentation/widgets/dive_3d_interactive_viewport.dart`
  (chart camera lock, label inputs)
- `lib/features/dive_3d/presentation/pages/site_seascape_page.dart`
- `lib/features/dive_3d/presentation/pages/spatial_site_page.dart`
- `lib/features/dive_3d/presentation/pages/dive_3d_page.dart` (exhaustive
  switch entries)
- `lib/l10n/*.arb` (all locales)
