import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:submersion/core/theme/app_colors.dart';
import 'package:submersion/features/dive_log/domain/entities/dive.dart';
import 'package:submersion/l10n/l10n_extension.dart';
import 'package:submersion/features/dive_log/presentation/providers/profile_legend_provider.dart';
import 'package:submersion/features/dive_log/presentation/widgets/chart_options_dialog.dart';
import 'package:submersion/features/dive_log/presentation/widgets/deco_stop_band.dart';
import 'package:submersion/features/dive_log/presentation/widgets/gas_colors.dart';
import 'package:submersion/features/dive_log/presentation/widgets/legend_candidates.dart';

/// Configuration for what data is available in the chart.
/// This determines which toggles appear in the legend.
class ProfileLegendConfig {
  final bool hasTemperatureData;
  final bool hasPressureData;
  final bool hasHeartRateData;
  final bool hasSacCurve;
  final bool hasCeilingCurve;
  final bool hasDecoStopCurve;
  final bool hasAscentRates;
  final bool hasEvents;
  final bool hasMaxDepthMarker;
  final bool hasPressureMarkers;
  final bool hasGasSwitches;
  final bool hasPhotoMarkers;
  final bool hasMultiTankPressure;
  final bool hasGasData;
  final List<DiveTank>? tanks;
  final Map<String, List<TankPressurePoint>>? tankPressures;

  /// Tank IDs whose pressure series is a synthesized linear estimate (#197),
  /// labelled with a "(est.)" suffix in the Tank Pressures section.
  final Set<String> estimatedTankIds;

  // Advanced decompression/gas data availability
  final bool hasNdlData;
  final bool hasPpO2Data;
  final bool hasPpN2Data;
  final bool hasPpHeData;
  final bool hasModData;
  final bool hasDensityData;
  final bool hasGfData;
  final bool hasSurfaceGfData;
  final bool hasMeanDepthData;
  final bool hasTtsData;
  final bool hasCnsData;
  final bool hasOtuData;
  const ProfileLegendConfig({
    this.hasTemperatureData = false,
    this.hasPressureData = false,
    this.hasHeartRateData = false,
    this.hasSacCurve = false,
    this.hasCeilingCurve = false,
    this.hasDecoStopCurve = false,
    this.hasAscentRates = false,
    this.hasEvents = false,
    this.hasMaxDepthMarker = false,
    this.hasPressureMarkers = false,
    this.hasGasSwitches = false,
    this.hasPhotoMarkers = false,
    this.hasMultiTankPressure = false,
    this.hasGasData = false,
    this.tanks,
    this.tankPressures,
    this.estimatedTankIds = const {},
    this.hasNdlData = false,
    this.hasPpO2Data = false,
    this.hasPpN2Data = false,
    this.hasPpHeData = false,
    this.hasModData = false,
    this.hasDensityData = false,
    this.hasGfData = false,
    this.hasSurfaceGfData = false,
    this.hasMeanDepthData = false,
    this.hasTtsData = false,
    this.hasCnsData = false,
    this.hasOtuData = false,
  });

  bool get hasTankListSection =>
      hasGasSwitches && !hasMultiTankPressure && (tanks?.length ?? 0) > 1;

  /// Whether any secondary toggles should be shown
  bool get hasSecondaryToggles =>
      hasCeilingCurve ||
      hasDecoStopCurve ||
      hasHeartRateData ||
      hasSacCurve ||
      hasAscentRates ||
      hasMaxDepthMarker ||
      hasPressureMarkers ||
      hasGasSwitches ||
      hasPhotoMarkers ||
      hasTankListSection ||
      hasGasData ||
      hasMultiTankPressure ||
      hasNdlData ||
      hasPpO2Data ||
      hasPpN2Data ||
      hasPpHeData ||
      hasModData ||
      hasDensityData ||
      hasGfData ||
      hasSurfaceGfData ||
      hasMeanDepthData ||
      hasTtsData ||
      hasCnsData ||
      hasOtuData;
}

/// Legend widget for the dive profile chart.
///
/// Displays primary toggles inline and secondary toggles in a popover menu.
/// Also includes zoom controls.
class DiveProfileLegend extends ConsumerWidget {
  final ProfileLegendConfig config;
  final double zoomLevel;
  final double minZoom;
  final double maxZoom;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onResetZoom;
  final double leftPadding;

