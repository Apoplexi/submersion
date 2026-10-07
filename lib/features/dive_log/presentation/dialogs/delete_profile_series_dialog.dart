import 'package:flutter/material.dart';

import 'package:submersion/l10n/l10n_extension.dart';

/// Confirmation dialog for deleting a profile series (revision).
///
/// Shows a warning that the deletion is permanent and cannot be undone.
/// If the series was imported from a dive computer, also shows an additional
/// warning about potential original data loss.
class DeleteProfileSeriesDialog extends StatelessWidget {
  /// The revision kind (e.g., 'computer_import', 'edit', 'create')
  final String revisionKind;

  /// Whether this series was imported from a dive computer (has a computerId).
  /// Used to show an additional warning about original data.
  final bool isComputerImport;

  const DeleteProfileSeriesDialog({
    super.key,
    required this.revisionKind,
    required this.isComputerImport,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        context.l10n.diveLog_profileEditor_deleteProfile_confirmTitle,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Main warning
            Text(context.l10n.diveLog_profileEditor_deleteProfile_confirmBody),
            const SizedBox(height: 16),

            // Additional warning for computer imports
            if (isComputerImport)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.error,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Theme.of(context).colorScheme.error,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context
                            .l10n
                            .diveLog_profileEditor_deleteProfile_computerImportWarning,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.l10n.diveLog_profileEditor_deleteProfile_cancel),
        ),
        FilledButton.tonalIcon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.delete, size: 18),
          label: Text(context.l10n.diveLog_profileEditor_deleteProfile_delete),
        ),
      ],
    );
  }
}
