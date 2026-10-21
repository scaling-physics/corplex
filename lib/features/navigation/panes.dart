import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../data/database_provider.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../home/adaptive.dart';
import '../home/mac_toolbar.dart';
import '../library/paper_detail_screen.dart';
import '../notes/note_editor_screen.dart';
import '../platform/mac_window.dart';
import '../projects/project_page.dart';
import '../projects/todos.dart' show openNoteAtSelection;
import '../settings/appearance_settings.dart';
import 'nav_target.dart';

/// The detail area must be at least this wide for more than one pane.
const panesMinAreaWidth = 1100.0;

/// A pane never gets narrower than this; preferred widths are 640-760.
const paneMinWidth = 520.0;
const paneMaxWidth = 760.0;
const _paneScrollWidth = 640.0;

/// The width of each of [count] panes in an [area] this wide: one pane
/// fills it; several share it between 520 and 760; more than fit keep
/// 640 and the stack scrolls.
double paneWidthFor(double area, int count) {
  if (count <= 1) return area;
  final fit = (area / paneMinWidth).floor();
  if (count <= fit) return (area / count).clamp(paneMinWidth, paneMaxWidth);
  return _paneScrollWidth;
}

/// Opens [target] in a new pane next to the focused one (beside the pane
/// it came from when called inside one); falls back to the usual open
/// where there are no panes.
void openInNewPane(BuildContext context, WidgetRef ref, NavTarget target) =>
    openTarget(context, ref, target, newPane: true);

/// Opens [target] replacing every open pane with one (a list click).
void openReplacingPanes(
  BuildContext context,
  WidgetRef ref,
  NavTarget target,
) => openTarget(context, ref, target, newPane: false);

/// Opens [target] through the ordinary openers; [newPane] null = decide
/// (a link from inside a pane, or a held command key, opens a new pane).
void openTarget(
  BuildContext context,
  WidgetRef ref,
  NavTarget target, {
  bool? newPane,
}) {
  switch (target) {
    case NoteTarget t:
      final start = t.selectionStart, end = t.selectionEnd;
      if (start != null && end != null) {
        openNoteAtSelection(
          context,
          ref,
          t.noteId,
          TextSelection(baseOffset: start, extentOffset: end),
          newPane: newPane,
        );
      } else {
        openNote(context, ref, t.noteId, newPane: newPane);
      }
    case PaperTarget t:
      openPaper(context, ref, t.paperId, newPane: newPane);
    case ProjectTarget t:
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProjectScreen(projectId: t.projectId),
        ),
      );
  }
}

/// Used by `openNote`/`openPaper`/`openNoteAtSelection` when the window has
/// a detail pane. Decides new pane vs replace and updates [panesProvider].
void openInPanes(
  BuildContext context,
  WidgetRef ref,
  NavTarget target, {
  bool? newPane,
}) {
  final scope = PaneScope.maybeOf(context);
  final tab = scope?.tab ?? (target is PaperTarget ? 1 : 0);
  var fresh = newPane;
  if (fresh == null) {
    final auto =
        scope != null &&
        ref.read(appearanceSettingsProvider).openLinksInPanes &&
        ref.read(panesFitProvider);
    fresh = auto || (isMac(context) && HardwareKeyboard.instance.isMetaPressed);
  }
  final notifier = ref.read(panesProvider.notifier);
  if (fresh && isMac(context)) {
    notifier.openAfter(tab, scope?.paneId, target);
  } else {
    notifier.replace(tab, target);
  }
}

/// Whether the detail area is wide enough for several panes (set by the
/// pane host).
final paneAreaWidthProvider = StateProvider<double>((ref) => 0);
final panesFitProvider = Provider<bool>(
  (ref) => ref.watch(paneAreaWidthProvider) >= panesMinAreaWidth,
);

/// Which pane a widget sits in, so a link it opens knows where it came from.
class PaneScope extends InheritedWidget {
  const PaneScope({
    super.key,
    required this.tab,
    required this.paneId,
    required super.child,
  });

