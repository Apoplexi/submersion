import 'package:flutter/material.dart';

import 'package:submersion/l10n/l10n_extension.dart';

/// Top-level Media section host. The console scaffold (sidebar on desktop,
/// tabs on phone) replaces this placeholder body as the section grows; for
/// now it only makes /media routable.
class MediaSectionPage extends StatelessWidget {
  const MediaSectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.nav_media)),
      body: const SizedBox.shrink(),
    );
  }
}
