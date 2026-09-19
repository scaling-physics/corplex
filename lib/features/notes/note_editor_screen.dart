import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/tables/attachments_table.dart';
import '../library/paper_detail_screen.dart';
import 'folder_picker_sheet.dart';
import 'folders_providers.dart';
import 'link_paper_sheet.dart';
import 'note_attachments_providers.dart';
import 'note_content.dart';
import 'note_papers_providers.dart';
import 'notes_providers.dart';
import 'tag_picker_sheet.dart';
import 'tags_providers.dart';

/// A single note, editable in place with no separate "edit mode" — typing
/// autosaves after a short pause, so there's nothing to remember to save.
class NoteEditorScreen extends ConsumerStatefulWidget {
  const NoteEditorScreen({super.key, required this.noteId});

  final String noteId;

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  final _titleController = TextEditingController();
  late final QuillController _quillController;
  Timer? _debounce;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadNote();
    _titleController.addListener(_scheduleSave);
  }

  Future<void> _loadNote() async {
    final db = ref.read(databaseProvider);
    final note = await (db.select(
      db.notes,
    )..where((n) => n.id.equals(widget.noteId))).getSingleOrNull();

    _quillController = QuillController(
      document: note == null ? Document() : decodeNoteContent(note.content),
      selection: const TextSelection.collapsed(offset: 0),
    );
    if (note != null && mounted) {
      _titleController.text = note.title;
    }
    _quillController.addListener(_scheduleSave);
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
            content: Value(encodeNoteContent(_quillController.document)),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _titleController.dispose();
    if (_loaded) _quillController.dispose();
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
    final noteAsync = ref.watch(noteByIdProvider(widget.noteId));
    final tagsAsync = ref.watch(tagsForNoteProvider(widget.noteId));
    final foldersAsync = ref.watch(foldersListProvider);
    final folderId = noteAsync.value?.folderId;
    final folderName = folderId == null
        ? null
        : foldersAsync.value
              ?.where((f) => f.id == folderId)
              .map((f) => f.name)
              .firstOrNull;

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_outlined),
            tooltip: folderName ?? 'Move to folder',
            onPressed: () =>
                showFolderPickerSheet(context, ref, widget.noteId, folderId),
          ),
          IconButton(
            icon: const Icon(Icons.tag),
            tooltip: 'Tags',
            onPressed: () => showTagPickerSheet(context, ref, widget.noteId),
          ),
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
                if (folderName != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GestureDetector(
                      onTap: () => showFolderPickerSheet(
                        context,
                        ref,
                        widget.noteId,
                        folderId,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.folder_outlined,
                            size: 16,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            folderName,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.secondary,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ...switch (tagsAsync.value) {
                  null || [] => const [],
                  final tags => [
                    Wrap(
                      spacing: 8,
                      runSpacing: -8,
                      children: tags
                          .map(
                            (tag) => InputChip(
                              label: Text('#${tag.name}'),
                              onPressed: () =>
                                  showTagPickerSheet(context, ref, widget.noteId),
                              onDeleted: () => removeTagFromNote(
                                ref.read(databaseProvider),
                                noteId: widget.noteId,
                                tagId: tag.id,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 8),
                  ],
                },
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
                QuillEditor.basic(
                  controller: _quillController,
                  config: const QuillEditorConfig(
                    scrollable: false,
                    padding: EdgeInsets.zero,
                    placeholder: 'Start writing…',
                  ),
                ),
              ],
            ),
      bottomNavigationBar: !_loaded
          ? null
          : SafeArea(
              child: QuillSimpleToolbar(
                controller: _quillController,
                config: const QuillSimpleToolbarConfig(
                  multiRowsDisplay: false,
                  showFontFamily: false,
                  showFontSize: false,
                  showSmallButton: false,
                  showLineHeightButton: false,
                  showInlineCode: false,
                  showColorButton: false,
                  showBackgroundColorButton: false,
                  showClearFormat: false,
                  showAlignmentButtons: false,
                  showListCheck: false,
                  showCodeBlock: false,
                  showIndent: false,
                  showLink: false,
                  showDirection: false,
                  showSearchButton: false,
                  showSubscript: false,
                  showSuperscript: false,
                  showUndo: false,
                  showRedo: false,
                  showDividers: false,
                ),
              ),
            ),
    );
  }
}