  final int tab;
  final int paneId;

  static PaneScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PaneScope>();

  @override
  bool updateShouldNotify(PaneScope old) =>
      tab != old.tab || paneId != old.paneId;
}

class PaneEntry {
  const PaneEntry(this.id, this.target);
  final int id;
  final NavTarget target;
}

class PaneStack {
  const PaneStack(this.panes, this.focus);
  static const empty = PaneStack([], -1);

  final List<PaneEntry> panes;
  final int focus;

  PaneEntry? get focused =>
      focus >= 0 && focus < panes.length ? panes[focus] : null;
}

/// One stack per tab (0 Notes, 1 Library).
class PanesState {
  const PanesState(this.notes, this.library);
  final PaneStack notes;
  final PaneStack library;

  PaneStack of(int tab) => tab == 0 ? notes : library;
  PanesState with_(int tab, PaneStack s) =>
      tab == 0 ? PanesState(s, library) : PanesState(notes, s);
}

/// The open panes. `selectedNoteProvider` / `selectedPaperProvider` mirror
/// the focused pane (Notes stack: its note; Library stack: its paper), and
/// setting either from outside (a list click) replaces the stack.
class PanesNotifier extends StateNotifier<PanesState> {
  PanesNotifier(this._ref)
    : super(const PanesState(PaneStack.empty, PaneStack.empty)) {
    final note = _ref.read(selectedNoteProvider);
    final paper = _ref.read(selectedPaperProvider);
    if (note != null) replace(0, NoteTarget(note));
    if (paper != null) replace(1, PaperTarget(paper));
    _ref.listen<String?>(selectedNoteProvider, (_, next) => _external(0, next));
    _ref.listen<String?>(
      selectedPaperProvider,
      (_, next) => _external(1, next),
    );
  }

  final Ref _ref;
  int _ids = 0;

  String? _expected(int tab) {
    final t = state.of(tab).focused?.target;
    return tab == 0
        ? (t is NoteTarget ? t.noteId : null)
        : (t is PaperTarget ? t.paperId : null);
  }

  void _external(int tab, String? next) {
    if (next == _expected(tab)) return;
    if (next == null) {
      closeFocused(tab);
    } else {
      replace(tab, tab == 0 ? NoteTarget(next) : PaperTarget(next));
    }
  }

  void _set(int tab, PaneStack s) {
    state = state.with_(tab, s);
    final want = _expected(tab);
    if (tab == 0) {
      final p = _ref.read(selectedNoteProvider.notifier);
      if (p.state != want) p.state = want;
    } else {
      final p = _ref.read(selectedPaperProvider.notifier);
      if (p.state != want) p.state = want;
    }
  }

  /// One pane, [target], replacing the stack.
  void replace(int tab, NavTarget target) {
    final s = state.of(tab);
    if (s.panes.length == 1 && s.panes.first.target.key == target.key) {
      _set(tab, PaneStack([PaneEntry(s.panes.first.id, target)], 0));
      return;
    }
    _set(tab, PaneStack([PaneEntry(_ids++, target)], 0));
  }

  /// [target] in a new pane right of pane [sourceId] (panes beyond it are
  /// dropped), or focus the pane that already shows it.
  void openAfter(int tab, int? sourceId, NavTarget target) {
    final s = state.of(tab);
    final existing = s.panes.indexWhere((p) => p.target.key == target.key);
    if (existing >= 0) {
      _set(tab, PaneStack(s.panes, existing));
      return;
    }
    var at = s.panes.indexWhere((p) => p.id == sourceId);
    if (at < 0) at = s.focus;
    final kept = [...s.panes.take(at + 1), PaneEntry(_ids++, target)];
    _set(tab, PaneStack(kept, kept.length - 1));
  }

