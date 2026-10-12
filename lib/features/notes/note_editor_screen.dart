import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/attachment_label.dart';
import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/tables/attachments_table.dart';
import '../audio/audio_link.dart';
import '../audio/audio_playback.dart';
import '../audio/audio_player_bar.dart';
import '../voice/voice_services.dart' show dictationOfferedProvider;
import '../voice/voice_sheet.dart';
import '../export/export_actions.dart';
import '../export/export_model.dart';
import '../ink/sketch_embed.dart';
import '../../theme/app_theme.dart';
import '../projects/project_picker_sheet.dart';
import '../trash/trash_actions.dart';
import '../settings/appearance_settings.dart';
import '../library/metadata_lookup.dart';
import 'note_stats.dart';
import 'paste_citation.dart';
import '../../theme/haptics.dart';
import '../projects/projects_providers.dart';
import '../projects/todos_request.dart';
import '../sync/merge.dart';
import '../home/adaptive.dart' show readablePadding, readableWidth;
import 'cite_paper_sheet.dart';
import 'citation_embed.dart';
import '../csl/style_picker.dart';
import 'math_embed.dart';
import 'math_markers.dart';
import 'note_bibliography.dart';
import 'note_link_sheet.dart';
import 'note_links.dart';
import 'note_templates.dart';
import '../library/add_attachment_sheet.dart';
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

/// Lets the reader beside a note (split view) push a quoted passage into
/// it without going through the database: the open editor owns the note's
/// text, and a write behind its back would be overwritten by its autosave.
class NoteEditorHandle {
  Future<void> Function({
    required String paperId,
    required String quote,
    required int page,
    required String pageLink,
    String? comment,
  })?
  appendQuote;
}

/// A single note, editable in place with no separate "edit mode" — typing
/// autosaves after a short pause, so there's nothing to remember to save.
class NoteEditorScreen extends ConsumerStatefulWidget {
  const NoteEditorScreen({
    super.key,
    required this.noteId,
    this.handle,
    this.embedded = false,
    this.onClose,
    this.initialSelection,
  });

  final String noteId;

  /// Where to put the caret (or select a range) once the note has loaded,
  /// in the editor's own offsets — chips and maths count as one character
  /// each. The page scrolls it into view. See `todos.dart`.
  final TextSelection? initialSelection;

  /// Set when the editor sits beside a PDF; see [NoteEditorHandle].
  final NoteEditorHandle? handle;

  /// One pane of a split view or the tablet layout: no back button.
  final bool embedded;

  /// How to leave when the note is moved to the trash; defaults to popping
  /// this page.
  final VoidCallback? onClose;

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

  // Owned here, not left to QuillEditor.basic: it makes a fresh FocusNode on
  // every build, so any rebuild (e.g. after an autosave) dropped the body's
  // focus and the keyboard jumped to the title mid-sentence.
  final _bodyFocus = FocusNode();
  final _bodyScroll = ScrollController();

  // The page scrolls (the editor inside it doesn't), so typewriter mode
  // moves this controller, measuring against the editor's caret.
  final _pageScroll = ScrollController();
  final _viewportKey = GlobalKey();
  final _editorKey = GlobalKey<EditorState>();

  /// What's in the database, so a save only happens for a real change.
  /// Merely opening a note, or moving the cursor, fires the listeners too;
  /// saving then would bump updatedAt, reorder the list and re-sync.
  String? _savedTitle;
  String? _savedContent;

  /// Recent values this editor saved. The database echoes each save back,
  /// sometimes after a newer one; an echo is not an outside change.
  final _ownTitles = <String>{};
  final _ownContents = <String>{};

  @override
  void initState() {
    super.initState();
    _loadNote();
    // A to-do tapped on the project page while this note is already open.
    ref.listenManual<NoteSelectionRequest?>(pendingNoteSelectionProvider, (
      _,
      request,
    ) {
      if (request == null || request.noteId != widget.noteId || !_loaded) {
        return;
      }
      ref.read(pendingNoteSelectionProvider.notifier).state = null;
      _quillController.updateSelection(
        _initialSelection(_quillController.document, request.selection),
        ChangeSource.local,
      );
      _revealInitialSelection();
    });
  }

