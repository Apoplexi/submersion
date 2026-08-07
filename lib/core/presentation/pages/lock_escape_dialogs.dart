import 'package:flutter/material.dart';

/// Escape-hatch dialogs for the startup lock screen. Rendered inside the
/// pre-l10n splash MaterialApp, so strings are plain English by the same
/// precedent as the rest of the startup UI.

/// Recovery-code entry. [onSubmit] returns true when the code unlocked the
/// database. The dialog pops with true on success, false/null on cancel.
Future<bool?> showRecoveryCodeUnlockDialog(
  BuildContext context, {
  required Future<bool> Function(String code) onSubmit,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => _SecretPromptDialog(
      title: 'Use recovery code',
      body:
          'Enter the 8-word recovery code you saved when you set up the '
          'app password.',
      fieldLabel: 'Recovery code',
      submitLabel: 'Unlock',
      errorText: 'Incorrect recovery code.',
      obscure: false,
      onSubmit: onSubmit,
    ),
  );
}

/// Confirms setting the locked database aside. Requires typing START FRESH.
Future<bool?> showStartFreshConfirmDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (context) => const _StartFreshConfirmDialog(),
  );
}

/// Forces a new password after a recovery-code unlock (the old password is
/// lost). Modal: no cancel, must complete.
Future<void> showForcedPasswordResetDialog(
  BuildContext context, {
  required Future<void> Function(String newPassword) onSubmit,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _NewPasswordDialog(
      title: 'Set a new password',
      body:
          'You unlocked with your recovery code, so your old password is '
          'no longer trusted. Choose a new one now.',
      onSubmit: onSubmit,
    ),
  );
}

/// Sidecar repair: confirm the password to rebuild the lost key file.
/// [onSubmit] rebuilds and returns true; the caller shows the new recovery
/// code afterwards. Declining is allowed (repair is reoffered next launch).
Future<bool?> showSidecarRepairDialog(
  BuildContext context, {
  required Future<bool> Function(String password) onSubmit,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => _SecretPromptDialog(
      title: 'Repair security key file',
      body:
          'Your security key file was missing and this device\'s keychain '
          'still holds the key. Confirm your password to write a new key '
          'file. Note: the password you enter here becomes the app password '
          'going forward, and you will receive a new recovery code.',
      fieldLabel: 'Password',
      submitLabel: 'Repair',
      errorText: 'Repair failed. Try again.',
      obscure: true,
      onSubmit: onSubmit,
    ),
  );
}

/// Shows a freshly generated recovery code with a save confirmation.
Future<void> showNewRecoveryCodeDialog(BuildContext context, String code) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('Your new recovery code'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Write this down and keep it safe. It is the only way to '
            'unlock if you forget your password, and it replaces any '
            'previous recovery code.',
          ),
          const SizedBox(height: 16),
          SelectableText(
            code,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('I saved it'),
        ),
      ],
    ),
  );
}

/// Shared single-secret prompt with inline error handling.
class _SecretPromptDialog extends StatefulWidget {
  final String title;
  final String body;
  final String fieldLabel;
  final String submitLabel;
  final String errorText;
  final bool obscure;
  final Future<bool> Function(String secret) onSubmit;

  const _SecretPromptDialog({
    required this.title,
    required this.body,
    required this.fieldLabel,
    required this.submitLabel,
    required this.errorText,
    required this.obscure,
    required this.onSubmit,
  });

  @override
  State<_SecretPromptDialog> createState() => _SecretPromptDialogState();
}

class _SecretPromptDialogState extends State<_SecretPromptDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  bool _showError = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _showError = false;
    });
    try {
      final ok = await widget.onSubmit(_controller.text);
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop(true);
      } else {
        setState(() => _showError = true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.body),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            obscureText: widget.obscure,
            autofocus: true,
            enabled: !_busy,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: widget.fieldLabel,
              border: const OutlineInputBorder(),
              errorText: _showError ? widget.errorText : null,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(widget.submitLabel),
        ),
      ],
    );
  }
}

class _StartFreshConfirmDialog extends StatefulWidget {
  const _StartFreshConfirmDialog();

  @override
  State<_StartFreshConfirmDialog> createState() =>
      _StartFreshConfirmDialogState();
}

class _StartFreshConfirmDialogState extends State<_StartFreshConfirmDialog> {
  final _controller = TextEditingController();
  bool _confirmed = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final match = _controller.text.trim() == 'START FRESH';
      if (match != _confirmed) setState(() => _confirmed = match);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Open a different database'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your current database stays on disk, renamed with a .locked '
            'suffix — nothing is deleted. You can recover it later with '
            'your password or by contacting support. Cloud sync will be '
            'turned off so the new database cannot mix with the old one.\n\n'
            'The app will start with a fresh, empty database. You can '
            'restore from a backup in the setup wizard.\n\n'
            'Type START FRESH to confirm.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'START FRESH',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _confirmed ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Set aside and start fresh'),
        ),
      ],
    );
  }
}

/// New password + confirmation, no cancel (forced reset after recovery).
class _NewPasswordDialog extends StatefulWidget {
  final String title;
  final String body;
  final Future<void> Function(String newPassword) onSubmit;

  const _NewPasswordDialog({
    required this.title,
    required this.body,
    required this.onSubmit,
  });

  @override
  State<_NewPasswordDialog> createState() => _NewPasswordDialogState();
}

class _NewPasswordDialogState extends State<_NewPasswordDialog> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_password.text.length < 4) {
      setState(() => _error = 'Password must be at least 4 characters.');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_password.text);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not set the new password. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.body),
          const SizedBox(height: 16),
          TextField(
            controller: _password,
            obscureText: true,
            autofocus: true,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'New password',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirm,
            obscureText: true,
            enabled: !_busy,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Confirm password',
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: const Text('Set password'),
        ),
      ],
    );
  }
}
