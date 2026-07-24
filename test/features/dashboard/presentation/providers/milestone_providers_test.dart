import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/constants/enums.dart';
import 'package:submersion/features/certifications/domain/entities/certification.dart';
import 'package:submersion/features/dashboard/presentation/providers/milestone_providers.dart';

Certification _cert(DateTime? issueDate, {String name = 'Open Water'}) =>
    Certification(
      id: name,
      name: name,
      agency: CertificationAgency.padi,
      issueDate: issueDate,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

void main() {
  group('nextDiveMilestone', () {
    test('ladder below 1000', () {
      expect(nextDiveMilestone(0), isNull);
      expect(nextDiveMilestone(1), 10);
      expect(nextDiveMilestone(10), 25);
      expect(nextDiveMilestone(247), 250);
      expect(nextDiveMilestone(999), 1000);
    });

    test('every 500 above 1000', () {
      expect(nextDiveMilestone(1000), 1500);
      expect(nextDiveMilestone(1501), 2000);
    });
  });

  group('upcomingAnniversaries', () {
    test('includes anniversary within window, computes years', () {
      final result = upcomingAnniversaries(
        [_cert(DateTime(2016, 8, 10))],
        DateTime(2026, 7, 24),
        windowDays: 60,
      );
      expect(result.single.years, 10);
      expect(result.single.date, DateTime(2026, 8, 10));
      expect(result.single.certName, 'Open Water');
    });

    test('excludes anniversary outside window', () {
      final result = upcomingAnniversaries(
        [_cert(DateTime(2016, 12, 25))],
        DateTime(2026, 7, 24),
        windowDays: 60,
      );
      expect(result, isEmpty);
    });

    test('anniversary earlier this year rolls to next year', () {
      final result = upcomingAnniversaries(
        [_cert(DateTime(2020, 1, 5))],
        DateTime(2026, 12, 20),
        windowDays: 60,
      );
      expect(result.single.date, DateTime(2027, 1, 5));
      expect(result.single.years, 7);
    });

    test('null issueDate ignored', () {
      expect(
        upcomingAnniversaries([_cert(null)], DateTime(2026, 7, 24)),
        isEmpty,
      );
    });

    test('sorted by soonest anniversary first', () {
      final result = upcomingAnniversaries(
        [
          _cert(DateTime(2020, 9, 1), name: 'Rescue'),
          _cert(DateTime(2018, 8, 1), name: 'AOW'),
        ],
        DateTime(2026, 7, 24),
        windowDays: 60,
      );
      expect(result.first.certName, 'AOW');
    });
  });
}
