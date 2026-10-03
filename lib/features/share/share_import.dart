import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/local_files.dart';
import '../../data/tables/attachments_table.dart';
import '../library/add_attachment_sheet.dart';
import '../library/library_actions.dart';
import '../library/paper_detail_screen.dart';
import '../notes/note_editor_screen.dart';
import 'shared_items.dart';

/// Where shared content comes from. A seam so tests don't need the
/// platform plugin (which has no implementation under `flutter test`).
abstract class ShareIntentSource {
  /// What the app was launched with, if it was launched by a share.
  Future<List<SharedMediaFile>> initial();

  /// Shares that arrive while the app is running.
  Stream<List<SharedMediaFile>> get stream;

  /// Tells the platform the launch share has been handled, so it isn't
  /// delivered again on the next start.
  Future<void> reset();
}

class PluginShareIntentSource implements ShareIntentSource {
  @override
  Future<List<SharedMediaFile>> initial() async {
    try {
      return await ReceiveSharingIntent.instance.getInitialMedia();
    } catch (_) {
      return const [];
    }
  }

  @override
  Stream<List<SharedMediaFile>> get stream {
    try {
      return ReceiveSharingIntent.instance.getMediaStream();
    } catch (_) {
      return const Stream.empty();
    }
  }

  @override
  Future<void> reset() async {
    try {
      await ReceiveSharingIntent.instance.reset();
    } catch (_) {}
  }
}

final shareIntentSourceProvider = Provider<ShareIntentSource>(
  (ref) => PluginShareIntentSource(),
);

/// Does something sensible with each shared item, then says what it did
/// (with an "Open" shortcut). Nothing here blocks on a question except
/// audio, which needs to know what to attach to.
Future<void> handleSharedItems(
  BuildContext context,
  WidgetRef ref,
  List<SharedItem> items,
) async {
  for (final item in items) {
    if (!context.mounted) return;
    switch (item) {
      case SharedPdf():
        await _importPdf(context, ref, item);
      case SharedAudio():
        await _attachAudio(context, ref, item);
      case SharedIdentifier():
        await addPaperFromIdentifier(context, ref, item.identifier);
      case SharedLink():
        await _saveLink(context, ref, item);
      case SharedText():
        await _saveText(context, ref, item);
    }
  }
}

void _saved(BuildContext context, String message, Widget Function() open) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: 'Open',
          onPressed: () =>
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => open())),
        ),
      ),
    );
}

Future<void> _importPdf(
  BuildContext context,
  WidgetRef ref,
  SharedPdf item,
) async {
  final db = ref.read(databaseProvider);
  final localPath = await copyIntoAppStorage(item.path, 'papers');
  final id = const Uuid().v4();
  await db
      .into(db.papers)
      .insert(
        PapersCompanion.insert(
          id: Value(id),
          title: item.name,
          pdfPath: Value(localPath),
        ),
      );
  if (!context.mounted) return;
  unawaited(
    enrichImportedPaper(ref, context, id, localPath, importedTitle: item.name),
  );
  _saved(
    context,
    'Added “${item.name}” to your library',
    () => PaperDetailScreen(paperId: id),
  );
}

Future<void> _saveLink(
  BuildContext context,
  WidgetRef ref,
  SharedLink item,
) async {
  final url = item.url.toString();
  final title = item.url.host.replaceFirst('www.', '');
  final id = await _newNote(
    ref.read(databaseProvider),
    title: title,
    delta: [
      {
        'insert': url,
        'attributes': {'link': url},
      },
      {'insert': '\n'},
    ],
  );
  if (!context.mounted) return;
  _saved(context, 'Saved link as a note', () => NoteEditorScreen(noteId: id));
}