  void focusPane(int tab, int id) {
    final s = state.of(tab);
    final i = s.panes.indexWhere((p) => p.id == id);
    if (i < 0 || i == s.focus) return;
    _set(tab, PaneStack(s.panes, i));
  }

  void close(int tab, int id) {
    final s = state.of(tab);
    final i = s.panes.indexWhere((p) => p.id == id);
    if (i < 0) return;
    final rest = [...s.panes]..removeAt(i);
    var focus = s.focus;
    if (i < focus) {
      focus--;
    } else if (i == focus) {
      focus = rest.isEmpty ? -1 : i.clamp(0, rest.length - 1);
    }
    _set(tab, PaneStack(rest, focus));
  }

  void closeFocused(int tab) {
    final f = state.of(tab).focused;
    if (f != null) close(tab, f.id);
  }

  /// Keeps only the focused pane (the window got too narrow for several).
  void collapseToFocused(int tab) {
    final f = state.of(tab).focused;
    if (f == null || state.of(tab).panes.length == 1) return;
    _set(tab, PaneStack([f], 0));
  }
}

final panesProvider = StateNotifierProvider<PanesNotifier, PanesState>(
  (ref) => PanesNotifier(ref),
);

final _noteTitleProvider = StreamProvider.autoDispose.family<String?, String>((
  ref,
  id,
) {
  final db = ref.watch(databaseProvider);
  return (db.select(
    db.notes,
  )..where((n) => n.id.equals(id))).watchSingleOrNull().map((n) => n?.title);
});

final _paperTitleProvider = StreamProvider.autoDispose.family<String?, String>((
  ref,
  id,
) {
  final db = ref.watch(databaseProvider);
  return (db.select(
    db.papers,
  )..where((p) => p.id.equals(id))).watchSingleOrNull().map((p) => p?.title);
});

/// The pane stack of one tab. Wide Mac windows lay the panes out side by
/// side in a horizontally scrolling row; elsewhere only the focused pane
/// shows (and the stack collapses to it).
class PaneHost extends ConsumerStatefulWidget {
  const PaneHost({super.key, required this.tab, required this.placeholder});

  final int tab;
  final Widget placeholder;

  @override
  ConsumerState<PaneHost> createState() => _PaneHostState();
}

