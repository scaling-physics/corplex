import '../export/export_images.dart';

import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart'
    show
        BooleanExpressionOperators,
        OrderingTerm,
        StringExpressionOperators,
        Value;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:url_launcher/url_launcher.dart';

import '../markup/image_markup_screen.dart';
import '../../data/attachment_label.dart';
import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/tables/attachments_table.dart';
import '../lock/lock_screen.dart';
import '../lock/locked_edit_rescue.dart';
import '../lock/note_crypto.dart' show NoteDecryptException, lockedPrefix;
import '../lock/note_lock_service.dart';
import '../lock/notes_password_dialogs.dart';
import '../audio/audio_link.dart';
import '../comments/comment_views.dart';
import '../comments/comments_data.dart' show pendingCommentsPanelProvider;
import '../comments/editor_comments.dart';
import '../audio/audio_playback.dart';
import '../audio/audio_player_bar.dart';
import '../voice/voice_services.dart' show dictationOfferedProvider;
import '../voice/voice_sheet.dart';
import '../export/export_actions.dart';
import '../export/export_model.dart';
import '../ink/ink_canvas.dart' show inkPolicy;
import '../ink/ink_catcher.dart';
import '../ink/ink_session.dart';
import '../ink/sketch_embed.dart';
import '../../theme/app_theme.dart';
import '../projects/project_picker_sheet.dart';
import '../spell/note_spell.dart';
import '../spell/spell_checker.dart';
import '../trash/trash_actions.dart';
import '../settings/appearance_settings.dart';
import '../library/metadata_lookup.dart';
import 'editor_document.dart';
import 'figure_embed.dart';
import 'figure_markers.dart';
import '../projects/figures.dart';
import '../projects/todos.dart' show openNoteAtSelection;
import 'note_stats.dart';
import 'table_embed.dart';
import 'note_versions_screen.dart';
import 'paste_citation.dart';
import '../../theme/haptics.dart';
import '../projects/projects_providers.dart';
import '../projects/todos_request.dart';
import '../sync/merge.dart';
import '../home/adaptive.dart' show readablePadding, readableWidth;
import '../platform/mac_window.dart'
    show MenuCommand, MenuCommandHandler, isDesktop, isMac, macPanePadding;
import 'note_find.dart';
import 'note_highlight.dart';
import 'note_zoom.dart';
import 'cite_paper_sheet.dart';
import 'citation_embed.dart';
import '../csl/style_picker.dart';
import 'math_embed.dart';
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
import 'note_drop.dart';
import 'note_file_actions.dart';
import 'note_lock_actions.dart' show openNoteFlushProvider;
import 'note_papers_providers.dart';
import 'notes_providers.dart';
import 'tag_picker_sheet.dart';
import 'tags_providers.dart';

/// Bumped by the Notes list (Return / Tab) to move the keyboard into the
/// open note's body; the embedded editor listens.
final noteBodyFocusRequestProvider = StateProvider<int>((ref) => 0);

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
///
/// A locked note whose key isn't unlocked shows [NoteLockScreen] instead of
/// the editor; unlocking (or the notes locking again, by timer, app pause
/// or "Close All Locked Notes") swaps between the two.
class NoteEditorScreen extends ConsumerWidget {
  const NoteEditorScreen({
    super.key,
    required this.noteId,
    this.handle,
    this.embedded = false,
    this.onClose,
    this.initialSelection,
  });

  final String noteId;
  final TextSelection? initialSelection;
  final NoteEditorHandle? handle;
  final bool embedded;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(noteLockServiceProvider);
    final note = ref.watch(noteByIdProvider(noteId));
    final loaded = note.hasValue;
    if (!loaded) {
      return Scaffold(appBar: AppBar(automaticallyImplyLeading: !embedded));
    }
    final value = note.value;
    if (value != null &&
        isLockedContent(value.content) &&
        !lock.canRead(value.content)) {
      return NoteLockScreen(title: value.title, embedded: embedded);
    }
    return _NoteEditorBody(
      noteId: noteId,
      handle: handle,
      embedded: embedded,
      onClose: onClose,
      initialSelection: initialSelection,
    );
  }
}

/// A single note, editable in place with no separate "edit mode" — typing
/// autosaves after a short pause, so there's nothing to remember to save.
class _NoteEditorBody extends ConsumerStatefulWidget {
  const _NoteEditorBody({
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
  ConsumerState<_NoteEditorBody> createState() => _NoteEditorBodyState();
}

class _NoteEditorBodyState extends ConsumerState<_NoteEditorBody> {
  final _titleController = TextEditingController();
  late final QuillController _quillController;

  NoteSpell? _spellHelper;

  /// Comments on passages: the tint, the popover, the panel.
  EditorComments? _commentsHelper;
  EditorComments get _comments => _commentsHelper ??= EditorComments(
    noteId: widget.noteId,
    controller: _quillController,
    ref: ref,
  );

  /// The comments panel is open beside the note (wide windows; on phones it
  /// is a bottom sheet and this stays false).
  bool _commentsOpen = false;

  /// The project page asked for this note's comments panel.
  void _openCommentsIfAsked() {
    if (!mounted || !_loaded) return;
    if (ref.read(pendingCommentsPanelProvider) != widget.noteId) return;
    ref.read(pendingCommentsPanelProvider.notifier).state = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openComments();
    });
  }

