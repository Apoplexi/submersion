import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/gps_log/data/repositories/track_geometry_cache_repository.dart';
import 'package:submersion/features/gps_log/domain/entities/gps_track.dart';
import 'package:submersion/features/gps_log/domain/track_colorization.dart';
import 'package:submersion/features/gps_log/domain/track_geometry.dart';
import 'package:submersion/features/gps_log/presentation/providers/gps_track_map_providers.dart';
import 'package:submersion/features/gps_log/presentation/widgets/gps_track_polyline_layer.dart';
import 'package:submersion/features/gps_log/presentation/widgets/track_color_legend.dart';
import 'package:submersion/features/gps_log/presentation/widgets/track_point_info_card.dart';
import 'package:submersion/features/gps_log/presentation/widgets/track_stats_header.dart';
import 'package:submersion/features/maps/presentation/widgets/map_attribution.dart';
import 'package:submersion/features/maps/presentation/widgets/map_compass_button.dart';
import 'package:submersion/features/maps/presentation/widgets/submersion_tile_layer.dart';
import 'package:submersion/features/maps/presentation/widgets/trackpad_zoom_map.dart';
import 'package:submersion/l10n/l10n_extension.dart';

/// Full-screen map of one recorded GPS surface track.
class GpsTrackDetailPage extends ConsumerStatefulWidget {
  const GpsTrackDetailPage({super.key, required this.trackId});

  final String trackId;

  @override
  ConsumerState<GpsTrackDetailPage> createState() => _GpsTrackDetailPageState();
}

class _GpsTrackDetailPageState extends ConsumerState<GpsTrackDetailPage> {
  final MapController _mapController = MapController();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final trackAsync = ref.watch(gpsTrackDetailProvider(widget.trackId));

