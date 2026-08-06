import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/media/domain/entities/media_item.dart';
import 'package:submersion/features/media/domain/entities/media_library_filter.dart';
import 'package:submersion/features/media/domain/entities/media_source_type.dart';
import 'package:submersion/features/media/presentation/widgets/media_library_groupers.dart';

MediaLibraryEntry entry(
  String id, {
  String? diveId,
  int? diveNumber,
  String? siteName,
  DateTime? takenAt,
}) => MediaLibraryEntry(
  item: MediaItem(
    id: id,
    diveId: diveId,
    mediaType: MediaType.photo,
    sourceType: MediaSourceType.localFile,
    filePath: '/tmp/$id',
    takenAt: takenAt ?? DateTime(2026, 6, 1),
    createdAt: takenAt ?? DateTime(2026, 6, 1),
    updatedAt: takenAt ?? DateTime(2026, 6, 1),
  ),
  diveNumber: diveNumber,
  siteName: siteName,
  diveDateTime: takenAt,
);

void main() {
  group('groupByDive', () {
    test('groups by diveId preserving first-seen order, unlinked last', () {
      final e1 = entry('e1', diveId: 'A', diveNumber: 9, siteName: 'Reef');
      final e2 = entry('e2', diveId: 'A', diveNumber: 9, siteName: 'Reef');
      final e3 = entry('e3', diveId: 'B', diveNumber: 8);
      final e4 = entry('e4');
      final e5 = entry('e5', diveId: 'A', diveNumber: 9, siteName: 'Reef');

      final groups = groupByDive([e1, e2, e3, e4, e5]);

      expect(groups, hasLength(3));
      final headers = groups
          .map((g) => (g.header as DiveGroupHeader).diveId)
          .toList();
      expect(headers, ['A', 'B', null]);
      expect(groups[0].entries, [e1, e2, e5]);
      expect(groups[1].entries, [e3]);
      expect(groups[2].entries, [e4]);

      final headerA = groups[0].header as DiveGroupHeader;
      expect(headerA.diveNumber, 9);
      expect(headerA.siteName, 'Reef');
    });

    test('no unlinked group when everything is linked', () {
      final groups = groupByDive([entry('e1', diveId: 'A')]);
      expect(groups, hasLength(1));
      expect((groups.single.header as DiveGroupHeader).diveId, 'A');
    });
  });

  group('groupByTimeline', () {
    test('groups by day with month starts computed per group', () {
      final e1 = entry('e1', takenAt: DateTime(2026, 6, 12, 10));
      final e2 = entry('e2', takenAt: DateTime(2026, 6, 12, 9));
      final e3 = entry('e3', takenAt: DateTime(2026, 6, 11, 15));
      final e4 = entry('e4', takenAt: DateTime(2026, 5, 3, 8));

      final groups = groupByTimeline([e1, e2, e3, e4]);

      expect(groups, hasLength(3));
      final h0 = groups[0].header as DateGroupHeader;
      final h1 = groups[1].header as DateGroupHeader;
      final h2 = groups[2].header as DateGroupHeader;

      expect(h0.dayStart, DateTime(2026, 6, 12));
      expect(h0.monthStart, DateTime(2026, 6));
      expect(groups[0].entries, [e1, e2]);

      expect(h1.dayStart, DateTime(2026, 6, 11));
      expect(h1.monthStart, DateTime(2026, 6));
      expect(groups[1].entries, [e3]);

      expect(h2.dayStart, DateTime(2026, 5, 3));
      expect(h2.monthStart, DateTime(2026, 5));
      expect(groups[2].entries, [e4]);
    });

    test('day buckets use local time of the sort timestamp', () {
      final utcEvening = entry(
        'e1',
        takenAt: DateTime.utc(2026, 6, 12, 23, 30),
      );
      final groups = groupByTimeline([utcEvening]);
      final header = groups.single.header as DateGroupHeader;
      final local = DateTime.utc(2026, 6, 12, 23, 30).toLocal();
      expect(header.dayStart, DateTime(local.year, local.month, local.day));
    });
  });
}