  Future<void> _loadNote() async {
    final db = _db;
    final note = await (db.select(
      db.notes,
    )..where((n) => n.id.equals(widget.noteId))).getSingleOrNull();

    final document = note == null ? Document() : _editable(note.content);
    var want = widget.initialSelection;
    final pending = mounted ? ref.read(pendingNoteSelectionProvider) : null;
    if (pending != null && pending.noteId == widget.noteId) {
      want ??= pending.selection;
      ref.read(pendingNoteSelectionProvider.notifier).state = null;
    }
    _quillController = QuillController(
      document: document,
      selection: _initialSelection(document, want),
    );
    if (note != null && mounted) {
      _titleController.text = note.title;
    }
    _savedTitle = _titleController.text;
    _savedContent = _stored();
    // Attached after the initial text is in place, so loading isn't an edit.
    _titleController.addListener(_scheduleSave);
    _quillController.addListener(_scheduleSave);
    _quillController.addListener(_followCursor);
    _docChanges = _quillController.document.changes.listen(_watchForWikilink);
    widget.handle?.appendQuote = _appendQuoteHere;
    if (mounted) setState(() => _loaded = true);
    if (want != null) _revealInitialSelection();
  }

  /// [NoteEditorScreen.initialSelection] clamped to the loaded document.
  TextSelection _initialSelection(Document document, TextSelection? want) {
    if (want == null || !want.isValid) {
      return const TextSelection.collapsed(offset: 0);
    }
    final max = (document.length - 1).clamp(0, 1 << 30);
    return TextSelection(
      baseOffset: want.start.clamp(0, max),
      extentOffset: want.end.clamp(0, max),
    );
  }

