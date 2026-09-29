import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/tables/attachments_table.dart';
import '../audio/audio_link.dart';
import '../audio/audio_playback.dart';
import '../audio/audio_player_bar.dart';
import '../ink/sketch_embed.dart';
import '../library/add_attachment_sheet.dart';
import '../library/highlights.dart';
import '../library/paper_detail_screen.dart';
import '../library/pdf_viewer_screen.dart';
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
  // Captured up front: dispose() must be able to flush a pending save, and
  // `ref` can't be used there.
  late final AppDatabase _db = ref.read(databaseProvider);

  /// What's in the database, so a save only happens for a real change.
  /// Merely opening a note, or moving the cursor, fires the listeners too;
  /// saving then would bump updatedAt, reorder the list and re-sync.
  String? _savedTitle;
  String? _savedContent;

  @override
  void initState() {
    super.initState();
    _loadNote();
  }

  Future<void> _loadNote() async {
    final db = _db;
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
    _savedTitle = _titleController.text;
    _savedContent = encodeNoteContent(_quillController.document);
    // Attached after the initial text is in place, so loading isn't an edit.
    _titleController.addListener(_scheduleSave);
    _quillController.addListener(_scheduleSave);
    if (mounted) setState(() => _loaded = true);
  }

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _save);
  }

  Future<void> _save() async {
    _debounce?.cancel();
    final title = _titleController.text;
    final content = encodeNoteContent(_quillController.document);
    if (title == _savedTitle && content == _savedContent) return;
    _savedTitle = title;
    _savedContent = content;
    await (_db.update(
      _db.notes,
    )..where((n) => n.id.equals(widget.noteId))).write(
      NotesCompanion(
        title: Value(title),
        content: Value(content),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> _attach(BuildContext context) async {
    final type = await showAddAttachmentSheet(
      context,
      ref,
      noteId: widget.noteId,
    );
    if (type != AttachmentType.podcast || !mounted) return;
    // Start what was just added, so "Mark" is usable straight away.
    final latest =
        await (_db.select(_db.attachments)
              ..where((a) => a.noteId.equals(widget.noteId))
              ..orderBy([(a) => OrderingTerm.desc(a.createdAt)])
              ..limit(1))
            .getSingleOrNull();
    if (latest != null && audioSourceOf(latest) != null) {
      await ref.read(audioPlaybackProvider).open(latest);
    }
  }

  /// Opens a quoted paper at the cited page (the PDF if it's on this
  /// device, otherwise the paper's details).
  Future<void> _openPaperAt(String paperId, int page) async {
    final paper = await (_db.select(
      _db.papers,
    )..where((p) => p.id.equals(paperId))).getSingleOrNull();
    if (!mounted) return;
    if (paper == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('That paper was removed.')));
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => paper.pdfPath == null
            ? PaperDetailScreen(paperId: paperId)
            : PdfViewerScreen(
                paperId: paperId,
                pdfPath: paper.pdfPath!,
                initialPage: page,
              ),
      ),
    );
  }

  /// Plays the recording a timestamp points at, from that moment.
  Future<void> _playFrom(String attachmentId, Duration at) async {
    final attachment = await (_db.select(
      _db.attachments,
    )..where((a) => a.id.equals(attachmentId))).getSingleOrNull();
    if (!mounted) return;
    if (attachment == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That recording was removed.')),
      );
      return;
    }
    await ref.read(audioPlaybackProvider).open(attachment, at: at);
  }

  /// Inserts a tappable "▸ 12:34" at the cursor (or the end of the note if
  /// it has none), linked to [attachmentId] at [at]. It's plain, unstyled
  /// text — not bold just because the cursor sat after a bold word — with
  /// a space either side so it never fuses with neighbouring words.
  void _insertTimestamp(String attachmentId, Duration at) {
    final controller = _quillController;
    final doc = controller.document;
    final docEnd = doc.length - 1;
    final cursor = controller.selection.baseOffset;
    var index = cursor < 0 || cursor > docEnd ? docEnd : cursor;

    // "▸" (not "▶", which Android draws as an emoji).
    final label = '▸ ${formatTimestamp(at)}';
    final before = index == 0 ? '\n' : doc.toPlainText()[index - 1];
    if (before.trim().isNotEmpty) {
      controller.replaceText(index, 0, ' ', null);
      index++;
    }
    controller.replaceText(index, 0, '$label ', null);
    for (final inline in <Attribute<Object?>>[
      Attribute.bold,
      Attribute.italic,
      Attribute.underline,
      Attribute.strikeThrough,
      Attribute.link,
    ]) {
      controller.formatText(
        index,
        label.length + 1,
        Attribute.clone(inline, null),
      );
    }
    // Only the label is the link, so typing on after it doesn't extend it.
    controller.formatText(
      index,
      label.length,
      LinkAttribute(audioTimestampLink(attachmentId, at)),
    );
    controller.updateSelection(
      TextSelection.collapsed(offset: index + label.length + 1),
      ChangeSource.local,
    );
  }

  @override
  void dispose() {
    // Leaving right after typing must not drop the last edit.
    if (_debounce?.isActive ?? false) _save();
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
          IconButton(
            icon: const Icon(Icons.attach_file),
            tooltip: 'Attach audio, image or file',
            onPressed: () => _attach(context),
          ),
        ],
      ),
      body: !_loaded
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              children: [
                TextField(
                  controller: _titleController,
                  style: Theme.of(context).textTheme.headlineMedium,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Title',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
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
                                  color: Theme.of(context)
                                      .colorScheme
                                      .secondary,
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
                              avatar: const Icon(Icons.tag, size: 16),
                              label: Text(tag.name),
                              onPressed: () => showTagPickerSheet(
                                context,
                                ref,
                                widget.noteId,
                              ),
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
                              avatar: const Icon(
                                Icons.article_outlined,
                                size: 16,
                              ),
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
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              File(a.path!),
                              width: 96,
                              height: 96,
                              fit: BoxFit.cover,
                            ),
                          );
                        }
                        return _AttachmentChip(attachment: a);
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                  ],
                },
                QuillEditor.basic(
                  controller: _quillController,
                  config: QuillEditorConfig(
                    scrollable: false,
                    padding: EdgeInsets.zero,
                    placeholder: 'Start writing…',
                    customLinkPrefixes: const [audioLinkScheme],
                    embedBuilders: const [SketchEmbedBuilder()],
                    // Audio timestamps play on a plain tap; other links
                    // keep Quill's default long-press menu.
                    customRecognizerBuilder: (attribute, leaf) {
                      if (attribute.key != Attribute.link.key) return null;
                      final link = attribute.value?.toString() ?? '';
                      if (parseAudioTimestampLink(link) case final t?) {
                        return TapGestureRecognizer()
                          ..onTap = () => _playFrom(t.attachmentId, t.at);
                      }
                      if (parsePaperPageLink(link) case final p?) {
                        return TapGestureRecognizer()
                          ..onTap = () => _openPaperAt(p.paperId, p.page);
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
      bottomNavigationBar: !_loaded
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AudioPlayerBar(onMark: _insertTimestamp),
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    border: Border(
                      top: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          // Pen input sits first and always visible, not at
                          // the scrolled-off end of the formatting row.
                          IconButton(
                            icon: const Icon(Icons.draw_outlined),
                            tooltip: 'Draw',
                            onPressed: () =>
                                insertSketch(context, _quillController),
                          ),
                          Container(
                            width: 1,
                            height: 24,
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                          Expanded(
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
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// A note's non-image attachment: audio plays in the player bar, a
/// podcast/web link opens in the browser, anything else just shows.
class _AttachmentChip extends ConsumerWidget {
  const _AttachmentChip({required this.attachment});

  final Attachment attachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = attachment;
    final title = a.title ?? a.url ?? 'Attachment';
    if (isAudioAttachment(a)) {
      final playback = ref.watch(audioPlaybackProvider);
      final isCurrent = playback.current?.id == a.id;
      return ActionChip(
        avatar: Icon(
          isCurrent && playback.playing ? Icons.graphic_eq : Icons.play_arrow,
          size: 18,
        ),
        label: Text(title, overflow: TextOverflow.ellipsis),
        onPressed: () => playback.open(a),
      );
    }
    if (a.url case final url?) {
      return ActionChip(
        avatar: Icon(
          a.type == AttachmentType.podcast ? Icons.podcasts : Icons.link,
          size: 18,
        ),
        label: Text(title, overflow: TextOverflow.ellipsis),
        onPressed: () =>
            launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      );
    }
    return Chip(
      avatar: const Icon(Icons.attach_file, size: 16),
      label: Text(title, overflow: TextOverflow.ellipsis),
    );
  }
}
