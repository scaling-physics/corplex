import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/tables/attachments_table.dart';
import '../library/paper_detail_screen.dart';
import 'link_paper_sheet.dart';
import 'note_attachments_providers.dart';
import 'note_papers_providers.dart';

/// A single note, editable in place with no separate "edit mode" — typing
/// autosaves after a short pause, so there's nothing to remember to save.
class NoteEditorScreen extends ConsumerStatefulWidget {
  const NoteEditorScreen({super.key, required this.noteId});

  final int noteId;

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  Timer? _debounce;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadNote();
    _titleController.addListener(_scheduleSave);
    _contentController.addListener(_scheduleSave);
  }

  Future<void> _loadNote() async {
    final db = ref.read(databaseProvider);
    final note = await (db.select(
      db.notes,
    )..where((n) => n.id.equals(widget.noteId))).getSingleOrNull();
    if (note != null && mounted) {
      _titleController.text = note.title;
      _contentController.text = note.content;
    }
    setState(() => _loaded = true);
  }

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _save);
  }

  Future<void> _save() async {
    final db = ref.read(databaseProvider);
    await (db.update(db.notes)..where((n) => n.id.equals(widget.noteId)))
        .write(
          NotesCompanion(
            title: Value(_titleController.text),
            content: Value(_contentController.text),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final linkedPapersAsync = ref.watch(
      linkedPapersForNoteProvider(widget.noteId),
    );
    final attachmentsAsync = ref.watch(
      attachmentsForNoteProvider(widget.noteId),
    );

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.link),
            tooltip: 'Link a paper',
            onPressed: () => showLinkPaperSheet(context, ref, widget.noteId),
          ),
        ],
      ),
      body: !_loaded
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                TextField(
                  controller: _titleController,
                  style: Theme.of(context).textTheme.headlineSmall,
                  decoration: const InputDecoration(
                    hintText: 'Title',
                    border: InputBorder.none,
                  ),
                ),
                ...switch (linkedPapersAsync.value) {
                  null || [] => const [],
                  final papers => [
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: -8,
                      children: papers
                          .map(
                            (paper) => InputChip(
                              label: Text(
                                paper.title,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      PaperDetailScreen(paperId: paper.id),
                                ),
                              ),
                              onDeleted: () => unlinkPaperFromNote(
                                ref.read(databaseProvider),
                                noteId: widget.noteId,
                                paperId: paper.id,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 8),
                  ],
                },
                ...switch (attachmentsAsync.value) {
                  null || [] => const [],
                  final attachments => [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: attachments.map((a) {
                        if (a.type == AttachmentType.image && a.path != null) {
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(a.path!),
                              width: 96,
                              height: 96,
                              fit: BoxFit.cover,
                            ),
                          );
                        }
                        return Chip(
                          avatar: const Icon(Icons.attach_file, size: 16),
                          label: Text(
                            a.title ?? a.url ?? 'Attachment',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                  ],
                },
                TextField(
                  controller: _contentController,
                  style: Theme.of(context).textTheme.bodyLarge,
                  decoration: const InputDecoration(
                    hintText: 'Start writing…',
                    border: InputBorder.none,
                  ),
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                ),
              ],
            ),
    );
  }
}
