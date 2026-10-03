import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/local_files.dart';
import '../../data/tables/attachments_table.dart';

/// Records an attachment for a note and/or a paper and returns its id.
/// Kept free of UI so it can be tested and reused (e.g. by share import).
Future<String> insertAttachment(
  AppDatabase db, {
  String? noteId,
  String? paperId,
  required AttachmentType type,
  String? path,
  String? url,
  String? title,
}) async {
  assert(noteId != null || paperId != null, 'attach to a note or a paper');
  final id = const Uuid().v4();
  await db
      .into(db.attachments)
      .insert(
        AttachmentsCompanion.insert(
          id: Value(id),
          noteId: Value(noteId),
          paperId: Value(paperId),
          type: type,
          path: Value(path),
          url: Value(url),
          title: Value(title),
        ),
      );
  return id;
}

/// Bottom sheet with the ways to attach material to a note or a paper:
/// audio (a downloaded NotebookLM audio overview, a lecture recording…),
/// a podcast link, an image, or any other file. Returns the new
/// attachment's type, or null if cancelled.
Future<AttachmentType?> showAddAttachmentSheet(
  BuildContext context,
  WidgetRef ref, {
  String? paperId,
  String? noteId,
}) {
  final db = ref.read(databaseProvider);
  Future<String> insert({
    required AttachmentType type,
    String? path,
    String? url,
    String? title,
  }) => insertAttachment(
    db,
    noteId: noteId,
    paperId: paperId,
    type: type,
    path: path,
    url: url,
    title: title,
  );

  return showModalBottomSheet<AttachmentType>(
    context: context,
    builder: (sheetContext) {
      Future<void> run(Future<AttachmentType?> Function() action) async {
        final type = await action();
        if (sheetContext.mounted) Navigator.pop(sheetContext, type);
      }

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.headphones_outlined),
              title: const Text('Audio'),
              subtitle: const Text(
                'A NotebookLM audio overview, lecture or podcast file',
              ),
              onTap: () => run(() => _addAudio(insert)),
            ),
            ListTile(
              leading: const Icon(Icons.podcasts),
              title: const Text('Podcast link'),
              subtitle: const Text('A NotebookLM share link or audio URL'),
              onTap: () => run(() => _addPodcastLink(sheetContext, insert)),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Image'),
              onTap: () => run(() => _addImage(insert)),
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: const Text('File'),
              onTap: () => run(() => _addFile(insert)),
            ),
          ],
        ),
      );
    },
  );
}

typedef _Insert = Future<String> Function({
  required AttachmentType type,
  String? path,
  String? url,
  String? title,
});

Future<AttachmentType?> _addAudio(_Insert insert) async {
  final picked = await FilePicker.pickFile(type: FileType.audio);
  if (picked?.path == null) return null;
  final localPath = await copyIntoAppStorage(picked!.path!, 'attachments');
  await insert(
    type: AttachmentType.podcast,
    path: localPath,
    title: titleFromFileName(picked.name),
  );
  return AttachmentType.podcast;
}

Future<AttachmentType?> _addPodcastLink(
  BuildContext context,
  _Insert insert,
) async {
  final controller = TextEditingController();
  final url = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Add podcast link'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'https://…'),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          Text(
            'Direct audio links (.mp3, .m4a…) play here. NotebookLM share '
            'links open in the browser — to listen and timestamp inside '
            'Corplex, download the audio overview and add it as Audio.',
            style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
              color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
          child: const Text('Add'),
        ),
      ],
    ),
  );
  if (url == null || url.isEmpty) return null;
  final uri = Uri.tryParse(url);
  await insert(
    type: AttachmentType.podcast,
    url: url,
    title: uri?.host.contains('notebooklm') ?? false
        ? 'NotebookLM audio overview'
        : null,
  );
  return AttachmentType.podcast;
}

Future<AttachmentType?> _addImage(_Insert insert) async {
  final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
  if (picked == null) return null;
  final localPath = await copyIntoAppStorage(picked.path, 'attachments');
  await insert(type: AttachmentType.image, path: localPath, title: picked.name);
  return AttachmentType.image;
}

Future<AttachmentType?> _addFile(_Insert insert) async {
  final picked = await FilePicker.pickFile();
  if (picked?.path == null) return null;
  final localPath = await copyIntoAppStorage(picked!.path!, 'attachments');
  await insert(type: AttachmentType.file, path: localPath, title: picked.name);
  return AttachmentType.file;
}
