import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_service.dart';
import '../auth/sign_in_screen.dart';
import '../../data/database_provider.dart';
import '../../data/trash.dart';
import '../audio/audio_player_bar.dart';
import '../library/library_screen.dart';
import '../ocr/ocr_service.dart';
import '../settings/appearance_settings.dart';
import '../library/library_actions.dart';
import '../platform/mac_window.dart';
import 'adaptive.dart';
import '../trash/trash_actions.dart';
import 'keyboard_shortcuts.dart';
import 'mac_sidebar.dart';
import '../sync/sync_ring.dart';
import '../sync/sync_service.dart';
import '../sync/transfer_settings.dart';
import '../notes/notes_screen.dart';
import '../review/review_prompt.dart';
import '../search/search_screen.dart';
import '../trash/trash_screen.dart';
import 'data_actions.dart';
import '../../theme/app_theme.dart';
import '../../theme/motion_widgets.dart';
import '../lock/note_lock_service.dart';
import '../lock/notes_password_settings.dart';

/// Top-level shell switching between the two primary spaces of the app:
/// quick note capture and the auto-organized paper library.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;
  StreamSubscription<MenuCommand>? _menu;

  @override
  void initState() {
    super.initState();
    // The native menu bar (macOS). A plain stream subscription rather than
    // a provider listener: the same command twice in a row must fire twice.
    _menu = ref.read(macWindowProvider).menuCommands.listen(_onCommand);
    // Housekeeping: items that have sat in the trash past the retention
    // period go for good. Never worth failing startup over.
    purgeTrash(ref.read(databaseProvider)).catchError((_) => 0);
    // Scanned papers whose text recognition was cut short carry on. With
    // none (every test, every fresh install) this is one empty query.
    ref.read(ocrStartupProvider);
  }

  @override
  void dispose() {
    _menu?.cancel();
    super.dispose();
  }

  /// Back to the home screen, closing anything pushed over it.
  void _home() {
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  void _onCommand(MenuCommand command) {
    if (!mounted) return;
    switch (command) {
      case MenuCommand.newNote:
        _home();
        createNote(context, ref);
      case MenuCommand.importPdf:
        _home();
        importPaper(context, ref);
      case MenuCommand.importReferences:
        importBibtexFile(context, ref);
      case MenuCommand.backup:
        backUpToFile(context, ref);
      case MenuCommand.exportMarkdown:
        exportAsMarkdown(context, ref);
      case MenuCommand.trash:
        _openTrash();
      case MenuCommand.showNotes:
        _home();
        setState(() => _index = 0);
      case MenuCommand.showLibrary:
        _home();
        setState(() => _index = 1);
      case MenuCommand.search:
        _openSearch();
      case MenuCommand.toggleSidebar:
        final visible = ref.read(macSidebarVisibleProvider.notifier);
        visible.state = !visible.state;
      case MenuCommand.settings:
        _showAccountMenu(context);
      case MenuCommand.back:
        Navigator.of(context, rootNavigator: true).maybePop();
      case MenuCommand.find:
        _openSearch();
      case MenuCommand.moveToTrash:
        _moveOpenItemToTrash();
      case MenuCommand.keyboardShortcuts:
        showKeyboardShortcuts(context);
      case MenuCommand.findNext:
      case MenuCommand.findPrevious:
      case MenuCommand.bold:
      case MenuCommand.italic:
      case MenuCommand.underline:
      case MenuCommand.strikethrough:
      case MenuCommand.title:
      case MenuCommand.heading:
      case MenuCommand.subheading:
      case MenuCommand.body:
      case MenuCommand.bulletList:
      case MenuCommand.numberedList:
      case MenuCommand.checklist:
      case MenuCommand.blockQuote:
      case MenuCommand.linkNote:
      case MenuCommand.citePaper:
      case MenuCommand.lockAllNotes:
        ref.read(noteLockServiceProvider).lockNow();
      case MenuCommand.lockNote:
        // The open note's editor handles it; nothing open, nothing to lock.
        break;
      case MenuCommand.interfaceLarger:
        ref.read(appearanceSettingsProvider).stepInterfaceScale(1);
      case MenuCommand.interfaceSmaller:
        ref.read(appearanceSettingsProvider).stepInterfaceScale(-1);
      case MenuCommand.interfaceDefault:
        ref.read(appearanceSettingsProvider).stepInterfaceScale(0);
      case MenuCommand.zoomIn:
      case MenuCommand.zoomOut:
      case MenuCommand.actualSize:
        // Context commands: they belong to the focused widget's
        // MenuCommandHandler. None took it, so there is nothing to act on.
        break;
    }
  }

  /// File > Move to Trash: the note or paper open in the pane, with the
  /// same Undo snackbar as the lists.
  Future<void> _moveOpenItemToTrash() async {
    final db = ref.read(databaseProvider);
    final messenger = ScaffoldMessenger.of(context);
    if (_index == 0) {
      final id = ref.read(selectedNoteProvider);
      if (id == null) return;
      final note = await db.managers.notes
          .filter((f) => f.id.equals(id))
          .getSingleOrNull();
      if (note == null) return;
      ref.read(selectedNoteProvider.notifier).state = null;
      await deleteNoteWithUndo(ref, messenger, id, note.title);
    } else {
      final id = ref.read(selectedPaperProvider);
      if (id == null) return;
      final paper = await db.managers.papers
          .filter((f) => f.id.equals(id))
          .getSingleOrNull();
      if (paper == null) return;
      ref.read(selectedPaperProvider.notifier).state = null;
      await deletePaperWithUndo(ref, messenger, id, paper.title);
    }
  }

  void _openSearch() =>
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const SearchScreen()));

  void _openTrash() =>
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const TrashScreen()));

  static const _screens = [NotesScreen(), LibraryScreen()];
  static const _titles = ['Notes', 'Library'];

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).value;
    final theme = Theme.of(context);

    return CallbackShortcuts(
      bindings: _shortcuts(context),
      child: Focus(
        autofocus: true,
        child: _buildScaffold(context, user, theme),
      ),
    );
  }

  /// Hardware-keyboard shortcuts (iPad Magic Keyboard, Android/ChromeOS
  /// keyboards): Cmd/Ctrl+N new note, +O import a PDF, +F search, +1/+2
  /// switch tabs. Invisible until used, like everything else.
  Map<ShortcutActivator, VoidCallback> _shortcuts(BuildContext context) {
    void search() =>
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const SearchScreen()));
    // On macOS the menu bar owns Cmd+N/O/1/2 (File and View menus), so
    // binding them here too would fire twice. Cmd+F stays: the menu's
    // search is Shift+Cmd+F, and the PDF viewer's own Cmd+F wins over this.
    final mac = isMac(context);
    final actions = <LogicalKeyboardKey, VoidCallback>{
      if (!mac) LogicalKeyboardKey.keyN: () => createNote(context, ref),
      if (!mac) LogicalKeyboardKey.keyO: () => importPaper(context, ref),
      LogicalKeyboardKey.keyF: search,
      if (!mac) LogicalKeyboardKey.digit1: () => setState(() => _index = 0),
      if (!mac) LogicalKeyboardKey.digit2: () => setState(() => _index = 1),
    };
    return {
      for (final entry in actions.entries)
        for (final meta in const [true, false])
          SingleActivator(entry.key, meta: meta, control: !meta): entry.value,
    };
  }

  Widget _buildScaffold(BuildContext context, AppUser? user, ThemeData theme) {
    final layout = homeLayoutFor(MediaQuery.sizeOf(context).width);
    if (layout == HomeLayout.compact) {
      return _phoneScaffold(context, user, theme);
    }

    if (isMac(context)) return _macScaffold(context, user, theme, layout);

    // Tablet: a rail instead of bottom tabs; the list (with its own header)
    // and, when there's room, the open note or paper beside it.
    final c = theme.colorScheme;
    final lists = Scaffold(
      appBar: _appBar(context, user, theme),
      body: _tabs(),
    );
    final expanded = layout == HomeLayout.expanded;
    final wideRail = MediaQuery.sizeOf(context).width >= 1280;
    // The audio bar is part of the body, not a bottomNavigationBar: a
    // Scaffold bottom bar strips the bottom safe-area inset from the body,
    // and the note editor beside the list needs it for its toolbar.
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  _Rail(
                    index: _index,
                    extended: wideRail,
                    onSelected: (value) => setState(() => _index = value),
                  ),
                  VerticalDivider(width: 1, color: c.outlineVariant),
                  if (expanded) ...[
                    SizedBox(width: wideRail ? 400 : 360, child: lists),
                    VerticalDivider(width: 1, color: c.outlineVariant),
                    Expanded(child: DetailPane(tab: _index)),
                  ] else
                    // One column, centred at a readable width.
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: readableWidth,
                          ),
                          child: lists,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const AudioPlayerBar(),
        ],
      ),
    );
  }

  /// The Mac window: a collapsible sidebar, then (wide) a resizable list
  /// column and the detail pane, or (narrower) one readable list column.
  /// No SafeArea: every column handles the title-bar band at its own top
  /// (the sidebar by padding, the AppBars by themselves).
  Widget _macScaffold(
    BuildContext context,
    AppUser? user,
    ThemeData theme,
    HomeLayout layout,
  ) {
    final c = theme.colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final sidebarOn = ref.watch(macSidebarVisibleProvider);
    final lists = Scaffold(
      appBar: AppBar(
        toolbarHeight: 52,
        titleSpacing: 18,
        title: Text(_titles[_index], style: theme.textTheme.titleLarge),
      ),
      body: _tabs(),
    );
    final Widget content;
    if (layout == HomeLayout.expanded) {
      final listWidth = ref.watch(macListWidthProvider);
      final room = width - (sidebarOn ? macSidebarWidth + 1 : 0);
      // The detail pane always keeps at least 360 points.
      final maxList = (room - 360 - 7).clamp(macListMinWidth, macListMaxWidth);
      final w = listWidth.width.clamp(macListMinWidth, maxList);
      content = Row(
        children: [
          SizedBox(
            key: const ValueKey('mac-list'),
            width: w.toDouble(),
            child: FocusTraversalGroup(child: lists),
          ),
          ColumnDivider(
            onDrag: (dx) => listWidth.set(w + dx),
            onDragEnd: listWidth.save,
          ),
          Expanded(
            child: FocusTraversalGroup(child: DetailPane(tab: _index)),
          ),
        ],
      );
    } else {
      content = FocusTraversalGroup(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: readableWidth),
            child: lists,
          ),
        ),
      );
    }
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                MacSidebarSlot(
                  visible: sidebarOn,
                  child: Row(
                    children: [
                      FocusTraversalGroup(
                        child: MacSidebar(
                          index: _index,
                          email: user?.email,
                          onSelected: (i) => setState(() => _index = i),
                          onPrimary: () => _index == 0
                              ? createNote(context, ref)
                              : importPaper(context, ref),
                          onSearch: _openSearch,
                          onTrash: _openTrash,
                          onSettings: () => _showAccountMenu(context),
                        ),
                      ),
                      VerticalDivider(width: 1, color: c.outlineVariant),
                    ],
                  ),
                ),
                Expanded(child: content),
              ],
            ),
          ),
          const AudioPlayerBar(),
        ],
      ),
    );
  }

  /// The tab content, under the opt-in "highlights to revisit" line (which
  /// takes no space unless the reader turned it on and something is due).
  Widget _tabs() => Column(
    children: [
      const ReviewPrompt(),
      Expanded(
        child: FadeThroughIndexedStack(index: _index, children: _screens),
      ),
    ],
  );

  PreferredSizeWidget _appBar(
    BuildContext context,
    AppUser? user,
    ThemeData theme,
  ) {
    return AppBar(
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
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: 'Search',
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const SearchScreen())),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: _AccountButton(
            email: user?.email,
            onPressed: () => _showAccountMenu(context),
          ),
        ),
      ],
    );
  }

  Widget _phoneScaffold(BuildContext context, AppUser? user, ThemeData theme) {
    return Scaffold(
      appBar: _appBar(context, user, theme),
      body: _tabs(),
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

  /// Everything that isn't the reading/writing loop lives behind the
  /// account button: sync and sign-in, trash, backup and restore.
  Future<void> _showAccountMenu(BuildContext context) async {
    final sync = ref.read(syncServiceProvider);
    final user = ref.read(authServiceProvider).currentUser;
    Widget content(BuildContext context) => SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (user == null)
            ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: const Text('Sign in'),
              subtitle: const Text('Sync your library across devices'),
              onTap: () => Navigator.pop(context, 'signin'),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(
                user.email,
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
                onTap: () => Navigator.pop(context, 'switch'),
              ),
            Consumer(
              builder: (context, ref, _) {
                final t = ref.watch(transferSettingsProvider);
                return Column(
                  children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.wifi),
                      title: const Text('Send files on Wi-Fi only'),
                      subtitle: const Text(
                        'Notes always sync. Opening a file downloads it '
                        'on any network.',
                      ),
                      value: t.wifiOnly,
                      onChanged: t.setWifiOnly,
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.cloud_download_outlined),
                      title: const Text('Download files when opened'),
                      subtitle: const Text(
                        'Otherwise papers and audio download in the '
                        'background.',
                      ),
                      value: t.onDemand,
                      onChanged: t.setOnDemand,
                    ),
                  ],
                );
              },
            ),
          ],
          const Divider(),
          Consumer(
            builder: (context, ref, _) {
              final settings = ref.watch(appearanceSettingsProvider);
              return ListTile(
                leading: const Icon(Icons.brightness_6_outlined),
                title: const Text('Appearance'),
                trailing: SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: ThemeMode.system, label: Text('Auto')),
                    ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                    ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                  ],
                  selected: {settings.themeMode},
                  onSelectionChanged: (s) => settings.setThemeMode(s.single),
                ),
              );
            },
          ),
          // Desktop only: the whole interface's size, for big or
          // low-density displays (View → Interface Size, ⌥⌘+ / ⌥⌘−).
          if (isDesktop(context))
            Consumer(
              builder: (context, ref, _) {
                final settings = ref.watch(appearanceSettingsProvider);
                return ListTile(
                  leading: const Icon(Icons.format_size),
                  title: const Text('Interface size'),
                  subtitle: const Text('For large or ultrawide displays'),
                  trailing: DropdownButton<double>(
                    value: settings.interfaceScale,
                    underline: const SizedBox.shrink(),
                    borderRadius: const BorderRadius.all(Radius.circular(8)),
                    items: [
                      for (final s in AppearanceSettings.interfaceScales)
                        DropdownMenuItem(
                          value: s,
                          child: Text('${(s * 100).round()}%'),
                        ),
                    ],
                    onChanged: (s) {
                      if (s != null) settings.setInterfaceScale(s);
                    },
                  ),
                );
              },
            ),
          const NotesPasswordSettings(),
          Consumer(
            builder: (context, ref, _) {
              final count = ref.watch(trashItemsProvider).value?.length ?? 0;
              return ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Trash'),
                subtitle: count == 0
                    ? null
                    : Text('$count item${count == 1 ? '' : 's'}'),
                onTap: () => Navigator.pop(context, 'trash'),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.save_alt_outlined),
            title: const Text('Back up to a file'),
            subtitle: const Text('Notes, papers and files in one zip'),
            onTap: () => Navigator.pop(context, 'backup'),
          ),
          ListTile(
            leading: const Icon(Icons.folder_zip_outlined),
            title: const Text('Export as Markdown'),
            subtitle: const Text('A folder of notes for Obsidian'),
            onTap: () => Navigator.pop(context, 'markdown'),
          ),
          ListTile(
            leading: const Icon(Icons.settings_backup_restore),
            title: const Text('Restore from a backup'),
            onTap: () => Navigator.pop(context, 'restore'),
          ),
          if (user != null) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sign out'),
              onTap: () => Navigator.pop(context, 'signout'),
            ),
            if (sync.currentStatus != SyncStatus.offline)
              ListTile(
                leading: const Icon(Icons.layers_clear_outlined),
                title: const Text('Sign out and clear this device'),
                onTap: () => Navigator.pop(context, 'clear'),
              ),
          ],
        ],
      ),
    );
    final String? action;
    if (isDesktop(context)) {
      // Settings: a centred dialog on the desktop.
      action = await showDialog<String>(
        context: context,
        builder: (context) => Dialog(
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                  child: Text(
                    'Settings',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Flexible(child: content(context)),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      );
    } else {
      action = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        builder: (context) => SafeArea(child: content(context)),
      );
    }
    if (action == null || !context.mounted) return;
    switch (action) {
      case 'signin':
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const SignInScreen()));
      case 'switch':
        await _eraseDevice(context, signOutAfter: false);
      case 'trash':
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const TrashScreen()));
      case 'backup':
        await backUpToFile(context, ref);
      case 'markdown':
        await exportAsMarkdown(context, ref);
      case 'restore':
        await restoreFromBackupFile(context, ref);
      case 'signout':
        await ref.read(authServiceProvider).signOut();
      case 'clear':
        await _eraseDevice(context, signOutAfter: true);
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
      icon: SyncRing(
        child: AnimatedSwitcher(
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
      ),
    );
  }
}