class _PaneHostState extends ConsumerState<PaneHost> {
  final _scroll = ScrollController();
  int? _lastFocusId;
  int _lastCount = 0;
  double _area = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _reveal(PaneStack stack, double width) {
    if (!_scroll.hasClients || stack.focus < 0) return;
    final left = stack.focus * (width + 1);
    final right = left + width;
    final view = _scroll.position.viewportDimension;
    double? to;
    if (right > _scroll.offset + view) {
      to = right - view;
    } else if (left < _scroll.offset) {
      to = left;
    }
    if (to == null) return;
    to = to.clamp(0, _scroll.position.maxScrollExtent);
    final d = AppMotion.of(context, AppMotion.medium);
    if (d == Duration.zero) {
      _scroll.jumpTo(to);
    } else {
      _scroll.animateTo(to, duration: d, curve: AppMotion.enter);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tab = widget.tab;
    final stack = ref.watch(panesProvider.select((s) => s.of(tab)));
    final notifier = ref.read(panesProvider.notifier);
    final mac = isMac(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final area = constraints.maxWidth;
        final wide = mac && area >= panesMinAreaWidth;
        if (area != _area) {
          _area = area;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final fits = mac && area >= panesMinAreaWidth;
            final p = ref.read(paneAreaWidthProvider.notifier);
            final v = mac ? area : 0.0;
            if (p.state != v) p.state = v;
            if (!fits) notifier.collapseToFocused(tab);
          });
        }
        if (stack.panes.length > 1 && !wide) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) notifier.collapseToFocused(tab);
          });
        }
        if (stack.panes.isEmpty) {
          return AnimatedSwitcher(
            duration: AppMotion.of(context, AppMotion.medium),
            switchInCurve: AppMotion.enter,
            switchOutCurve: Curves.easeOut,
            child: widget.placeholder,
          );
        }
        final shell = MacPaneChrome.maybeOf(context);
        if (!wide) {
          final f = stack.focused!;
          return AnimatedSwitcher(
            duration: AppMotion.of(context, AppMotion.medium),
            switchInCurve: AppMotion.enter,
            switchOutCurve: Curves.easeOut,
            child: _PaneFrame(
              key: ValueKey('pane-${f.id}'),
              tab: tab,
              entry: f,
              focused: true,
              showHeader: false,
              shell: shell,
            ),
          );
        }
        final n = stack.panes.length;
        final w = paneWidthFor(area, n);
        final focusId = stack.focused?.id;
        if (focusId != _lastFocusId || n != _lastCount) {
          _lastFocusId = focusId;
          _lastCount = n;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _reveal(ref.read(panesProvider).of(tab), w);
          });
        }
        final c = Theme.of(context).colorScheme;
        return ColoredBox(
          color: c.surface,
          child: SingleChildScrollView(
            key: const ValueKey('pane-row'),
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < n; i++) ...[
                  if (i > 0) VerticalDivider(width: 1, color: c.outlineVariant),
                  SizedBox(
                    key: ValueKey('pane-slot-${stack.panes[i].id}'),
                    width: w,
                    child: _PaneFrame(
                      key: ValueKey('pane-${stack.panes[i].id}'),
                      tab: tab,
                      entry: stack.panes[i],
                      focused: i == stack.focus,
                      showHeader: n > 1 && i != stack.focus,
                      shell: shell,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PaneFrame extends ConsumerWidget {
  const _PaneFrame({
    super.key,
    required this.tab,
    required this.entry,
    required this.focused,
    required this.showHeader,
    required this.shell,
  });

  final int tab;
  final PaneEntry entry;
  final bool focused;
  final bool showHeader;
  final MacPaneChrome? shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(panesProvider.notifier);
    void close() => notifier.close(tab, entry.id);
    final target = entry.target;
    final String? title;
    final Widget screen;
    switch (target) {
      case NoteTarget t:
        final name = ref.watch(_noteTitleProvider(t.noteId));
        // A note deleted or synced away takes its own pane with it.
        if (name.hasValue && name.value == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => close());
        }
        title = name.value;
        screen = NoteEditorScreen(
          key: ValueKey('note-${t.noteId}'),
          noteId: t.noteId,
          embedded: true,
          onClose: close,
        );
      case PaperTarget t:
        final name = ref.watch(_paperTitleProvider(t.paperId));
        if (name.hasValue && name.value == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => close());
        }
        title = name.value;
        screen = PaperDetailScreen(
          key: ValueKey('paper-${t.paperId}'),
          paperId: t.paperId,
          embedded: true,
          onClose: close,
        );
      case ProjectTarget():
        title = null;
        screen = const SizedBox.shrink();
    }
    Widget body = screen;
    if (shell != null) {
      body = MacPaneChrome(
        leading: focused ? shell!.leading : const SizedBox.shrink(),
        trailing: focused ? shell!.trailing : const SizedBox.shrink(),
        extraLeading: focused ? shell!.extraLeading : 0,
        child: body,
      );
    }
    final c = Theme.of(context).colorScheme;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => notifier.focusPane(tab, entry.id),
      child: PaneScope(
        tab: tab,
        paneId: entry.id,
        child: Column(
          children: [
            if (showHeader)
              CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape): close,
                },
                child: Container(
                  key: ValueKey('pane-header-${entry.id}'),
                  height: 30,
                  color: c.surfaceContainerHighest,
                  padding: const EdgeInsets.only(left: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title == null || title.isEmpty
                              ? context.l10n.panesUntitled
                              : title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        tooltip: context.l10n.panesClose,
                        onPressed: close,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 30,
                          height: 30,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(key: const ValueKey('pane-body'), child: body),
          ],
        ),
      ),
    );
  }
}
