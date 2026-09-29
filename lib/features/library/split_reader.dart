import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../notes/note_editor_screen.dart';
import '../notes/note_papers_providers.dart';
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

  @override
  void initState() {
    super.initState();
    // After the first frame: providers can't change while building.
    Future.microtask(() => _paired.state = _handle);
  }

  @override
  void dispose() {
    // Deferred for the same reason; only clear our own handle.
    final paired = _paired;
    final handle = _handle;
    Future.microtask(() {
      if (paired.state == handle) paired.state = null;
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
        return Row(
          children: [
            Expanded(flex: 11, child: reader),
            VerticalDivider(
              width: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            Expanded(
              flex: 9,
              child: NoteEditorScreen(
                noteId: widget.noteId,
                handle: _handle,
                embedded: true,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The note to read alongside [paper]: the one most recently edited among
/// those linked to it, or a new one (titled after it, linked) if none.
Future<String> noteForReading(AppDatabase db, Paper paper) async {
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
          title: Value('Notes on ${paper.title}'),
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
  final noteId = await noteForReading(ref.read(databaseProvider), paper);
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