  /// Scrolls the page so the initial selection sits about a third of the way
  /// down, and focuses the body so the selection shows. Retries for a few
  /// frames while the editor is still being laid out.
  void _revealInitialSelection([int attempt = 0]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final render = _editorKey.currentState?.renderEditor;
      final viewport = _viewportKey.currentContext?.findRenderObject();
      if (render == null ||
          !render.attached ||
          viewport is! RenderBox ||
          !viewport.hasSize ||
          !_pageScroll.hasClients) {
        if (attempt < 6) _revealInitialSelection(attempt + 1);
        return;
      }
      _bodyFocus.requestFocus();
      final sel = _quillController.selection;
      final caret = render.getLocalRectForCaret(
        TextPosition(offset: sel.start.clamp(0, sel.end)),
      );
      final caretY = render.localToGlobal(caret.center).dy;
      final top = viewport.localToGlobal(Offset.zero).dy;
      final position = _pageScroll.position;
      final to = (position.pixels + caretY - (top + viewport.size.height / 3))
          .clamp(position.minScrollExtent, position.maxScrollExtent);
      _pageScroll.jumpTo(to);
    });
  }

  /// Typewriter mode: after the caret moves (typing, arrow keys, a tap),
  /// ease the page so its line sits at ~40% of the visible height. Only
  /// reacts to the editor's own changes, never to scrolling, so reading by
  /// hand is left alone; skipped while a range is selected (dragging
  /// handles) or the body isn't focused.
  void _followCursor() {
    if (!ref.read(appearanceSettingsProvider).typewriter) return;
    if (!_bodyFocus.hasFocus) return;
    final selection = _quillController.selection;
    if (!selection.isValid || !selection.isCollapsed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageScroll.hasClients) return;
      final render = _editorKey.currentState?.renderEditor;
      final viewport = _viewportKey.currentContext?.findRenderObject();
      if (render == null || !render.attached || viewport is! RenderBox) return;
      if (!viewport.hasSize) return;
      final sel = _quillController.selection;
      if (!sel.isValid || !sel.isCollapsed) return;
      final caret = render.getLocalRectForCaret(
        TextPosition(offset: sel.baseOffset),
      );
      final caretY = render.localToGlobal(caret.center).dy;
      final top = viewport.localToGlobal(Offset.zero).dy;
      final target = top + viewport.size.height * 0.4;
      final position = _pageScroll.position;
      final to = (position.pixels + caretY - target).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if ((to - position.pixels).abs() < 2) return;
      final duration = AppMotion.of(context, AppMotion.short);
      if (duration == Duration.zero) {
        _pageScroll.jumpTo(to);
      } else {
        _pageScroll.animateTo(to, duration: duration, curve: AppMotion.enter);
      }
    });
  }

  /// Adds a quote to the end of the open note (see [NoteEditorHandle]).
  Future<void> _appendQuoteHere({
    required String paperId,
    required String quote,
    required int page,
    required String pageLink,
    String? comment,
  }) async {
    final content = appendQuote(
      _stored(),
      quote: quote,
      page: page,
      pageLink: pageLink,
      comment: comment,
    );
    await _docChanges?.cancel();
    _quillController.document = _editable(content);
    _docChanges = _quillController.document.changes.listen(_watchForWikilink);
    await linkPaperToNote(_db, noteId: widget.noteId, paperId: paperId);
    _scheduleSave();
  }

  /// The note as it is stored: citation chips written out as `[@key]`
  /// (see `citation_embed.dart`).
  String _stored() =>
      citationEmbedsToText(
        mathEmbedsToText(encodeNoteContent(_quillController.document)),
      );

  /// Stored content as the editor shows it, with citations as chips.
  static Document _editable(String stored) =>
      decodeNoteContent(citationsToEmbeds(mathToEmbeds(stored)));

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _save);
  }

  Future<void> _save() async {
    _debounce?.cancel();
    final title = _titleController.text;
    final content = _stored();
    if (title == _savedTitle && content == _savedContent) return;
    _savedTitle = title;
    _savedContent = content;
    _remember(_ownTitles, title);
    _remember(_ownContents, content);
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

  static void _remember(Set<String> recent, String value) {
    recent
      ..remove(value)
      ..add(value);
    if (recent.length > 20) recent.remove(recent.first);
  }

  /// The note changed in the database, not through this editor: a sync
  /// pulled or merged another device's edit. Take it in, merging with
  /// anything typed here since the last save, so the next autosave doesn't
  /// write the stale text back over it.
  void _absorbOutsideChange(Note note) {
    if (note.title != _savedTitle && !_ownTitles.contains(note.title)) {
      final untouched = _titleController.text == _savedTitle;
      _savedTitle = note.title;
      if (untouched) _titleController.text = note.title;
    }
    // Compared as the editor would save it: an empty or plain-text body
    // in the database is the same note as its Delta form.
    final theirs = encodeNoteContent(decodeNoteContent(note.content));
    if (theirs == _savedContent || _ownContents.contains(theirs)) return;
    final current = _stored();
    final merged = current == _savedContent
        ? theirs
        : mergeNoteContent(_savedContent, current, theirs) ?? current;
    _savedContent = theirs;
    if (merged == current) return;

    final cursor = _quillController.selection;
    _docChanges?.cancel();
    final document = _editable(merged);
    _quillController.document = document;
    _docChanges = document.changes.listen(_watchForWikilink);
    final max = document.length - 1;
    _quillController.updateSelection(
      TextSelection(
        baseOffset: cursor.baseOffset.clamp(0, max),
        extentOffset: cursor.extentOffset.clamp(0, max),
      ),
      ChangeSource.silent,
    );
  }

  Future<void> _attach(BuildContext context) async {
    final type = await showAddAttachmentSheet(
      context,
      ref,
      noteId: widget.noteId,
      onVoiceNote: _insertVoiceResult,
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

  /// Records a voice note (or dictates) and puts it at the cursor.
  Future<void> _recordVoice(BuildContext context, VoiceMode mode) async {
    final result = await showVoiceSheet(
      context,
      mode: mode,
      noteId: widget.noteId,
    );
    if (result != null && mounted) _insertVoiceResult(result);
  }

  /// `▸ 0:00 Voice note` (a tappable link to the recording) and its
  /// transcript, or just the text of a dictation.
  void _insertVoiceResult(VoiceResult result) {
    if (!mounted) return;
    if (result.attachmentId case final id?) {
      _insertTimestamp(id, Duration.zero);
    }
    insertVoiceText(_quillController, result);
    reportVoiceResult(context, ref, result);
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
        if (op.data == '/') {
          _maybeShowCommands(at);
          return;
        }
        if (op.data case final String pasted) {
          if (pastedIdentifier(pasted) case final id?) {
            _offerPastedCitation(at, pasted, id);
            return;
          }
        }
        if (op.data == r'$') {
          convertTypedDollar(context, _quillController, at);
          return;
        }
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

  /// A DOI or arXiv link was just pasted on its own: offer to turn it into
  /// a citation (and add the paper). Declining, or ignoring the snackbar,
  /// leaves the text as pasted.
  void _offerPastedCitation(int at, String pasted, PaperIdentifier id) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final db = _db;
    final lookup = ref.read(metadataLookupProvider);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Add this paper and cite it?'),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'Add',
            onPressed: () => _citePasted(messenger, db, lookup, at, pasted, id),
          ),
        ),
      );
  }

  Future<void> _citePasted(
    ScaffoldMessengerState messenger,
    AppDatabase db,
    MetadataLookup lookup,
    int at,
    String pasted,
    PaperIdentifier id,
  ) async {
    void say(String text) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
    final String? paperId;
    try {
      paperId = await paperIdForIdentifier(db, lookup, id);
    } on LookupFailed {
      say('Couldn\'t reach the lookup service. The link is unchanged.');
      return;
    }
    if (paperId == null) {
      say('No paper found for ${id.value}.');
      return;
    }
    final key = await ensureCitekey(db, paperId);
    if (!mounted) return;
    final controller = _quillController;
    // The pasted text may have moved while the lookup ran.
    final text = controller.document.toPlainText();
    var index = text.startsWith(pasted, at) ? at : text.indexOf(pasted);
    if (index < 0) {
      final cursor = controller.selection.baseOffset;
      final end = controller.document.length - 1;
      index = cursor < 0 || cursor > end ? end : cursor;
    } else {
      controller.replaceText(
        index,
        pasted.length,
        '',
        TextSelection.collapsed(offset: index),
      );
    }
    insertCitation(controller, index, key);
    AppHaptics.confirm();
  }

  /// A "/" typed at the start of a line or after a space opens the
  /// command list — the note's less obvious actions, without hunting
  /// through menus. "and/or" or a URL doesn't trigger it; dismissing the
  /// list leaves the "/" as typed.
  void _maybeShowCommands(int slashAt) {
    final text = _quillController.document.toPlainText();
    if (slashAt >= text.length || text[slashAt] != '/') return;
    if (slashAt > 0 && !RegExp(r'\s').hasMatch(text[slashAt - 1])) return;
    Future.microtask(() async {
      if (!mounted) return;
      final command = await showModalBottomSheet<_Command>(
        context: context,
        showDragHandle: true,
        // Sized to the list, so every command shows without scrolling.
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final c in _Command.values)
                if (c != _Command.dictate || ref.read(dictationOfferedProvider))
                  ListTile(
                  leading: Icon(c.icon),
                  title: Text(c.label),
                  subtitle: Text(c.hint),
                  onTap: () => Navigator.pop(context, c),
                ),
            ],
          ),
        ),
      );
      if (command == null || !mounted) return;
      // Remove the "/" if it's still where it was typed.
      final now = _quillController.document.toPlainText();
      if (slashAt < now.length && now[slashAt] == '/') {
        _quillController.replaceText(
          slashAt,
          1,
          '',
          TextSelection.collapsed(offset: slashAt),
        );
      }
      if (!mounted) return;
      switch (command) {
        case _Command.cite:
          await _citePaper(context);
        case _Command.equation:
          await insertDisplayMath(context, _quillController);
        case _Command.link:
          await _linkNote(context);
        case _Command.draw:
          await insertSketch(context, _quillController);
        case _Command.heading:
          _quillController.formatSelection(Attribute.h2);
        case _Command.template:
          _insertTemplate();
        case _Command.bibliography:
          await _addBibliography(context);
        case _Command.attach:
          await _attach(context);
        case _Command.voice:
          await _recordVoice(context, VoiceMode.voiceNote);
        case _Command.dictate:
          await _recordVoice(context, VoiceMode.dictate);
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
    insertCitation(controller, index, key);
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
    final style = await pickCitationStyle(context);
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
    if (widget.onClose case final close?) {
      close();
    } else {
      Navigator.of(context).pop();
    }
    await deleteNoteWithUndo(ref, messenger, widget.noteId, title);
  }

  Future<void> _showWordCount(BuildContext context) async {
    final stats = noteStats(_quillController.document);
    final linked = await ref.read(
      linkedPapersForNoteProvider(widget.noteId).future,
    );
    if (!context.mounted) return;
    await showNoteStatsSheet(context, stats, linkedPapers: linked.length);
  }

  Future<void> _export(BuildContext context) async {
    await _save();
    if (!context.mounted) return;
    await exportNotes(context, ref.read(databaseProvider), [
      ExportNote(_titleController.text, _stored()),
    ], title: _titleController.text);
  }

  @override
  void dispose() {
    widget.handle?.appendQuote = null;
    _docChanges?.cancel();
    // Leaving right after typing must not drop the last edit.
    if (_debounce?.isActive ?? false) _save();
    _debounce?.cancel();
    _titleController.dispose();
    _bodyFocus.dispose();
    _bodyScroll.dispose();
    _pageScroll.dispose();
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
    ref.listen(noteByIdProvider(widget.noteId), (_, next) {
      if (next.value case final note? when _loaded) _absorbOutsideChange(note);
    });
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
      // The toolbar rides on top of the keyboard (see bottomNavigationBar),
      // so the body must not also shrink for it.
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
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
              'words' => _showWordCount(context),
              'typewriter' =>
                ref
                    .read(appearanceSettingsProvider)
                    .setTypewriter(
                      !ref.read(appearanceSettingsProvider).typewriter,
                    ),
              'trash' => _moveToTrash(),
              _ => null,
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'project',
                child: ListTile(
                  leading: Icon(Icons.folder_special_outlined),
                  title: Text('Add to project'),
                ),
              ),
              const PopupMenuItem(
                value: 'link',
                child: ListTile(
                  leading: Icon(Icons.add_link),
                  title: Text('Link to a note'),
                  subtitle: Text('Or type [[ while writing'),
                ),
              ),
              const PopupMenuItem(
                value: 'cite',
                child: ListTile(
                  leading: Icon(Icons.format_quote),
                  title: Text('Cite a paper'),
                  subtitle: Text('Or type [@ while writing'),
                ),
              ),
              const PopupMenuItem(
                value: 'template',
                child: ListTile(
                  leading: Icon(Icons.article_outlined),
                  title: Text('Literature note template'),
                  subtitle: Text('Summary, method, findings, critique'),
                ),
              ),
              const PopupMenuItem(
                value: 'bibliography',
                child: ListTile(
                  leading: Icon(Icons.list_alt),
                  title: Text('Add bibliography'),
                ),
              ),
              const PopupMenuItem(
                value: 'export',
                child: ListTile(
                  leading: Icon(Icons.ios_share),
                  title: Text('Export'),
                  subtitle: Text('Markdown, Word or PDF, with references'),
                ),
              ),
              const PopupMenuItem(
                value: 'words',
                child: ListTile(
                  leading: Icon(Icons.format_list_numbered),
                  title: Text('Word count'),
                  subtitle: Text('And reading time'),
                ),
              ),
              PopupMenuItem(
                value: 'typewriter',
                child: ListTile(
                  leading: const Icon(Icons.vertical_align_center),
                  title: const Text('Typewriter scrolling'),
                  subtitle: const Text('Keep the line you type centred'),
                  trailing: ref.read(appearanceSettingsProvider).typewriter
                      ? const Icon(Icons.check)
                      : null,
                ),
              ),
              const PopupMenuItem(
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
      body: LayoutBuilder(
        builder: (context, box) => !_loaded
            ? const SizedBox.shrink()
            : ListView(
                key: _viewportKey,
                controller: _pageScroll,
                // Centred at a readable width on a tablet. In typewriter
                // mode the end of the note can rise to the caret line.
                padding: EdgeInsets.fromLTRB(
                  readablePadding(box.maxWidth),
                  0,
                  readablePadding(box.maxWidth),
                  ref.watch(appearanceSettingsProvider).typewriter
                      ? box.maxHeight * 0.6
                      : 32,
                ),
                children: [
                  TextField(
                    controller: _titleController,
                    style: Theme.of(context).textTheme.headlineMedium,
                    textCapitalization: TextCapitalization.sentences,
                    // A long title wraps rather than scrolling out of
                    // sight; Return moves on to the body (a title is one
                    // line of text, even when it wraps).
                    maxLines: null,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _bodyFocus.requestFocus(),
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
                          if (a.type == AttachmentType.image &&
                              a.path != null) {
                            return _ImagePreview(path: a.path!);
                          }
                          return _AttachmentChip(attachment: a);
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                    ],
                  },
                  QuillEditor.basic(
                    controller: _quillController,
                    focusNode: _bodyFocus,
                    scrollController: _bodyScroll,
                    config: QuillEditorConfig(
                      editorKey: _editorKey,
                      scrollable: false,
                      padding: EdgeInsets.zero,
                      placeholder: 'Start writing…',
                      customLinkPrefixes: const [audioLinkScheme],
                      embedBuilders: const [
                        SketchEmbedBuilder(),
                        CitationEmbedBuilder(),
                        MathInlineEmbedBuilder(),
                        MathBlockEmbedBuilder(),
                      ],
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
      ),
      // A Scaffold leaves its bottom bar under the keyboard; pad it up by the
      // keyboard's height so formatting and Draw stay in reach while typing.
      bottomNavigationBar: !_loaded
          ? null
          : Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
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
                      // The keyboard covers the system bar; no gap above it.
                      bottom: MediaQuery.viewInsetsOf(context).bottom == 0,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Center(
                          // Same width as the text above it on a tablet.
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: readableWidth,
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
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant,
                                ),
                                // The everyday formats stay on the bar; the
                                // rest sit behind "Aa", so the row fits a
                                // phone without scrolling.
                                Expanded(
                                  child: _FormatBar(
                                    controller: _quillController,
                                    onDone: _bodyFocus.requestFocus,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
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
    final title = a.label;
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

/// An image attached to the note, in its own shape (a snapped figure is
/// usually wide; a square crop would cut it off). Tap to see it full screen
/// and zoom in.
class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Image, tap to enlarge',
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => _ImageViewer(path: path),
          ),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(path),
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const SizedBox.square(
                dimension: 96,
                child: Icon(Icons.broken_image_outlined),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: InteractiveViewer(
        maxScale: 6,
        child: Center(child: Image.file(File(path))),
      ),
    );
  }
}

/// The note's formatting row: bold, italic, underline, the two lists, and
/// "Aa" for headings, quote and strikethrough.
class _FormatBar extends StatelessWidget {
  const _FormatBar({required this.controller, required this.onDone});

  final QuillController controller;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    Widget toggle(Attribute attribute) => QuillToolbarToggleStyleButton(
      controller: controller,
      attribute: attribute,
    );
    return SingleChildScrollView(
      // Only scrolls on the very narrowest screens.
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          toggle(Attribute.bold),
          toggle(Attribute.italic),
          toggle(Attribute.underline),
          toggle(Attribute.ul),
          toggle(Attribute.ol),
          _TextStyleButton(controller: controller, onDone: onDone),
        ],
      ),
    );
  }
}

