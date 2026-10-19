import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';

import 'note_lock_service.dart';

/// Shortest notes password we accept. The password protects text that can't
/// be recovered without it, so a one-letter password is refused; beyond
/// that the reader chooses.
const minNotesPasswordLength = 6;

/// What this platform calls unlocking with your body.
String biometricName(AppLocalizations l10n, TargetPlatform platform) =>
    switch (platform) {
      TargetPlatform.macOS => l10n.lockBiometricTouch,
      TargetPlatform.iOS => l10n.lockBiometricFaceTouch,
      TargetPlatform.android => l10n.lockBiometricFingerprint,
      _ => l10n.lockBiometricGeneric,
    };

/// Gets the notes unlocked for something that needs the current key:
/// sets the password first if there isn't one, tries biometrics if they're
/// on, otherwise asks for the password. True once the notes are unlocked.
Future<bool> ensureNotesUnlocked(
  BuildContext context,
  NoteLockService service,
) async {
  final reason = context.l10n.lockBiometricReason;
  if (!await service.hasPassword()) {
    if (!context.mounted) return false;
    return showSetNotesPasswordDialog(context, service);
  }
  if (await service.isUnlocked()) return true;
  if (await service.biometricsEnabled() &&
      await service.unlockWithBiometrics(reason: reason) &&
      await service.isUnlocked()) {
    return true;
  }
  if (!context.mounted) return false;
  return showUnlockNotesDialog(context, service);
}

/// "Set a notes password": password, confirmation, optional hint and the
/// plain warning. Then offers biometrics when the device has them. True if
/// the password was set.
Future<bool> showSetNotesPasswordDialog(
  BuildContext context,
  NoteLockService service, {
  bool reset = false,
}) async {
  final done = await showDialog<bool>(
    context: context,
    builder: (_) => _SetPasswordDialog(service: service, reset: reset),
  );
  if (done != true) return false;
  if (!context.mounted) return true;
  await offerBiometrics(context, service);
  return true;
}

/// Asks whether to unlock with biometrics from now on (only if the device
/// has them and they aren't on already).
Future<void> offerBiometrics(
  BuildContext context,
  NoteLockService service,
) async {
  if (!await service.biometricsAvailable() ||
      await service.biometricsEnabled() ||
      !context.mounted) {
    return;
  }
  final name = biometricName(context.l10n, Theme.of(context).platform);
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.l10n.lockOfferTitle(name)),
      content: Text(context.l10n.lockOfferBody(name)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(context.l10n.lockNotNow),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(context.l10n.lockUseBiometric(name)),
        ),
      ],
    ),
  );
  if (yes == true) await service.setBiometrics(true);
}

class _SetPasswordDialog extends StatefulWidget {
  const _SetPasswordDialog({required this.service, required this.reset});

  final NoteLockService service;
  final bool reset;

  @override
  State<_SetPasswordDialog> createState() => _SetPasswordDialogState();
}

class _SetPasswordDialogState extends State<_SetPasswordDialog> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _hint = TextEditingController();
  String Function(AppLocalizations)? _error;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    _hint.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_password.text.length < minNotesPasswordLength) {
      setState(() => _error = (l) => l.lockMinLength(minNotesPasswordLength));
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = (l) => l.lockMismatch);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final hint = _hint.text.trim().isEmpty ? null : _hint.text.trim();
    if (widget.reset) {
      await widget.service.resetPassword(_password.text, hint: hint);
    } else {
      await widget.service.setPassword(_password.text, hint: hint);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    return AlertDialog(
      title: Text(
        widget.reset ? context.l10n.lockResetTitle : context.l10n.lockSetTitle,
      ),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  context.l10n.lockForgottenWarning,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: c.onErrorContainer,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _password,
                autofocus: true,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: context.l10n.lockPassword,
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _confirm,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: context.l10n.lockConfirm,
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _hint,
                decoration: InputDecoration(
                  labelText: context.l10n.lockHintOptional,
                  helperText: context.l10n.lockHintHelper,
                ),
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!(context.l10n), style: TextStyle(color: c.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: Text(context.l10n.commonCancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(
            widget.reset
                ? context.l10n.lockResetPassword
                : context.l10n.lockSetPassword,
          ),
        ),
      ],
    );
  }
}

