import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database_provider.dart';
import '../../l10n/l10n.dart';
import '../home/adaptive.dart';
import '../library/pdf_viewer_screen.dart';
import '../notes/note_sections.dart' show NoteHeading;
import '../notes/notes_providers.dart';
import '../platform/mac_window.dart';
import '../projects/project_page.dart';
import '../search/saved_searches.dart' show savedSearchRunRequestProvider;
import '../search/search_screen.dart';
import 'nav_history.dart';
import 'nav_target.dart';
import 'panes.dart';
import 'quick_switcher_data.dart';
import 'quick_switcher_nav.dart';
import 'switcher_rank.dart';

/// How a chosen row opens: plainly, beside the current pane (⌘↩), or a
/// paper's PDF at its last page (⌥↩).
enum SwitcherOpen { normal, newPane, pdf }

/// A command the `>` prefix lists.
class SwitcherCommand {
  const SwitcherCommand(
    this.id,
    this.label,
    this.icon, {
    this.command,
    this.noteOnly = false,
    this.keys,
  });

  final String id;
  final String Function(AppLocalizations l10n) label;
  final IconData icon;

  /// The menu command it runs; null for "Open project…", which narrows the
  /// list instead.
  final MenuCommand? command;
  final bool noteOnly;
  final String? keys;
}

/// The commands of `>`, in order. Note-only ones show while a note is open.
final switcherCommands = <SwitcherCommand>[
  SwitcherCommand(
    'today',
    (l) => l.switcherCmdToday,
    Icons.today_outlined,
    command: MenuCommand.todaysNote,
    keys: '⌘T',
  ),
  SwitcherCommand(
    'new',
    (l) => l.switcherCmdNewNote,
    Icons.edit_note,
    command: MenuCommand.newNote,
    keys: '⌘N',
  ),
  SwitcherCommand(
    'import',
    (l) => l.switcherCmdImportPdf,
    Icons.picture_as_pdf_outlined,
    command: MenuCommand.importPdf,
    keys: '⌘O',
  ),
  SwitcherCommand(
    'export',
    (l) => l.switcherCmdExport,
    Icons.ios_share,
    command: MenuCommand.exportMarkdown,
  ),
  SwitcherCommand(
    'bibliography',
    (l) => l.switcherCmdBibliography,
    Icons.format_list_numbered,
    command: MenuCommand.addBibliography,
    noteOnly: true,
  ),
  SwitcherCommand(
    'lock',
    (l) => l.switcherCmdLockNote,
    Icons.lock_outline,
    command: MenuCommand.lockNote,
    noteOnly: true,
  ),
  SwitcherCommand(
    'lockAll',
    (l) => l.switcherCmdLockAll,
    Icons.lock_clock_outlined,
    command: MenuCommand.lockAllNotes,
  ),
  SwitcherCommand(
    'attachments',
    (l) => l.switcherCmdAttachments,
    Icons.attach_file,
    command: MenuCommand.showAttachments,
    keys: '⌘3',
  ),
  SwitcherCommand(
    'project',
    (l) => l.switcherCmdOpenProject,
    Icons.folder_special_outlined,
  ),
  SwitcherCommand(
    'settings',
    (l) => l.switcherCmdSettings,
    Icons.settings_outlined,
    command: MenuCommand.settings,
    keys: '⌘,',
  ),
  SwitcherCommand(
    'shortcuts',
    (l) => l.switcherCmdShortcuts,
    Icons.keyboard_outlined,
    command: MenuCommand.keyboardShortcuts,
    keys: '⌘/',
  ),
];

/// What the switcher returned.
class SwitcherChoice {
  const SwitcherChoice.item(this.item, [this.open = SwitcherOpen.normal])
    : command = null,
      heading = null,
      navigator = null;
  const SwitcherChoice.command(this.command)
    : item = null,
      heading = null,
      navigator = null,
      open = SwitcherOpen.normal;
  const SwitcherChoice.heading(this.heading, this.navigator)
    : item = null,
      command = null,
      open = SwitcherOpen.normal;

  final SwitcherItem? item;
  final SwitcherCommand? command;
  final NoteHeading? heading;
  final NoteNavigator? navigator;
  final SwitcherOpen open;
}

/// Shows the switcher: a Spotlight-like panel near the top on desktop, a
/// bottom sheet elsewhere. Null if dismissed.
Future<SwitcherChoice?> showQuickSwitcher(
  BuildContext context,
  WidgetRef ref,
) {
  final navigator = ref.read(noteNavigatorRegistryProvider).focused;
  if (isDesktop(context)) {
    return showDialog<SwitcherChoice>(
      context: context,
      barrierColor: Colors.black26,
      builder: (_) => Dialog(
        key: const ValueKey('quick-switcher'),
        alignment: Alignment.topCenter,
        insetPadding: const EdgeInsets.fromLTRB(24, 96, 24, 24),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: QuickSwitcherPanel(navigator: navigator),
        ),
      ),
    );
  }
  return showModalBottomSheet<SwitcherChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheet) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheet).bottom),
      child: SizedBox(
        key: const ValueKey('quick-switcher'),
        height: MediaQuery.sizeOf(sheet).height * 0.7,
        child: QuickSwitcherPanel(navigator: navigator, expand: true),
      ),
    ),
  );
}