enum _TextStyle {
  title('Title', Icons.title),
  heading('Heading', Icons.text_fields),
  subheading('Subheading', Icons.short_text),
  body('Body text', Icons.notes),
  quote('Quote', Icons.format_quote),
  strike('Strikethrough', Icons.format_strikethrough);

  const _TextStyle(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// "Aa": the less frequent formats, as a menu that says which is on.
class _TextStyleButton extends StatelessWidget {
  const _TextStyleButton({required this.controller, required this.onDone});

  final QuillController controller;
  final VoidCallback onDone;

  bool _isOn(_TextStyle style, Map<String, Attribute> attrs) {
    final header = attrs[Attribute.header.key]?.value;
    return switch (style) {
      _TextStyle.title => header == 1,
      _TextStyle.heading => header == 2,
      _TextStyle.subheading => header == 3,
      _TextStyle.body => header == null,
      _TextStyle.quote => attrs.containsKey(Attribute.blockQuote.key),
      _TextStyle.strike => attrs.containsKey(Attribute.strikeThrough.key),
    };
  }

  void _apply(_TextStyle style) {
    final attrs = controller.getSelectionStyle().attributes;
    controller.formatSelection(switch (style) {
      _TextStyle.title => Attribute.h1,
      _TextStyle.heading => Attribute.h2,
      _TextStyle.subheading => Attribute.h3,
      _TextStyle.body => Attribute.header,
      _TextStyle.quote =>
        _isOn(style, attrs)
            ? Attribute.clone(Attribute.blockQuote, null)
            : Attribute.blockQuote,
      _TextStyle.strike =>
        _isOn(style, attrs)
            ? Attribute.clone(Attribute.strikeThrough, null)
            : Attribute.strikeThrough,
    });
    onDone();
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_TextStyle>(
      tooltip: 'Text style',
      onSelected: _apply,
      itemBuilder: (_) {
        final attrs = controller.getSelectionStyle().attributes;
        return [
          for (final style in _TextStyle.values) ...[
            if (style == _TextStyle.quote) const PopupMenuDivider(),
            CheckedPopupMenuItem(
              value: style,
              checked: _isOn(style, attrs),
              child: Text(style.label),
            ),
          ],
        ];
      },
      child: SizedBox.square(
        dimension: 40,
        child: Center(
          child: Text(
            'Aa',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// What "/" in a note offers.
enum _Command {
  cite(
    'Cite a paper',
    'Insert a citation from your library',
    Icons.format_quote,
  ),
  equation('Equation', r'LaTeX maths, or type $$', Icons.functions),
  link('Link to a note', 'Or type [[', Icons.link),
  draw('Draw', 'A sketch, with a pen or finger', Icons.draw_outlined),
  heading('Heading', 'Make this line a heading', Icons.title),
  attach('Attach', 'Audio, an image or a file', Icons.attach_file),
  voice('Voice note', 'Record a thought as you read', Icons.mic_none),
  dictate('Dictate', 'Speak instead of typing', Icons.keyboard_voice_outlined),
  template(
    'Literature note template',
    'Summary, method, findings, critique',
    Icons.article_outlined,
  ),
  bibliography(
    'Add bibliography',
    'A reference list of what this note cites',
    Icons.list_alt,
  );

  const _Command(this.label, this.hint, this.icon);

  final String label;
  final String hint;
  final IconData icon;
}
