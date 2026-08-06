import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:submersion/core/theme/app_colors.dart';
import 'package:submersion/features/dive_log/domain/entities/dive.dart';
import 'package:submersion/l10n/l10n_extension.dart';
import 'package:submersion/features/dive_log/presentation/providers/profile_legend_provider.dart';
import 'package:submersion/features/dive_log/presentation/widgets/chart_options_dialog.dart';

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
    final colorScheme = Theme.of(context).colorScheme;

    // Initialize tank pressures if needed
    if (config.hasMultiTankPressure && config.tankPressures != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        legendNotifier.initializeTankPressures(
          config.tankPressures!.keys.toList(),
        );
      });
    }

    return Padding(
      padding: EdgeInsets.only(left: leftPadding, bottom: 8),
      child: Row(
        children: [
          // Primary toggles + options button flowing together
          Expanded(
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Depth legend (always shown, not a toggle)
                _buildLegendItem(
                  context,
                  color: AppColors.chartDepth,
                  label: context.l10n.diveLog_legend_label_depth,
                ),
                // Temperature toggle (primary)
                if (config.hasTemperatureData)
                  _buildMetricToggle(
                    context,
                    color: colorScheme.tertiary,
                    label: context.l10n.diveLog_legend_label_temp,
                    isEnabled: legendState.showTemperature,
                    onTap: legendNotifier.toggleTemperature,
                  ),
                // Pressure toggle (primary) - only if single tank
                if (config.hasPressureData && !config.hasMultiTankPressure)
                  _buildMetricToggle(
                    context,
                    color: Colors.orange,
                    label: context.l10n.diveLog_legend_label_pressure,
                    isEnabled: legendState.showPressure,
                    onTap: legendNotifier.togglePressure,
                  ),
                // Events toggle (primary)
                if (config.hasEvents)
                  _buildMetricToggle(
                    context,
                    color: Colors.amber,
                    label: context.l10n.diveLog_legend_label_events,
                    isEnabled: legendState.showEvents,
                    onTap: legendNotifier.toggleEvents,
                  ),
                // "More" button flows right after the last toggle
                if (config.hasSecondaryToggles)
                  _MoreOptionsButton(config: config, legendState: legendState),
              ],
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
