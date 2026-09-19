import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_service.dart';
import '../auth/sign_in_screen.dart';
import '../library/library_screen.dart';
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
            icon: Icon(user == null ? Icons.account_circle_outlined : Icons.account_circle),
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
    final signOut = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Sign out'),
          onTap: () => Navigator.pop(context, true),
        ),
      ),
    );
    if (signOut == true) {
      await ref.read(authServiceProvider).signOut();
    }
  }
}
