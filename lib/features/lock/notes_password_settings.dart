import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';

import 'note_lock_service.dart';
import 'notes_password_dialogs.dart';

/// The "Notes password" block in Settings. Nothing at all until a password
/// exists (setting one happens from a note's menu, "Lock note").
class NotesPasswordSettings extends ConsumerWidget {
  const NotesPasswordSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(hasNotesPasswordProvider).value != true) {
      return const SizedBox.shrink();
    }
    final service = ref.watch(noteLockServiceProvider);
    final name = biometricName(context.l10n, Theme.of(context).platform);
    return FutureBuilder<(bool, bool)>(
      // Re-asked on every rebuild, i.e. whenever the service changes.
      future: _biometricState(service),
      builder: (context, snapshot) {
        final (available, enabled) = snapshot.data ?? (false, false);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
              child: Text(
                context.l10n.lockNotesPassword,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.password_outlined),
              title: Text(context.l10n.lockChangePassword),
              onTap: () async {
                final ok = await showChangeNotesPasswordDialog(
                  context,
                  service,
                );
                if (ok && context.mounted) {
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    SnackBar(content: Text(context.l10n.lockPasswordChanged)),
                  );
                }
              },
            ),
            if (available)
              SwitchListTile(
                secondary: const Icon(Icons.fingerprint),
                title: Text(context.l10n.lockUseBiometric(name)),
                subtitle: Text(context.l10n.lockBiometricSubtitle),
                value: enabled,
                onChanged: (on) async {
                  if (on && !service.anyUnlocked) {
                    final ok = await showUnlockNotesDialog(
                      context,
                      service,
                      message: context.l10n.lockEnterToTurnOn,
                    );
                    if (!ok) return;
                  }
                  await service.setBiometrics(on);
                },
              ),
            if (service.anyUnlocked)
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: Text(context.l10n.lockNow),
                subtitle: Text(context.l10n.lockNowSubtitle),
                onTap: service.lockNow,
              ),
            ListTile(
              leading: const Icon(Icons.restart_alt),
              title: Text(context.l10n.lockResetItem),
              subtitle: Text(context.l10n.lockResetItemSubtitle),
              onTap: () => _reset(context, service),
            ),
          ],
        );
      },
    );
  }

  static Future<(bool, bool)> _biometricState(NoteLockService s) async =>
      (await s.biometricsAvailable(), await s.biometricsEnabled());

  Future<void> _reset(BuildContext context, NoteLockService service) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.lockResetDialogTitle),
        content: Text(context.l10n.lockResetBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.lockContinue),
          ),
        ],
      ),
    );
    if (go != true || !context.mounted) return;
    await showSetNotesPasswordDialog(context, service, reset: true);
  }
}