  void _openComments() {
    if (!_loaded) return;
    if (MediaQuery.sizeOf(context).width >= 900) {
      setState(() => _commentsOpen = true);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheet).height * 0.7,
        ),
        child: _comments.panel(
          context: context,
          showClose: false,
          onClose: () => Navigator.pop(sheet),
          afterPick: (_) {
            Navigator.pop(sheet);
            _bodyFocus.requestFocus();
          },
        ),
      ),
    );
  }

  /// [scaffold], with the comments panel beside it when it is open.
  Widget _withCommentsPanel(Widget scaffold) {
    if (!_commentsOpen || !_loaded) return scaffold;
    return Row(
      children: [
        Expanded(child: scaffold),
        VerticalDivider(
          width: 1,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        SizedBox(
          width: 320,
          child: SafeArea(
            child: _comments.panel(
              context: context,
              onClose: () => setState(() => _commentsOpen = false),
              afterPick: (_) => _bodyFocus.requestFocus(),
            ),
          ),
        ),
      ],
    );
  }

  /// Spell check for the body, rebuilding the editor as results arrive.
  /// Call from build only: it follows the setting and the platform checker.
  NoteSpell _spellNow() {
    final spell = _spellHelper ??=
        NoteSpell(
          controller: _quillController,
          checker: () => ref.read(spellCheckerProvider),
        )..addListener(() {
          if (mounted) setState(() {});
        });
    spell.enabled =
        ref.watch(appearanceSettingsProvider.select((s) => s.spellCheck)) &&
        ref.watch(spellCheckerProvider).available;
    return spell;
  }

  /// Find in note (⌘F / ⋮ → Find in note) is open; [_findStep] moves it
  /// to the next or previous match (⌘G / ⇧⌘G).
  bool _finding = false;
  final _findStep = ValueNotifier<void Function(int)?>(null);

  void _openFind() => setState(() => _finding = true);

  void _closeFind() => setState(() => _finding = false);
  Timer? _debounce;
  bool _loaded = false;
  // Captured up front: dispose() must be able to flush a pending save, and
  // `ref` can't be used there.
  late final AppDatabase _db = ref.read(databaseProvider);
  StreamSubscription<DocChange>? _docChanges;

  /// Figure and table numbers for the chips in this note.
  final _figures = FigureScope();

  // Owned here, not left to QuillEditor.basic: it makes a fresh FocusNode on
  // every build, so any rebuild (e.g. after an autosave) dropped the body's
  // focus and the keyboard jumped to the title mid-sentence.
  final _bodyFocus = FocusNode();

  /// Pen input: inline drawings, the floating tools (see [InkSession]).
  InkSession? _ink;
  final _titleFocus = FocusNode();
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

  // ---- Locked notes ----
  // The editor only ever holds a locked note's *text*; the database gets an
  // envelope (`encryptBody`) on every save, and `_savedContent` /
  // `_ownContents` are the decrypted bodies, since every save produces
  // different ciphertext.
  late final NoteLockService _lock;
  late final LockedEditRescue _rescue;
  late final Map<String, Future<void> Function()> _flushRegistry;

  /// This note is locked: saves encrypt.
  bool _locked = false;

  /// The envelope last seen in the database (to know when its key goes).
  String? _envelope;

  /// The body couldn't be decrypted (damaged): never save over it.
  bool _blocked = false;

  /// The notes locked under this editor and a save was cut short; the
  /// text went to [LockedEditRescue] instead.
  bool _lockedOut = false;

  /// Saves run one at a time (encrypting is async).
  Future<void> _saveQueue = Future.value();
  int _absorbSeq = 0;

  @override
  void initState() {
    super.initState();
    _lock = ref.read(noteLockServiceProvider);
    _rescue = ref.read(lockedEditRescueProvider);
    _flushRegistry = ref.read(openNoteFlushProvider);
    _flushRegistry[widget.noteId] = _save;
    _loadNote();
    ref.listenManual<String?>(
      pendingCommentsPanelProvider,
      (_, _) => _openCommentsIfAsked(),
    );
    _figures.onOpen = _openFigure;
    ref.listenManual<FigureContext>(
      figureContextProvider(widget.noteId),
      (_, next) => _figures.setContext(next, widget.noteId),
      fireImmediately: true,
    );
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

    var body = note?.content ?? '';
    if (note != null && isLockedContent(body)) {
      _locked = true;
      _envelope = body;
      try {
        body = await _lock.decryptBody(widget.noteId, body);
      } on NoteLockedException {
        // The gate shows the lock screen; this editor is about to go.
        body = '';
        _blocked = true;
      } on NoteDecryptException {
        body = '';
        _blocked = true;
      }
    }
    if (!mounted) return;
    _lock.addListener(_onLockChanged);

    final document = note == null ? Document() : _editable(body);
    var want = widget.initialSelection;
    final pending = mounted ? ref.read(pendingNoteSelectionProvider) : null;
    if (pending != null && pending.noteId == widget.noteId) {
      want ??= pending.selection;
      ref.read(pendingNoteSelectionProvider.notifier).state = null;
    }
    _quillController = QuillController(
      document: document,
      selection: _initialSelection(document, want),
      // Files and pictures on the clipboard become attachments.
      // ignore: experimental_member_use
      config: QuillControllerConfig(
        // ignore: experimental_member_use
        clipboardConfig: QuillClipboardConfig(
          // ignore: experimental_member_use
          onClipboardPaste: () =>
              pasteFilesIntoNote(context, ref, widget.noteId),
        ),
      ),
    );
    _ink = InkSession(
      controller: _quillController,
      // Drawing hides the keyboard, as in Notes.
      onInkStart: () => _bodyFocus.unfocus(),
      onQuietEdit: () {
        if (mounted) setState(() {});
      },
    );
    // Tapping back into the text puts the drawing tools away.
    _bodyFocus.addListener(_leaveDrawingIfTyping);
    _quillController.addListener(_leaveDrawingIfTyping);
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
    _figures.documentChanged(document);
    widget.handle?.appendQuote = _appendQuoteHere;
    if (mounted) setState(() => _loaded = true);
    _openCommentsIfAsked();
    if (want != null) _revealInitialSelection();
    _restoreRescued();
  }

  /// Typing that was cut off when the notes locked: back into the editor
  /// (and saved, encrypted, by the usual autosave).
  void _restoreRescued() {
    final rescued = _rescue.take(widget.noteId);
    if (rescued == null || !mounted || _blocked) return;
    if (rescued.content == _stored() &&
        rescued.title == _titleController.text) {
      return;
    }
    if (rescued.content != _stored()) {
      _docChanges?.cancel();
      final document = _editable(rescued.content);
      _quillController.document = document;
      _docChanges = document.changes.listen(_watchForWikilink);
      _figures.documentChanged(document);
    }
    if (rescued.title != _titleController.text) {
      _titleController.text = rescued.title;
    }
    _scheduleSave();
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
    _figures.documentChanged(_quillController.document);
    await linkPaperToNote(_db, noteId: widget.noteId, paperId: paperId);
    _scheduleSave();
  }

  /// The note as it is stored: citation chips written out as `[@key]`
  /// (see `citation_embed.dart`).
  String _stored() => storedFromEditor(_quillController.document);

  /// Stored content as the editor shows it, with citations as chips.
  static Document _editable(String stored) => editorDocument(stored);

  void _scheduleSave() {
    _debounce?.cancel();
    if (_locked) _lock.touch();
    // Sooner for a locked note: if the notes lock, whatever hasn't been
    // encrypted and saved yet has to be rescued from memory.
    _debounce = Timer(Duration(milliseconds: _locked ? 150 : 400), _save);
  }

  Future<void> _save() {
    _debounce?.cancel();
    // Read now: dispose() calls this and then tears the controllers down.
    final title = _titleController.text;
    final content = _blocked ? '' : _stored();
    return _saveQueue = _saveQueue.then((_) => _saveNow(title, content));
  }

  Future<void> _saveNow(String title, String content) async {
    if (_blocked || _lockedOut) return;
    if (title == _savedTitle && content == _savedContent) return;
    var written = content;
    if (!_locked) {
      // Someone else may have locked the note since this editor loaded it
      // (the list's menu, another path): never write plain text over an
      // envelope. Checked and written in one transaction.
      // One conditional UPDATE: it only matches while the row isn't locked.
      final changed =
          await (_db.update(_db.notes)..where(
                (n) =>
                    n.id.equals(widget.noteId) &
                    n.content.like('$lockedPrefix%').not(),
              ))
              .write(
                NotesCompanion(
                  title: Value(title),
                  content: Value(content),
                  updatedAt: Value(DateTime.now()),
                ),
              );
      final row = changed > 0
          ? null
          : await (_db.select(
              _db.notes,
            )..where((n) => n.id.equals(widget.noteId))).getSingleOrNull();
      final nowLocked = row != null && isLockedContent(row.content);
      if (nowLocked) _envelope = row.content;
      if (!nowLocked) {
        _savedTitle = title;
        _savedContent = content;
        _remember(_ownTitles, title);
        _remember(_ownContents, content);
        return;
      }
      _locked = true;
      if (mounted) setState(() {});
    }
    if (_locked) {
      try {
        written = await _lock.encryptBody(widget.noteId, content);
      } on NoteLockedException {
        // The key went before this could be written: keep the text in
        // memory for the next unlock instead of losing it (or, worse,
        // writing it unencrypted).
        _lockedOut = true;
        _rescue.keep(widget.noteId, title, content);
        return;
      }
    }
    _savedTitle = title;
    _savedContent = content;
    _remember(_ownTitles, title);
    _remember(_ownContents, content);
    await (_db.update(
      _db.notes,
    )..where((n) => n.id.equals(widget.noteId))).write(
      NotesCompanion(
        title: Value(title),
        content: Value(written),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// The notes locked or unlocked. If this note's key just went and there
  /// is typing that isn't saved yet, keep it for the next unlock — the lock
  /// screen replaces this editor in the same frame.
  void _onLockChanged() {
    if (!_locked || _blocked || _lockedOut || !_loaded) return;
    if (_envelope == null || _lock.canRead(_envelope!)) return;
    _lockedOut = true;
    _debounce?.cancel();
    final title = _titleController.text;
    final content = _stored();
    if (title != _savedTitle || content != _savedContent) {
      _rescue.keep(widget.noteId, title, content);
    }
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
    if (isLockedContent(note.content)) {
      _locked = true;
      _envelope = note.content;
      final seq = ++_absorbSeq;
      _lock
          .decryptBody(widget.noteId, note.content)
          .then((plain) {
            if (mounted && seq == _absorbSeq) _absorbPlain(note, plain);
          })
          .catchError((_) {
            // Locked meanwhile (the gate shows the lock screen), or damaged.
          });
      return;
    }
    if (_locked) {
      // The lock was taken off (here or on another device).
      _locked = false;
      _envelope = null;
    }
    _absorbPlain(note, note.content);
  }

  void _absorbPlain(Note note, String body) {
    if (_blocked) return;
    if (note.title != _savedTitle && !_ownTitles.contains(note.title)) {
      final untouched = _titleController.text == _savedTitle;
      _savedTitle = note.title;
      if (untouched) _titleController.text = note.title;
    }
    // Compared as the editor would save it: an empty or plain-text body
    // in the database is the same note as its Delta form.
    final theirs = encodeNoteContent(decodeNoteContent(body));
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
    _figures.documentChanged(document);
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
    _figures.documentChanged(_quillController.document);
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
      // A column in a scroll view, not a lazy list: every command is
      // built (and findable), and it scrolls when the screen is short.
      Widget list(BuildContext context) => SingleChildScrollView(
        child: Column(
          children: [
            for (final c in _Command.values)
              if (c != _Command.dictate || ref.read(dictationOfferedProvider))
                ListTile(
                  leading: Icon(c.icon),
                  title: Text(c.label),
                  subtitle: Text(c.hint),
                  dense: isDesktop(context),
                  onTap: () => Navigator.pop(context, c),
                ),
          ],
        ),
      );
      // A desktop shows it as a small panel in the middle of the window; a
      // bottom sheet would sit alone at the foot of a very wide one.
      final command = isDesktop(context)
          ? await showDialog<_Command>(
              context: context,
              builder: (context) => Dialog(
                clipBehavior: Clip.antiAlias,
                insetPadding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: list(context),
                  ),
                ),
              ),
            )
          : await showModalBottomSheet<_Command>(
              context: context,
              showDragHandle: true,
              // Sized to the list, so every command shows without scrolling.
              isScrollControlled: true,
              builder: (context) => SafeArea(child: list(context)),
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
        case _Command.figure:
          _insertCaption(FigureKind.figure);
        case _Command.table:
          _insertCaption(FigureKind.table);
        case _Command.refer:
          await _referToFigure(context);
        case _Command.link:
          await _linkNote(context);
        case _Command.draw:
          _ink?.insertAtCursor();
        case _Command.insertTable:
          _insertTable();
        case _Command.heading:
          _quillController.formatSelection(Attribute.h2);
        case _Command.checklist:
          _quillController.formatSelection(Attribute.unchecked);
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

  /// Starts a figure or table caption: a numbered chip at the start of the
  /// current line (on a new line below when the line has text), the cursor
  /// after it ready for the caption.
  void _insertCaption(FigureKind kind) {
    final controller = _quillController;
    final docEnd = controller.document.length - 1;
    final cursor = controller.selection.baseOffset;
    final index = cursor < 0 || cursor > docEnd ? docEnd : cursor;
    var at = index;
    final found = controller.document.queryChild(index);
    if (found.node case final Line line) {
      at = line.documentOffset;
      if (line.length > 1) {
        at += line.length - 1;
        controller.replaceText(at, 0, '\n', null);
        at += 1;
      }
    }
    controller.replaceText(
      at,
      0,
      Embeddable(figureDefType, figureDefMarker(kind, newFigureLabel())),
      null,
    );
    controller.replaceText(
      at + 1,
      0,
      ' ',
      TextSelection.collapsed(offset: at + 2),
    );
    _bodyFocus.requestFocus();
  }

  /// Offers this note's figures and tables and the other chapters', and
  /// inserts a reference chip at the cursor.
  Future<void> _referToFigure(BuildContext context) async {
    final picked = await showFigureRefSheet(context, _figures);
    if (picked == null || !mounted) return;
    final controller = _quillController;
    final docEnd = controller.document.length - 1;
    final sel = controller.selection;
    final start = sel.start < 0 || sel.start > docEnd ? docEnd : sel.start;
    final length = sel.isValid && sel.end <= docEnd ? sel.end - sel.start : 0;
    controller.replaceText(
      start,
      length,
      Embeddable(figureRefType, figureRefMarker(picked.kind, picked.label)),
      TextSelection.collapsed(offset: start + 1),
    );
    _bodyFocus.requestFocus();
  }

  /// A reference chip was tapped: select the definition here, or open the
  /// chapter that holds it, with the definition selected.
  Future<void> _openFigure(FigureKind kind, String label) async {
    final entry = _figures.find(kind, label);
    if (entry == null) return;
    if (entry.noteId == widget.noteId) {
      // After the tap itself, which also places the caret under the chip.
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;
      for (final d in figureDefsIn(_quillController.document.toDelta())) {
        if (d.kind != kind || d.label != label) continue;
        _quillController.updateSelection(
          TextSelection(baseOffset: d.offset, extentOffset: d.offset + 1),
          ChangeSource.local,
        );
        _revealInitialSelection();
        return;
      }
      return;
    }
    final note = await (_db.select(
      _db.notes,
    )..where((n) => n.id.equals(entry.noteId))).getSingleOrNull();
    final offset = note == null
        ? null
        : figureOffset(note.content, kind, label);
    if (!mounted) return;
    openNoteAtSelection(
      context,
      ref,
      entry.noteId,
      TextSelection(baseOffset: offset ?? 0, extentOffset: (offset ?? 0) + 1),
    );
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

  /// Locks this note: asks for (or first sets) the notes password, saves
  /// what's typed, then encrypts the note and its versions. The editor stays
  /// open and unlocked.
  Future<void> _lockNote() async {
    if (!_loaded || _locked || _blocked) return;
    final ok = await ensureNotesUnlocked(context, _lock);
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final attachments = await (_db.select(
      _db.attachments,
    )..where((a) => a.noteId.equals(widget.noteId))).get();
    if (!mounted) return;
    _debounce?.cancel();
    await _save();
    // From here saves encrypt, so nothing typed meanwhile is written plain.
    _locked = true;
    try {
      await _lock.lockNote(widget.noteId);
    } catch (_) {
      _locked = false;
      rethrow;
    }
    if (!mounted) return;
    setState(() {});
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            attachments.isEmpty
                ? 'Note locked'
                : 'Note locked. Attached files (images, audio, PDFs) '
                      'aren\'t encrypted — only the note\'s text and sketches.',
          ),
        ),
      );
  }

  /// Takes the lock off (needs the notes unlocked).
  Future<void> _removeLock() async {
    if (!_locked) return;
    if (!await _lock.isUnlocked() && !await _lock.unlockWithBiometrics()) {
      if (!mounted) return;
      final ok = await showUnlockNotesDialog(context, _lock);
      if (!ok || !mounted) return;
    }
    _debounce?.cancel();
    await _save();
    // Plain from here on; the database echo of the change sees it.
    await _lock.removeLock(widget.noteId);
    _locked = false;
    _envelope = null;
    if (mounted) setState(() {});
  }

  /// Puts the drawing tools away once the cursor is in the text: the body
  /// has focus and the selection isn't beside the chosen drawing. (A finger
  /// tap on a drawing also focuses the editor, with the cursor at the
  /// drawing — that is choosing it, not leaving it.) Checked after the frame,
  /// when Quill has settled the selection.
  void _leaveDrawingIfTyping() {
    final ink = _ink;
    if (ink == null || ink.active == null || !_bodyFocus.hasFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final active = ink.active;
      if (!mounted || active == null || !_bodyFocus.hasFocus) return;
      final sel = _quillController.selection;
      final atDrawing =
          sel.isCollapsed &&
          (sel.baseOffset == active || sel.baseOffset == active + 1);
      if (!atDrawing) ink.deactivate();
    });
  }

  /// A tap in the blank space under the text: type at the end, as Notes does.
  void _focusEnd() {
    if (!_loaded) return;
    final end = _quillController.document.length - 1;
    _quillController.updateSelection(
      TextSelection.collapsed(offset: end),
      ChangeSource.local,
    );
    _bodyFocus.requestFocus();
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
    final content = _stored();
    final figures = await figureIndexForNote(
      _db,
      widget.noteId,
      liveContent: content,
      lock: _lock,
    );
    final images = await noteExportImages(_db, widget.noteId);
    if (!context.mounted) return;
    await exportNotes(
      context,
      _db,
      [ExportNote(_titleController.text, content, images: images)],
      title: _titleController.text,
      figures: figures,
    );
  }

  @override
  void dispose() {
    _findStep.dispose();
    _spellHelper?.dispose();
    _commentsHelper?.dispose();
    widget.handle?.appendQuote = null;
    _lock.removeListener(_onLockChanged);
    if (_flushRegistry[widget.noteId] == _save) {
      _flushRegistry.remove(widget.noteId);
    }
    _docChanges?.cancel();
    // Leaving right after typing must not drop the last edit.
    if (_debounce?.isActive ?? false) _save();
    _debounce?.cancel();
    _titleController.dispose();
    _figures.dispose();
    _bodyFocus.removeListener(_leaveDrawingIfTyping);
    if (_loaded) _quillController.removeListener(_leaveDrawingIfTyping);
    _bodyFocus.dispose();
    _ink?.dispose();
    _titleFocus.dispose();
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

    final desktop = isDesktop(context);
    // A mouse or trackpad draws on a chosen drawing on a desktop.
    inkPolicy.mouseAlwaysDraws = desktop;
    final zoom = desktop ? ref.watch(noteZoomProvider).scale : 1.0;
    ref.listen(noteBodyFocusRequestProvider, (_, _) {
      if (widget.embedded && _loaded) _bodyFocus.requestFocus();
    });
    if (_loaded) {
      _comments.sync(ref.watch(commentViewsProvider(widget.noteId)));
    }
    final scaffold = Scaffold(
      // The toolbar rides on top of the keyboard (see bottomNavigationBar),
      // so the body must not also shrink for it.
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        // One toolbar row, as in Apple Notes: the formatting controls on
        // the left of the header, the note's actions on the right. The
        // header never holds the note's title.
        titleSpacing: 8,
        centerTitle: false,
        title: desktop && _loaded
            ? _DesktopFormatBar(
                controller: _quillController,
                mac: isMac(context),
                onDraw: () => _ink?.insertAtCursor(),
                onDone: _bodyFocus.requestFocus,
              )
            : null,
        actions: [
          if (_locked)
            IconButton(
              icon: const Icon(Icons.lock_outline),
              tooltip: 'Locked — tap to lock now',
              onPressed: _lock.lockNow,
            ),
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
              'versions' => showNoteVersions(
                context,
                noteId: widget.noteId,
                flush: _save,
              ),
              'typewriter' =>
                ref
                    .read(appearanceSettingsProvider)
                    .setTypewriter(
                      !ref.read(appearanceSettingsProvider).typewriter,
                    ),
              'lock' => _lockNote(),
              'unlock' => _removeLock(),
              'pin' => setNotePinned(
                ref.read(databaseProvider),
                widget.noteId,
                !(ref.read(noteByIdProvider(widget.noteId)).value?.pinned ??
                    false),
              ),
              'find' => _openFind(),
              'comments' => _openComments(),
              'duplicate' => duplicateNoteAndOpen(context, ref, widget.noteId),
              'print' => printNote(context, ref, widget.noteId),
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
              const PopupMenuItem(
                value: 'versions',
                child: ListTile(
                  leading: Icon(Icons.history),
                  title: Text('Versions'),
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
              if (_locked)
                const PopupMenuItem(
                  value: 'unlock',
                  child: ListTile(
                    leading: Icon(Icons.lock_open_outlined),
                    title: Text('Remove lock'),
                  ),
                )
              else
                const PopupMenuItem(
                  value: 'lock',
                  child: ListTile(
                    leading: Icon(Icons.lock_outline),
                    title: Text('Lock note'),
                    subtitle: Text('Needs your notes password to open'),
                  ),
                ),
              const PopupMenuItem(
                value: 'comments',
                child: ListTile(
                  leading: Icon(Icons.comment_outlined),
                  title: Text('Comments'),
                ),
              ),
              const PopupMenuItem(
                value: 'find',
                child: ListTile(
                  leading: Icon(Icons.search),
                  title: Text('Find in note'),
                ),
              ),
              if (ref.read(noteByIdProvider(widget.noteId)).value?.pinned ??
                  false)
                const PopupMenuItem(
                  value: 'pin',
                  child: ListTile(
                    leading: Icon(Icons.push_pin),
                    title: Text('Unpin'),
                  ),
                )
              else
                const PopupMenuItem(
                  value: 'pin',
                  child: ListTile(
                    leading: Icon(Icons.push_pin_outlined),
                    title: Text('Pin to top'),
                  ),
                ),
              const PopupMenuItem(
                value: 'duplicate',
                child: ListTile(
                  leading: Icon(Icons.copy_outlined),
                  title: Text('Duplicate'),
                ),
              ),
              if (isMac(context))
                const PopupMenuItem(
                  value: 'print',
                  child: ListTile(
                    leading: Icon(Icons.print_outlined),
                    title: Text('Print…'),
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
      body: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, box) => !_loaded
                  ? const SizedBox.shrink()
                  : ListView(
                      key: _viewportKey,
                      controller: _pageScroll,
                      // Centred at a readable width on a tablet. In typewriter
                      // mode the end of the note can rise to the caret line.
                      padding: EdgeInsets.fromLTRB(
                        _sideMargin(box.maxWidth, desktop),
                        0,
                        _sideMargin(box.maxWidth, desktop),
                        ref.watch(appearanceSettingsProvider).typewriter
                            ? box.maxHeight * 0.6
                            : 32,
                      ),
                      children: [
                        if (desktop && noteAsync.value != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: Center(
                              child: Text(
                                DateFormat("d MMMM y 'at' HH:mm")
                                    .format(noteAsync.value!.updatedAt),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ),
                          ),
                        // Tab goes on into the body, as Return does.
                        Focus(
                          canRequestFocus: false,
                          skipTraversal: true,
                          onKeyEvent: (_, e) {
                            if (desktop &&
                                e is KeyDownEvent &&
                                e.logicalKey == LogicalKeyboardKey.tab &&
                                !HardwareKeyboard.instance.isShiftPressed) {
                              _bodyFocus.requestFocus();
                              return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          },
                          child: TextField(
                            controller: _titleController,
                            focusNode: _titleFocus,
                            style: desktop
                                ? Theme.of(context).textTheme.headlineMedium
                                      ?.copyWith(
                                        fontSize: 32 * zoom,
                                        height: 1.2,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.4,
                                      )
                                : Theme.of(context).textTheme.headlineMedium,
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
                                    color: Theme.of(context)
                                        .colorScheme
                                        .secondary,
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
                                      onPressed: () => Navigator.of(context)
                                          .push(
                                            MaterialPageRoute(
                                              builder: (_) => PaperDetailScreen(
                                                paperId: paper.id,
                                              ),
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
                                  return _ImagePreview(attachment: a);
                                }
                                return _AttachmentChip(attachment: a);
                              }).toList(),
                            ),
                            const SizedBox(height: 8),
                          ],
                        },
                        FigureScopeInherited(
                          scope: _figures,
                          child: InkSessionScope(
                            session: _ink!,
                            child: InkCatcher(
                              session: _ink!,
                              editorKey: _editorKey,
                              onTapBelow: _focusEnd,
                              child: QuillEditor.basic(
                                controller: _quillController,
                                focusNode: _bodyFocus,
                                scrollController: _bodyScroll,
                                config: QuillEditorConfig(
                                  editorKey: _editorKey,
                                  textSpanBuilder: _comments.marks.wrap(
                                    _spellNow().spanBuilder,
                                  ),
                                  contextMenuBuilder: (ctx, state) =>
                                      _comments.contextMenu(
                                        ctx,
                                        state,
                                        _spellNow().contextMenu,
                                        innerWins: () =>
                                            _spellNow()
                                                .misspellingAtSelection() !=
                                            null,
                                      ),
                                  onTapUp: (details, position) => _comments
                                      .onTapUp(context, details, position),
                                  scrollable: false,
                                  padding: EdgeInsets.zero,
                                  placeholder: 'Start writing…',
                                  customStyles: desktop
                                      ? _desktopStyles(context, zoom)
                                      : _mobileStyles(context),
                                  customStyleBuilder: noteStyleFor,
                                  customShortcuts: desktop
                                      ? _desktopShortcuts
                                      : null,
                                  customActions: desktop
                                      ? {
                                          _NoteCommandIntent:
                                              CallbackAction<
                                                _NoteCommandIntent
                                              >(
                                                onInvoke: (i) {
                                                  _commands[i.command]?.call();
                                                  return null;
                                                },
                                              ),
                                          _PassKeyIntent: DoNothingAction(
                                            consumesKey: false,
                                          ),
                                        }
                                      : null,
                                  // ignore: experimental_member_use
                                  onKeyPressed: desktop ? _onBodyKey : null,
                                  customLinkPrefixes: const [audioLinkScheme],
                                  embedBuilders: const [
                                    FigureDefEmbedBuilder(),
                                    FigureRefEmbedBuilder(),
                                    SketchEmbedBuilder(),
                                    TableEmbedBuilder(),
                                    CitationEmbedBuilder(),
                                    MathInlineEmbedBuilder(),
                                    MathBlockEmbedBuilder(),
                                  ],
                                  // Audio timestamps play on a plain tap; other links
                                  // keep Quill's default long-press menu.
                                  customRecognizerBuilder: (attribute, leaf) {
                                    if (attribute.key != Attribute.link.key) {
                                      return null;
                                    }
                                    final link =
                                        attribute.value?.toString() ?? '';
                                    if (parseAudioTimestampLink(link)
                                        case final t?) {
                                      return TapGestureRecognizer()
                                        ..onTap = () =>
                                            _playFrom(t.attachmentId, t.at);
                                    }
                                    if (parsePaperPageLink(link)
                                        case final p?) {
                                      return TapGestureRecognizer()
                                        ..onTap = () =>
                                            _openPaperAt(p.paperId, p.page);
                                    }
                                    if (parseNoteLink(link) case final id?) {
                                      return TapGestureRecognizer()
                                        ..onTap = () => _openNote(id);
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                        _Backlinks(noteId: widget.noteId),
                      ],
                    ),
            ),
          ),
          // While a drawing is chosen: pen, inks, eraser, undo, Done.
          if (_ink != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Center(child: InlineInkToolbar(session: _ink!)),
            ),
        ],
      ),
      // A Scaffold leaves its bottom bar under the keyboard; pad it up by the
      // keyboard's height so formatting and Draw stay in reach while typing.
      bottomNavigationBar: !_loaded
          ? null
          : desktop
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_finding)
                  NoteFindBar(
                    controller: _quillController,
                    step: _findStep,
                    onClose: _closeFind,
                  ),
                AudioPlayerBar(onMark: _insertTimestamp),
              ],
            )
          : Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_finding)
                    NoteFindBar(
                      controller: _quillController,
                      step: _findStep,
                      onClose: _closeFind,
                    ),
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
                                  onPressed: () => _ink?.insertAtCursor(),
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
    final shown = _withCommentsPanel(scaffold);
    if (!desktop) return shown;
    return MenuCommandHandler(
      commands: _commands,
      child: isMac(context)
          ? NoteDropTarget(noteId: widget.noteId, child: shown)
          : shown,
    );
  }

  /// Menu-bar and shortcut commands the editor takes (Format menu, text
  /// zoom, Move to Trash). Clicking a Format item while editing applies it
  /// at the selection, exactly like the toolbar buttons.
  /// A 3×3 table at the cursor, its first cell ready to type in.
  void _insertTable() {
    insertTableAtCursor(
      _quillController,
      onQuiet: () {
        if (mounted) setState(() {});
      },
    );
  }

  /// ⌥⌘K: comment on the selected passage (or say how to).
  Future<void> _commentOnSelection() async {
    if (!_loaded) return;
    if (!await _comments.addFromSelection(context) && mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Select the passage to comment on.')),
      );
    }
  }

  late final Map<MenuCommand, VoidCallback> _commands = {
    MenuCommand.bold: () => _toggle(Attribute.bold),
    MenuCommand.italic: () => _toggle(Attribute.italic),
    MenuCommand.underline: () => _toggle(Attribute.underline),
    MenuCommand.strikethrough: () => _toggle(Attribute.strikeThrough),
    MenuCommand.title: () => _setHeader(Attribute.h1),
    MenuCommand.heading: () => _setHeader(Attribute.h2),
    MenuCommand.subheading: () => _setHeader(Attribute.h3),
    MenuCommand.body: () => _setHeader(Attribute.header),
    MenuCommand.bulletList: () => _toggle(Attribute.ul),
    MenuCommand.numberedList: () => _toggle(Attribute.ol),
    MenuCommand.checklist: () => _toggle(Attribute.unchecked),
    MenuCommand.blockQuote: () => _toggle(Attribute.blockQuote),
    MenuCommand.monospaced: () => _toggle(Attribute.codeBlock),
    MenuCommand.highlight: _toggleHighlight,
    MenuCommand.insertTable: _insertTable,
    MenuCommand.linkNote: () => _linkNote(context),
    MenuCommand.citePaper: () => _citePaper(context),
    MenuCommand.find: _openFind,
    MenuCommand.addComment: _commentOnSelection,
    MenuCommand.findNext: () =>
        _finding ? _findStep.value?.call(1) : _openFind(),
    MenuCommand.findPrevious: () =>
        _finding ? _findStep.value?.call(-1) : _openFind(),
    MenuCommand.zoomIn: () => ref.read(noteZoomProvider).zoomIn(),
    MenuCommand.zoomOut: () => ref.read(noteZoomProvider).zoomOut(),
    MenuCommand.actualSize: () => ref.read(noteZoomProvider).reset(),
    MenuCommand.moveToTrash: () => _moveToTrash(),
    MenuCommand.duplicateNote: () =>
        duplicateNoteAndOpen(context, ref, widget.noteId),
    MenuCommand.printNote: () => printNote(context, ref, widget.noteId),
    // File → Lock Note: lock this note, or, if it already is, lock now.
    MenuCommand.lockNote: () => _locked ? _lock.lockNow() : _lockNote(),
  };

  void _toggle(Attribute attribute) {
    if (!_loaded) return;
    final on = _quillController.getSelectionStyle().attributes.containsKey(
      attribute.key,
    );
    // A list or quote toggled "on" over another list kind switches kind.
    final sameValue =
        on &&
        _quillController.getSelectionStyle().attributes[attribute.key]?.value ==
            attribute.value;
    _quillController.formatSelection(
      on && sameValue ? Attribute.clone(attribute, null) : attribute,
    );
    _bodyFocus.requestFocus();
  }

  /// Format → Highlight: the last-used colour (yellow to begin with) on the
  /// selection, or off again if the selection already has it.
  void _toggleHighlight() {
    if (!_loaded) return;
    final on = selectionHighlight(_quillController) != null;
    if (on) {
      removeHighlight(_quillController);
    } else {
      _quillController.formatSelection(lastHighlight.attribute);
    }
    _bodyFocus.requestFocus();
  }

  void _setHeader(Attribute attribute) {
    if (!_loaded) return;
    _quillController.formatSelection(attribute);
    _bodyFocus.requestFocus();
  }

  /// Shift+Tab at the very start of the body goes back to the title.
  KeyEventResult? _onBodyKey(KeyEvent event, Node? node) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.tab &&
        HardwareKeyboard.instance.isShiftPressed &&
        _quillController.selection.isCollapsed &&
        _quillController.selection.baseOffset == 0) {
      _titleFocus.requestFocus();
      return KeyEventResult.handled;
    }
    return null;
  }
}

double _sideMargin(double width, bool desktop) =>
    desktop ? macPanePadding(width) : readablePadding(width);

class _NoteCommandIntent extends Intent {
  const _NoteCommandIntent(this.command);
  final MenuCommand command;
}

/// A key flutter_quill binds that the Mac menu bar owns (⌘1/⌘2 tabs, ⌘0,
/// ⌘M minimise, ⌘F/⌘G find): let it through to the menu.
class _PassKeyIntent extends Intent {
  const _PassKeyIntent();
}

/// Overrides of flutter_quill's macOS shortcuts so the Format menu's keys
/// do what the menu says. Everything else Quill binds stays.
final Map<ShortcutActivator, Intent> _desktopShortcuts = {
  const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
      const _NoteCommandIntent(MenuCommand.linkNote),
  const SingleActivator(LogicalKeyboardKey.keyK, meta: true, shift: true):
      const _NoteCommandIntent(MenuCommand.citePaper),
  const SingleActivator(LogicalKeyboardKey.keyB, meta: true, shift: true):
      const _NoteCommandIntent(MenuCommand.body),
  const SingleActivator(LogicalKeyboardKey.keyT, meta: true, shift: true):
      const _NoteCommandIntent(MenuCommand.title),
  const SingleActivator(LogicalKeyboardKey.keyH, meta: true, shift: true):
      const _NoteCommandIntent(MenuCommand.heading),
  const SingleActivator(LogicalKeyboardKey.keyJ, meta: true, shift: true):
      const _NoteCommandIntent(MenuCommand.subheading),
  const SingleActivator(LogicalKeyboardKey.keyX, meta: true, shift: true):
      const _NoteCommandIntent(MenuCommand.strikethrough),
  const SingleActivator(LogicalKeyboardKey.quote, meta: true):
      const _NoteCommandIntent(MenuCommand.blockQuote),
  for (final key in [
    LogicalKeyboardKey.digit0,
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.keyF,
    LogicalKeyboardKey.keyG,
    LogicalKeyboardKey.keyM,
    LogicalKeyboardKey.backquote,
  ])
    SingleActivator(key, meta: true): const _PassKeyIntent(),
  const SingleActivator(LogicalKeyboardKey.keyM, meta: true, shift: true):
      const _NoteCommandIntent(MenuCommand.monospaced),
  const SingleActivator(LogicalKeyboardKey.keyE, meta: true, shift: true):
      const _NoteCommandIntent(MenuCommand.highlight),
};

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
  const _ImagePreview({required this.attachment});

  final Attachment attachment;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Image, tap to enlarge',
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => AttachmentImageViewer(attachment: attachment),
          ),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: isDesktop(context) ? 340 : 220,
            maxWidth: isDesktop(context) ? readableWidth : double.infinity,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(attachment.path!),
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

