import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:submersion/features/media/domain/entities/media_library_filter.dart';
import 'package:submersion/features/media/presentation/widgets/media_library_grid.dart';
import 'package:submersion/features/media/presentation/widgets/media_library_groupers.dart';
import 'package:submersion/l10n/l10n_extension.dart';

/// Sectioned presentation shared by the by-dive and timeline modes: group
/// headers over non-scrolling thumbnail grids inside one scrolling list,
/// with the same near-end load-more contract as the flat grid.
class MediaLibraryGroupedList extends StatelessWidget {
  const MediaLibraryGroupedList({
    super.key,
    required this.groups,
    required this.hasMore,
    required this.onLoadMore,
    required this.onTileTap,
    this.selectedIds = const {},
    this.onTileLongPress,
  });

  final List<MediaLibraryGroup> groups;
  final bool hasMore;
  final VoidCallback onLoadMore;
  final void Function(MediaLibraryEntry entry) onTileTap;

  /// Ids rendered with the selection overlay.
  final Set<String> selectedIds;

  /// Long-press hook for entering selection mode.
  final void Function(MediaLibraryEntry entry)? onTileLongPress;

  static const double _loadMoreThreshold = 400;

  String _diveHeaderLabel(BuildContext context, DiveGroupHeader header) {
    if (header.diveId == null) {
      return context.l10n.media_library_unlinkedHeader;
    }
    final siteName = header.siteName;
    final parts = <String>[
      if (header.diveNumber != null) '#${header.diveNumber}',
      if (siteName != null && siteName.isNotEmpty) siteName,
    ];
    if (parts.isEmpty) {
      final date = header.diveDateTime;
      if (date != null) {
        final locale = Localizations.localeOf(context).toString();
        return DateFormat.yMMMd(locale).format(date);
      }
      return '';
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();

    final rows = <Widget>[];
    DateTime? lastMonth;
    for (final group in groups) {
      final header = group.header;
      if (header is DateGroupHeader) {
        if (lastMonth != header.monthStart) {
          lastMonth = header.monthStart;
          rows.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
              child: Text(
                DateFormat.yMMMM(locale).format(header.monthStart),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          );
        }
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Text(
              DateFormat.MMMEd(locale).format(header.dayStart),
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        );
      } else if (header is DiveGroupHeader) {
        final label = _diveHeaderLabel(context, header);
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: header.diveId != null
                ? InkWell(
                    // push, not go: `/dives/:diveId` is a child route, so a
                    // stack-replacing `go` would strand the user on the dive
                    // list when they press back instead of returning them to
                    // the library.
                    onTap: () => context.push('/dives/${header.diveId}'),
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  )
                : Text(label, style: Theme.of(context).textTheme.titleMedium),
          ),
        );
      }
      rows.add(
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 140,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemCount: group.entries.length,
          itemBuilder: (context, index) {
            final entry = group.entries[index];
            return MediaLibraryTile(
              entry: entry,
              selected: selectedIds.contains(entry.item.id),
              onTap: () => onTileTap(entry),
              onLongPress: onTileLongPress == null
                  ? null
                  : () => onTileLongPress!(entry),
            );
          },
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (hasMore &&
            notification.metrics.pixels >=
                notification.metrics.maxScrollExtent - _loadMoreThreshold) {
          onLoadMore();
        }
        return false;
      },
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 8),
        itemCount: rows.length,
        itemBuilder: (context, index) => rows[index],
      ),
    );
  }
}
