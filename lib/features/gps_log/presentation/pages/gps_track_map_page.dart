import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/core/utils/unit_formatter.dart';
import 'package:submersion/features/gps_log/data/repositories/track_geometry_cache_repository.dart';
import 'package:submersion/features/gps_log/domain/entities/gps_track.dart';
import 'package:submersion/features/gps_log/presentation/providers/gps_track_map_providers.dart';
import 'package:submersion/features/gps_log/presentation/widgets/gps_track_thumbnail.dart';
import 'package:submersion/features/gps_log/presentation/widgets/track_camera.dart';
import 'package:submersion/features/gps_log/presentation/widgets/track_row_labels.dart';
import 'package:submersion/features/maps/presentation/widgets/map_attribution.dart';
import 'package:submersion/features/maps/presentation/widgets/map_compass_button.dart';
import 'package:submersion/features/maps/presentation/widgets/map_interaction_options.dart';
import 'package:submersion/features/maps/presentation/widgets/submersion_tile_layer.dart';
import 'package:submersion/features/maps/presentation/widgets/trackpad_zoom_map.dart';
import 'package:submersion/features/settings/presentation/providers/settings_providers.dart';
import 'package:submersion/l10n/l10n_extension.dart';
import 'package:submersion/shared/providers/map_list_selection_provider.dart';
import 'package:submersion/shared/widgets/app_date_picker.dart';
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
    final picked = await showAppDateRangePicker(
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
    // Capped: every track drawn here hydrates a full point blob and, on a cold
    // cache, spawns its own simplification isolate.
    final tracksAsync = ref.watch(overviewTracksProvider);
    final tracks = tracksAsync.value ?? const <GpsTrack>[];
    final truncated = ref.watch(overviewTracksTruncatedProvider);
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
        truncatedNotice: truncated
            ? l10n.gpsTrack_map_truncated(kOverviewTrackLimit)
            : null,
      ),
      // Distinguish "still loading" from "genuinely none": reading
      // `value ?? []` as authoritative flashed "No recorded tracks" on every
      // cold open and after every filter change, and showed the same message
      // when the query had actually failed.
      mapPane: switch (tracksAsync) {
        AsyncLoading() when tracks.isEmpty => const Center(
          child: CircularProgressIndicator(),
        ),
        AsyncError() => Center(child: Text(l10n.common_error_tryAgain)),
        _ when tracks.isEmpty => Center(
          child: Text(l10n.gpsTrack_map_noTracks),
        ),
        _ => _OverviewMap(
          tracks: tracks,
          selectedId: selection.selectedId,
          controller: _mapController,
        ),
      },
    );
  }
}

class _TrackListPane extends ConsumerWidget {
  const _TrackListPane({
    required this.tracks,
    required this.selectedId,
    this.truncatedNotice,
  });

  final List<GpsTrack> tracks;
  final String? selectedId;

  /// Set when the cap dropped tracks the date filter allowed.
  final String? truncatedNotice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final units = UnitFormatter(ref.watch(settingsProvider));
    final notice = truncatedNotice;
    return ListView.builder(
      // The notice occupies index 0 so it scrolls with the rows rather than
      // stealing height from a narrow list pane.
      itemCount: tracks.length + (notice == null ? 0 : 1),
      itemBuilder: (context, index) {
        if (notice != null) {
          if (index == 0) {
            return Padding(
              key: const ValueKey('gps-track-truncated-notice'),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                notice,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            );
          }
          index -= 1;
        }
        final track = tracks[index];
        return ListTile(
          // See gps_logger_page: an unkeyed recycled row keeps the previous
          // track's map camera.
          key: ValueKey(track.id),
          selected: track.id == selectedId,
          leading: GpsTrackThumbnail(trackId: track.id),
          minLeadingWidth: kTrackThumbnailWidth,
          title: Text(formatTrackStart(units, track)),
          subtitle: Text(
            formatTrackSubtitle(l10n, track, formatTrackDuration(track)),
          ),
          onTap: () => ref
              .read(mapListSelectionProvider(_kSectionKey).notifier)
              .select(track.id),
        );
      },
    );
  }
}

class _OverviewMap extends ConsumerStatefulWidget {
  const _OverviewMap({
    required this.tracks,
    required this.selectedId,
    required this.controller,
  });

  final List<GpsTrack> tracks;
  final String? selectedId;
  final MapController controller;

  @override
  ConsumerState<_OverviewMap> createState() => _OverviewMapState();
}

class _OverviewMapState extends ConsumerState<_OverviewMap> {
  bool _mapReady = false;

  /// Signature of the framing currently applied, so a filter change or a
  /// late-arriving simplify re-frames but an unrelated rebuild does not.
  String? _framedOn;

  List<GpsTrack> get tracks => widget.tracks;
  String? get selectedId => widget.selectedId;
  MapController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
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

    // Re-frame when the visible set changes: the date filter narrowing, a
    // selection promoting a track, or a per-track simplify finishing. A
    // FutureProvider reload keeps its previous value, so the map never
    // unmounts and initialCameraFit would never apply again.
    final signature = '${tracks.length}:${allPoints.length}:$selectedId';
    if (_mapReady && _framedOn != signature) {
      _framedOn = signature;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) camera.applyTo(controller);
      });
    }

    return TrackpadZoomMap(
      controller: controller,
      child: FlutterMap(
        mapController: controller,
        options: MapOptions(
          onMapReady: () {
            _mapReady = true;
            _framedOn = signature;
          },
          initialCameraFit: camera.fit,
          initialCenter: camera.center ?? const LatLng(0, 0),
          initialZoom: camera.zoom ?? 13.0,
          interactionOptions: rotatableMapInteraction,
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
