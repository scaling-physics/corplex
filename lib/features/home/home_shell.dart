import 'dart:async';

import 'package:flutter/material.dart';

import '../spell/spell_checker.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_service.dart';
import '../auth/sign_in_screen.dart';
import '../../data/database_provider.dart';
import '../../data/trash.dart';
import '../../l10n/l10n.dart';
import '../audio/audio_player_bar.dart';
import '../capture/quick_capture.dart';
import '../capture/quick_capture_actions.dart';
import '../library/library_screen.dart';
import '../library/papers_providers.dart' show filteredPapersProvider;
import '../search/pdf_text_index.dart' show pdfIndexStartupProvider;
import '../ocr/ocr_service.dart';
import '../settings/appearance_settings.dart';
import '../library/library_actions.dart';
import '../platform/mac_window.dart';
import 'adaptive.dart';
import '../trash/trash_actions.dart';
import 'keyboard_shortcuts.dart';
import 'mac_sidebar.dart';
import '../sync/sync_messages.dart';
import '../sync/sync_ring.dart';
import '../sync/sync_service.dart';
import '../sync/transfer_settings.dart';
import '../attachments/attachments_browser.dart';
import '../attachments/attachments_providers.dart' show allAttachmentsProvider;
import 'mac_toolbar.dart';
import '../notes/note_file_actions.dart';
import '../notes/notes_screen.dart';
import '../projects/projects_providers.dart';
import '../notes/tags_providers.dart';
import '../notes/folders_providers.dart';
import '../notes/notes_providers.dart';
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
  StreamSubscription<QuickCapture>? _captures;

  // Mac: the toolbar's search field, whose results fill the list column,
  // and whether the attachments fill the window in place of list and pane.
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'mac-toolbar-search');
  Timer? _searchDebounce;
  String _searchQuery = '';
  bool _attachments = false;

  @override
  void initState() {
    super.initState();
    // The native menu bar (macOS). A plain stream subscription rather than
    // a provider listener: the same command twice in a row must fire twice.
    _menu = ref.read(macWindowProvider).menuCommands.listen(_onCommand);
    // Quick capture: the global hotkey, the Dock menu and Services. The
    // hotkey is registered while the setting is on (inert off the Mac).
    final window = ref.read(macWindowProvider);
    _captures = window.captures.listen(_onCapture);
    window.setQuickNoteHotKey(
      ref.read(appearanceSettingsProvider).quickNoteHotKey,
    );
    ref.listenManual(
      appearanceSettingsProvider.select((s) => s.quickNoteHotKey),
      (previous, on) {
        if (previous != on) window.setQuickNoteHotKey(on);
      },
    );
    // Housekeeping: items that have sat in the trash past the retention
    // period go for good. Never worth failing startup over.
    purgeTrash(ref.read(databaseProvider)).catchError((_) => 0);
    // Scanned papers whose text recognition was cut short carry on. With
    // none (every test, every fresh install) this is one empty query.
    ref.read(ocrStartupProvider);
    // Papers' full text for search is indexed quietly in the background.
    ref.read(pdfIndexStartupProvider);
  }

  @override
  void dispose() {
    _menu?.cancel();
    _captures?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged(String text) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      setState(() {
        _searchQuery = text.trim();
        if (_searchQuery.isNotEmpty) _attachments = false;
      });
    });
  }

  /// Leaves search results and the attachments for the list (choosing a
  /// sidebar row, as in Notes).
  void _clearMacModes() {
    _searchDebounce?.cancel();
    _searchController.clear();
    _searchQuery = '';
    _attachments = false;
  }

  void _showMacAttachments() {
    _home();
    setState(() {
      _clearMacModes();
      _attachments = true;
    });
  }

  /// Back to the home screen, closing anything pushed over it.
  void _home() {
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  void _onCapture(QuickCapture capture) {
    if (!mounted) return;
    _home();
    setState(() => _index = 0);
    handleQuickCapture(context, ref, capture);
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
      case MenuCommand.showAttachments:
        if (isMac(context)) {
          _showMacAttachments();
        } else {
          _home();
          showAttachmentsBrowser(context);
        }
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
      case MenuCommand.highlight:
      case MenuCommand.monospaced:
      case MenuCommand.title:
      case MenuCommand.heading:
      case MenuCommand.subheading:
      case MenuCommand.body:
      case MenuCommand.bulletList:
      case MenuCommand.numberedList:
      case MenuCommand.checklist:
      case MenuCommand.blockQuote:
      case MenuCommand.insertTable:
      case MenuCommand.addComment:
      case MenuCommand.linkNote:
      case MenuCommand.citePaper:
      case MenuCommand.collapseSections:
      case MenuCommand.expandSections:
        // Editor commands; no note editor has focus, so nothing to format.
        // (An empty case falls through, so these need their own body:
        // they once fell into lockAllNotes and ⌘B locked every note.)
        break;
      case MenuCommand.lockAllNotes:
        ref.read(noteLockServiceProvider).lockNow();
      case MenuCommand.lockNote:
        // The open note's editor handles it; nothing open, nothing to lock.
        break;
      case MenuCommand.duplicateNote:
      case MenuCommand.printNote:
        // The open note's editor takes these when it has focus; from the
        // list, they act on the note open in the pane.
        final id = _index == 0 ? ref.read(selectedNoteProvider) : null;
        if (id == null) break;
        command == MenuCommand.printNote
            ? printNote(context, ref, id)
            : duplicateNoteAndOpen(context, ref, id);
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
    final l10n = context.l10n;
    if (_index == 0) {
      final id = ref.read(selectedNoteProvider);
      if (id == null) return;
      final note = await db.managers.notes
          .filter((f) => f.id.equals(id))
          .getSingleOrNull();
      if (note == null) return;
      ref.read(selectedNoteProvider.notifier).state = null;
      await deleteNoteWithUndo(
        ref,
        messenger,
        id,
        note.title,
        l10n: l10n,
      );
    } else {
      final id = ref.read(selectedPaperProvider);
      if (id == null) return;
      final paper = await db.managers.papers
          .filter((f) => f.id.equals(id))
          .getSingleOrNull();
      if (paper == null) return;
      ref.read(selectedPaperProvider.notifier).state = null;
      await deletePaperWithUndo(
        ref,
        messenger,
        id,
        paper.title,
        l10n: l10n,
      );
    }
  }

  /// Search: on a Mac the toolbar's field (results in the list column),
  /// elsewhere the search page.
  void _openSearch() {
    if (isMac(context)) {
      _home();
      if (_attachments) setState(() => _attachments = false);
      _searchFocus.requestFocus();
      _searchController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _searchController.text.length,
      );
      return;
    }
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SearchScreen()));
  }

  void _openTrash() =>
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const TrashScreen()));

  static const _screens = [NotesScreen(), LibraryScreen()];

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
    final lights = ref.watch(macFullScreenProvider)
        ? 0.0
        : macTrafficLightsWidth;
    final expanded = layout == HomeLayout.expanded;
    final searching = _searchQuery.isNotEmpty;

    // List and pane widths (expanded layout).
    final listWidth = ref.watch(macListWidthProvider);
    final room = width - (sidebarOn ? macSidebarWidth + 1 : 0);
    // The detail pane always keeps at least 360 points.
    final maxList = (room - 360 - 7).clamp(macListMinWidth, macListMaxWidth);
    final w = listWidth.width.clamp(macListMinWidth, maxList);
    final pane = room - w - 7;
    // A narrow pane needs its row for the note's formatting buttons: the
    // search field moves to the list's row then (always, without a pane).
    final searchInList = !expanded || pane < 820;

    void toggleSidebar() {
      final visible = ref.read(macSidebarVisibleProvider.notifier);
      visible.state = !visible.state;
    }

    final sidebarButton = MacToolbarButton(
      key: const ValueKey('mac-show-sidebar'),
      icon: Icons.view_sidebar_outlined,
      tooltip: context.l10n.homeShowSidebarTooltip,
      onPressed: toggleSidebar,
    );
    // The space's main action: New note / Import PDF, first in the pane's
    // part of the toolbar row (Notes' compose button).
    final primary = MacToolbarButton(
      key: const ValueKey('mac-primary-action'),
      icon: _index == 0 ? Icons.edit_square : Icons.upload_file_outlined,
      tooltip: _index == 0
          ? context.l10n.homeNewNoteTooltip
          : context.l10n.homeImportPdfTooltip,
      onPressed: () =>
          _index == 0 ? createNote(context, ref) : importPaper(context, ref),
    );
    Widget search(double width) => MacToolbarSearch(
      controller: _searchController,
      focusNode: _searchFocus,
      onChanged: _onSearchChanged,
      width: width,
    );

    // Like Notes, the list is titled by the folder, project or tag shown,
    // with its count under it.
    final String title;
    final String subtitle;
    if (searching) {
      title = context.l10n.commonSearch;
      subtitle = context.l10n.homeSearchSubtitle;
    } else if (_index == 0) {
      title = notesFilterTitle(
        ref.watch(notesFilterProvider),
        folders: ref.watch(foldersListProvider).value ?? const [],
        projects: ref.watch(projectsListProvider).value ?? const [],
        tags: ref.watch(tagsListProvider).value ?? const [],
        l10n: context.l10n,
      );
      subtitle = context.l10n.homeCountNotes(
        ref.watch(visibleNotesProvider).value?.length ?? 0,
      );
    } else {
      title = context.l10n.commonLibrary;
      subtitle = context.l10n.homeCountPapers(
        ref.watch(filteredPapersProvider).value?.length ?? 0,
      );
    }
    final listMenu = _index == 0
        ? PopupMenuButton<String>(
            key: const ValueKey('mac-list-menu'),
            tooltip: context.l10n.commonMore,
            icon: const Icon(Icons.more_horiz, size: 19),
            onSelected: (v) {
              if (v == 'attachments') _showMacAttachments();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'attachments',
                child: ListTile(
                  leading: const Icon(Icons.attach_file),
                  title: Text(context.l10n.homeShowAttachments),
                  trailing: const Text('⌘3'),
                ),
              ),
            ],
          )
        : LibraryMenuButton(
            key: const ValueKey('mac-list-menu'),
            onShowAttachments: _showMacAttachments,
          );

    final lists = Column(
      children: [
        MacToolbarRow(
          leadingInset: sidebarOn ? 0 : lights,
          leading: [if (!sidebarOn) sidebarButton],
          title: title,
          titleKey: const ValueKey('mac-list-title'),
          subtitle: subtitle,
          actions: [
            listMenu,
            // Without a pane the row's other controls come here.
            if (!expanded) primary,
            if (searchInList) search(expanded ? 150 : 200),
          ],
        ),
        Expanded(
          child: Material(
            type: MaterialType.transparency,
            child: IndexedStack(
              // The list keeps its place while results show over it.
              index: searching ? 1 : 0,
              sizing: StackFit.expand,
              children: [
                _tabs(),
                if (searching)
                  SearchResultsView(
                    query: _searchQuery,
                    onOpenNote: (id) {
                      setState(() => _index = 0);
                      openNote(context, ref, id);
                    },
                    onOpenPaper: (id) {
                      setState(() => _index = 1);
                      openPaper(context, ref, id);
                    },
                  )
                else
                  const SizedBox.shrink(),
              ],
            ),
          ),
        ),
      ],
    );

    final Widget content;
    if (_attachments) {
      content = Column(
        children: [
          MacToolbarRow(
            leadingInset: sidebarOn ? 0 : lights,
            leading: [if (!sidebarOn) sidebarButton],
            title: context.l10n.homeAttachments,
            subtitle: context.l10n.homeCountItems(
              ref.watch(allAttachmentsProvider).value?.length ?? 0,
            ),
            actions: [
              TextButton(
                key: const ValueKey('mac-attachments-done'),
                onPressed: () => setState(() => _attachments = false),
                child: Text(context.l10n.commonDone),
              ),
              search(200),
            ],
          ),
          Expanded(
            child: AttachmentsBrowserScreen(
              embedded: true,
              onLeave: () => setState(() => _attachments = false),
            ),
          ),
        ],
      );
    } else if (expanded) {
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
            child: FocusTraversalGroup(
              child: MacPaneChrome(
                leading: primary,
                trailing: searchInList
                    ? const SizedBox(width: 6)
                    : search(pane >= 1000 ? 220 : 180),
                child: DetailPane(tab: _index),
              ),
            ),
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
            // Each column draws its part of the toolbar row in the title
            // bar band, so none of them takes the band as padding.
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: Row(
                children: [
                  MacSidebarSlot(
                    visible: sidebarOn,
                    child: Row(
                      children: [
                        FocusTraversalGroup(
                          child: MacSidebar(
                            index: _index,
                            selectionShown: !searching && !_attachments,
                            email: user?.email,
                            onSelected: (i) => setState(() {
                              _clearMacModes();
                              _index = i;
                            }),
                            onToggleSidebar: toggleSidebar,
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
          _index == 0 ? context.l10n.commonNotes : context.l10n.commonLibrary,
          key: ValueKey(_index),
          style: theme.textTheme.headlineMedium,
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: context.l10n.commonSearch,
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
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.edit_note_outlined),
                selectedIcon: const Icon(Icons.edit_note),
                label: context.l10n.commonNotes,
              ),
              NavigationDestination(
                icon: const Icon(Icons.library_books_outlined),
                selectedIcon: const Icon(Icons.library_books),
                label: context.l10n.commonLibrary,
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
    Widget content(BuildContext context) {
      final l10n = context.l10n;
      return SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (user == null)
              ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: Text(l10n.settingsSignIn),
                subtitle: Text(l10n.settingsSignInSubtitle),
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
                    title: Text(l10n.settingsSyncNow),
                    subtitle: Text(_syncLabel(l10n, status, sync.lastError)),
                    enabled: status != SyncStatus.offline,
                    onTap: sync.syncNow,
                  );
                },
              ),
              if (sync.accountMismatch)
                ListTile(
                  leading: const Icon(Icons.swap_horiz),
                  title: Text(l10n.settingsUseThisAccount),
                  subtitle: Text(l10n.settingsUseThisAccountSubtitle),
                  onTap: () => Navigator.pop(context, 'switch'),
                ),
              Consumer(
                builder: (context, ref, _) {
                  final t = ref.watch(transferSettingsProvider);
                  return Column(
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.wifi),
                        title: Text(l10n.settingsWifiOnly),
                        subtitle: Text(l10n.settingsWifiOnlySubtitle),
                        value: t.wifiOnly,
                        onChanged: t.setWifiOnly,
                      ),
                      SwitchListTile(
                        secondary: const Icon(Icons.cloud_download_outlined),
                        title: Text(l10n.settingsOnDemand),
                        subtitle: Text(l10n.settingsOnDemandSubtitle),
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
                  title: Text(l10n.settingsAppearance),
                  trailing: SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text(l10n.settingsThemeAuto),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text(l10n.settingsThemeLight),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text(l10n.settingsThemeDark),
                      ),
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
                    title: Text(l10n.settingsInterfaceSize),
                    subtitle: Text(l10n.settingsInterfaceSizeSubtitle),
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
            if (isMac(context))
              Consumer(
                builder: (context, ref, _) {
                  final settings = ref.watch(appearanceSettingsProvider);
                  return SwitchListTile(
                    secondary: const Icon(Icons.keyboard_command_key),
                    title: Text(l10n.settingsQuickNote),
                    subtitle: Text(l10n.settingsQuickNoteSubtitle),
                    value: settings.quickNoteHotKey,
                    onChanged: settings.setQuickNoteHotKey,
                  );
                },
              ),
            Consumer(
              builder: (context, ref, _) {
                final settings = ref.watch(appearanceSettingsProvider);
                if (!ref.watch(spellCheckerProvider).available) {
                  return const SizedBox.shrink();
                }
                return SwitchListTile(
                  secondary: const Icon(Icons.spellcheck),
                  title: Text(l10n.settingsSpellCheck),
                  value: settings.spellCheck,
                  onChanged: settings.setSpellCheck,
                );
              },
            ),
            const NotesPasswordSettings(),
            Consumer(
              builder: (context, ref, _) {
                final count = ref.watch(trashItemsProvider).value?.length ?? 0;
                return ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: Text(l10n.commonTrash),
                  subtitle: count == 0
                      ? null
                      : Text(l10n.settingsTrashCount(count)),
                  onTap: () => Navigator.pop(context, 'trash'),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.save_alt_outlined),
              title: Text(l10n.settingsBackUp),
              subtitle: Text(l10n.settingsBackUpSubtitle),
              onTap: () => Navigator.pop(context, 'backup'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_zip_outlined),
              title: Text(l10n.settingsExportMarkdown),
              subtitle: Text(l10n.settingsExportMarkdownSubtitle),
              onTap: () => Navigator.pop(context, 'markdown'),
            ),
            ListTile(
              leading: const Icon(Icons.settings_backup_restore),
              title: Text(l10n.settingsRestoreFromBackup),
              onTap: () => Navigator.pop(context, 'restore'),
            ),
            if (user != null) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout),
                title: Text(l10n.settingsSignOut),
                onTap: () => Navigator.pop(context, 'signout'),
              ),
              if (sync.currentStatus != SyncStatus.offline)
                ListTile(
                  leading: const Icon(Icons.layers_clear_outlined),
                  title: Text(l10n.settingsSignOutClear),
                  onTap: () => Navigator.pop(context, 'clear'),
                ),
            ],
          ],
        ),
      );
    }

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
                    context.l10n.commonSettings,
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
          signOutAfter
              ? context.l10n.settingsClearTitle
              : context.l10n.settingsReplaceTitle,
        ),
        content: Text(
          pending == 0
              ? context.l10n.settingsEraseSafe
              : context.l10n.settingsErasePending(pending),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              signOutAfter
                  ? context.l10n.settingsClearAndSignOut
                  : context.l10n.settingsReplace,
            ),
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

  static String _syncLabel(
    AppLocalizations l10n,
    SyncStatus status,
    String? error,
  ) => switch (status) {
    SyncStatus.offline => l10n.settingsSyncOffline,
    SyncStatus.syncing => l10n.settingsSyncSyncing,
    SyncStatus.upToDate => l10n.settingsSyncUpToDate,
    SyncStatus.error => localizedSyncError(l10n, error),
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
      0 => (Icons.add, context.l10n.commonNewNote, createNote),
      _ => (
        Icons.upload_file_outlined,
        context.l10n.commonImportPdf,
        importPaper,
      ),
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
      tooltip: email ?? context.l10n.settingsSignIn,
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
      0 => (Icons.add, context.l10n.commonNewNote, createNote),
      _ => (
        Icons.upload_file_outlined,
        context.l10n.commonImportPdf,
        importPaper,
      ),
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
      destinations: [
        NavigationRailDestination(
          icon: const Icon(Icons.edit_note_outlined),
          selectedIcon: const Icon(Icons.edit_note),
          label: Text(context.l10n.commonNotes),
        ),
        NavigationRailDestination(
          icon: const Icon(Icons.library_books_outlined),
          selectedIcon: const Icon(Icons.library_books),
          label: Text(context.l10n.commonLibrary),
        ),
      ],
    );
  }
}
