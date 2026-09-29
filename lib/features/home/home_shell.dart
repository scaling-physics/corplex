import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_service.dart';
import '../auth/sign_in_screen.dart';
import '../audio/audio_player_bar.dart';
import '../library/library_screen.dart';
import '../sync/sync_service.dart';
import '../notes/notes_screen.dart';
import '../../theme/app_theme.dart';
import '../../theme/motion_widgets.dart';

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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        titleSpacing: 20,
        title: AnimatedSwitcher(
          duration: AppMotion.medium,
          switchInCurve: AppMotion.enter,
          switchOutCurve: Curves.easeOut,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.25),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.centerLeft,
            children: [...previous, ?current],
          ),
          child: Text(
            _titles[_index],
            key: ValueKey(_index),
            style: theme.textTheme.headlineMedium,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _AccountButton(
              email: user?.email,
              onPressed: () => user == null
                  ? Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SignInScreen()),
                    )
                  : _showAccountMenu(context),
            ),
          ),
        ],
      ),
      body: FadeThroughIndexedStack(index: _index, children: _screens),
      floatingActionButton: _PrimaryAction(index: _index),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Keeps a podcast playing (and controllable) between screens.
          const AudioPlayerBar(),
          NavigationBar(
            selectedIndex: _index,
            animationDuration: AppMotion.medium,
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(
                ref.read(authServiceProvider).currentUser?.email ?? '',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
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

/// The one main action for the current tab, labelled so it's obvious what
/// it does. Morphs between tabs rather than popping.
class _PrimaryAction extends ConsumerWidget {
  const _PrimaryAction({required this.index});

  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (icon, label, action) = switch (index) {
      0 => (Icons.add, 'New note', createNote),
      _ => (Icons.upload_file_outlined, 'Import PDF', importPaper),
    };
    return FloatingActionButton.extended(
      heroTag: null,
      onPressed: () => action(context, ref),
      icon: AnimatedSwitcher(
        duration: AppMotion.short,
        child: Icon(icon, key: ValueKey(icon)),
      ),
      label: AnimatedSize(
        duration: AppMotion.medium,
        curve: AppMotion.standard,
        child: AnimatedSwitcher(
          duration: AppMotion.short,
          child: Text(label, key: ValueKey(label)),
        ),
      ),
    );
  }
}

/// Signed out: a plain outline icon. Signed in: a sage disc with the
/// account's initial.
class _AccountButton extends StatelessWidget {
  const _AccountButton({required this.email, required this.onPressed});

  final String? email;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final email = this.email;
    return IconButton(
      tooltip: email ?? 'Sign in',
      onPressed: onPressed,
      icon: AnimatedSwitcher(
        duration: AppMotion.medium,
        child: email == null
            ? const Icon(Icons.account_circle_outlined, key: ValueKey('out'))
            : CircleAvatar(
                key: const ValueKey('in'),
                radius: 15,
                backgroundColor: c.primaryContainer,
                foregroundColor: c.onPrimaryContainer,
                child: Text(
                  email.isEmpty ? '?' : email[0].toUpperCase(),
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: c.onPrimaryContainer),
                ),
              ),
      ),
    );
  }
}