/// Body type for the note on a desktop: a little smaller than the phone's
/// 16 pt but looser (1.5), headings stepped down, calm paragraph spacing.
DefaultStyles _desktopStyles(BuildContext context, double zoom) {
  final theme = Theme.of(context);
  final c = theme.colorScheme;
  final base = DefaultTextStyle.of(context).style.copyWith(
    fontSize: 15.5 * zoom,
    height: 1.55,
    color: c.onSurface,
    decoration: TextDecoration.none,
  );
  DefaultTextBlockStyle heading(double size, double top, FontWeight weight) =>
      DefaultTextBlockStyle(
        base.copyWith(
          fontSize: size * zoom,
          height: 1.25,
          fontWeight: weight,
          letterSpacing: -0.2,
        ),
        const HorizontalSpacing(0, 0),
        VerticalSpacing(top, 4),
        VerticalSpacing.zero,
        null,
      );
  const none = HorizontalSpacing(0, 0);
  return DefaultStyles(
    paragraph: DefaultTextBlockStyle(
      base,
      none,
      const VerticalSpacing(0, 6),
      VerticalSpacing.zero,
      null,
    ),
    h1: heading(28, 18, FontWeight.w700),
    h2: heading(21, 16, FontWeight.w600),
    h3: heading(17, 12, FontWeight.w600),
    placeHolder: DefaultTextBlockStyle(
      base.copyWith(color: c.onSurfaceVariant.withValues(alpha: 0.6)),
      none,
      VerticalSpacing.zero,
      VerticalSpacing.zero,
      null,
    ),
    lists: DefaultListBlockStyle(
      base,
      none,
      const VerticalSpacing(2, 4),
      const VerticalSpacing(0, 3),
      null,
      null,
    ),
    quote: DefaultTextBlockStyle(
      base.copyWith(color: c.onSurfaceVariant, fontStyle: FontStyle.italic),
      none,
      const VerticalSpacing(6, 8),
      const VerticalSpacing(2, 2),
      BoxDecoration(
        border: Border(left: BorderSide(width: 3, color: c.primary)),
      ),
    ),
    code: _codeBlockStyle(context, base.fontSize! * 0.9, base.height),
  );
}

