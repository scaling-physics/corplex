import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/local_files.dart';
import '../../data/tables/attachments_table.dart';

/// Bottom sheet offering the three ways to attach material to a paper:
/// a podcast link (e.g. NotebookLM), an image, or any other file.
Future<void> showAddAttachmentSheet(
  BuildContext context,
  WidgetRef ref,
  String paperId,
) {
  return showModalBottomSheet(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.podcasts),
            title: const Text('Podcast link'),
            subtitle: const Text('e.g. a NotebookLM share link'),
            onTap: () {
              Navigator.pop(sheetContext);
              _addPodcastLink(context, ref, paperId);
            },
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('Image'),
            onTap: () async {
              Navigator.pop(sheetContext);
              await _addImage(ref, paperId);
            },
          ),
          ListTile(
            leading: const Icon(Icons.attach_file),
            title: const Text('File'),
            onTap: () async {
              Navigator.pop(sheetContext);
              await _addFile(ref, paperId);
            },
          ),
        ],
      ),
    ),
  );
}

Future<void> _addPodcastLink(
  BuildContext context,
  WidgetRef ref,
  String paperId,
) async {
  final controller = TextEditingController();
  final url = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Add podcast link'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'https://…'),
        keyboardType: TextInputType.url,
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
  if (url == null || url.isEmpty) return;

  final db = ref.read(databaseProvider);
  await db.into(db.attachments).insert(
        AttachmentsCompanion.insert(
          paperId: Value(paperId),
          type: AttachmentType.podcast,
          url: Value(url),
        ),
      );
}

Future<void> _addImage(WidgetRef ref, String paperId) async {
  final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
  if (picked == null) return;

  final localPath = await copyIntoAppStorage(picked.path, 'attachments');
  final db = ref.read(databaseProvider);
  await db.into(db.attachments).insert(
        AttachmentsCompanion.insert(
          paperId: Value(paperId),
          type: AttachmentType.image,
          path: Value(localPath),
          title: Value(picked.name),
        ),
      );
}

Future<void> _addFile(WidgetRef ref, String paperId) async {
  final picked = await FilePicker.pickFile();
  if (picked?.path == null) return;

  final localPath = await copyIntoAppStorage(picked!.path!, 'attachments');
  final db = ref.read(databaseProvider);
  await db.into(db.attachments).insert(
        AttachmentsCompanion.insert(
          paperId: Value(paperId),
          type: AttachmentType.file,
          path: Value(localPath),
          title: Value(picked.name),
        ),
      );
}
