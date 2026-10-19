import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../data/database_provider.dart';
import '../../theme/app_theme.dart';
import '../library/paper_detail_screen.dart';
import '../notes/note_editor_screen.dart';
import 'mac_toolbar.dart';

/// How the home screen arranges itself for the window it has, so an iPad
/// (or a tablet, or a wide split-screen window) gets a tablet layout rather
/// than a stretched phone:
///
/// * **compact** (< 600): the phone layout — bottom tabs, full-screen pages.
/// * **medium** (600–899, e.g. iPad portrait): a navigation rail on the
///   left; lists and pages are centred at a readable width.
/// * **expanded** (≥ 900, iPad landscape, 13-inch iPad portrait): rail,
///   list and the open note or paper side by side.
enum HomeLayout { compact, medium, expanded }

HomeLayout homeLayoutFor(double width) => width >= 900
    ? HomeLayout.expanded
    : width >= 600
    ? HomeLayout.medium
    : HomeLayout.compact;

/// The widest a column of reading/writing text should get.
const readableWidth = 720.0;

/// Horizontal padding that centres content at [readableWidth] inside
/// [available], but never less than [minimum].
double readablePadding(double available, {double minimum = 24}) {
  final extra = (available - readableWidth) / 2;
  return extra > minimum ? extra : minimum;
}

/// The note / paper shown in the detail pane of the expanded layout.
final selectedNoteProvider = StateProvider<String?>((ref) => null);
final selectedPaperProvider = StateProvider<String?>((ref) => null);

/// Whether the home screen is showing a detail pane beside its lists. Only
/// home-screen actions (lists, New note, Import PDF) should ask this; a
/// page pushed on top of home opens things as pages.
bool hasDetailPane(BuildContext context) =>
    homeLayoutFor(MediaQuery.sizeOf(context).width) == HomeLayout.expanded;

/// Opens a note: in the detail pane when there is one, otherwise as a page.
void openNote(BuildContext context, WidgetRef ref, String noteId) {
  if (hasDetailPane(context)) {
    ref.read(selectedNoteProvider.notifier).state = noteId;
    return;
  }
  Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => NoteEditorScreen(noteId: noteId)));
}

/// Opens a paper: in the detail pane when there is one, otherwise as a page.
void openPaper(BuildContext context, WidgetRef ref, String paperId) {
  if (hasDetailPane(context)) {
    ref.read(selectedPaperProvider.notifier).state = paperId;
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => PaperDetailScreen(paperId: paperId)),
  );
}

final _noteExistsProvider = StreamProvider.autoDispose.family<bool, String>((
  ref,
  id,
) {
  final db = ref.watch(databaseProvider);
  return (db.select(
    db.notes,
  )..where((n) => n.id.equals(id))).watchSingleOrNull().map((n) => n != null);
});

final _paperExistsProvider = StreamProvider.autoDispose.family<bool, String>((
  ref,
  id,
) {
  final db = ref.watch(databaseProvider);
  return (db.select(
    db.papers,
  )..where((p) => p.id.equals(id))).watchSingleOrNull().map((p) => p != null);
});

/// The right-hand pane of the expanded layout: the selected note (Notes
/// tab) or paper (Library tab), or a quiet placeholder.
class DetailPane extends ConsumerWidget {
  const DetailPane({super.key, required this.tab});

  /// 0 = Notes, 1 = Library.
  final int tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Widget child;
    if (tab == 0) {
      final id = ref.watch(selectedNoteProvider);
      // A note deleted (swiped away, trashed, synced away) leaves the pane.
      final exists = id == null
          ? false
          : ref.watch(_noteExistsProvider(id)).value ?? true;
      child = id != null && exists
          ? NoteEditorScreen(
              key: ValueKey('note-$id'),
              noteId: id,
              embedded: true,
              onClose: () =>
                  ref.read(selectedNoteProvider.notifier).state = null,
            )
          : const _Placeholder(
              key: ValueKey('note-none'),
              icon: Icons.edit_note_outlined,
              text: 'Pick a note, or start a new one.',
            );
    } else {
      final id = ref.watch(selectedPaperProvider);
      final exists = id == null
          ? false
          : ref.watch(_paperExistsProvider(id)).value ?? true;
      child = id != null && exists
          ? PaperDetailScreen(
              key: ValueKey('paper-$id'),
              paperId: id,
              embedded: true,
              onClose: () =>
                  ref.read(selectedPaperProvider.notifier).state = null,
            )
          : const _Placeholder(
              key: ValueKey('paper-none'),
              icon: Icons.library_books_outlined,
              text: 'Pick a paper to read, annotate and cite.',
            );
    }
    // Cross-fade when the selection changes (or empties).
    return AnimatedSwitcher(
      duration: AppMotion.of(context, AppMotion.medium),
      switchInCurve: AppMotion.enter,
      switchOutCurve: Curves.easeOut,
      child: child,
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final chrome = MacPaneChrome.maybeOf(context);
    final placeholder = ColoredBox(
      color: c.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: c.outline),
            const SizedBox(height: 12),
            Text(
              text,
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(color: c.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
    // The Mac pane keeps its part of the toolbar row with nothing open.
    if (chrome == null) return placeholder;
    return Scaffold(appBar: macPaneBar(chrome), body: placeholder);
  }
}

/// Centres a screen's content at [readableWidth] on a wide window, so a
/// list doesn't stretch edge to edge on an iPad. No-op on a phone.
class ReadableColumn extends StatelessWidget {
  const ReadableColumn({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: readableWidth),
      child: child,
    ),
  );
}
