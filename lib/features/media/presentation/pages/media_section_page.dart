import 'package:flutter/material.dart';

import 'package:submersion/features/media/presentation/pages/media_library_view.dart';
import 'package:submersion/features/media/presentation/widgets/media_console_scaffold.dart';
import 'package:submersion/features/media_store/presentation/widgets/transfers_view.dart';
import 'package:submersion/l10n/l10n_extension.dart';

/// Top-level Media section host: owns the selected console section and
/// renders its content inside [MediaConsoleScaffold] (sidebar on desktop,
/// tabs on phone). Section bodies land in later tasks.
class MediaSectionPage extends StatefulWidget {
  const MediaSectionPage({super.key});

  @override
  State<MediaSectionPage> createState() => _MediaSectionPageState();
}

class _MediaSectionPageState extends State<MediaSectionPage> {
  MediaConsoleSection _section = MediaConsoleSection.library;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.nav_media)),
      body: MediaConsoleScaffold(
        selected: _section,
        onSelect: (section) => setState(() => _section = section),
        child: switch (_section) {
          MediaConsoleSection.library => const MediaLibraryView(),
          MediaConsoleSection.transfers => const TransfersView(),
        },
      ),
    );
  }
}
