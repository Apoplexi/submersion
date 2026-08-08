import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/gps_log/data/repositories/track_geometry_cache_repository.dart';
import 'package:submersion/features/gps_log/domain/entities/gps_track.dart';
import 'package:submersion/features/gps_log/domain/track_colorization.dart';
import 'package:submersion/features/gps_log/domain/track_geometry.dart';
import 'package:submersion/features/gps_log/presentation/providers/gps_track_map_providers.dart';
import 'package:submersion/features/gps_log/presentation/widgets/gps_track_polyline_layer.dart';
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

    return Scaffold(
      appBar: AppBar(title: Text(l10n.gpsTrack_detail_title)),
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
    final points =
        ref.watch(gpsTrackGeometryProvider((trackId, TrackLod.detail))).value ??
        fallbackPoints;
    final drawable = points.length >= 2 ? points : fallbackPoints;
    final runs = bucketizeTrack(drawable, TrackColorMode.uniform);
    final bounds = trackBounds(drawable)!;

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
            // A track a few hundred metres wide would otherwise fit past the
            // tile provider's max zoom and render blank.
            maxZoom: 16.0,
          ),
        ),
        children: [
          submersionTileLayer(ref),
          GpsTrackPolylineLayer(runs: runs, mode: TrackColorMode.uniform),
          const MapAttribution(),
          MapCompassButton(controller: controller),
        ],
      ),
    );
  }
}