  const DiveProfileLegend({
    super.key,
    required this.config,
    required this.zoomLevel,
    this.minZoom = 1.0,
    this.maxZoom = 10.0,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onResetZoom,
    this.leftPadding = 0.0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final legendState = ref.watch(profileLegendProvider);
    final legendNotifier = ref.read(profileLegendProvider.notifier);

    // Initialize tank pressures if needed
    if (config.hasMultiTankPressure && config.tankPressures != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        legendNotifier.initializeTankPressures(
          config.tankPressures!.keys.toList(),
        );
      });
    }

    final candidates = _buildCandidates(context, legendState, legendNotifier);
    final showMoreButton = candidates.isNotEmpty || config.hasTankListSection;

    return Padding(
      padding: EdgeInsets.only(left: leftPadding, bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final depthLabel = context.l10n.diveLog_legend_label_depth;
                final reserved =
                    _depthChromeWidth +
                    _labelWidth(context, depthLabel) +
                    _itemSpacing +
                    (showMoreButton ? _moreButtonWidth : 0) +
                    _safetyMargin;
                final admitted = selectInlineCandidates(
                  candidates: candidates,
                  availableWidth: constraints.maxWidth - reserved,
                  itemWidth: (c) =>
                      _toggleChromeWidth +
                      _labelWidth(context, c.label) +
                      _itemSpacing,
                );
                // The admitted set is measured to fit, so this scroll view
                // never actually scrolls; it exists to clip gracefully in
                // degenerate over-constrained layouts instead of throwing
                // RenderFlex overflow errors.
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  child: Row(
                    children: [
                      _buildLegendItem(
                        context,
                        color: AppColors.chartDepth,
                        label: depthLabel,
                      ),
                      for (final candidate in admitted) ...[
                        const SizedBox(width: _itemSpacing),
                        _buildMetricToggle(
                          context,
                          color: candidate.color,
                          label: candidate.label,
                          isEnabled: candidate.isActive,
                          onTap: candidate.onTap,
                        ),
                      ],
                      if (showMoreButton) ...[
                        const SizedBox(width: _itemSpacing),
                        _MoreOptionsButton(
                          config: config,
                          legendState: legendState,
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 4),
          // Zoom controls
          _ZoomControls(
            zoomLevel: zoomLevel,
            minZoom: minZoom,
            maxZoom: maxZoom,
            onZoomIn: onZoomIn,
            onZoomOut: onZoomOut,
            onResetZoom: onResetZoom,
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(
    BuildContext context, {
    required Color color,
    required String label,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 3),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }

  // Geometry of one inline toggle as built by _buildMetricToggle below:
  // horizontal padding 2+2, checkbox icon 14, gap 2, swatch 10, gap 3,
  // then the label text. _toggleChromeWidth MUST change in lockstep with
  // any visual edit to _buildMetricToggle.
  static const double _toggleChromeWidth = 2 + 2 + 14 + 2 + 10 + 3;

  // Geometry of the always-shown depth legend item (_buildLegendItem):
  // swatch 10, gap 3, label text.
  static const double _depthChromeWidth = 10 + 3;

  static const double _itemSpacing = 4;
  static const double _moreButtonWidth = 32;
  static const double _safetyMargin = 8;

  double _labelWidth(BuildContext context, String label) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: Theme.of(context).textTheme.labelSmall,
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  /// Builds every toggle available for this dive, in canonical display order
  /// (priority = list position). See the design spec for the ranking
  /// rationale: profile essentials first, deco metrics next, per-gas
  /// analysis and markers last.
  List<LegendCandidate> _buildCandidates(
    BuildContext context,
    ProfileLegendState state,
    ProfileLegend notifier,
  ) {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;
    final candidates = <LegendCandidate>[];

    void add({
      required bool present,
      required String id,
      required String label,
      required Color color,
      required bool isActive,
      required VoidCallback onTap,
    }) {
      if (!present) return;
      candidates.add(
        LegendCandidate(
          id: id,
          label: label,
          color: color,
          isActive: isActive,
          priority: candidates.length,
          onTap: onTap,
        ),
      );
    }

    add(
      present: config.hasTemperatureData,
      id: 'temperature',
      label: l10n.diveLog_legend_label_temp,
      color: colorScheme.tertiary,
      isActive: state.showTemperature,
      onTap: notifier.toggleTemperature,
    );
    add(
      present: config.hasPressureData && !config.hasMultiTankPressure,
      id: 'pressure',
      label: l10n.diveLog_legend_label_pressure,
      color: Colors.orange,
      isActive: state.showPressure,
      onTap: notifier.togglePressure,
    );
    if (config.hasMultiTankPressure && config.tankPressures != null) {
      final sortedIds = sortTankIdsByOrder(
        config.tankPressures!.keys,
        config.tanks,
      );
      for (var i = 0; i < sortedIds.length; i++) {
        final tankId = sortedIds[i];
        DiveTank? tank;
        for (final t in config.tanks ?? const <DiveTank>[]) {
          if (t.id == tankId) tank = t;
        }
        final baseLabel = tank != null
            ? tankLegendLabel(context, tank, fallbackIndex: i + 1)
            : l10n.diveLog_tank_title(i + 1);
        add(
          present: true,
          id: 'tank:$tankId',
          label: config.estimatedTankIds.contains(tankId)
              ? '$baseLabel ${l10n.diveLog_pressure_estimatedSuffix}'
              : baseLabel,
          color: tank != null
              ? GasColors.forGasMix(tank.gasMix)
              : tankFallbackColor(i),
          isActive: state.showTankPressure[tankId] ?? true,
          onTap: () => notifier.toggleTankPressure(tankId),
        );
      }
    }
    add(
      present: config.hasEvents,
      id: 'events',
      label: l10n.diveLog_legend_label_events,
      color: Colors.amber,
      isActive: state.showEvents,
      onTap: notifier.toggleEvents,
    );
    add(
      present: config.hasCeilingCurve,
      id: 'ceiling',
      label: l10n.diveLog_legend_label_ceiling,
      color: const Color(0xFFD32F2F),
      isActive: state.showCeiling,
      onTap: notifier.toggleCeiling,
    );
    add(
      present: config.hasDecoStopCurve,
      id: 'decoStops',
      label: l10n.diveLog_legend_label_decoStops,
      color: decoStopBandColor,
      isActive: state.showDecoStops,
      onTap: notifier.toggleDecoStops,
    );
    add(
      present: config.hasNdlData,
      id: 'ndl',
      label: l10n.diveLog_legend_label_ndl,
      color: Colors.yellow.shade700,
      isActive: state.showNdl,
      onTap: notifier.toggleNdl,
    );
    add(
      present: config.hasGasSwitches,
      id: 'gasSwitches',
      label: l10n.diveLog_legend_label_gasSwitches,
      color: GasColors.nitrox,
      isActive: state.showGasSwitchMarkers,
      onTap: notifier.toggleGasSwitchMarkers,
    );
    add(
      present: config.hasSacCurve,
      id: 'sac',
      label: l10n.diveLog_legend_label_sacRate,
      color: Colors.teal,
      isActive: state.showSac,
      onTap: notifier.toggleSac,
    );
    add(
      present: config.hasHeartRateData,
      id: 'heartRate',
      label: l10n.diveLog_legend_label_heartRate,
      color: Colors.red,
      isActive: state.showHeartRate,
      onTap: notifier.toggleHeartRate,
    );
    add(
      present: config.hasAscentRates,
      id: 'ascentRateColors',
      label: l10n.diveLog_legend_label_ascentRate,
      color: Colors.lime.shade700,
      isActive: state.showAscentRateColors,
      onTap: notifier.toggleAscentRateColors,
    );
    add(
      present: config.hasAscentRates,
      id: 'ascentRateLine',
      label: l10n.diveLog_legend_label_ascentRateLine,
      color: Colors.lime,
      isActive: state.showAscentRateLine,
      onTap: notifier.toggleAscentRateLine,
    );
    add(
      present: config.hasMaxDepthMarker,
      id: 'maxDepth',
      label: l10n.diveLog_legend_label_maxDepth,
      color: Colors.red,
      isActive: state.showMaxDepthMarker,
      onTap: notifier.toggleMaxDepthMarker,
    );
    add(
      present: config.hasTtsData,
      id: 'tts',
      label: l10n.diveLog_legend_label_tts,
      color: const Color(0xFFAD1457),
      isActive: state.showTts,
      onTap: notifier.toggleTts,
    );
    add(
      present: config.hasCnsData,
      id: 'cns',
      label: l10n.diveLog_legend_label_cns,
      color: const Color(0xFFE65100),
      isActive: state.showCns,
      onTap: notifier.toggleCns,
    );
    add(
      present: config.hasMeanDepthData,
      id: 'meanDepth',
      label: l10n.diveLog_legend_label_meanDepth,
      color: Colors.blueGrey,
      isActive: state.showMeanDepth,
      onTap: notifier.toggleMeanDepth,
    );
    add(
      present: config.hasGfData,
      id: 'gf',
      label: l10n.diveLog_legend_label_gfPercent,
      color: Colors.deepPurple,
      isActive: state.showGf,
      onTap: notifier.toggleGf,
    );
    add(
      present: config.hasSurfaceGfData,
      id: 'surfaceGf',
      label: l10n.diveLog_legend_label_surfaceGf,
      color: Colors.purple.shade300,
      isActive: state.showSurfaceGf,
      onTap: notifier.toggleSurfaceGf,
    );
    add(
      present: config.hasPpO2Data,
      id: 'ppO2',
      label: l10n.diveLog_legend_label_ppO2,
      color: const Color(0xFF00ACC1),
      isActive: state.showPpO2,
      onTap: notifier.togglePpO2,
    );
    add(
      present: config.hasPpN2Data,
      id: 'ppN2',
      label: l10n.diveLog_legend_label_ppN2,
      color: Colors.indigo,
      isActive: state.showPpN2,
      onTap: notifier.togglePpN2,
    );
    add(
      present: config.hasPpHeData,
      id: 'ppHe',
      label: l10n.diveLog_legend_label_ppHe,
      color: Colors.pink.shade300,
      isActive: state.showPpHe,
      onTap: notifier.togglePpHe,
    );
    add(
      present: config.hasModData,
      id: 'mod',
      label: l10n.diveLog_legend_label_mod,
      color: Colors.deepOrange,
      isActive: state.showMod,
      onTap: notifier.toggleMod,
    );
    add(
      present: config.hasDensityData,
      id: 'density',
      label: l10n.diveLog_legend_label_gasDensity,
      color: Colors.brown,
      isActive: state.showDensity,
      onTap: notifier.toggleDensity,
    );
    add(
      present: config.hasOtuData,
      id: 'otu',
      label: l10n.diveLog_legend_label_otu,
      color: const Color(0xFF6D4C41),
      isActive: state.showOtu,
      onTap: notifier.toggleOtu,
    );
    add(
      present: config.hasPressureMarkers,
      id: 'pressureMarkers',
      label: l10n.diveLog_legend_label_pressureThresholds,
      color: Colors.orange,
      isActive: state.showPressureMarkers,
      onTap: notifier.togglePressureMarkers,
    );
    add(
      present: config.hasPhotoMarkers,
      id: 'photoMarkers',
      label: l10n.diveLog_legend_label_photoMarkers,
      color: Colors.cyan,
      isActive: state.showPhotoMarkers,
      onTap: notifier.togglePhotoMarkers,
    );
    add(
      present: config.hasGasData,
      id: 'gasTimeline',
      label: l10n.diveLog_legend_label_showGas,
      color: GasColors.nitrox,
      isActive: state.showGas,
      onTap: notifier.toggleGas,
    );
    return candidates;
  }

  Widget _buildMetricToggle(
    BuildContext context, {
    required Color color,
    required String label,
    required bool isEnabled,
    required VoidCallback onTap,
  }) {
    return Semantics(
      toggled: isEnabled,
      label: '$label ${isEnabled ? 'enabled' : 'disabled'}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isEnabled ? Icons.check_box : Icons.check_box_outline_blank,
                size: 14,
                color: isEnabled
                    ? color
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 2),
              Container(
                width: 10,
                height: 3,
                decoration: BoxDecoration(
                  color: isEnabled ? color : color.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 3),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: isEnabled
                      ? null
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Button that shows badge with active secondary toggle count and opens popover
class _MoreOptionsButton extends ConsumerWidget {
  final ProfileLegendConfig config;
  final ProfileLegendState legendState;

  const _MoreOptionsButton({required this.config, required this.legendState});

  int get _activeSecondaryCount {
    var count = 0;
    if (config.hasHeartRateData && legendState.showHeartRate) count++;
    if (config.hasSacCurve && legendState.showSac) count++;
    if (config.hasAscentRates && legendState.showAscentRateColors) count++;
    if (config.hasAscentRates && legendState.showAscentRateLine) count++;
    if (config.hasMaxDepthMarker && legendState.showMaxDepthMarker) count++;
    if (config.hasPressureMarkers && legendState.showPressureMarkers) count++;
    if (config.hasGasSwitches && legendState.showGasSwitchMarkers) count++;
    if (config.hasPhotoMarkers && legendState.showPhotoMarkers) count++;

    // Advanced deco/gas toggles
    if (config.hasCeilingCurve && legendState.showCeiling) count++;
    if (config.hasDecoStopCurve && legendState.showDecoStops) count++;
    if (config.hasNdlData && legendState.showNdl) count++;
    if (config.hasPpO2Data && legendState.showPpO2) count++;
    if (config.hasPpN2Data && legendState.showPpN2) count++;
    if (config.hasPpHeData && legendState.showPpHe) count++;
    if (config.hasModData && legendState.showMod) count++;
    if (config.hasDensityData && legendState.showDensity) count++;
    if (config.hasGfData && legendState.showGf) count++;
    if (config.hasSurfaceGfData && legendState.showSurfaceGf) count++;
    if (config.hasMeanDepthData && legendState.showMeanDepth) count++;
    if (config.hasTtsData && legendState.showTts) count++;
    if (config.hasCnsData && legendState.showCns) count++;
    if (config.hasOtuData && legendState.showOtu) count++;
    if (config.hasGasData && legendState.showGas) count++;

    // Count active tank pressure toggles
    if (config.hasMultiTankPressure && config.tankPressures != null) {
      for (final tankId in config.tankPressures!.keys) {
        if (legendState.showTankPressure[tankId] ?? true) count++;
      }
    }

    return count;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeCount = _activeSecondaryCount;

    return IconButton(
      onPressed: () => _showMoreOptions(context),
      icon: Badge(
        isLabelVisible: activeCount > 0,
        label: Text(
          activeCount.toString(),
          style: const TextStyle(fontSize: 10),
        ),
        child: const Icon(Icons.tune, size: 18),
      ),
      tooltip: context.l10n.diveLog_profile_tooltip_moreOptions,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      style: IconButton.styleFrom(
        foregroundColor: activeCount > 0
            ? colorScheme.primary
            : colorScheme.onSurfaceVariant,
      ),
    );
  }

  void _showMoreOptions(BuildContext context) {
    final renderBox = context.findRenderObject() as RenderBox;
    final buttonOffset = renderBox.localToGlobal(Offset.zero);
    final buttonSize = renderBox.size;

    showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (dialogContext) => ChartOptionsDialog(
        config: config,
        anchorOffset: buttonOffset,
        anchorSize: buttonSize,
      ),
    );
  }
}

/// Zoom controls widget
class _ZoomControls extends StatelessWidget {
  final double zoomLevel;
  final double minZoom;
  final double maxZoom;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onResetZoom;

  const _ZoomControls({
    required this.zoomLevel,
    required this.minZoom,
    required this.maxZoom,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onResetZoom,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isZoomed = zoomLevel > 1.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Zoom out button
        IconButton(
          onPressed: zoomLevel > minZoom ? onZoomOut : null,
          icon: const Icon(Icons.remove),
          iconSize: 18,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          tooltip: context.l10n.diveLog_profile_tooltip_zoomOut,
        ),
        // Zoom level indicator
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            '${zoomLevel.toStringAsFixed(1)}x',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
              color: isZoomed
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        // Zoom in button
        IconButton(
          onPressed: zoomLevel < maxZoom ? onZoomIn : null,
          icon: const Icon(Icons.add),
          iconSize: 18,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          tooltip: context.l10n.diveLog_profile_tooltip_zoomIn,
        ),
        // Reset zoom / fit button
        if (isZoomed)
          IconButton(
            onPressed: onResetZoom,
            icon: const Icon(Icons.fit_screen),
            iconSize: 18,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: context.l10n.diveLog_profile_tooltip_resetZoom,
          ),
      ],
    );
  }
}