/// Asks for the notes password (to lock a note, remove a lock, turn on
/// biometrics…). True once the notes are unlocked.
Future<bool> showUnlockNotesDialog(
  BuildContext context,
  NoteLockService service, {
  String? message,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _UnlockDialog(service: service, message: message),
  );
  return ok == true;
}

class _UnlockDialog extends StatefulWidget {
  const _UnlockDialog({required this.service, required this.message});

  final NoteLockService service;
  final String? message;

  @override
  State<_UnlockDialog> createState() => _UnlockDialogState();
}

class _UnlockDialogState extends State<_UnlockDialog> {
  final _password = TextEditingController();
  bool _wrong = false;
  String? _hint;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.service.hint().then((h) {
      if (mounted) setState(() => _hint = h);
    });
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await widget.service.unlock(_password.text);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _busy = false;
        _wrong = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(context.l10n.lockNotesPassword),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.message ?? context.l10n.lockEnterPassword),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              autofocus: true,
              obscureText: true,
              decoration: InputDecoration(
                labelText: context.l10n.lockPassword,
                errorText: _wrong ? context.l10n.lockWrongPassword : null,
                helperText: _hint == null
                    ? null
                    : context.l10n.lockHint(_hint!),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(context.l10n.commonCancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.onPrimary,
                  ),
                )
              : Text(context.l10n.lockUnlock),
        ),
      ],
    );
  }
}

/// Change the notes password: old, new, confirm, hint. True if changed.
Future<bool> showChangeNotesPasswordDialog(
  BuildContext context,
  NoteLockService service,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _ChangePasswordDialog(service: service),
  );
  return ok == true;
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.service});

  final NoteLockService service;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  final _hint = TextEditingController();
  String Function(AppLocalizations)? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.service.hint().then((h) {
      if (mounted && h != null) _hint.text = h;
    });
  }

  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    _confirm.dispose();
    _hint.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_new.text.length < minNotesPasswordLength) {
      setState(() => _error = (l) => l.lockMinLength(minNotesPasswordLength));
      return;
    }
    if (_new.text != _confirm.text) {
      setState(() => _error = (l) => l.lockNewMismatch);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await widget.service.changePassword(
      _old.text,
      _new.text,
      hint: _hint.text,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _busy = false;
        _error = (l) => l.lockCurrentWrong;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(context.l10n.lockChangeTitle),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _old,
                autofocus: true,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: context.l10n.lockCurrentPassword,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _new,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: context.l10n.lockNewPassword,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _confirm,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: context.l10n.lockConfirm,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _hint,
                decoration: InputDecoration(
                  labelText: context.l10n.lockHintOptional,
                ),
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!(context.l10n), style: TextStyle(color: c.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: Text(context.l10n.commonCancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(context.l10n.lockChangePassword),
        ),
      ],
    );
  }
}

/// Unlocks the notes for something that only needs to *read* (export, add
/// to a locked note): biometrics if on, else the password dialog (with hint)
/// showing [reason]. True if some key was unlocked. Unlike
/// [ensureNotesUnlocked] it never offers to set a password.
Future<bool> requestNotesUnlock(
  BuildContext context,
  NoteLockService service, {
  String? reason,
}) async {
  final l10n = context.l10n;
  if (await service.biometricsEnabled() &&
      await service.unlockWithBiometrics(reason: l10n.lockBiometricReason)) {
    return true;
  }
  if (!context.mounted) return false;
  return showUnlockNotesDialog(
    context,
    service,
    message: reason ?? l10n.lockUnlockToContinue,
  );
}
