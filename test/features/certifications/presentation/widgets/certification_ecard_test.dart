import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/constants/enums.dart';
import 'package:submersion/features/certifications/domain/entities/certification.dart';
import 'package:submersion/features/certifications/presentation/widgets/certification_card_photo.dart';
import 'package:submersion/features/certifications/presentation/widgets/certification_ecard.dart';

import '../../../../helpers/l10n_test_helpers.dart';

/// A valid 1x1 transparent PNG, so the image decoder has real bytes.
final _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGA'
  'hKmMIQAAAABJRU5ErkJggg==',
);

final _now = DateTime(2026, 8, 9);

Certification _makeCert({
  String name = 'Open Water Diver',
  CertificationAgency agency = CertificationAgency.padi,
  String? cardNumber,
  DateTime? issueDate,
  DateTime? expiryDate,
  String? instructorName,
  Uint8List? photoFront,
  Uint8List? photoBack,
}) {
  return Certification(
    id: 'cert-1',
    name: name,
    agency: agency,
    cardNumber: cardNumber,
    issueDate: issueDate,
    expiryDate: expiryDate,
    instructorName: instructorName,
    photoFront: photoFront,
    photoBack: photoBack,
    createdAt: _now,
    updatedAt: _now,
  );
}

Future<void> _pumpCard(
  WidgetTester tester, {
  required Certification certification,
  String diverName = 'Eric Griffin',
  bool showBack = false,
}) async {
  await tester.pumpWidget(
    localizedMaterialApp(
      locale: const Locale('en'),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            child: CertificationEcard(
              certification: certification,
              diverName: diverName,
              showBack: showBack,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('CertificationEcard back face', () {
    testWidgets('renders the uploaded photo when photoBack is set', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        certification: _makeCert(photoBack: _onePixelPng),
        showBack: true,
      );

      expect(find.byType(CertificationCardPhoto), findsOneWidget);
    });

    testWidgets('renders the generated back when photoBack is null', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        certification: _makeCert(instructorName: 'Jane Doe'),
        showBack: true,
      );

      expect(find.byType(CertificationCardPhoto), findsNothing);
      expect(find.text('INSTRUCTOR'), findsOneWidget);
      expect(find.text('Jane Doe'), findsOneWidget);
    });
  });

  group('CertificationEcard front face', () {
    testWidgets('renders the uploaded photo when photoFront is set', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        certification: _makeCert(photoFront: _onePixelPng),
      );

      expect(find.byType(CertificationCardPhoto), findsOneWidget);
    });

    testWidgets('photo card repeats agency, name and diver in the strip', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        certification: _makeCert(
          photoFront: _onePixelPng,
          cardNumber: '1802G4921',
        ),
      );

      // Exact joined strings, not textContaining: the generated card renders
      // these same facts as separate Text widgets, so only a whole-line match
      // proves the info strip is what is on screen.
      expect(find.text('PADI  -  Open Water Diver'), findsOneWidget);
      expect(find.text('ERIC GRIFFIN  -  1802G4921'), findsOneWidget);
    });

    testWidgets('photo card strip omits a missing card number', (tester) async {
      await _pumpCard(
        tester,
        certification: _makeCert(photoFront: _onePixelPng),
      );

      // The detail line is the diver name alone, with no trailing separator.
      expect(find.text('ERIC GRIFFIN'), findsOneWidget);
      expect(find.textContaining('ERIC GRIFFIN  -  '), findsNothing);
    });

    testWidgets('photo card still shows the expired badge', (tester) async {
      await _pumpCard(
        tester,
        certification: _makeCert(
          photoFront: _onePixelPng,
          expiryDate: DateTime(2020, 1, 1),
        ),
      );

      // Assert the photo path is what rendered, so this cannot pass by way of
      // the generated card's own badge.
      expect(find.byType(CertificationCardPhoto), findsOneWidget);
      expect(find.text('EXPIRED'), findsOneWidget);
    });

    testWidgets('renders the generated front when photoFront is null', (
      tester,
    ) async {
      await _pumpCard(tester, certification: _makeCert());

      expect(find.byType(CertificationCardPhoto), findsNothing);
      expect(find.text('Open Water Diver'), findsOneWidget);
    });
  });
}