/// Phones and tablets keep Quill's defaults except for the monospaced block,
/// which follows the theme.
DefaultStyles _mobileStyles(BuildContext context) =>
    DefaultStyles(code: _codeBlockStyle(context, 14.5, 1.45));

/// A monospaced paragraph: monospace type on a soft surface, rounded.
DefaultTextBlockStyle _codeBlockStyle(
  BuildContext context,
  double size,
  double? height,
) {
  final c = Theme.of(context).colorScheme;
  return DefaultTextBlockStyle(
    TextStyle(
      fontFamily: 'Menlo',
      fontFamilyFallback: const [
        'SF Mono',
        'Roboto Mono',
        'Consolas',
        'monospace',
      ],
      fontSize: size,
      height: height,
      color: c.onSurface,
    ),
    const HorizontalSpacing(0, 0),
    const VerticalSpacing(6, 6),
    VerticalSpacing.zero,
    BoxDecoration(
      color: c.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
  );
}

/// The desktop formatting controls, in the header row: small icon buttons
/// whose tooltips name their shortcuts.
class _DesktopFormatBar extends StatelessWidget {
  const _DesktopFormatBar({
    required this.controller,
    required this.mac,
    required this.onDraw,
    required this.onDone,
  });

  final QuillController controller;
  final bool mac;
  final VoidCallback onDraw;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final cmd = mac ? '\u2318' : 'Ctrl+';
    final shift = mac ? '\u21e7' : 'Shift+';
    Widget toggle(Attribute attribute, String tip) =>
        QuillToolbarToggleStyleButton(
          controller: controller,
          attribute: attribute,
          options: QuillToolbarToggleStyleButtonOptions(
            iconSize: 15,
            iconButtonFactor: 1.8,
            tooltip: tip,
          ),
        );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          SizedBox.square(
            dimension: 30,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 18,
              icon: const Icon(Icons.draw_outlined),
              tooltip: 'Draw',
              onPressed: onDraw,
            ),
          ),
          Container(width: 1, height: 20, color: c.outlineVariant),
          const SizedBox(width: 4),
          toggle(Attribute.bold, 'Bold ${cmd}B'),
          toggle(Attribute.italic, 'Italic ${cmd}I'),
          toggle(Attribute.underline, 'Underline ${cmd}U'),
          toggle(Attribute.ul, 'Bulleted list $shift${cmd}7'),
          toggle(Attribute.ol, 'Numbered list $shift${cmd}9'),
          QuillToolbarToggleCheckListButton(
            controller: controller,
            options: QuillToolbarToggleCheckListButtonOptions(
              iconSize: 15,
              iconButtonFactor: 1.8,
              tooltip: 'Checklist $shift${cmd}L',
            ),
          ),
          _HighlightButton(controller: controller, onDone: onDone),
          _TextStyleButton(controller: controller, onDone: onDone, size: 30),
        ],
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