/// Carries out [choice] through the app's usual paths. [home] closes pages
/// pushed over home, [showTab] switches the Notes/Library tab and
/// [runCommand] is the shell's menu-command handling.
Future<void> runSwitcherChoice(
  BuildContext context,
  WidgetRef ref,
  SwitcherChoice choice, {
  required VoidCallback home,
  required void Function(int tab) showTab,
  required void Function(MenuCommand command) runCommand,
}) async {
  final heading = choice.heading;
  if (heading != null) {
    choice.navigator?.jumpTo(heading);
    return;
  }
  final cmd = choice.command?.command;
  if (cmd != null) {
    if (choice.command!.noteOnly) {
      ref.read(noteNavigatorRegistryProvider).focused?.run(cmd);
    } else {
      runCommand(cmd);
    }
    return;
  }
  final item = choice.item;
  if (item == null) return;
  switch (item.kind) {
    case SwitcherKind.note:
      home();
      showTab(0);
      choice.open == SwitcherOpen.newPane
          ? openInNewPane(context, ref, NoteTarget(item.id))
          : openNote(context, ref, item.id);
    case SwitcherKind.paper:
      home();
      showTab(1);
      if (choice.open == SwitcherOpen.pdf && item.hasPdf) {
        final paper = await ref
            .read(databaseProvider)
            .managers
            .papers
            .filter((f) => f.id.equals(item.id))
            .getSingleOrNull();
        final path = paper?.pdfPath;
        if (path != null && context.mounted) {
          if (!ref.read(navReplayingProvider)) {
            ref
                .read(navHistoryProvider.notifier)
                .visit(PaperTarget(item.id, page: paper?.lastPage));
          }
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PdfViewerScreen(
                paperId: item.id,
                pdfPath: path,
                initialPage: paper?.lastPage,
              ),
            ),
          );
          return;
        }
      }
      if (!context.mounted) return;
      choice.open == SwitcherOpen.newPane
          ? openInNewPane(context, ref, PaperTarget(item.id))
          : openPaper(context, ref, item.id);
    case SwitcherKind.project:
      home();
      if (!ref.read(navReplayingProvider)) {
        ref.read(navHistoryProvider.notifier).visit(ProjectTarget(item.id));
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ProjectScreen(projectId: item.id),
        ),
      );
    case SwitcherKind.folder:
      home();
      showTab(0);
      ref.read(notesFilterProvider.notifier).state = FolderFilter(item.id);
    case SwitcherKind.tag:
      home();
      showTab(0);
      ref.read(notesFilterProvider.notifier).state = TagFilter(item.id);
    case SwitcherKind.savedSearch:
      if (isMac(context)) {
        ref.read(savedSearchRunRequestProvider.notifier).state = item.query;
      } else {
        home();
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
        );
      }
  }
}

