import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/media/data/services/repair/media_repair_service.dart';
import 'package:submersion/features/media/domain/entities/media_item.dart';
import 'package:submersion/features/media/domain/entities/media_library_filter.dart';
import 'package:submersion/features/media/domain/entities/media_source_type.dart';
import 'package:submersion/features/media/domain/services/media_repair_types.dart';
import 'package:submersion/features/media/presentation/providers/media_repair_providers.dart';

MediaItem broken(String id, {String? localPath}) => MediaItem(
  id: id,
  mediaType: MediaType.photo,
  sourceType: MediaSourceType.localFile,
  filePath: localPath ?? '/gone/$id.jpg',
  localPath: localPath ?? '/gone/$id.jpg',
  originalFilename: '$id.jpg',
  isOrphaned: true,
  takenAt: DateTime(2026, 6, 1),
  createdAt: DateTime(2026, 6, 1),
  updatedAt: DateTime(2026, 6, 1),
);

class _FakeSource implements CandidateSource {
  _FakeSource(this.harvestResult);
  final CandidateHarvest harvestResult;

  @override
  Future<CandidateHarvest> harvest(List<MediaItem> brokenRows) async =>
      harvestResult;
}

void main() {
  late List<RepairProposal>? appliedProposals;

  RepairWizardNotifier notifier({
    required List<MediaItem> missingRows,
    required CandidateHarvest harvest,
    Set<String> offlinePaths = const {},
    RepairApplyReport? report,
  }) {
    appliedProposals = null;
    return RepairWizardNotifier(
      loadMissingRows: () async => missingRows,
      buildSources: (config) => [_FakeSource(harvest)],
      isVolumeOnline: (path) async => !offlinePaths.contains(path),
      applyProposals: (proposals) async {
        appliedProposals = proposals;
        return report ??
            const RepairApplyReport(
              relinked: 0,
              cloudBacked: 0,
              reuploadsQueued: 0,
              failed: 0,
              skipped: 0,
            );
      },
    );
  }

  test('harvest produces review with exact and probable pre-checked', () async {
    final n = notifier(
      missingRows: [broken('a'), broken('b'), broken('c')],
      harvest: CandidateHarvest(
        byFilename: {
          'a.jpg': [
            const RepairCandidate.file(
              path: '/nas/a.jpg',
              sizeBytes: 4,
              hash: null,
            ),
          ],
          'b.jpg': [const RepairCandidate.store(verified: true)],
        },
      ),
    );

    await n.harvest(const RepairWizardConfig());

    final state = n.state as RepairWizardReview;
    expect(state.proposals, hasLength(3));
    expect(n.isChecked('a'), isTrue); // probable
    expect(n.isChecked('b'), isTrue); // exact (store)
    expect(n.isChecked('c'), isFalse); // unmatched
  });

  test('volume-offline rows are excluded from the wizard', () async {
    final n = notifier(
      missingRows: [
        broken('a'),
        broken('off', localPath: '/nas/off.jpg'),
      ],
      harvest: const CandidateHarvest(byFilename: {}),
      offlinePaths: {'/nas/off.jpg'},
    );

    await n.harvest(const RepairWizardConfig());

    final state = n.state as RepairWizardReview;
    expect(state.proposals.map((p) => p.item.id), ['a']);
  });

  test(
    'applyChecked forwards only checked proposals and reaches done',
    () async {
      final n = notifier(
        missingRows: [broken('a'), broken('c')],
        harvest: CandidateHarvest(
          byFilename: {
            'a.jpg': [
              const RepairCandidate.file(path: '/nas/a.jpg', sizeBytes: 4),
            ],
          },
        ),
        report: const RepairApplyReport(
          relinked: 1,
          cloudBacked: 0,
          reuploadsQueued: 0,
          failed: 0,
          skipped: 0,
        ),
      );

      await n.harvest(const RepairWizardConfig());
      await n.applyChecked();

      expect(appliedProposals!.map((p) => p.item.id), ['a']);
      final done = n.state as RepairWizardDone;
      expect(done.report.relinked, 1);
    },
  );

  test('toggleProposal flips membership', () async {
    final n = notifier(
      missingRows: [broken('a')],
      harvest: CandidateHarvest(
        byFilename: {
          'a.jpg': [
            const RepairCandidate.file(path: '/nas/a.jpg', sizeBytes: 4),
          ],
        },
      ),
    );
    await n.harvest(const RepairWizardConfig());
    expect(n.isChecked('a'), isTrue);
    n.toggleProposal('a');
    expect(n.isChecked('a'), isFalse);
  });
}