/// The tablet navigation: the primary action on top, then the two spaces.
/// [extended] (wide windows) shows labels beside the icons.
class _Rail extends ConsumerWidget {
  const _Rail({
    required this.index,
    required this.extended,
    required this.onSelected,
  });

  final int index;
  final bool extended;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (icon, label, action) = switch (index) {
      0 => (Icons.add, 'New note', createNote),
      _ => (Icons.upload_file_outlined, 'Import PDF', importPaper),
    };
    return NavigationRail(
      selectedIndex: index,
      onDestinationSelected: onSelected,
      extended: extended,
      minExtendedWidth: 200,
      labelType: extended
          ? NavigationRailLabelType.none
          : NavigationRailLabelType.all,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      leading: Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 20),
        child: extended
            ? FloatingActionButton.extended(
                heroTag: null,
                elevation: 0,
                onPressed: () => action(context, ref),
                icon: Icon(icon),
                label: Text(label),
              )
            : FloatingActionButton(
                heroTag: null,
                elevation: 0,
                tooltip: label,
                onPressed: () => action(context, ref),
                child: AnimatedSwitcher(
                  duration: AppMotion.short,
                  child: Icon(icon, key: ValueKey(icon)),
                ),
              ),
      ),
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.edit_note_outlined),
          selectedIcon: Icon(Icons.edit_note),
          label: Text('Notes'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.library_books_outlined),
          selectedIcon: Icon(Icons.library_books),
          label: Text('Library'),
        ),
      ],
    );
  }
}
