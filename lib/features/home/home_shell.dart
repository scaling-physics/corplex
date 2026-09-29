import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_service.dart';
import '../auth/sign_in_screen.dart';
import '../library/library_screen.dart';
import '../sync/sync_service.dart';
import '../notes/notes_screen.dart';

/// Top-level shell switching between the two primary spaces of the app:
/// quick note capture and the auto-organized paper library.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  static const _screens = [NotesScreen(), LibraryScreen()];
  static const _titles = ['Notes', 'Library'];

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          IconButton(
            icon: Icon(
              user == null
                  ? Icons.account_circle_outlined
                  : Icons.account_circle,
            ),
            tooltip: user == null ? 'Sign in' : user.email,
            onPressed: () => user == null
                ? Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SignInScreen()),
                  )
                : _showAccountMenu(context),
          ),
        ],
      ),
      body: _screens[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.edit_note_outlined),
            selectedIcon: Icon(Icons.edit_note),
            label: 'Notes',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_books_outlined),
            selectedIcon: Icon(Icons.library_books),
            label: 'Library',
          ),
        ],
      ),
    );
  }

  Future<void> _showAccountMenu(BuildContext context) async {
    final sync = ref.read(syncServiceProvider);
    final signOut = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Sync detail lives here, not on the main screens: it's
            // background plumbing until the user goes looking for it.
            Consumer(
              builder: (context, ref, _) {
                final status =
                    ref.watch(syncStatusProvider).value ?? sync.currentStatus;
                return ListTile(
                  leading: const Icon(Icons.sync),
                  title: const Text('Sync now'),
                  subtitle: Text(_syncLabel(status, sync.lastError)),
                  enabled: status != SyncStatus.offline,
                  onTap: sync.syncNow,
                );
              },
            ),
            if (sync.accountMismatch)
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: const Text('Use this account on this device'),
                subtitle: const Text(
                  'Replaces what\'s on this device with this account\'s data.',
                ),
                onTap: () {
                  Navigator.pop(context);
                  _eraseDevice(context, signOutAfter: false);
                },
              ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sign out'),
              onTap: () => Navigator.pop(context, true),
            ),
            if (sync.currentStatus != SyncStatus.offline)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Sign out and clear this device'),
                onTap: () {
                  Navigator.pop(context);
                  _eraseDevice(context, signOutAfter: true);
                },
              ),
          ],
        ),
      ),
    );
    if (signOut == true) {
      await ref.read(authServiceProvider).signOut();
    }
  }

  /// Wipes this device's copy of the library, after warning about anything
  /// that hasn't reached the cloud yet (that part would be lost for good).
  Future<void> _eraseDevice(
    BuildContext context, {
    required bool signOutAfter,
  }) async {
    final sync = ref.read(syncServiceProvider);
    final auth = ref.read(authServiceProvider);
    if (!sync.accountMismatch) await sync.syncNow(); // Push what we can.
    final pending = await sync.pendingChanges();
    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          signOutAfter ? 'Clear this device?' : 'Replace this device\'s data?',
        ),
        content: Text(
          pending == 0
              ? 'Notes, papers and files on this device will be removed. '
                    'Everything is safe in your account.'
              : '$pending change${pending == 1 ? '' : 's'} on this device '
                    'haven\'t synced and will be lost for good. Everything '
                    'else is safe in your account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(signOutAfter ? 'Clear and sign out' : 'Replace'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (signOutAfter) {
      await sync.stop(); // No sync may run while the data is being removed.
      await sync.eraseLocalData();
      await auth.signOut();
    } else {
      await sync.eraseLocalData();
    }
  }

  static String _syncLabel(SyncStatus status, String? error) =>
      switch (status) {
        SyncStatus.offline => 'Not syncing',
        SyncStatus.syncing => 'Syncing…',
        SyncStatus.upToDate => 'Up to date',
        SyncStatus.error => error ?? 'Sync failed',
      };
}
