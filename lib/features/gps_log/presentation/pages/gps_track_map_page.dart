import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/gps_log/data/repositories/track_geometry_cache_repository.dart';
import 'package:submersion/features/gps_log/domain/entities/gps_track.dart';
import 'package:submersion/features/gps_log/presentation/providers/gps_track_map_providers.dart';
import 'package:submersion/features/gps_log/presentation/widgets/gps_track_thumbnail.dart';
import 'package:submersion/features/gps_log/presentation/widgets/track_camera.dart';
import 'package:submersion/features/maps/presentation/widgets/map_attribution.dart';
import 'package:submersion/features/maps/presentation/widgets/map_compass_button.dart';
import 'package:submersion/features/maps/presentation/widgets/submersion_tile_layer.dart';
import 'package:submersion/features/maps/presentation/widgets/trackpad_zoom_map.dart';
import 'package:submersion/l10n/l10n_extension.dart';
import 'package:submersion/shared/providers/map_list_selection_provider.dart';
import 'package:submersion/shared/widgets/map_list_layout/map_list_scaffold.dart';

const String _kSectionKey = 'gps-tracks';

/// Every recorded track on one map, bound to a list pane on desktop.
class GpsTrackMapPage extends ConsumerStatefulWidget {
  const GpsTrackMapPage({super.key});

  @override
  ConsumerState<GpsTrackMapPage> createState() => _GpsTrackMapPageState();
}

class _GpsTrackMapPageState extends ConsumerState<GpsTrackMapPage> {
  final MapController _mapController = MapController();

  Future<void> _pickRange() async {
    final existing = ref.read(trackDateFilterProvider);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: existing,
    );
    if (picked != null) {
      ref.read(trackDateFilterProvider.notifier).state = picked;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tracks =
        ref.watch(filteredTracksProvider).value ?? const <GpsTrack>[];
    final selection = ref.watch(mapListSelectionProvider(_kSectionKey));
    final range = ref.watch(trackDateFilterProvider);

    return MapListScaffold(
      sectionKey: _kSectionKey,
      title: l10n.gpsTrack_map_title,
      onBackPressed: () => context.go('/gps-log'),
      actions: [
        TextButton.icon(
          key: const ValueKey('gps-track-date-filter'),
          icon: const Icon(Icons.date_range),
          label: Text(
            range == null
                ? l10n.gpsTrack_filter_all
                : '${DateFormat.yMd().format(range.start)} - '
                      '${DateFormat.yMd().format(range.end)}',
          ),
          onPressed: _pickRange,
        ),
        if (range != null)
          IconButton(
            key: const ValueKey('gps-track-date-filter-clear'),
            icon: const Icon(Icons.filter_alt_off_outlined),
            tooltip: l10n.gpsTrack_filter_clear,
            onPressed: () =>
                ref.read(trackDateFilterProvider.notifier).state = null,
          ),
      ],
      listPane: _TrackListPane(
        tracks: tracks,
        selectedId: selection.selectedId,
      ),
      mapPane: tracks.isEmpty
          ? Center(child: Text(l10n.gpsTrack_map_noTracks))
          : _OverviewMap(
              tracks: tracks,
              selectedId: selection.selectedId,
              controller: _mapController,
            ),
    );
  }
}

class _TrackListPane extends ConsumerWidget {
  const _TrackListPane({required this.tracks, required this.selectedId});

  final List<GpsTrack> tracks;
  final String? selectedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return ListView.builder(
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        return ListTile(
          selected: track.id == selectedId,
          leading: GpsTrackThumbnail(trackId: track.id),
          minLeadingWidth: kTrackThumbnailWidth,
          // Wall-clock-as-UTC: render the UTC components directly.
          title: Text(
            DateFormat.yMMMd().add_jm().format(
              DateTime.fromMillisecondsSinceEpoch(track.startTime, isUtc: true),
            ),
          ),
          subtitle: Text('${l10n.gpsTrack_stats_fixes}: ${track.pointCount}'),
          onTap: () => ref
              .read(mapListSelectionProvider(_kSectionKey).notifier)
              .select(track.id),
        );
      },
    );
  }
}

class _OverviewMap extends ConsumerWidget {
  const _OverviewMap({
    required this.tracks,
    required this.selectedId,
    required this.controller,
  });

  final List<GpsTrack> tracks;
  final String? selectedId;
  final MapController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    // Unselected tracks are muted and drawn first; the selected one is drawn
    // last with a thicker stroke so it sits on top of any it overlaps.
    final unselected = <Polyline<String>>[];
    Polyline<String>? selected;
    final allPoints = <GpsTrackPoint>[];

    for (final track in tracks) {
      final geometry =
          ref
              .watch(gpsTrackGeometryProvider((track.id, TrackLod.thumbnail)))
              .value ??
          const <GpsTrackPoint>[];
      if (geometry.length < 2) continue;
      allPoints.addAll(geometry);

      final line = Polyline<String>(
        points: [for (final p in geometry) LatLng(p.latitude, p.longitude)],
        color: track.id == selectedId ? scheme.primary : scheme.outline,
        strokeWidth: track.id == selectedId ? 4.0 : 2.0,
        strokeCap: StrokeCap.round,
        hitValue: track.id,
      );
      if (track.id == selectedId) {
        selected = line;
      } else {
        unselected.add(line);
      }
    }

    final camera = TrackCamera.forPoints(allPoints);
    if (camera == null) {
      return const SizedBox.shrink();
    }

    return TrackpadZoomMap(
      controller: controller,
      child: FlutterMap(
        mapController: controller,
        options: MapOptions(
          initialCameraFit: camera.fit,
          initialCenter: camera.center ?? const LatLng(0, 0),
          initialZoom: camera.zoom ?? 13.0,
        ),
        children: [
          submersionTileLayer(ref),
          PolylineLayer<String>(
            // Selected drawn last so it sits above any track it overlaps.
            polylines: [...unselected, ?selected],
          ),
          const MapAttribution(),
          MapCompassButton(controller: controller),
        ],
      ),
    );
  }
}
