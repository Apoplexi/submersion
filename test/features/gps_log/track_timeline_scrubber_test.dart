import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/constants/units.dart';
import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/gps_log/presentation/widgets/track_timeline_scrubber.dart';
import 'package:submersion/features/settings/presentation/providers/settings_providers.dart';

/// The scrubber reads the diver's 12h/24h preference, so it needs settings.
class _TestSettingsNotifier extends StateNotifier<AppSettings>
    implements SettingsNotifier {
  _TestSettingsNotifier(TimeFormat format)
    : super(AppSettings(timeFormat: format));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const int _startMs = 1700000000000;
const int _endMs = 1700003600000;

Future<void> _pump(
  WidgetTester tester, {
  required TrackScrubberMode mode,
  int startMs = _startMs,
  int endMs = _endMs,
  void Function(int, int)? onChanged,
  TimeFormat timeFormat = TimeFormat.twentyFourHour,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith(
          (ref) => _TestSettingsNotifier(timeFormat),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: TrackTimelineScrubber(
            startMs: startMs,
            endMs: endMs,
            mode: mode,
            onChanged: onChanged ?? (_, _) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders a range slider in trim mode', (tester) async {
    await _pump(tester, mode: TrackScrubberMode.range);
    expect(find.byType(RangeSlider), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('renders a single slider in split mode', (tester) async {
    await _pump(tester, mode: TrackScrubberMode.single);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.byType(RangeSlider), findsNothing);
  });

  testWidgets('reports millisecond values, not slider fractions', (
    tester,
  ) async {
    int? reportedStart;
    await _pump(
      tester,
      mode: TrackScrubberMode.range,
      onChanged: (s, _) => reportedStart = s,
    );
    await tester.drag(find.byType(RangeSlider), const Offset(40, 0));
    await tester.pumpAndSettle();

    expect(reportedStart, isNotNull);
    expect(reportedStart, greaterThanOrEqualTo(_startMs));
    expect(reportedStart, lessThanOrEqualTo(_endMs));
  });

  testWidgets('labels the ends with wall-clock times, not device-local', (
    tester,
  ) async {
    // The times belong to the recording device's wall clock; formatting via
    // toLocal() would shift them for anyone reviewing from another zone.
    await _pump(
      tester,
      mode: TrackScrubberMode.range,
      startMs: DateTime.utc(2026, 5, 22, 8).millisecondsSinceEpoch,
      endMs: DateTime.utc(2026, 5, 22, 12).millisecondsSinceEpoch,
    );
    expect(find.text('08:00'), findsOneWidget);
    expect(find.text('12:00'), findsOneWidget);
  });

  testWidgets('labels honour the 12-hour preference', (tester) async {
    // DateFormat.Hm() hardcoded a 24-hour clock, ignoring the setting.
    await _pump(
      tester,
      mode: TrackScrubberMode.range,
      startMs: DateTime.utc(2026, 5, 22, 8).millisecondsSinceEpoch,
      endMs: DateTime.utc(2026, 5, 22, 13).millisecondsSinceEpoch,
      timeFormat: TimeFormat.twelveHour,
    );
    expect(find.text('08:00'), findsNothing);
    expect(find.textContaining('8:00'), findsOneWidget);
    expect(find.textContaining('1:00'), findsOneWidget);
  });

  testWidgets('handles a zero-length span without asserting', (tester) async {
    await _pump(
      tester,
      mode: TrackScrubberMode.range,
      startMs: _startMs,
      endMs: _startMs,
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(RangeSlider), findsNothing);
  });
}
