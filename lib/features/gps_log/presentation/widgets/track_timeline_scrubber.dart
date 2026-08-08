import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Whether the scrubber picks a range (trim) or a single instant (split).
enum TrackScrubberMode { range, single }

/// A timeline over a track's span, in wall-clock-as-UTC milliseconds.
///
/// Labels format the UTC components directly - the times belong to the
/// recording device's wall clock, so converting to the viewer's zone would
/// shift every label for anyone reviewing a track from another country.
class TrackTimelineScrubber extends StatefulWidget {
  const TrackTimelineScrubber({
    super.key,
    required this.startMs,
    required this.endMs,
    required this.mode,
    required this.onChanged,
  });

  final int startMs;
  final int endMs;
  final TrackScrubberMode mode;

  /// For [TrackScrubberMode.range], both bounds. For
  /// [TrackScrubberMode.single], the same value is passed twice.
  final void Function(int startMs, int endMs) onChanged;

  @override
  State<TrackTimelineScrubber> createState() => _TrackTimelineScrubberState();
}

class _TrackTimelineScrubberState extends State<TrackTimelineScrubber> {
  late double _low = widget.startMs.toDouble();
  late double _high = widget.endMs.toDouble();
  late double _single = (widget.startMs + (widget.endMs - widget.startMs) / 2)
      .toDouble();

  String _label(num ms) => DateFormat.Hm().format(
    DateTime.fromMillisecondsSinceEpoch(ms.toInt(), isUtc: true),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final min = widget.startMs.toDouble();
    final max = widget.endMs.toDouble();

    // A zero-length span would make the slider assert; show it disabled
    // rather than crashing on a degenerate track.
    if (max <= min) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(_label(min), style: theme.textTheme.labelMedium),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.mode == TrackScrubberMode.range)
          RangeSlider(
            values: RangeValues(_low, _high),
            min: min,
            max: max,
            labels: RangeLabels(_label(_low), _label(_high)),
            onChanged: (v) {
              setState(() {
                _low = v.start;
                _high = v.end;
              });
              widget.onChanged(v.start.toInt(), v.end.toInt());
            },
          )
        else
          Slider(
            value: _single,
            min: min,
            max: max,
            label: _label(_single),
            onChanged: (v) {
              setState(() => _single = v);
              widget.onChanged(v.toInt(), v.toInt());
            },
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_label(min), style: theme.textTheme.labelSmall),
            Text(_label(max), style: theme.textTheme.labelSmall),
          ],
        ),
      ],
    );
  }
}
