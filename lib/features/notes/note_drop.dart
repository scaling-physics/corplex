import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:quill_native_bridge/quill_native_bridge.dart';

import '../../data/database_provider.dart';
import '../../data/local_files.dart';
import '../../data/tables/attachments_table.dart';
import '../library/add_attachment_sheet.dart' show insertAttachment;
import '../library/library_screen.dart' show importPdfAt;
import '../share/shared_items.dart' show audioFileExtensions;
import 'note_papers_providers.dart' show linkPaperToNote;

const _imageExtensions = {
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.heic',
  '.heif',
  '.webp',
  '.tif',
  '.tiff',
  '.bmp',
};

/// What a file pasted or dropped into a note becomes.
enum NoteFileKind {
  /// An image attachment, previewed in the note.
  image,

  /// An audio attachment, playable with the player bar.
  audio,

  /// A paper in the Library, linked to the note.
  pdf,

  /// Any other file, as a file attachment.
  file,
}

NoteFileKind noteFileKind(String path) {
  final ext = p.extension(path).toLowerCase();
  if (ext == '.pdf') return NoteFileKind.pdf;
  if (_imageExtensions.contains(ext)) return NoteFileKind.image;
  if (audioFileExtensions.contains(ext)) return NoteFileKind.audio;
  return NoteFileKind.file;
}

/// Adds files pasted or dropped into note [noteId], as the attach sheet
/// would: images, audio and other files become the note's attachments
/// (copied into app storage); a PDF joins the Library as a paper (with the
/// usual lookup) and is linked to the note. Folders are skipped. Returns
/// how many were added.
Future<int> addFilesToNote(
  BuildContext context,
  WidgetRef ref,
  String noteId,
  List<String> paths,
) async {
  final db = ref.read(databaseProvider);
  var added = 0;
  for (final path in paths) {
    if (!FileSystemEntity.isFileSync(path)) continue;
    final name = p.basename(path);
    final kind = noteFileKind(path);
    if (kind == NoteFileKind.pdf) {
      if (!context.mounted) break;
      final paperId = await importPdfAt(context, ref, path, name);
      await linkPaperToNote(db, noteId: noteId, paperId: paperId);
    } else {
      final local = await copyIntoAppStorage(path, 'attachments');
      await insertAttachment(
        db,
        noteId: noteId,
        type: switch (kind) {
          NoteFileKind.image => AttachmentType.image,
          NoteFileKind.audio => AttachmentType.podcast,
          _ => AttachmentType.file,
        },
        path: local,
        title: kind == NoteFileKind.audio ? titleFromFileName(name) : name,
      );
    }
    added++;
  }
  return added;
}

/// Adds a pasted picture (a screenshot, an image copied in Preview) to note
/// [noteId] as an image attachment.
Future<void> addImageBytesToNote(
  WidgetRef ref,
  String noteId,
  Uint8List png,
) async {
  final path = await saveBytesToAppStorage(png, 'attachments', 'Pasted.png');
  await insertAttachment(
    ref.read(databaseProvider),
    noteId: noteId,
    type: AttachmentType.image,
    path: path,
    title: 'Pasted image',
  );
}

/// What the system clipboard holds beyond text, for pasting into a note.
/// The real one asks the platform through quill_native_bridge (the plugin
/// Quill itself uses); tests override [noteClipboardProvider].
abstract class NoteClipboard {
  /// Paths of files copied in Finder (or another file manager).
  Future<List<String>> files();

  /// A copied picture, as PNG bytes.
  Future<Uint8List?> image();
}

class PlatformNoteClipboard implements NoteClipboard {
  const PlatformNoteClipboard();

  static final _bridge = QuillNativeBridge();

  @override
  Future<List<String>> files() async {
    try {
      if (!await _bridge.isSupported(
        QuillNativeBridgeFeature.getClipboardFiles,
      )) {
        return const [];
      }
      return await _bridge.getClipboardFiles();
    } on Object {
      return const [];
    }
  }

  @override
  Future<Uint8List?> image() async {
    try {
      if (!await _bridge.isSupported(
        QuillNativeBridgeFeature.getClipboardImage,
      )) {
        return null;
      }
      return await _bridge.getClipboardImage();
    } on Object {
      return null;
    }
  }
}

final noteClipboardProvider = Provider<NoteClipboard>(
  (ref) => const PlatformNoteClipboard(),
);

/// Paste into note [noteId] (Quill's `onClipboardPaste`): copied files are
/// attached; a copied picture is attached unless there is text too (apps
/// often put a picture of copied text beside it, and the text is what's
/// meant). True when it handled the paste, false to let Quill paste text.
Future<bool> pasteFilesIntoNote(
  BuildContext context,
  WidgetRef ref,
  String noteId,
) async {
  final clipboard = ref.read(noteClipboardProvider);
  final files = await clipboard.files();
  if (files.isNotEmpty && context.mounted) {
    return await addFilesToNote(context, ref, noteId, files) > 0;
  }
  if (await Clipboard.hasStrings()) return false;
  final image = await clipboard.image();
  if (image == null || image.isEmpty) return false;
  await addImageBytesToNote(ref, noteId, image);
  return true;
}

/// Accepts files dragged from Finder onto the note (Mac only), with a quiet
/// tint and "Drop to attach" while something is over it.
class NoteDropTarget extends ConsumerStatefulWidget {
  const NoteDropTarget({super.key, required this.noteId, required this.child});

  final String noteId;
  final Widget child;

  @override
  ConsumerState<NoteDropTarget> createState() => _NoteDropTargetState();
}

class _NoteDropTargetState extends ConsumerState<NoteDropTarget> {
  bool _over = false;

  Future<void> _drop(DropDoneDetails details) async {
    setState(() => _over = false);
    final paths = <String>[];
    final scoped = <Uint8List>[];
    for (final item in details.files) {
      // Files from outside the sandbox come with a security-scoped bookmark
      // that must be opened before they can be read.
      final bookmark = item.extraAppleBookmark;
      if (bookmark != null && bookmark.isNotEmpty) {
        try {
          if (await DesktopDrop.instance.startAccessingSecurityScopedResource(
            bookmark: bookmark,
          )) {
            scoped.add(bookmark);
          }
        } on Object {
          // Read it anyway; a drop usually grants access by itself.
        }
      }
      paths.add(item.path);
    }
    try {
      if (mounted) await addFilesToNote(context, ref, widget.noteId, paths);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Couldn\'t add that file.')),
        );
      }
    } finally {
      for (final b in scoped) {
        await DesktopDrop.instance.stopAccessingSecurityScopedResource(
          bookmark: b,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return DropTarget(
      // A route pushed over the note still gets drag events otherwise.
      enable: ModalRoute.of(context)?.isCurrent ?? true,
      onDragEntered: (_) => setState(() => _over = true),
      onDragExited: (_) => setState(() => _over = false),
      onDragDone: _drop,
      child: Stack(
        children: [
          widget.child,
          if (_over)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.primary.withValues(alpha: 0.06),
                    border: Border.all(color: c.primary, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      'Drop to attach',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(color: c.primary),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
