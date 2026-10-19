import 'package:drift/drift.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../l10n/l10n.dart';
import '../notes/note_editor_screen.dart';
import '../notes/note_papers_providers.dart';
import '../platform/mac_window.dart';
import 'flight.dart';
import 'split_fraction.dart';
import 'pdf_viewer_screen.dart';
import 'quote_to_note.dart';

/// Below this width the reader and the note don't fit side by side.
const splitBreakpoint = 840.0;

bool canSplit(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= splitBreakpoint;

/// The paper's PDF beside a note about it. Quoting a selection drops it
/// straight into the note. Falls back to the plain reader if the window
/// gets narrow (e.g. iPad Split View / Slide Over).
class SplitReaderScreen extends ConsumerStatefulWidget {
  const SplitReaderScreen({
    super.key,
    required this.paperId,
    required this.pdfPath,
    required this.noteId,
    this.initialPage,
  });

  final String paperId;
  final String pdfPath;
  final String noteId;
  final int? initialPage;

  @override
  ConsumerState<SplitReaderScreen> createState() => _SplitReaderScreenState();
}

class _SplitReaderScreenState extends ConsumerState<SplitReaderScreen> {
  final _handle = NoteEditorHandle();
  late final _paired = ref.read(pairedNoteProvider.notifier);
  late final _pane = ref.read(pairedPaneKeyProvider.notifier);
  final _paneKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // After the first frame: providers can't change while building.
    Future.microtask(() {
      _paired.state = _handle;
      _pane.state = _paneKey;
    });
  }

  @override
  void dispose() {
    // Deferred for the same reason; only clear our own handle.
    final paired = _paired;
    final handle = _handle;
    final pane = _pane;
    final paneKey = _paneKey;
    Future.microtask(() {
      if (paired.state == handle) paired.state = null;
      if (pane.state == paneKey) pane.state = null;
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reader = PdfViewerScreen(
      paperId: widget.paperId,
      pdfPath: widget.pdfPath,
      initialPage: widget.initialPage,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < splitBreakpoint) return reader;
        final note = KeyedSubtree(
          key: _paneKey,
          child: NoteEditorScreen(
            noteId: widget.noteId,
            handle: _handle,
            embedded: true,
          ),
        );
        if (isDesktop(context)) {
          return ResizableSplit(
            total: constraints.maxWidth,
            fraction: ref.watch(splitFractionProvider),
            onChanged: ref.read(splitFractionProvider.notifier).save,
            reader: reader,
            note: note,
          );
        }
        return Row(
          children: [
            Expanded(flex: 11, child: reader),
            VerticalDivider(
              width: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            Expanded(
              flex: 9,
              child: KeyedSubtree(
                key: _paneKey,
                child: NoteEditorScreen(
                  noteId: widget.noteId,
                  handle: _handle,
                  embedded: true,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The PDF and the note side by side with a draggable divider. The divider
/// is a thin line with a wider invisible grip (resize cursor); the PDF
/// keeps at least [minReaderFraction] and the note [minNoteWidth]. The new
/// share is remembered when the drag ends ([onChanged]).
class ResizableSplit extends StatefulWidget {
  const ResizableSplit({
    super.key,
    required this.total,
    required this.fraction,
    required this.onChanged,
    required this.reader,
    required this.note,
  });

  final double total;
  final double fraction;
  final ValueChanged<double> onChanged;
  final Widget reader;
  final Widget note;

  /// Width of the draggable strip around the divider line.
  static const grip = 9.0;

  @override
  State<ResizableSplit> createState() => _ResizableSplitState();
}

class _ResizableSplitState extends State<ResizableSplit> {
  /// The share while a drag is in progress; null otherwise.
  double? _dragging;

  double get _fraction =>
      clampSplitFraction(_dragging ?? widget.fraction, widget.total);

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final readerWidth = (widget.total * _fraction).roundToDouble();
    return Row(
      children: [
        SizedBox(width: readerWidth, child: widget.reader),
        MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            key: const ValueKey('split-divider'),
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            onHorizontalDragStart: (_) => setState(() => _dragging = _fraction),
            onHorizontalDragUpdate: (d) => setState(() {
              _dragging = clampSplitFraction(
                (readerWidth + d.delta.dx) / widget.total,
                widget.total,
              );
            }),
            onHorizontalDragEnd: (_) {
              final done = _dragging;
              setState(() => _dragging = null);
              if (done != null) widget.onChanged(done);
            },
            child: SizedBox(
              width: ResizableSplit.grip,
              child: Center(
                child: VerticalDivider(
                  width: 1,
                  color: _dragging != null ? c.primary : c.outlineVariant,
                ),
              ),
            ),
          ),
        ),
        Expanded(child: widget.note),
      ],
    );
  }
}

/// The note to read alongside [paper]: the one most recently edited among
/// those linked to it, or a new one (titled after it, linked) if none.
Future<String> noteForReading(
  AppDatabase db,
  Paper paper, {
  String? newNoteTitle,
}) async {
  final existing =
      await (db.select(db.notes).join([
              innerJoin(
                db.notePaperRefs,
                db.notePaperRefs.noteId.equalsExp(db.notes.id),
              ),
            ])
            ..where(db.notePaperRefs.paperId.equals(paper.id))
            ..orderBy([OrderingTerm.desc(db.notes.updatedAt)])
            ..limit(1))
          .map((r) => r.readTable(db.notes))
          .getSingleOrNull();
  if (existing != null) return existing.id;
  final id = const Uuid().v4();
  await db
      .into(db.notes)
      .insert(
        NotesCompanion.insert(
          id: Value(id),
          title: Value(newNoteTitle ?? 'Notes on ${paper.title}'),
        ),
      );
  await linkPaperToNote(db, noteId: id, paperId: paper.id);
  return id;
}

/// Opens the paper beside its note.
Future<void> openSplitReader(
  BuildContext context,
  WidgetRef ref,
  Paper paper,
) async {
  final title = context.l10n.viewerNotesOn(paper.title);
  final noteId = await noteForReading(
    ref.read(databaseProvider),
    paper,
    newNoteTitle: title,
  );
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SplitReaderScreen(
        paperId: paper.id,
        pdfPath: paper.pdfPath!,
        noteId: noteId,
        initialPage: paper.lastPage,
      ),
    ),
  );
}
