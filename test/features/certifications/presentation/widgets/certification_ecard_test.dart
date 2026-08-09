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
}
