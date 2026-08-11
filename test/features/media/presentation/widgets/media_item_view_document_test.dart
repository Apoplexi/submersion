import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/media/domain/entities/media_item.dart';
import 'package:submersion/features/media/domain/value_objects/media_source_data.dart';
import 'package:submersion/features/media/presentation/widgets/media_item_view.dart';

import '../support/media_widget_harness.dart';

/// Document attachments resolve to raw document bytes that `Image.file` /
/// `Image.memory` cannot decode, so [MediaItemView] must divert them to its
/// document placeholder before they ever reach an Image widget.
///
/// Every file written here holds a *decodable* 1x1 PNG regardless of its
/// name: that keeps the assertions honest about what the branch is gated on
/// (`item.isDocument`, not "these bytes happen to be undecodable").
void main() {
  late Directory tempDir;
  late File pdfFile;
  late File txtFile;
  late File pngFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('media_item_view_doc');
    final bytes = onePixelPng();
    pdfFile = File('${tempDir.path}/reef-map.pdf')..writeAsBytesSync(bytes);
    txtFile = File('${tempDir.path}/dive-notes.txt')..writeAsBytesSync(bytes);
    pngFile = File('${tempDir.path}/reef.png')..writeAsBytesSync(bytes);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> pumpView(
    WidgetTester tester, {
    required MediaItem item,
    MediaSourceData? resolverData,
  }) async {
    await tester.pumpWidget(
      await mediaTestApp(
        resolverData: resolverData,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 120,
              height: 120,
              child: MediaItemView(item: item),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  MediaItem document(String? filename) => testMediaItem(
    id: 'doc-1',
    mediaType: MediaType.document,
    originalFilename: filename,
  );

  testWidgets('a PDF resolving to FileData draws the PDF placeholder, '
      'never an Image', (tester) async {
    await pumpView(
      tester,
      item: document('reef-map.pdf'),
      resolverData: FileData(file: pdfFile),
    );

    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
    expect(find.text('reef-map.pdf'), findsOneWidget);
    // The bytes behind that path decode fine; the diversion is by media type.
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('a non-PDF document resolving to FileData draws the generic '
      'description icon', (tester) async {
    await pumpView(
      tester,
      item: document('dive-notes.txt'),
      resolverData: FileData(file: txtFile),
    );

    expect(find.byIcon(Icons.description_outlined), findsOneWidget);
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsNothing);
    expect(find.text('dive-notes.txt'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('a PDF resolving to BytesData draws the placeholder instead of '
      'Image.memory', (tester) async {
    await pumpView(
      tester,
      item: document('reef-map.pdf'),
      resolverData: BytesData(bytes: onePixelPng()),
    );

    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
    expect(find.text('reef-map.pdf'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('a non-PDF document resolving to BytesData draws the generic '
      'description icon', (tester) async {
    await pumpView(
      tester,
      item: document('dive-notes.txt'),
      resolverData: BytesData(bytes: onePixelPng()),
    );

    expect(find.byIcon(Icons.description_outlined), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('the filename caption is omitted when originalFilename is null', (
    tester,
  ) async {
    await pumpView(
      tester,
      item: document(null),
      resolverData: FileData(file: pdfFile),
    );

    // Extensionless (no name at all) reads as a generic document, and the
    // placeholder is icon-only: no empty caption row.
    expect(find.byIcon(Icons.description_outlined), findsOneWidget);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('a photo resolving to the same file still renders an Image', (
    tester,
  ) async {
    // Control for the two document tests above: identical resolution, photo
    // media type, so the switch falls through to Image.file.
    await pumpView(
      tester,
      item: testMediaItem(originalFilename: 'reef.png'),
      resolverData: FileData(file: pngFile),
    );

    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsNothing);
    expect(find.byIcon(Icons.description_outlined), findsNothing);
  });
}
