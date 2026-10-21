import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../home/adaptive.dart';
import '../home/mac_toolbar.dart' show MacToolbarButton;
import '../../l10n/l10n.dart';
import '../library/pdf_viewer_screen.dart';
import '../projects/project_page.dart';
import '../projects/todos.dart' show openNoteAtSelection;
import 'nav_history.dart';
import 'nav_target.dart';

/// How far a replayed place was scrolled (0..1), for the screen that shows
/// it to apply once it has laid out and then clear. [key] is the
/// `NavTarget.key` (`note:<id>`, `paper:<id>`).
typedef NavScrollRequest = ({String key, double fraction});

final navScrollRequestProvider = StateProvider<NavScrollRequest?>(
  (ref) => null,
);

/// A scroll position as a fraction of what can scroll, or null when there is
/// nothing to scroll (or no position yet).
double? scrollFractionOf(ScrollController controller) {
  if (!controller.hasClients) return null;
  final p = controller.position;
  if (!p.hasContentDimensions || p.maxScrollExtent <= 0) return null;
  return (p.pixels / p.maxScrollExtent).clamp(0.0, 1.0);
}

/// Takes the pending scroll request for [key] (clearing it), or null.
double? takeScrollRequest(WidgetRef ref, String key) {
  final request = ref.read(navScrollRequestProvider);
  if (request == null || request.key != key) return null;
  ref.read(navScrollRequestProvider.notifier).state = null;
  return request.fraction;
}

/// Scrolls [controller] to [fraction] of its extent once it has laid out,
/// retrying for a few frames; [mounted] says whether the owner still exists.
void restoreScrollFraction(
  ScrollController controller,
  double fraction,
  bool Function() mounted, {
  int attempt = 0,
}) {
  SchedulerBinding.instance.addPostFrameCallback((_) {
    if (!mounted()) return;
    if (controller.hasClients &&
        controller.position.hasContentDimensions &&
        (controller.position.maxScrollExtent > 0 || fraction == 0)) {
      final p = controller.position;
      p.jumpTo((fraction * p.maxScrollExtent).clamp(0.0, p.maxScrollExtent));
      return;
    }
    if (attempt < 10) {
      restoreScrollFraction(
        controller,
        fraction,
        mounted,
        attempt: attempt + 1,
      );
    }
  });
  SchedulerBinding.instance.scheduleFrame();
}

/// Whether the place still exists (a deleted or trashed note, paper or
/// project is forgotten rather than replayed).
Future<bool> navTargetExists(AppDatabase db, NavTarget target) async {
  switch (target) {
    case NoteTarget(:final noteId):
      return await (db.select(db.notes)
                ..where((n) => n.id.equals(noteId))
                ..limit(1))
              .getSingleOrNull() !=
          null;
    case PaperTarget(:final paperId):
      return await (db.select(db.papers)
                ..where((p) => p.id.equals(paperId))
                ..limit(1))
              .getSingleOrNull() !=
          null;
    case ProjectTarget(:final projectId):
      return await (db.select(db.projects)
                ..where((p) => p.id.equals(projectId))
                ..limit(1))
              .getSingleOrNull() !=
          null;
  }
}

/// Opens a project's page and records it in the history.
Future<void> openProjectPage(
  BuildContext context,
  WidgetRef ref,
  String projectId,
) {
  recordNavVisit(ref, ProjectTarget(projectId));
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ProjectScreen(projectId: projectId),
    ),
  );
}

/// Whether history has anywhere to go (the toolbar shows its buttons only
/// then).
bool navHasHistory(NavHistory h) => h.canGoBack || h.canGoForward;

/// Entries that live in a pushed route rather than the pane: a project's
/// page and a PDF opened at a page.
bool _isPushedPlace(NavTarget t) =>
    t is ProjectTarget || (t is PaperTarget && t.page != null);

/// Back: closes a page pushed over home first (history walks places, not
/// routes), else steps back through the places visited.
Future<void> navigateBack(BuildContext context, WidgetRef ref) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  if (navigator.canPop()) {
    final notifier = ref.read(navHistoryProvider.notifier);
    final current = notifier.history.current;
    // Closing the page the history's current place lives in: the place
    // underneath is the previous entry, so step to it without replaying.
    if (current != null &&
        _isPushedPlace(current.target) &&
        notifier.history.canGoBack) {
      notifier.back();
    }
    await navigator.maybePop();
    return;
  }
  await _step(context, ref, forward: false);
}

