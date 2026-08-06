import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/media/domain/entities/media_item.dart';
import 'package:submersion/features/media/domain/entities/media_library_filter.dart';
import 'package:submersion/features/media/domain/entities/media_source_type.dart';

void main() {
  test('round-trips every field', () {
    final filter = MediaLibraryFilter(
      mediaType: MediaType.video,
      siteId: 's1',
      tripId: 't1',
      diveId: 'd1',
      fromDate: DateTime(2026, 6, 1),
      toDate: DateTime(2026, 6, 30),
      sourceType: MediaSourceType.localFile,
      health: MediaHealthFilter.unlinked,
    );

    expect(MediaLibraryFilter.fromJson(filter.toJson()), filter);
  });

  test('an empty filter round-trips to none', () {
    expect(
      MediaLibraryFilter.fromJson(MediaLibraryFilter.none.toJson()),
      MediaLibraryFilter.none,
    );
  });

  test('unknown enum values decode to null rather than throwing', () {
    final decoded = MediaLibraryFilter.fromJson({
      'mediaType': 'hologram',
      'health': 'exploded',
      'sourceType': 'telepathy',
    });
    expect(decoded.mediaType, isNull);
    expect(decoded.health, isNull);
    expect(decoded.sourceType, isNull);
  });

  test('malformed dates decode to null rather than throwing', () {
    final decoded = MediaLibraryFilter.fromJson({
      'fromDate': 'yesterday',
      'toDate': null,
    });
    expect(decoded.fromDate, isNull);
    expect(decoded.toDate, isNull);
  });

  test('dates serialize as epoch millis', () {
    final filter = MediaLibraryFilter(fromDate: DateTime(2026, 6, 1));
    expect(
      filter.toJson()['fromDate'],
      DateTime(2026, 6, 1).millisecondsSinceEpoch,
    );
  });
}
