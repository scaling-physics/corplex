import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final name = biometricName(Theme.of(context).platform);
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
                'Notes password',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.password_outlined),
              title: const Text('Change password'),
              onTap: () async {
                final ok = await showChangeNotesPasswordDialog(
                  context,
                  service,
                );
                if (ok && context.mounted) {
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    const SnackBar(content: Text('Notes password changed')),
                  );
                }
              },
            ),
            if (available)
              SwitchListTile(
                secondary: const Icon(Icons.fingerprint),
                title: Text('Use $name'),
                subtitle: const Text('Open locked notes without typing'),
                value: enabled,
                onChanged: (on) async {
                  if (on && !service.anyUnlocked) {
                    final ok = await showUnlockNotesDialog(
                      context,
                      service,
                      message: 'Enter your notes password to turn this on.',
                    );
                    if (!ok) return;
                  }
                  await service.setBiometrics(on);
                },
              ),
            if (service.anyUnlocked)
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text('Lock now'),
                subtitle: const Text('Locked notes ask for the password again'),
                onTap: service.lockNow,
              ),
            ListTile(
              leading: const Icon(Icons.restart_alt),
              title: const Text('Reset password…'),
              subtitle: const Text('For a forgotten password'),
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
        title: const Text('Reset the notes password?'),
        content: const Text(
          'You\'ll choose a new password for notes you lock from now on.\n\n'
          'Notes already locked stay locked under the old password. Without '
          'it they can\'t be opened — not by you, and not by us. If you '
          'remember the old password later, entering it opens them again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (go != true || !context.mounted) return;
    await showSetNotesPasswordDialog(context, service, reset: true);
  }
}
