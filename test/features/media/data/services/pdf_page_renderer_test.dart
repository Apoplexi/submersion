import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';
import 'package:submersion/features/media/data/services/pdf_page_renderer.dart';

/// pdfium cannot load under flutter_test: the Flutter path needs the
/// bundled plugin binary (not present in the test harness) and the Dart
/// path needs either the PDFIUM_PATH environment variable or dart
/// native-assets support (flutter_test provides neither). Worse, a failed
/// engine init crashes pdfrx's background worker isolate, which hangs the
/// calling future to timeout rather than throwing. So these tests only
/// run when the host explicitly provides a pdfium build via PDFIUM_PATH;
/// the in-app runtime always has the bundled plugin binary. Exercised by
/// manual desktop smoke tests otherwise.
final _pdfiumAvailable = () {
  final path = Platform.environment['PDFIUM_PATH'];
  return path != null && File(path).existsSync();
}();

void main() {
  setUpAll(() {
    // Pure-Dart initializer: picks up PDFIUM_PATH.
    PdfPageRenderer.initializer = pdfrxInitialize;
  });

  test(
    'renders first page of a pdf to a jpeg within maxDimension',
    () async {
      final bytes = await PdfPageRenderer.renderFirstPageJpeg(
        file: File('test/fixtures/sample.pdf'),
        maxDimension: 256,
      );
      expect(bytes, isNotNull);
      final decoded = img.decodeJpg(bytes!);
      expect(decoded, isNotNull);
      expect(
        decoded!.width <= 256 && decoded.height <= 256,
        isTrue,
        reason: 'longest edge must be capped',
      );
    },
    skip: _pdfiumAvailable ? false : 'needs PDFIUM_PATH (see header note)',
  );

  test(
    'returns null for garbage bytes',
    () async {
      final bytes = await PdfPageRenderer.renderFirstPageJpeg(
        bytes: Uint8List.fromList([1, 2, 3]),
      );
      expect(bytes, isNull);
    },
    skip: _pdfiumAvailable ? false : 'needs PDFIUM_PATH (see header note)',
  );
}
