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
import '../export/export_actions.dart';
import '../export/export_model.dart';
import '../ink/sketch_embed.dart';
import '../../theme/app_theme.dart';
import '../projects/project_picker_sheet.dart';
import '../trash/trash_actions.dart';
import '../projects/projects_providers.dart';
import 'cite_paper_sheet.dart';
import 'note_bibliography.dart';
import 'note_link_sheet.dart';
import 'note_links.dart';
import 'note_templates.dart';
import '../library/add_attachment_sheet.dart';
import '../library/citation_formatter.dart';
import '../library/citations.dart';
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
  StreamSubscription<DocChange>? _docChanges;

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
    _docChanges = _quillController.document.changes.listen(_watchForWikilink);
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

  /// Typing "[[" opens the note picker, like a wiki link; "[@" opens the
  /// paper picker for a citation.
  void _watchForWikilink(DocChange change) {
    if (change.source != ChangeSource.local) return;
    // Where the change inserted a single "[", from the change itself
    // rather than the cursor (which may not have moved yet).
    var at = 0;
    int? end;
    for (final op in change.change.toList()) {
      if (op.isRetain) {
        at += op.length!;
      } else if (op.isInsert) {
        if (op.data == '[' || op.data == '@') end = at + 1;
        break;
      }
    }
    if (end == null || end < 2) return;
    final text = _quillController.document.toPlainText();
    if (end > text.length) return;
    final typed = text.substring(end - 2, end);
    if (typed != '[[' && typed != '[@') return;
    final cite = typed == '[@';
    final start = end - 2;
    // After this change has finished applying.
    Future.microtask(() async {
      _quillController.replaceText(
        start,
        2,
        '',
        TextSelection.collapsed(offset: start),
      );
      if (!mounted) return;
      if (cite) {
        await _citePaper(context);
      } else {
        await _linkNote(context);
      }
    });
  }

  /// Inserts `[@citekey]` for a chosen paper at the cursor (assigning the
  /// paper its citekey the first time).
  Future<void> _citePaper(BuildContext context) async {
    final paperId = await showCitePaperSheet(context);
    if (paperId == null || !mounted) return;
    final key = await ensureCitekey(ref.read(databaseProvider), paperId);
    if (!mounted) return;
    final controller = _quillController;
    final docEnd = controller.document.length - 1;
    final cursor = controller.selection.baseOffset;
    final index = cursor < 0 || cursor > docEnd ? docEnd : cursor;
    final marker = citationMarker(key);
    controller.replaceText(index, 0, '$marker ', null);
    controller.updateSelection(
      TextSelection.collapsed(offset: index + marker.length + 1),
      ChangeSource.local,
    );
  }

  void _insertTemplate() {
    final controller = _quillController;
    final cursor = controller.selection.baseOffset;
    final docEnd = controller.document.length - 1;
    insertLiteratureTemplate(
      controller,
      cursor < 0 || cursor > docEnd ? docEnd : cursor,
    );
  }

  Future<void> _addBibliography(BuildContext context) async {
    final style = await showDialog<CitationStyle>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Reference style'),
        children: [
          for (final s in CitationStyle.values.where(
            (s) => s != CitationStyle.bibtex,
          ))
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, s),
              child: Text(s.label),
            ),
        ],
      ),
    );
    if (style == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final n = await insertBibliography(
      _quillController,
      ref.read(databaseProvider),
      style,
    );
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          n == 0
              ? 'No citations to list yet. Type [@ to cite a paper.'
              : 'Added $n reference${n == 1 ? '' : 's'}',
        ),
      ),
    );
  }

  Future<void> _linkNote(BuildContext context) async {
    final picked = await showNoteLinkSheet(
      context,
      ref,
      excludeNoteId: widget.noteId,
    );
    if (picked == null || !mounted) return;
    final controller = _quillController;
    final docEnd = controller.document.length - 1;
    final cursor = controller.selection.baseOffset;
    final index = cursor < 0 || cursor > docEnd ? docEnd : cursor;
    controller.replaceText(index, 0, '${picked.title} ', null);
    controller.formatText(
      index,
      picked.title.length + 1,
      Attribute.clone(Attribute.link, null),
    );
    controller.formatText(
      index,
      picked.title.length,
      LinkAttribute(noteLink(picked.id)),
    );
    controller.updateSelection(
      TextSelection.collapsed(offset: index + picked.title.length + 1),
      ChangeSource.local,
    );
  }

  void _openNote(String id) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => NoteEditorScreen(noteId: id)));

  /// Leaves the editor first so a pending autosave can't recreate the
  /// note the moment it's deleted, then trashes it with Undo.
  Future<void> _moveToTrash() async {
    final messenger = ScaffoldMessenger.of(context);
    final title = _titleController.text;
    _debounce?.cancel();
    await _save();
    if (!mounted) return;
    Navigator.of(context).pop();
    await deleteNoteWithUndo(ref, messenger, widget.noteId, title);
  }

  Future<void> _export(BuildContext context) async {
    await _save();
    if (!context.mounted) return;
    await exportNotes(
      context,
      ref.read(databaseProvider),
      [
        ExportNote(
          _titleController.text,
          encodeNoteContent(_quillController.document),
        ),
      ],
      title: _titleController.text,
    );
  }

  @override
  void dispose() {
    _docChanges?.cancel();
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
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) => switch (v) {
              'project' => showProjectPickerSheet(
                context,
                noteId: widget.noteId,
              ),
              'link' => _linkNote(context),
              'cite' => _citePaper(context),
              'template' => _insertTemplate(),
              'bibliography' => _addBibliography(context),
              'export' => _export(context),
              'trash' => _moveToTrash(),
              _ => null,
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'project',
                child: ListTile(
                  leading: Icon(Icons.folder_special_outlined),
                  title: Text('Add to project'),
                ),
              ),
              PopupMenuItem(
                value: 'link',
                child: ListTile(
                  leading: Icon(Icons.add_link),
                  title: Text('Link to a note'),
                  subtitle: Text('Or type [[ while writing'),
                ),
              ),
              PopupMenuItem(
                value: 'cite',
                child: ListTile(
                  leading: Icon(Icons.format_quote),
                  title: Text('Cite a paper'),
                  subtitle: Text('Or type [@ while writing'),
                ),
              ),
              PopupMenuItem(
                value: 'template',
                child: ListTile(
                  leading: Icon(Icons.article_outlined),
                  title: Text('Literature note template'),
                  subtitle: Text('Summary, method, findings, critique'),
                ),
              ),
              PopupMenuItem(
                value: 'bibliography',
                child: ListTile(
                  leading: Icon(Icons.list_alt),
                  title: Text('Add bibliography'),
                ),
              ),
              PopupMenuItem(
                value: 'export',
                child: ListTile(
                  leading: Icon(Icons.ios_share),
                  title: Text('Export'),
                  subtitle: Text('Markdown, Word or PDF, with references'),
                ),
              ),
              PopupMenuItem(
                value: 'trash',
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('Move to trash'),
                ),
              ),
            ],
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
                ...switch (ref
                    .watch(projectsForNoteProvider(widget.noteId))
                    .value) {
                  null || [] => const [],
                  final projects => [
                    Wrap(
                      spacing: 8,
                      runSpacing: -8,
                      children: [
                        for (final project in projects)
                          InputChip(
                            avatar: const Icon(
                              Icons.folder_special_outlined,
                              size: 16,
                            ),
                            label: Text(project.name),
                            onPressed: () => showProjectPickerSheet(
                              context,
                              noteId: widget.noteId,
                            ),
                            onDeleted: () => removeNoteFromProject(
                              ref.read(databaseProvider),
                              projectId: project.id,
                              noteId: widget.noteId,
                            ),
                          ),
                      ],
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
                      if (parseNoteLink(link) case final id?) {
                        return TapGestureRecognizer()
                          ..onTap = () => _openNote(id);
                      }
                      return null;
                    },
                  ),
                ),
                _Backlinks(noteId: widget.noteId),
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

/// "Linked from": notes that link here. Hidden when there are none.
class _Backlinks extends ConsumerWidget {
  const _Backlinks({required this.noteId});

  final String noteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(backlinksProvider(noteId)).value ?? const [];
    return AnimatedSize(
      duration: AppMotion.medium,
      curve: AppMotion.standard,
      alignment: Alignment.topCenter,
      child: notes.isEmpty
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Linked from',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final n in notes)
                        ActionChip(
                          avatar: const Icon(Icons.north_west, size: 16),
                          label: Text(
                            n.title.isEmpty ? 'Untitled' : n.title,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => NoteEditorScreen(noteId: n.id),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}