Future<void> _saveText(
  BuildContext context,
  WidgetRef ref,
  SharedText item,
) async {
  final firstLine = item.text.split('\n').first.trim();
  final id = await _newNote(
    ref.read(databaseProvider),
    title: firstLine.length > 60 ? '${firstLine.substring(0, 60)}…' : firstLine,
    delta: [
      {'insert': '${item.text}\n'},
    ],
  );
  if (!context.mounted) return;
  _saved(context, 'Saved as a note', () => NoteEditorScreen(noteId: id));
}

Future<String> _newNote(
  AppDatabase db, {
  required String title,
  required List<Map<String, Object?>> delta,
}) async {
  final id = const Uuid().v4();
  await db
      .into(db.notes)
      .insert(
        NotesCompanion.insert(
          id: Value(id),
          title: Value(title),
          content: Value(jsonEncode(delta)),
        ),
      );
  return id;
}

Future<void> _attachAudio(
  BuildContext context,
  WidgetRef ref,
  SharedAudio item,
) async {
  final db = ref.read(databaseProvider);
  final target = await _pickAudioTarget(context, db, item.name);
  if (target == null || !context.mounted) return;

  final localPath = await copyIntoAppStorage(item.path, 'attachments');
  var noteId = target.noteId;
  if (target.paperId == null && noteId == null) {
    noteId = await _newNote(
      db,
      title: item.name,
      delta: [
        {'insert': '\n'},
      ],
    );
  }
  await insertAttachment(
    db,
    noteId: noteId,
    paperId: target.paperId,
    type: AttachmentType.podcast,
    path: localPath,
    title: titleFromFileName(item.path),
  );
  if (!context.mounted) return;
  _saved(
    context,
    'Audio attached',
    () => noteId != null
        ? NoteEditorScreen(noteId: noteId)
        : PaperDetailScreen(paperId: target.paperId!),
  );
}

/// Where a shared recording should live: a new note, a recent note, or a
/// paper. (`null` fields for both = a new note.)
Future<({String? noteId, String? paperId})?> _pickAudioTarget(
  BuildContext context,
  AppDatabase db,
  String name,
) async {
  final notes =
      await (db.select(db.notes)
            ..orderBy([(n) => OrderingTerm.desc(n.updatedAt)])
            ..limit(8))
          .get();
  final papers =
      await (db.select(db.papers)
            ..orderBy([(p) => OrderingTerm.desc(p.updatedAt)])
            ..limit(8))
          .get();
  if (!context.mounted) return null;

  return showModalBottomSheet<({String? noteId, String? paperId})>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                'Attach “$name” to…',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('A new note'),
              onTap: () =>
                  Navigator.pop(context, (noteId: null, paperId: null)),
            ),
            for (final n in notes)
              ListTile(
                leading: const Icon(Icons.edit_note_outlined),
                title: Text(
                  n.title.isEmpty ? 'Untitled' : n.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () =>
                    Navigator.pop(context, (noteId: n.id, paperId: null)),
              ),
            for (final paper in papers)
              ListTile(
                leading: const Icon(Icons.article_outlined),
                title: Text(
                  paper.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () =>
                    Navigator.pop(context, (noteId: null, paperId: paper.id)),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Listens for shares — the one that launched the app and any that arrive
/// later — and hands them to [handleSharedItems]. Invisible: it renders
/// [child] untouched.
class ShareCoordinator extends ConsumerStatefulWidget {
  const ShareCoordinator({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ShareCoordinator> createState() => _ShareCoordinatorState();
}

class _ShareCoordinatorState extends ConsumerState<ShareCoordinator> {
  StreamSubscription<List<SharedMediaFile>>? _sub;

  @override
  void initState() {
    super.initState();
    final source = ref.read(shareIntentSourceProvider);
    _sub = source.stream.listen(_handle);
    source.initial().then((media) async {
      if (media.isEmpty) return;
      _handle(media);
      await source.reset();
    });
  }

  void _handle(List<SharedMediaFile> media) {
    final items = classifyShared(media);
    if (items.isEmpty || !mounted) return;
    handleSharedItems(context, ref, items);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