Future<void> navigateForward(BuildContext context, WidgetRef ref) =>
    _step(context, ref, forward: true);

Future<void> _step(
  BuildContext context,
  WidgetRef ref, {
  required bool forward,
}) async {
  final notifier = ref.read(navHistoryProvider.notifier);
  final db = ref.read(databaseProvider);
  final history = notifier.history;
  final before = history.current?.target.key;
  var entry = forward ? notifier.forward() : notifier.back();
  while (entry != null && !await navTargetExists(db, entry.target)) {
    notifier.forget(entry.target.key);
    if (forward) {
      entry = notifier.forward();
    } else {
      // Forgetting leaves the previous place current.
      final cur = history.current;
      entry = cur != null && cur.target.key != before ? cur : null;
    }
  }
  if (entry == null || !context.mounted) return;
  replayNavEntry(context, ref, entry);
}

/// Shows [entry] through the normal open functions without recording it as
/// a new visit, and asks the screen to restore its scroll.
void replayNavEntry(BuildContext context, WidgetRef ref, NavEntry entry) {
  final replaying = ref.read(navReplayingProvider.notifier);
  replaying.state = true;
  try {
    final target = entry.target;
    final scroll = entry.scroll;
    ref.read(navScrollRequestProvider.notifier).state = scroll == null
        ? null
        : (key: target.key, fraction: scroll);
    if (hasDetailPane(context) && Navigator.of(context).canPop()) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
    switch (target) {
      case NoteTarget(:final noteId, :final selectionStart, :final selectionEnd)
          when selectionStart != null && selectionEnd != null:
        openNoteAtSelection(
          context,
          ref,
          noteId,
          TextSelection(baseOffset: selectionStart, extentOffset: selectionEnd),
        );
      case NoteTarget(:final noteId):
        openNote(context, ref, noteId);
      case PaperTarget(:final paperId, :final page) when page != null:
        _openPdfAt(context, ref, paperId, page);
      case PaperTarget(:final paperId):
        openPaper(context, ref, paperId);
      case ProjectTarget(:final projectId):
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ProjectScreen(projectId: projectId),
          ),
        );
    }
  } finally {
    // Routes build on the next frame; keep the flag up until then so a
    // screen that records itself while building doesn't.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (replaying.mounted) replaying.state = false;
    });
    SchedulerBinding.instance.scheduleFrame();
  }
}

Future<void> _openPdfAt(
  BuildContext context,
  WidgetRef ref,
  String paperId,
  int page,
) async {
  final db = ref.read(databaseProvider);
  final paper = await (db.select(
    db.papers,
  )..where((p) => p.id.equals(paperId))).getSingleOrNull();
  if (paper == null || !context.mounted) return;
  if (paper.pdfPath == null) {
    openPaper(context, ref, paperId);
    return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PdfViewerScreen(
        paperId: paperId,
        pdfPath: paper.pdfPath!,
        initialPage: page,
      ),
    ),
  );
}

/// Back and Forward in the Mac pane's toolbar row. Built only while there is
/// history; an end with nowhere to go is disabled.
class BackForwardButtons extends ConsumerWidget {
  const BackForwardButtons({super.key});

  /// Two buttons (34 pt) and their gaps.
  static const width = 80.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(navHistoryProvider);
    final h = ref.read(navHistoryProvider.notifier).history;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          MacToolbarButton(
            key: const ValueKey('nav-back'),
            icon: Icons.arrow_back_ios_new,
            tooltip: context.l10n.historyBack,
            onPressed: h.canGoBack ? () => navigateBack(context, ref) : null,
          ),
          MacToolbarButton(
            key: const ValueKey('nav-forward'),
            icon: Icons.arrow_forward_ios,
            tooltip: context.l10n.historyForward,
            onPressed: h.canGoForward
                ? () => navigateForward(context, ref)
                : null,
          ),
        ],
      ),
    );
  }
}