    final mode = ref.watch(trackColorModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.gpsTrack_detail_title),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SegmentedButton<TrackColorMode>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: TrackColorMode.uniform,
                  label: Text(l10n.gpsTrack_colorMode_uniform),
                ),
                ButtonSegment(
                  value: TrackColorMode.speed,
                  label: Text(l10n.gpsTrack_colorMode_speed),
                ),
                ButtonSegment(
                  value: TrackColorMode.elapsed,
                  label: Text(l10n.gpsTrack_colorMode_elapsed),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (selection) {
                // Only bucketizeTrack re-runs; the decoded and simplified
                // geometry stay resident, so this is a frame not a reload.
                ref.read(trackColorModeProvider.notifier).state =
                    selection.first;
              },
            ),
          ),
        ),
      ),
      body: trackAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        // A corrupt or undecodable blob must not crash the page. Surface it
        // as a readable message; deletion is offered from the list.
        error: (_, _) => Center(child: Text(l10n.gpsTrack_detail_unreadable)),
        data: (track) {
          if (track == null) {
            return Center(child: Text(l10n.gpsTrack_detail_notFound));
          }
          final points = track.effectivePoints;
          if (points.length < 2) {
            return Center(child: Text(l10n.gpsTrack_detail_noPoints));
          }
          return Column(
            children: [
              TrackStatsHeader(
                points: points,
                diveCount:
                    ref
                        .watch(divesOnTrackProvider(widget.trackId))
                        .value
                        ?.length ??
                    0,
              ),
              Expanded(
                child: _TrackMap(
                  trackId: widget.trackId,
                  fallbackPoints: points,
                  controller: _mapController,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TrackMap extends ConsumerStatefulWidget {
  const _TrackMap({
    required this.trackId,
    required this.fallbackPoints,
    required this.controller,
  });

  final String trackId;
  final List<GpsTrackPoint> fallbackPoints;
  final MapController controller;

  @override
  ConsumerState<_TrackMap> createState() => _TrackMapState();
}

class _TrackMapState extends ConsumerState<_TrackMap> {
  final LayerHitNotifier<int> _hitNotifier = ValueNotifier(null);
  ({GpsTrackPoint point, double speedMps})? _inspected;

  String get trackId => widget.trackId;
  List<GpsTrackPoint> get fallbackPoints => widget.fallbackPoints;
  MapController get controller => widget.controller;

  @override
  void dispose() {
    _hitNotifier.dispose();
    super.dispose();
  }

  /// Resolves a tap on the polyline back to a real recorded fix.
  void _handleTap(List<TrackRun> runs, List<GpsTrackPoint> fullPoints) {
    final hit = _hitNotifier.value;
    if (hit == null || hit.hitValues.isEmpty) {
      setState(() => _inspected = null);
      return;
    }
    final runIndex = hit.hitValues.first;
    if (runIndex < 0 || runIndex >= runs.length) return;
    final found = nearestPointInRun(
      fullPoints: fullPoints,
      run: runs[runIndex],
      tapped: hit.coordinate,
    );
    setState(() => _inspected = found);
  }

  @override
  Widget build(BuildContext context) {
    // Fall back to the unsimplified points while the isolate is working, so
    // the map draws immediately rather than flashing empty.
    final points =
        ref.watch(gpsTrackGeometryProvider((trackId, TrackLod.detail))).value ??
        fallbackPoints;
    final drawable = points.length >= 2 ? points : fallbackPoints;
    final mode = ref.watch(trackColorModeProvider);
    final runs = bucketizeTrack(drawable, mode);
    final bounds = trackBounds(drawable)!;

    final inspected = _inspected;

    return Stack(
      children: [
        Positioned.fill(
          child: TrackpadZoomMap(
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
                  // A track a few hundred metres wide would otherwise fit
                  // past the tile provider's max zoom and render blank.
                  maxZoom: 16.0,
                ),
              ),
              children: [
                submersionTileLayer(ref),
                // The notifier is populated by the layer's own hit test, so
                // the tap handler has to wrap the layer - MapOptions.onTap
                // fires without it being set.
                GestureDetector(
                  onTap: () => _handleTap(runs, drawable),
                  child: GpsTrackPolylineLayer(
                    runs: runs,
                    mode: mode,
                    hitNotifier: _hitNotifier,
                  ),
                ),
                MarkerLayer(markers: _markers(context, drawable)),
                const MapAttribution(),
                MapCompassButton(controller: controller),
              ],
            ),
          ),
        ),
        Positioned(
          left: 12,
          bottom: 12,
          child: TrackColorLegend(
            mode: mode,
            speedRangeMps: speedRange(drawable),
          ),
        ),
        if (inspected != null)
          Positioned(
            right: 12,
            bottom: 12,
            child: TrackPointInfoCard(
              point: inspected.point,
              speedMps: inspected.speedMps,
              onDismiss: () => setState(() => _inspected = null),
            ),
          ),
      ],
    );
  }

  /// Start and end pins, plus one pin per dive logged during this track.
  ///
  /// Keys live on the marker CHILD via KeyedSubtree, never on the Marker
  /// itself: flutter_map reuses Marker.key for every repeated world copy it
  /// renders at low zoom, which would make those copies duplicate-keyed
  /// siblings in the layer's Stack.
  List<Marker> _markers(BuildContext context, List<GpsTrackPoint> points) {
    final scheme = Theme.of(context).colorScheme;
    final dives = ref.watch(divesOnTrackProvider(trackId)).value ?? const [];

    return [
      Marker(
        point: LatLng(points.first.latitude, points.first.longitude),
        width: 24,
        height: 24,
        child: KeyedSubtree(
          key: const ValueKey('track-start-marker'),
          child: _pin(scheme, Icons.play_arrow, scheme.tertiary),
        ),
      ),
      Marker(
        point: LatLng(points.last.latitude, points.last.longitude),
        width: 24,
        height: 24,
        child: KeyedSubtree(
          key: const ValueKey('track-end-marker'),
          child: _pin(scheme, Icons.stop, scheme.outline),
        ),
      ),
      for (final dive in dives)
        if (dive.entryLocation != null)
          Marker(
            point: LatLng(
              dive.entryLocation!.latitude,
              dive.entryLocation!.longitude,
            ),
            width: 32,
            height: 32,
            child: KeyedSubtree(
              key: ValueKey('track-dive-marker-${dive.id}'),
              child: GestureDetector(
                onTap: () => context.push('/dives/${dive.id}'),
                child: _pin(scheme, Icons.scuba_diving, scheme.primary),
              ),
            ),
          ),
    ];
  }

  Widget _pin(ColorScheme scheme, IconData icon, Color color) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
      ),
      child: Icon(icon, size: 14, color: color),
    );
  }
}