class _Entry {
  const _Entry({
    required this.title,
    required this.icon,
    required this.hint,
    required this.choice,
    this.subtitle = '',
    this.keys,
    this.kind,
    this.selects,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String hint;
  final String? keys;
  final SwitcherKind? kind;
  /// The choice for each way of opening (⌘↩, ⌥↩ fall back to normal).
  final SwitcherChoice Function(SwitcherOpen open) choice;

  /// "Open project…": narrows the list to this kind instead of choosing.
  final SwitcherKind? selects;
}

class _Row {
  const _Row.header(this.header) : entry = null;
  const _Row.entry(this.entry) : header = null;
  final String? header;
  final _Entry? entry;
}

IconData _iconFor(SwitcherKind kind) => switch (kind) {
  SwitcherKind.note => Icons.notes_outlined,
  SwitcherKind.paper => Icons.article_outlined,
  SwitcherKind.project => Icons.folder_special_outlined,
  SwitcherKind.savedSearch => Icons.saved_search,
  SwitcherKind.folder => Icons.folder_outlined,
  SwitcherKind.tag => Icons.tag,
};

String _kindLabel(AppLocalizations l, SwitcherKind kind) => switch (kind) {
  SwitcherKind.note => l.switcherNotes,
  SwitcherKind.paper => l.switcherPapers,
  SwitcherKind.project => l.switcherProjects,
  SwitcherKind.savedSearch => l.switcherSearches,
  SwitcherKind.folder => l.switcherFolders,
  SwitcherKind.tag => l.switcherTags,
};

/// The switcher's content: one field and a list of results.
class QuickSwitcherPanel extends ConsumerStatefulWidget {
  const QuickSwitcherPanel({super.key, this.navigator, this.expand = false});

  /// The note editor to jump around in (`#`) and run note commands on.
  final NoteNavigator? navigator;

  /// Fill the height (the bottom sheet) instead of sizing to the results.
  final bool expand;

  @override
  ConsumerState<QuickSwitcherPanel> createState() => _QuickSwitcherPanelState();
}

class _QuickSwitcherPanelState extends ConsumerState<QuickSwitcherPanel> {
  final _controller = TextEditingController();
  late final FocusNode _focus = FocusNode(onKeyEvent: _onKey);
  final _selectedKey = GlobalKey();
  int _selected = 0;
  SwitcherKind? _only;
  List<_Row> _rows = const [];

  List<_Entry> get _entries => [
    for (final r in _rows)
      if (r.entry != null) r.entry!,
  ];

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final entries = _entries;
    if (key == LogicalKeyboardKey.arrowDown) {
      if (entries.isNotEmpty) _move((_selected + 1) % entries.length);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (entries.isNotEmpty) {
        _move((_selected - 1 + entries.length) % entries.length);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (event is KeyRepeatEvent) return KeyEventResult.handled;
      final keys = HardwareKeyboard.instance;
      _activate(
        _selected,
        keys.isMetaPressed || keys.isControlPressed
            ? SwitcherOpen.newPane
            : keys.isAltPressed
            ? SwitcherOpen.pdf
            : SwitcherOpen.normal,
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace &&
        _controller.text.isEmpty &&
        _only != null) {
      setState(() {
        _only = null;
        _selected = 0;
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _move(int to) {
    setState(() => _selected = to);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _selectedKey.currentContext;
      if (c != null && c.mounted) {
        Scrollable.ensureVisible(c, duration: Duration.zero);
      }
    });
  }

  void _activate(int index, SwitcherOpen open) {
    final entries = _entries;
    if (index < 0 || index >= entries.length) return;
    final entry = entries[index];
    if (entry.selects != null) {
      setState(() {
        _only = entry.selects;
        _controller.clear();
        _selected = 0;
      });
      return;
    }
    Navigator.of(context).pop(entry.choice(open));
  }

  List<_Row> _build(
    AppLocalizations l10n,
    List<SwitcherItem> items,
    String text,
  ) {
    SwitcherChoice itemChoice(SwitcherItem i, SwitcherOpen o) =>
        SwitcherChoice.item(i, o);
    String hintFor(SwitcherItem i) => switch (i.kind) {
      SwitcherKind.note ||
      SwitcherKind.paper ||
      SwitcherKind.project => l10n.switcherHintOpen,
      _ => l10n.switcherHintShow,
    };
    _Entry entryFor(SwitcherItem i) => _Entry(
      title: i.title.isEmpty ? '—' : i.title,
      subtitle: switch (i.kind) {
        SwitcherKind.project => l10n.switcherSubProject,
        SwitcherKind.folder => l10n.switcherSubFolder,
        SwitcherKind.tag => l10n.switcherSubTag,
        SwitcherKind.savedSearch => i.subtitle.isEmpty
            ? l10n.switcherSubSearch
            : '${l10n.switcherSubSearch} · ${i.subtitle}',
        _ => i.subtitle,
      },
      icon: i.pinned ? Icons.push_pin_outlined : _iconFor(i.kind),
      hint: hintFor(i),
      kind: i.kind,
      choice: (o) => itemChoice(i, o),
    );

    List<_Row> grouped(List<SwitcherItem> list) {
      final kinds = <SwitcherKind>[];
      for (final i in list) {
        if (!kinds.contains(i.kind)) kinds.add(i.kind);
      }
      final rows = <_Row>[];
      for (final k in kinds) {
        if (kinds.length > 1) rows.add(_Row.header(_kindLabel(l10n, k)));
        for (final i in list.where((i) => i.kind == k)) {
          rows.add(_Row.entry(entryFor(i)));
        }
      }
      return rows;
    }

    if (text.startsWith('#')) {
      final note = widget.navigator;
      if (note == null) return const [];
      final headings = note.headings();
      final order = rankHeadings(headings, text.substring(1));
      return [
        if (order.isNotEmpty) _Row.header(l10n.switcherHeadings),
        for (final i in order)
          _Row.entry(
            _Entry(
              title: headings[i].text,
              subtitle: 'H${headings[i].level}',
              icon: Icons.title,
              hint: l10n.switcherHintJump,
              choice: (_) => SwitcherChoice.heading(headings[i], note),
            ),
          ),
      ];
    }

    if (text.startsWith('>')) {
      final q = foldForMatch(text.substring(1).trim());
      final noteOpen = widget.navigator != null;
      final listed = [
        for (final c in switcherCommands)
          if (!c.noteOnly || noteOpen)
            if (q.isEmpty || matchTier(q, foldForMatch(c.label(l10n))) != null)
              c,
      ];
      if (q.isNotEmpty) {
        listed.sort(
          (a, b) => matchTier(q, foldForMatch(a.label(l10n)))!.compareTo(
            matchTier(q, foldForMatch(b.label(l10n)))!,
          ),
        );
      }
      return [
        for (final c in listed)
          _Row.entry(
            _Entry(
              title: c.label(l10n),
              icon: c.icon,
              hint: l10n.switcherHintRun,
              keys: isMac(context) ? c.keys : null,
              selects: c.command == null ? SwitcherKind.project : null,
              choice: (_) => SwitcherChoice.command(c),
            ),
          ),
      ];
    }

    final pool = _only == null
        ? items
        : [
            for (final i in items)
              if (i.kind == _only) i,
          ];

    if (text.isEmpty || text == '?') {
      if (_only != null) {
        final all = [...pool]
          ..sort(
            (a, b) => foldForMatch(a.title).compareTo(foldForMatch(b.title)),
          );
        return grouped(all);
      }
      final history = ref.watch(navHistoryProvider.notifier).history;
      final byKey = {
        for (final i in items)
          if (i.targetKey != null) i.targetKey!: i,
      };
      final r = switcherRecents(
        historyNewestFirst: [
          for (final e in history.entries.reversed) e.target.key,
        ],
        byKey: byKey,
        pinned: [
          for (final i in items)
            if (i.kind == SwitcherKind.note && i.pinned) i,
        ],
        currentKey: history.current?.target.key,
      );
      return [
        if (r.recent.isNotEmpty && r.pinned.isNotEmpty)
          _Row.header(l10n.switcherRecent),
        for (final i in r.recent) _Row.entry(entryFor(i)),
        if (r.pinned.isNotEmpty && r.recent.isNotEmpty)
          _Row.header(l10n.switcherPinned),
        for (final i in r.pinned) _Row.entry(entryFor(i)),
      ];
    }

    final ranked = rankSwitcherItems(pool, text);
    return grouped(ranked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    ref.watch(navHistoryProvider);
    final items = ref.watch(switcherItemsProvider).value ?? const [];
    final text = _controller.text;
    _rows = _build(l10n, items, text);
    final entries = _entries;
    if (_selected >= entries.length) _selected = 0;

    final empty = entries.isEmpty;
    final message = text.startsWith('#') && widget.navigator == null
        ? l10n.switcherNoNote
        : text.trim().isNotEmpty && empty
        ? l10n.switcherNoResults(text)
        : null;

    var entryIndex = -1;
    final list = <Widget>[];
    for (final row in _rows) {
      if (row.header != null) {
        list.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
            child: Text(
              row.header!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: c.onSurfaceVariant,
              ),
            ),
          ),
        );
        continue;
      }
      entryIndex++;
      final index = entryIndex;
      final selected = index == _selected;
      final e = row.entry!;
      list.add(
        InkWell(
          key: selected ? _selectedKey : ValueKey('switcher-row-$index'),
          onTap: () => _activate(index, SwitcherOpen.normal),
          child: Container(
            color: selected ? c.secondaryContainer : null,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(e.icon, size: 20, color: c.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge,
                      ),
                      if (e.subtitle.isNotEmpty)
                        Text(
                          e.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: c.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                if (e.keys != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      e.keys!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: c.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (selected)
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Text(
                      e.hint,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: c.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    final body = ListView(
      shrinkWrap: !widget.expand,
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        if (message != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: c.onSurfaceVariant,
              ),
            ),
          ),
        ...list,
        if (text == '?')
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              l10n.switcherHelp,
              key: const ValueKey('switcher-help'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: c.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );

    return Semantics(
      label: l10n.switcherTitle,
      child: Column(
        mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              key: const ValueKey('switcher-field'),
              controller: _controller,
              focusNode: _focus,
              autofocus: true,
              textInputAction: TextInputAction.go,
              onChanged: (_) => setState(() => _selected = 0),
              onSubmitted: (_) {},
              decoration: InputDecoration(
                hintText: _only == SwitcherKind.project
                    ? l10n.switcherProjects
                    : l10n.switcherPlaceholder,
                prefixIcon: const Icon(Icons.search),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
          const Divider(height: 1),
          if (widget.expand)
            Expanded(child: body)
          else
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 440),
                child: body,
              ),
            ),
        ],
      ),
    );
  }
}