/// The Mac format bar's highlighter: a menu of five colours (and Remove).
class _HighlightButton extends StatelessWidget {
  const _HighlightButton({required this.controller, required this.onDone});

  final QuillController controller;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final cmd = isMac(context) ? '\u2318' : 'Ctrl+';
    final shift = isMac(context) ? '\u21e7' : 'Shift+';
    return PopupMenuButton<Object>(
      tooltip: 'Highlight $shift${cmd}E',
      onSelected: (choice) {
        chooseHighlight(controller, choice);
        onDone();
      },
      itemBuilder: (_) => highlightMenuItems(context, controller),
      child: SizedBox.square(
        dimension: 30,
        child: Icon(
          Icons.border_color_outlined,
          size: 16,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
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
  strike('Strikethrough', Icons.format_strikethrough),
  monospaced('Monospaced', Icons.code),
  highlight('Highlight', Icons.border_color_outlined),
  table('Table', Icons.grid_on);

  const _TextStyle(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// "Aa": the less frequent formats, as a menu that says which is on.
class _TextStyleButton extends StatelessWidget {
  const _TextStyleButton({
    required this.controller,
    required this.onDone,
    this.size = 40,
  });

  final QuillController controller;
  final VoidCallback onDone;
  final double size;

  bool _isOn(_TextStyle style, Map<String, Attribute> attrs) {
    final header = attrs[Attribute.header.key]?.value;
    return switch (style) {
      _TextStyle.title => header == 1,
      _TextStyle.heading => header == 2,
      _TextStyle.subheading => header == 3,
      _TextStyle.body => header == null,
      _TextStyle.quote => attrs.containsKey(Attribute.blockQuote.key),
      _TextStyle.strike => attrs.containsKey(Attribute.strikeThrough.key),
      _TextStyle.monospaced => attrs.containsKey(Attribute.codeBlock.key),
      _TextStyle.highlight => attrs.containsKey(Attribute.background.key),
      _TextStyle.table => false,
    };
  }

  Future<void> _chooseHighlight(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final choice = await showMenu<Object>(
      context: context,
      position: RelativeRect.fromLTRB(
        topLeft.dx,
        topLeft.dy,
        overlay.size.width - topLeft.dx - box.size.width,
        overlay.size.height - topLeft.dy - box.size.height,
      ),
      items: highlightMenuItems(context, controller),
    );
    if (choice == null) return;
    chooseHighlight(controller, choice);
    onDone();
  }

  void _apply(_TextStyle style) {
    if (style == _TextStyle.table) {
      // The first cell takes focus, so the editor must not.
      insertTableAtCursor(controller);
      return;
    }
    final attrs = controller.getSelectionStyle().attributes;
    controller.formatSelection(switch (style) {
      _TextStyle.highlight || _TextStyle.table => Attribute.background,
      _TextStyle.monospaced =>
        _isOn(style, attrs)
            ? Attribute.clone(Attribute.codeBlock, null)
            : Attribute.codeBlock,
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
      onSelected: (style) => style == _TextStyle.highlight
          ? _chooseHighlight(context)
          : _apply(style),
      itemBuilder: (_) {
        final attrs = controller.getSelectionStyle().attributes;
        return [
          for (final style in _TextStyle.values) ...[
            if (style == _TextStyle.quote ||
                style == _TextStyle.monospaced ||
                style == _TextStyle.table)
              const PopupMenuDivider(),
            CheckedPopupMenuItem(
              value: style,
              checked: _isOn(style, attrs),
              child: Text(style.label),
            ),
          ],
        ];
      },
      child: SizedBox.square(
        dimension: size,
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
  figure(
    'Figure caption',
    'A numbered figure caption for this line',
    Icons.image_outlined,
  ),
  table(
    'Table caption',
    'A numbered table caption for this line',
    Icons.table_chart_outlined,
  ),
  refer(
    'Refer to a figure or table',
    'Insert its number, kept right as things move',
    Icons.tag,
  ),
  link('Link to a note', 'Or type [[', Icons.link),
  draw('Draw', 'A sketch, with a pen or finger', Icons.draw_outlined),
  insertTable('Table', 'Rows and columns, 3 by 3 to start', Icons.grid_on),
  heading('Heading', 'Make this line a heading', Icons.title),
  checklist('Checklist', 'Tick-box items', Icons.check_box_outlined),
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
