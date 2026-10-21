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
import '../../l10n/l10n.dart';
import 'editor_document.dart';
import 'heading_fold_controller.dart';
import 'heading_fold.dart' show FoldLine;
import 'heading_fold_ui.dart';
import 'block_handles.dart';
import 'block_ops.dart';
import 'contents_block.dart';
import 'callout_embed.dart';
import 'figure_embed.dart';
import 'date_embed.dart';
import 'footnote_embed.dart';
import 'figure_markers.dart';
import '../projects/figures.dart';
import '../navigation/back_forward.dart';
import '../navigation/link_peek.dart';
import '../navigation/nav_history.dart';
import '../navigation/nav_target.dart';
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
import '../home/mac_toolbar.dart' show MacPaneChrome, macPaneBar;
import '../platform/mac_window.dart'
    show
        MacWindowDragArea,
        MenuCommand,
        MenuCommandHandler,
        isDesktop,
        isMac,
        macPanePadding,
        macToolbarHeight;
import 'note_find.dart';
import 'note_highlight.dart';
import 'note_zoom.dart';
import 'cite_paper_sheet.dart';
import 'citation_embed.dart';
import '../csl/style_picker.dart';
import 'math_embed.dart';
import 'note_bibliography.dart';
import 'block_ids.dart';
import 'note_aliases.dart';
import 'note_embed.dart';
import 'note_link_open.dart';
import 'note_link_sheet.dart';
import 'note_links.dart';
import 'note_sections.dart';
import '../navigation/outline_overlay.dart';
import '../navigation/quick_switcher_nav.dart';
import '../navigation/switcher_rank.dart' show adjacentHeading;
import '../navigation/outline_pinch.dart';
import 'unlinked_mentions.dart';
import 'note_templates.dart';
import 'daily_notes.dart' show openNeighbouringDailyNote;
import 'templates.dart'
    show pickAndInsertTemplate, setNoteTemplate, templateNotesProvider;
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
      final chrome = MacPaneChrome.maybeOf(context);
      return Scaffold(
        appBar: chrome != null
            ? macPaneBar(chrome)
            : AppBar(automaticallyImplyLeading: !embedded),
      );
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
    folds: _folds,
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
  late final NoteNavigatorRegistry _navRegistry;
  late final CallbackNoteNavigator _navigator;
  // Captured up front: dispose() must be able to flush a pending save, and
  // `ref` can't be used there.
  late final AppDatabase _db = ref.read(databaseProvider);
  StreamSubscription<DocChange>? _docChanges;

  /// Figure and table numbers for the chips in this note.
  final _figures = FigureScope();

  /// Collapsed sections: they exist only in the editor's document (see
  /// `heading_fold.dart`); everything that reads the whole note goes
  /// through [_stored] or [HeadingFolds.unfoldedDocument].
  late final HeadingFolds _folds = HeadingFolds(noteId: widget.noteId);

  /// Where the pointer is over the page, for the heading chevrons.
  final _hoverY = ValueNotifier<double?>(null);
  final _blockHub = BlockHandleHub();

  /// The figures index counts the whole note, hidden sections included.
  void _figuresChanged() => _figures.documentChanged(_folds.unfoldedDocument());

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

  /// Back/forward: where this note was scrolled when it closed, and the
  /// peek card for note and paper links under a resting mouse.
  late final NavHistoryNotifier _navHistory;
  late final _peek = LinkPeekController(context: () => context);
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
    _navHistory = ref.read(navHistoryProvider.notifier);
    // Back/forward to this note while it is already open.
    ref.listenManual<NavScrollRequest?>(navScrollRequestProvider, (_, r) {
      if (r == null || r.key != 'note:${widget.noteId}' || !_loaded) return;
      ref.read(navScrollRequestProvider.notifier).state = null;
      restoreScrollFraction(_pageScroll, r.fraction, () => mounted);
    });
    _navRegistry = ref.read(noteNavigatorRegistryProvider);
    _navigator = CallbackNoteNavigator(
      noteId: widget.noteId,
      titleOf: () => _titleController.text,
      headingsOf: _switcherHeadings,
      jumpToHeading: _jumpToHeading,
      runCommand: (command) {
        final action = _commands[command];
        action?.call();
        return action != null;
      },
    );
    _navRegistry.register(_navigator);
    _bodyFocus.addListener(_registerNavigator);
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
      _selectUnfolded(request.selection);
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
    // Folding moves lines about: put the drawing tools away first.
    _folds.addListener(() {
      if (_ink?.active != null) _ink!.deactivate();
    });
    // Tapping back into the text puts the drawing tools away.
    _bodyFocus.addListener(_leaveDrawingIfTyping);
    _quillController.addListener(_leaveDrawingIfTyping);
    if (note != null && mounted) {
      _titleController.text = note.title;
    }
    // Sections folded when the note was last open, except the one the
    // selection is about to land in.
    _folds.attach(_quillController);
    _savedTitle = _titleController.text;
    _savedContent = _stored();
    // Attached after the initial text is in place, so loading isn't an edit.
    _titleController.addListener(_scheduleSave);
    _quillController.addListener(_scheduleSave);
    _quillController.addListener(_followCursor);
    _docChanges = _quillController.document.changes.listen(_watchForWikilink);
    _figuresChanged();
    widget.handle?.appendQuote = _appendQuoteHere;
    if (mounted) setState(() => _loaded = true);
    _openCommentsIfAsked();
    if (want != null) _revealInitialSelection();
    if (takeScrollRequest(ref, 'note:${widget.noteId}') case final f?) {
      restoreScrollFraction(_pageScroll, f, () => mounted);
    }
    _restoreRescued();
    unawaited(_restoreFolds());
  }

  /// Folds the sections that were collapsed when the note was last open
  /// (read from preferences after the note is on screen, so a slow or
  /// missing store never delays opening it), except the one the selection
  /// is in.
  Future<void> _restoreFolds() async {
    final keys = await _folds.store.load(widget.noteId);
    if (!mounted || _blocked) return;
    _folds.loaded(keys);
    if (keys.isEmpty || _folds.touched) return;
    _folds.applyKeys(
      keys,
      protectOffset: _folds.unfoldedOffset(_quillController.selection.start),
    );
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
      final keys = _folds.collapsedKeys();
      final document = _editable(rescued.content);
      _quillController.document = document;
      _docChanges = document.changes.listen(_watchForWikilink);
      _folds.applyKeys(keys);
      _figuresChanged();
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
    final keys = _folds.collapsedKeys();
    _quillController.document = _editable(content);
    _docChanges = _quillController.document.changes.listen(_watchForWikilink);
    // The quote lands at the end: don't hide it in a collapsed last section.
    _folds.applyKeys(keys, protectTail: true);
    _figuresChanged();
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
    if (_loaded) unawaited(_folds.persist());
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

    // Collapsed sections stay collapsed, and the cursor is kept in the
    // whole note's offsets while the document is swapped.
    final cursor = _quillController.selection;
    final keys = _folds.collapsedKeys();
    final base = _folds.unfoldedOffset(cursor.baseOffset);
    final extent = _folds.unfoldedOffset(cursor.extentOffset);
    _docChanges?.cancel();
    final document = _editable(merged);
    _quillController.document = document;
    _docChanges = document.changes.listen(_watchForWikilink);
    final max = document.length - 1;
    _quillController.updateSelection(
      TextSelection(
        baseOffset: base.clamp(0, max),
        extentOffset: extent.clamp(0, max),
      ),
      ChangeSource.silent,
    );
    _folds.applyKeys(keys);
    _figuresChanged();
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
    insertVoiceText(_quillController, result, l10n: context.l10n);
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
      ).showSnackBar(SnackBar(content: Text(context.l10n.editorPaperRemoved)));
      return;
    }
    recordNavVisit(
      ref,
      PaperTarget(paperId, page: paper.pdfPath == null ? null : page),
    );
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
        SnackBar(content: Text(context.l10n.editorRecordingRemoved)),
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
    _folds.onChange(change);
    _figuresChanged();
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
        if (op.data == '@') _maybeShowDatePicker(at);
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
    // "![[" embeds a note instead of linking it.
    final embed = !cite && end >= 3 && text[end - 3] == '!';
    final start = embed ? end - 3 : end - 2;
    // After this change has finished applying.
    Future.microtask(() async {
      _quillController.replaceText(
        start,
        embed ? 3 : 2,
        '',
        TextSelection.collapsed(offset: start),
      );
      if (!mounted) return;
      if (cite) {
        await _citePaper(context);
      } else {
        await _linkNote(context, embed: embed);
      }
    });
  }

  /// An "@" typed at the start of a line or after a space offers a date;
  /// dismissing leaves the "@".
  void _maybeShowDatePicker(int at) {
    if (!dateTriggerAt(_quillController.document.toPlainText(), at)) return;
    Future.microtask(() async {
      if (!mounted) return;
      await pickDateForAt(context, _quillController, at);
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
    final l10n = context.l10n;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.editorAddPaperAndCite),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: l10n.commonAdd,
            onPressed: () =>
                _citePasted(messenger, l10n, db, lookup, at, pasted, id),
          ),
        ),
      );
  }

  Future<void> _citePasted(
    ScaffoldMessengerState messenger,
    AppLocalizations l10n,
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
      say(l10n.editorLookupUnreachable);
      return;
    }
    if (paperId == null) {
      say(l10n.editorNoPaperFound(id.value));
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
                if (c != _Command.insertTemplate ||
                    (ref.read(templateNotesProvider).value?.isNotEmpty ??
                        false))
                  ListTile(
                    leading: Icon(c.icon),
                    title: Text(c.label(context.l10n)),
                    subtitle: Text(c.hint(context.l10n)),
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
        case _Command.footnote:
          await insertFootnote(context, _quillController);
        case _Command.date:
          await insertDateMention(context, _quillController);
        case _Command.callout:
          await insertCallout(context, _quillController);
        case _Command.figure:
          _insertCaption(FigureKind.figure);
        case _Command.table:
          _insertCaption(FigureKind.table);
        case _Command.refer:
          await _referToFigure(context);
        case _Command.embed:
          await _linkNote(context, embed: true);
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
        case _Command.toggle:
          _insertToggle();
        case _Command.contents:
          insertContentsAtCursor(_quillController);
        case _Command.template:
          _insertTemplate();
        case _Command.insertTemplate:
          await _insertTemplateNote();
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
      for (final d in figureDefsIn(_folds.unfoldedDocument().toDelta())) {
        if (d.kind != kind || d.label != label) continue;
        _selectUnfolded(
          TextSelection(baseOffset: d.offset, extentOffset: d.offset + 1),
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
      l10n: context.l10n,
    );
  }

  /// `/` → Insert template: one of the reader's templates (or the
  /// literature skeleton) at the caret.
  Future<void> _insertTemplateNote() => pickAndInsertTemplate(
    context,
    ref,
    _quillController,
    noteTitle: _titleController.text,
    insertLiterature: _insertTemplate,
  );

  /// ⋮ → Previous / Next day's note on a daily note.
  Future<void> _openDay({required bool previous}) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final opened = await openNeighbouringDailyNote(
      context,
      ref,
      widget.noteId,
      previous: previous,
    );
    if (!opened) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(previous ? l10n.dailyNoEarlier : l10n.dailyNoLater),
          ),
        );
    }
  }

  Future<void> _addBibliography(BuildContext context) async {
    final style = await pickCitationStyle(context);
    if (style == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    // It reads the citations from the editor's document: open every
    // section so none is missed.
    _folds.expandAll();
    final n = await insertBibliography(
      _quillController,
      ref.read(databaseProvider),
      style,
    );
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          n == 0 ? l10n.editorNoCitations : l10n.editorAddedReferences(n),
        ),
      ),
    );
  }

  /// The note being edited, for `[[#Heading]]` and `[[#^` in the picker.
  LiveNote get _liveNote => LiveNote(
    noteId: widget.noteId,
    title: _titleController.text,
    document: _folds.unfoldedDocument,
    assignBlockId: _assignBlockIdHere,
  );

  /// Marks the paragraph starting at [lineStart] (an offset in the unfolded
  /// note) with a block id, in the open editor — never through the
  /// database, whose autosave would overwrite it.
  String _assignBlockIdHere(int lineStart) {
    final live = _folds.reveal(lineStart);
    final lines = docLines(_quillController.document.toDelta());
    final line = lines.firstWhere(
      (l) => l.start == live,
      orElse: () => lines.last,
    );
    if (line.blockId != null) return line.blockId!;
    final id = blockIdFor(null, {
      for (final l in lines)
        if (l.blockId != null) l.blockId!,
    });
    _quillController.replaceText(
      line.end,
      0,
      Embeddable(blockIdEmbedType, id),
      null,
    );
    return id;
  }

  Future<void> _linkNote(BuildContext context, {bool embed = false}) async {
    final picked = await showNoteLinkSheet(
      context,
      ref,
      excludeNoteId: widget.noteId,
      live: _liveNote,
      embed: embed,
    );
    if (picked == null || !mounted) return;
    final controller = _quillController;
    if (embed) {
      insertNoteEmbed(controller, picked.link);
      _bodyFocus.requestFocus();
      return;
    }
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
      LinkAttribute(picked.link),
    );
    controller.updateSelection(
      TextSelection.collapsed(offset: index + picked.title.length + 1),
      ChangeSource.local,
    );
  }

  /// A tap on a note link: the note, or one heading or paragraph of it
  /// (selected, with folds opened). Links into this very note just move
  /// the selection.
  /// The note or paper link under a mouse pointer (global [position]), or
  /// null. The pointer must be on the link's text, not merely on its line.
  PeekRequest? _peekAt(Offset position) {
    if (!_loaded) return null;
    final render = _editorKey.currentState?.renderEditor;
    if (render == null || !render.attached) return null;
    final TextPosition pos;
    final Rect caret;
    final Offset local;
    try {
      pos = render.getPositionForOffset(position);
      caret = render.getLocalRectForCaret(pos);
      local = render.globalToLocal(position);
    } on Object {
      return null;
    }
    if (local.dy < caret.top - 2 ||
        local.dy > caret.bottom + 2 ||
        (local.dx - caret.left).abs() > 16) {
      return null;
    }
    final document = _quillController.document;
    for (final offset in [pos.offset, pos.offset - 1]) {
      if (offset < 0 || offset >= document.length) continue;
      final leaf = document.querySegmentLeafNode(offset).leaf;
      final link = leaf?.style.attributes[Attribute.link.key]?.value
          ?.toString();
      if (link == null) continue;
      if (parseNoteLinkTarget(link) case final t?) {
        return PeekRequest.note(t);
      }
      if (parsePaperPageLink(link) case final p?) {
        return PeekRequest(PaperTarget(p.paperId, page: p.page));
      }
    }
    return null;
  }

  void _onPointerHover(PointerHoverEvent event) {
    if (event.kind != PointerDeviceKind.mouse) return;
    final request = _peekAt(event.position);
    if (request == null) {
      _peek.leave();
    } else {
      _peek.hover(
        request,
        Rect.fromCenter(center: event.position, width: 2, height: 18),
      );
    }
  }

  void _openLinkTarget(NoteLinkTarget target) {
    if (target.heading == null && target.block == null) {
      _openNote(target.noteId);
      return;
    }
    if (target.noteId == widget.noteId) {
      final selection = selectionForTarget(
        docLines(_folds.unfoldedDocument().toDelta()),
        target,
      );
      if (selection != null) {
        // After the tap itself, which also places the caret.
        Future.delayed(Duration.zero, () {
          if (!mounted) return;
          _selectUnfolded(selection);
          _revealInitialSelection();
        });
      }
      return;
    }
    unawaited(openNoteLink(context, ref, target));
  }

  void _openNote(String id) {
    recordNavVisit(ref, NoteTarget(id));
    _pushNote(id);
  }

  void _pushNote(String id) => Navigator.of(context)
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
    await deleteNoteWithUndo(
      ref,
      messenger,
      widget.noteId,
      title,
      l10n: context.l10n,
    );
  }

  /// Locks this note: asks for (or first sets) the notes password, saves
  /// what's typed, then encrypts the note and its versions. The editor stays
  /// open and unlocked.
  Future<void> _lockNote() async {
    if (!_loaded || _locked || _blocked) return;
    final ok = await ensureNotesUnlocked(context, _lock);
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
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
                ? l10n.notesNoteLocked
                : l10n.editorNoteLockedFiles,
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
    var end = _quillController.document.length - 1;
    // A collapsed last section ends the note with its "…": start a line of
    // its own under it rather than typing beside it.
    if (_folds.lines.last.isFold) {
      _quillController.replaceText(end, 0, '\n', null);
      end += 1;
    }
    _quillController.updateSelection(
      TextSelection.collapsed(offset: end),
      ChangeSource.local,
    );
    _bodyFocus.requestFocus();
  }

  /// Selects a range given in the whole note's offsets (to-dos, citations,
  /// figure definitions, find), opening whatever sections hide it first.
  void _selectUnfolded(TextSelection want) {
    if (!want.isValid) return;
    final start = _folds.reveal(want.start);
    final length = want.end - want.start;
    final max = _quillController.document.length - 1;
    _quillController.updateSelection(
      TextSelection(
        baseOffset: start.clamp(0, max),
        extentOffset: (start + length).clamp(0, max),
      ),
      ChangeSource.local,
    );
  }

  /// Outline (⋮, View → Outline ⌃⌘O, pinch out on a trackpad): the note
  /// zoomed out to its headings.
  bool _outlineOpen = false;

  void _toggleOutline() {
    if (!_loaded) return;
    setState(() => _outlineOpen = !_outlineOpen);
  }

  void _closeOutline() {
    if (_outlineOpen) setState(() => _outlineOpen = false);
  }

  void _pickHeading(NoteHeading heading) {
    setState(() => _outlineOpen = false);
    _selectUnfolded(TextSelection.collapsed(offset: heading.offset));
    _revealInitialSelection();
  }

  /// Wraps the page with the pinch gesture (Mac) and the outline overlay.
  Widget _withOutline(Widget page) {
    if (!_loaded) return page;
    Widget body = page;
    if (isMac(context)) {
      body = PinchDetector(
        onPinchOut: _outlineOpen ? null : _toggleOutline,
        onPinchIn: _outlineOpen ? _closeOutline : null,
        child: page,
      );
    }
    if (!_outlineOpen) return body;
    final headings = headingsOf(docLines(_folds.unfoldedDocument().toDelta()));
    final caret = _folds.unfoldedOffset(
      _quillController.selection.isValid ? _quillController.selection.start : 0,
    );
    return Stack(
      children: [
        Positioned.fill(child: body),
        Positioned.fill(
          child: OutlineOverlay(
            headings: headings,
            current: currentHeadingIndex(headings, caret),
            onPick: _pickHeading,
            onClose: _closeOutline,
          ),
        ),
      ],
    );
  }

  // Quick switcher and heading keys -------------------------------------

  void _registerNavigator() {
    if (_bodyFocus.hasFocus) _navRegistry.register(_navigator);
  }

  List<NoteHeading> _switcherHeadings() =>
      _loaded ? headingsOf(docLines(_folds.unfoldedDocument().toDelta())) : [];

  void _jumpToHeading(NoteHeading heading) {
    if (!_loaded || !mounted) return;
    _selectUnfolded(TextSelection.collapsed(offset: heading.offset));
    _revealInitialSelection();
  }

  /// ⌥⌘↑ / ⌥⌘↓: the caret to the previous / next heading.
  void _stepHeading({required bool forward}) {
    if (!_loaded) return;
    final caret = _folds.unfoldedOffset(
      _quillController.selection.extentOffset,
    );
    final target = adjacentHeading(
      _switcherHeadings(),
      caret,
      forward: forward,
    );
    if (target != null) _jumpToHeading(target);
  }

  /// The link under the caret or selection, if any.
  String? _linkAtCaret() {
    final doc = _quillController.document;
    final sel = _quillController.selection;
    if (!sel.isValid) return null;
    String? at(int index, int length) {
      if (index < 0 || index + length > doc.length - 1 + 1) return null;
      final v = doc.collectStyle(index, length).attributes[Attribute.link.key];
      return v?.value?.toString();
    }

    if (!sel.isCollapsed) return at(sel.start, sel.end - sel.start);
    return at(sel.start, 1) ?? at(sel.start - 1, 1);
  }

  /// ⌘L / Format → Open Link: follows the link at the caret like a tap.
  void _openLinkAtCaret() {
    if (!_loaded) return;
    final link = _linkAtCaret();
    if (link == null || link.isEmpty) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(context.l10n.switcherNoLink)));
      return;
    }
    if (parseAudioTimestampLink(link) case final t?) {
      unawaited(_playFrom(t.attachmentId, t.at));
    } else if (parsePaperPageLink(link) case final p?) {
      unawaited(_openPaperAt(p.paperId, p.page));
    } else if (parseNoteLinkTarget(link) case final target?) {
      _openLinkTarget(target);
    } else if (Uri.tryParse(link) case final uri? when uri.hasScheme) {
      unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
    }
  }

  Future<void> _showWordCount(BuildContext context) async {
    final stats = noteStats(_folds.unfoldedDocument());
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
      [
        ExportNote(
          _titleController.text,
          content,
          images: images,
          id: widget.noteId,
        ),
      ],
      title: _titleController.text,
      figures: figures,
    );
  }

  @override
  void dispose() {
    if (_loaded) {
      _navHistory.reportScrollFor(
        'note:${widget.noteId}',
        scrollFractionOf(_pageScroll),
      );
    }
    _peek.dispose();
    _findStep.dispose();
    _hoverY.dispose();
    _blockHub.dispose();
    _spellHelper?.dispose();
    _commentsHelper?.dispose();
    widget.handle?.appendQuote = null;
    _lock.removeListener(_onLockChanged);
    if (_flushRegistry[widget.noteId] == _save) {
      _flushRegistry.remove(widget.noteId);
    }
    _bodyFocus.removeListener(_registerNavigator);
    _navRegistry.unregister(_navigator);
    _docChanges?.cancel();
    // Leaving right after typing must not drop the last edit.
    if (_debounce?.isActive ?? false) _save();
    _debounce?.cancel();
    _titleController.dispose();
    _figures.dispose();
    _folds.dispose();
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
    // In the Mac window's pane this app bar is the pane's part of the
    // toolbar row: New note first, the search field last.
    final chrome = MacPaneChrome.maybeOf(context);
    final scaffold = Scaffold(
      // The toolbar rides on top of the keyboard (see bottomNavigationBar),
      // so the body must not also shrink for it.
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        toolbarHeight: chrome == null ? null : macToolbarHeight,
        leading: chrome == null ? null : Center(child: chrome.leading),
        leadingWidth: chrome?.leadingExtent,
        flexibleSpace: chrome == null ? null : const MacWindowDragArea(),
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
              tooltip: context.l10n.editorLockedTapToLock,
              onPressed: _lock.lockNow,
            ),
          IconButton(
            icon: const Icon(Icons.folder_outlined),
            tooltip: folderName ?? context.l10n.editorMoveToFolder,
            onPressed: () =>
                showFolderPickerSheet(context, ref, widget.noteId, folderId),
          ),
          IconButton(
            icon: const Icon(Icons.tag),
            tooltip: context.l10n.editorTags,
            onPressed: () => showTagPickerSheet(context, ref, widget.noteId),
          ),
          IconButton(
            icon: const Icon(Icons.link),
            tooltip: context.l10n.editorLinkPaper,
            onPressed: () => showLinkPaperSheet(context, ref, widget.noteId),
          ),
          IconButton(
            icon: const Icon(Icons.attach_file),
            tooltip: context.l10n.editorAttach,
            onPressed: () => _attach(context),
          ),
          PopupMenuButton<String>(
            tooltip: context.l10n.commonMore,
            onSelected: (v) => switch (v) {
              'project' => showProjectPickerSheet(
                context,
                noteId: widget.noteId,
              ),
              'link' => _linkNote(context),
              'aliases' => showAliasesDialog(context, ref, widget.noteId),
              'cite' => _citePaper(context),
              'template' => _insertTemplate(),
              'astemplate' => setNoteTemplate(
                ref.read(databaseProvider),
                widget.noteId,
                !(ref.read(noteByIdProvider(widget.noteId)).value?.isTemplate ??
                    false),
              ),
              'prevday' => _openDay(previous: true),
              'nextday' => _openDay(previous: false),
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
              'outline' => _toggleOutline(),
              'collapse' => _folds.collapseAll(),
              'expand' => _folds.expandAll(),
              'comments' => _openComments(),
              'duplicate' => duplicateNoteAndOpen(context, ref, widget.noteId),
              'print' => printNote(context, ref, widget.noteId),
              'trash' => _moveToTrash(),
              _ => null,
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'project',
                child: ListTile(
                  leading: Icon(Icons.folder_special_outlined),
                  title: Text(context.l10n.editorAddToProject),
                ),
              ),
              PopupMenuItem(
                value: 'link',
                child: ListTile(
                  leading: Icon(Icons.add_link),
                  title: Text(context.l10n.editorLinkToNote),
                  subtitle: Text(context.l10n.editorLinkToNoteHint),
                ),
              ),
              PopupMenuItem(
                value: 'aliases',
                child: ListTile(
                  leading: Icon(Icons.label_outline),
                  title: Text(context.l10n.aliasesMenu),
                  subtitle: Text(context.l10n.aliasesMenuHint),
                ),
              ),
              PopupMenuItem(
                value: 'cite',
                child: ListTile(
                  leading: Icon(Icons.format_quote),
                  title: Text(context.l10n.notesCiteAPaper),
                  subtitle: Text(context.l10n.editorCiteHint),
                ),
              ),
              PopupMenuItem(
                value: 'template',
                child: ListTile(
                  leading: Icon(Icons.article_outlined),
                  title: Text(context.l10n.editorTemplate),
                  subtitle: Text(context.l10n.editorTemplateHint),
                ),
              ),
              PopupMenuItem(
                value: 'bibliography',
                child: ListTile(
                  leading: Icon(Icons.list_alt),
                  title: Text(context.l10n.editorAddBibliography),
                ),
              ),
              PopupMenuItem(
                value: 'export',
                child: ListTile(
                  leading: Icon(Icons.ios_share),
                  title: Text(context.l10n.editorExport),
                  subtitle: Text(context.l10n.editorExportHint),
                ),
              ),
              PopupMenuItem(
                value: 'words',
                child: ListTile(
                  leading: Icon(Icons.format_list_numbered),
                  title: Text(context.l10n.editorWordCount),
                  subtitle: Text(context.l10n.editorWordCountHint),
                ),
              ),
              PopupMenuItem(
                value: 'versions',
                child: ListTile(
                  leading: Icon(Icons.history),
                  title: Text(context.l10n.notesVersions),
                ),
              ),
              PopupMenuItem(
                value: 'typewriter',
                child: ListTile(
                  leading: const Icon(Icons.vertical_align_center),
                  title: Text(context.l10n.editorTypewriter),
                  subtitle: Text(context.l10n.editorTypewriterHint),
                  trailing: ref.read(appearanceSettingsProvider).typewriter
                      ? const Icon(Icons.check)
                      : null,
                ),
              ),
              if (_locked)
                PopupMenuItem(
                  value: 'unlock',
                  child: ListTile(
                    leading: Icon(Icons.lock_open_outlined),
                    title: Text(context.l10n.notesRemoveLock),
                  ),
                )
              else
                PopupMenuItem(
                  value: 'lock',
                  child: ListTile(
                    leading: Icon(Icons.lock_outline),
                    title: Text(context.l10n.notesLockNote),
                    subtitle: Text(context.l10n.editorLockHint),
                  ),
                ),
              PopupMenuItem(
                value: 'comments',
                child: ListTile(
                  leading: Icon(Icons.comment_outlined),
                  title: Text(context.l10n.commentsTitle),
                ),
              ),
              PopupMenuItem(
                value: 'find',
                child: ListTile(
                  leading: Icon(Icons.search),
                  title: Text(context.l10n.editorFindInNote),
                ),
              ),
              if (_loaded)
                PopupMenuItem(
                  value: 'outline',
                  child: ListTile(
                    leading: const Icon(Icons.format_list_bulleted),
                    title: Text(context.l10n.outlineTitle),
                  ),
                ),
              if (_loaded && _folds.headings().any((h) => !h.folded))
                PopupMenuItem(
                  value: 'collapse',
                  child: ListTile(
                    leading: const Icon(Icons.unfold_less),
                    title: Text(context.l10n.foldCollapseAll),
                  ),
                ),
              if (_loaded && _folds.headings().any((h) => h.folded))
                PopupMenuItem(
                  value: 'expand',
                  child: ListTile(
                    leading: const Icon(Icons.unfold_more),
                    title: Text(context.l10n.foldExpandAll),
                  ),
                ),
              if (ref.read(noteByIdProvider(widget.noteId)).value?.pinned ??
                  false)
                PopupMenuItem(
                  value: 'pin',
                  child: ListTile(
                    leading: Icon(Icons.push_pin),
                    title: Text(context.l10n.notesUnpin),
                  ),
                )
              else
                PopupMenuItem(
                  value: 'pin',
                  child: ListTile(
                    leading: Icon(Icons.push_pin_outlined),
                    title: Text(context.l10n.notesPinToTop),
                  ),
                ),
              PopupMenuItem(
                value: 'astemplate',
                child: ListTile(
                  leading: const Icon(Icons.dashboard_customize_outlined),
                  title: Text(
                    ref
                                .read(noteByIdProvider(widget.noteId))
                                .value
                                ?.isTemplate ??
                            false
                        ? context.l10n.templatesStopUsing
                        : context.l10n.templatesUse,
                  ),
                ),
              ),
              if (ref.read(noteByIdProvider(widget.noteId)).value?.dailyDate !=
                  null) ...[
                PopupMenuItem(
                  value: 'prevday',
                  child: ListTile(
                    leading: const Icon(Icons.chevron_left),
                    title: Text(context.l10n.dailyPrevious),
                  ),
                ),
                PopupMenuItem(
                  value: 'nextday',
                  child: ListTile(
                    leading: const Icon(Icons.chevron_right),
                    title: Text(context.l10n.dailyNext),
                  ),
                ),
              ],
              PopupMenuItem(
                value: 'duplicate',
                child: ListTile(
                  leading: Icon(Icons.copy_outlined),
                  title: Text(context.l10n.notesDuplicate),
                ),
              ),
              if (isMac(context))
                PopupMenuItem(
                  value: 'print',
                  child: ListTile(
                    leading: Icon(Icons.print_outlined),
                    title: Text(context.l10n.editorPrint),
                  ),
                ),
              PopupMenuItem(
                value: 'trash',
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text(context.l10n.commonMoveToTrash),
                ),
              ),
            ],
          ),
          ?chrome?.trailing,
        ],
      ),
      body: BlockHandleTouch(hub: _blockHub, child: MouseRegion(
        // Where the pointer is on the page, for the heading chevrons and
        // block handles (an ancestor of them, so reaching for one doesn't
        // hide it).
        onHover: (e) {
          _hoverY.value = e.position.dy;
          _blockHub.setHover(e.position);
        },
        onExit: (_) {
          _hoverY.value = null;
          _blockHub.setHover(null);
        },
        child: Stack(
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
                                  context.l10n.editorEditDate(
                                    DateFormat.yMMMMd(
                                      Localizations.localeOf(context)
                                          .toString(),
                                    ).format(noteAsync.value!.updatedAt),
                                    DateFormat.Hm().format(
                                      noteAsync.value!.updatedAt,
                                    ),
                                  ),
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
                              decoration: InputDecoration(
                                hintText: context.l10n.editorTitleHint,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                filled: false,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                              ),
                            ),
                          ),
                          // "Also: …", only when the note has aliases.
                          NoteAliasLine(noteId: widget.noteId),
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
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
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
                                                builder: (_) =>
                                                    PaperDetailScreen(
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
                          HeadingFoldScope(
                            folds: _folds,
                            child: FigureScopeInherited(
                              scope: _figures,
                              child: InkSessionScope(
                                session: _ink!,
                                child: InkCatcher(
                                  session: _ink!,
                                  editorKey: _editorKey,
                                  onTapBelow: _focusEnd,
                                  child: Listener(
 onPointerHover: _onPointerHover,
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
                                      placeholder:
                                          context.l10n.editorStartWriting,
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
                                                      _commands[i.command]
                                                          ?.call();
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
                                      customLinkPrefixes: const [
                                        audioLinkScheme,
                                      ],
                                      embedBuilders: [
                                        const FoldEmbedBuilder(),
                                        ContentsEmbedBuilder(
                                          onJump: _jumpToHeading,
                                        ),
                                        FigureDefEmbedBuilder(),
                                        FigureRefEmbedBuilder(),
                                        SketchEmbedBuilder(),
                                        TableEmbedBuilder(),
                                        CitationEmbedBuilder(),
                                        MathInlineEmbedBuilder(),
                                        MathBlockEmbedBuilder(),
                                        FootnoteEmbedBuilder(),
                                        DateEmbedBuilder(),
                                        CalloutEmbedBuilder(),
                                        BlockIdEmbedBuilder(),
                                        NoteEmbedBuilder(),
                                      ],
                                      // Audio timestamps play on a plain tap; other links
                                      // keep Quill's default long-press menu.
                                      customRecognizerBuilder:
                                          (attribute, leaf) {
                                            if (attribute.key !=
                                                Attribute.link.key) {
                                              return null;
                                            }
                                            final link =
                                                attribute.value?.toString() ??
                                                '';
                                            if (parseAudioTimestampLink(link)
                                                case final t?) {
                                              return TapGestureRecognizer()
                                                ..onTap = () => _playFrom(
                                                  t.attachmentId,
                                                  t.at,
                                                );
                                            }
                                            if (parsePaperPageLink(link)
                                                case final p?) {
                                              return TapGestureRecognizer()
                                                ..onTap = () => _openPaperAt(
                                                  p.paperId,
                                                  p.page,
                                                );
                                            }
                                            if (parseNoteLinkTarget(link)
                                                case final target?) {
                                              return TapGestureRecognizer()
                                                ..onTap = () =>
                                                    _openLinkTarget(target);
                                            }
                                            return null;
                                          },
                                    ),
                                  ),
),
                                ),
                              ),
                            ),
                          ),
                          _Backlinks(noteId: widget.noteId),
                          UnlinkedMentionsSection(noteId: widget.noteId),
                        ],
                      ),
              ),
            ),
            // Drag handles: only ever visible beside a line the pointer is at.
            if (_loaded && !_quillController.readOnly)
              Positioned.fill(
                child: BlockHandles(
                  folds: _folds,
                  controller: _quillController,
                  editorKey: _editorKey,
                  scroll: _pageScroll,
                  hub: _blockHub,
                  onCopyLink: _copyBlockLink,
                ),
              ),
            // (Above the handles, so a chevron wins where the two meet.)
            // Fold chevrons in the left margin of the headings.
            if (_loaded)
              Positioned.fill(
                child: HeadingChevrons(
                  folds: _folds,
                  controller: _quillController,
                  editorKey: _editorKey,
                  scroll: _pageScroll,
                  hoverY: _hoverY,
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
      )),
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
                    folds: _folds,
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
                      folds: _folds,
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
                                  tooltip: context.l10n.editorDraw,
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
    final shown = _withOutline(_withCommentsPanel(scaffold));
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
  /// `/` → Toggle list: the cursor's line becomes a toggle (starting `▸ `)
  /// with an empty indented line under it for its first child, the caret at
  /// the end of the toggle's own line.
  void _insertToggle() {
    final sel = _quillController.selection;
    if (!sel.isValid) return;
    final lines = _folds.lines;
    final i = lineAtOffset(lines, sel.start);
    if (i == null) return;
    final next = [...lines];
    next[i] = turnLineInto(lines[i], TurnInto.toggle);
    final base = next[i].indent;
    final hasChild =
        i + 1 < lines.length &&
        (lines[i + 1].isFold || lines[i + 1].indent > base);
    if (!hasChild) {
      next.insert(i + 1, FoldLine([], {'indent': base + 1}));
    }
    applyBlockEdit(
      _quillController,
      lines,
      next,
      caretLine: i,
      caretAtEnd: true,
    );
    _folds.documentChanged();
  }

  /// Handle menu → Copy link to block: a heading links to the heading, any
  /// other line gets a block id (written in the open editor) and links to
  /// that.
  Future<void> _copyBlockLink(int liveStart) async {
    final lines = docLines(_quillController.document.toDelta());
    final line = lines.where((l) => l.start == liveStart).firstOrNull;
    if (line == null) return;
    final String link;
    if (line.isHeading) {
      link = noteLink(widget.noteId, heading: line.text.trim());
    } else if (line.hasText) {
      link = noteLink(
        widget.noteId,
        block: _assignBlockIdHere(_folds.unfoldedOffset(liveStart)),
      );
    } else {
      return;
    }
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(context.l10n.blocksLinkCopied)));
  }

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
        SnackBar(content: Text(context.l10n.editorSelectPassage)),
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
    MenuCommand.outline: _toggleOutline,
    MenuCommand.collapseSections: () => _folds.collapseAll(),
    MenuCommand.expandSections: () => _folds.expandAll(),
    MenuCommand.linkNote: () => _linkNote(context),
    MenuCommand.citePaper: () => _citePaper(context),
    MenuCommand.footnote: () => insertFootnote(context, _quillController),
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
    MenuCommand.openLink: _openLinkAtCaret,
    MenuCommand.addBibliography: () => _addBibliography(context),
    MenuCommand.moveBlockUp: () =>
        moveBlockAtCaret(_quillController, _folds, -1),
    MenuCommand.moveBlockDown: () =>
        moveBlockAtCaret(_quillController, _folds, 1),
    MenuCommand.previousHeading: () => _stepHeading(forward: false),
    MenuCommand.nextHeading: () => _stepHeading(forward: true),
    MenuCommand.goTo: () =>
        ref.read(quickSwitcherRequestProvider.notifier).state++,
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
  // Where ⌘K is "link a note", the quick switcher is ⇧⌘O (⌘P stays Print).
  const SingleActivator(LogicalKeyboardKey.keyO, meta: true, shift: true):
      const _NoteCommandIntent(MenuCommand.goTo),
  const SingleActivator(LogicalKeyboardKey.keyL, meta: true):
      const _NoteCommandIntent(MenuCommand.openLink),
  const SingleActivator(LogicalKeyboardKey.arrowUp, meta: true, control: true):
      const _NoteCommandIntent(MenuCommand.moveBlockUp),
  const SingleActivator(
    LogicalKeyboardKey.arrowDown,
    meta: true,
    control: true,
  ): const _NoteCommandIntent(
    MenuCommand.moveBlockDown,
  ),
  const SingleActivator(LogicalKeyboardKey.arrowUp, meta: true, alt: true):
      const _NoteCommandIntent(MenuCommand.previousHeading),
  const SingleActivator(LogicalKeyboardKey.arrowDown, meta: true, alt: true):
      const _NoteCommandIntent(MenuCommand.nextHeading),
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
                    context.l10n.editorLinkedFrom,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final n in notes)
                        LinkPeek.target(
                          target: NoteTarget(n.id),
                          child: ActionChip(
                          avatar: const Icon(Icons.north_west, size: 16),
                          label: Text(
                            n.title.isEmpty
                                ? context.l10n.commonUntitled
                                : n.title,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onPressed: () {
                            recordNavVisit(ref, NoteTarget(n.id));
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => NoteEditorScreen(noteId: n.id),
                              ),
                            );
                          },
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
      label: context.l10n.editorImageTapToEnlarge,
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
    final l10n = context.l10n;
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
              tooltip: context.l10n.editorDraw,
              onPressed: onDraw,
            ),
          ),
          Container(width: 1, height: 20, color: c.outlineVariant),
          const SizedBox(width: 4),
          toggle(Attribute.bold, l10n.editorTipBold('${cmd}B')),
          toggle(Attribute.italic, l10n.editorTipItalic('${cmd}I')),
          toggle(Attribute.underline, l10n.editorTipUnderline('${cmd}U')),
          toggle(Attribute.ul, l10n.editorTipBulleted('$shift${cmd}7')),
          toggle(Attribute.ol, l10n.editorTipNumbered('$shift${cmd}9')),
          QuillToolbarToggleCheckListButton(
            controller: controller,
            options: QuillToolbarToggleCheckListButtonOptions(
              iconSize: 15,
              iconButtonFactor: 1.8,
              tooltip: l10n.editorTipChecklist('$shift${cmd}L'),
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
      tooltip: context.l10n.editorTipHighlight('$shift${cmd}E'),
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
  title(Icons.title),
  heading(Icons.text_fields),
  subheading(Icons.short_text),
  body(Icons.notes),
  quote(Icons.format_quote),
  strike(Icons.format_strikethrough),
  monospaced(Icons.code),
  highlight(Icons.border_color_outlined),
  table(Icons.grid_on);

  const _TextStyle(this.icon);

  final IconData icon;

  String label(AppLocalizations l10n) => switch (this) {
    title => l10n.editorStyleTitle,
    heading => l10n.editorStyleHeading,
    subheading => l10n.editorStyleSubheading,
    body => l10n.editorStyleBody,
    quote => l10n.editorStyleQuote,
    strike => l10n.editorStyleStrike,
    monospaced => l10n.editorStyleMonospaced,
    highlight => l10n.editorStyleHighlight,
    table => l10n.editorStyleTable,
  };
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
      tooltip: context.l10n.editorTextStyle,
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
              child: Text(style.label(context.l10n)),
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
  cite(Icons.format_quote),
  equation(Icons.functions),
  figure(Icons.image_outlined),
  table(Icons.table_chart_outlined),
  refer(Icons.tag),
  link(Icons.link),
  embed(Icons.input),
  draw(Icons.draw_outlined),
  insertTable(Icons.grid_on),
  heading(Icons.title),
  checklist(Icons.check_box_outlined),
  attach(Icons.attach_file),
  voice(Icons.mic_none),
  dictate(Icons.keyboard_voice_outlined),
  template(Icons.article_outlined),
  insertTemplate(Icons.dashboard_customize_outlined),
  bibliography(Icons.list_alt),
  footnote(Icons.notes),
  date(Icons.event_outlined),
  callout(Icons.campaign_outlined),
  toggle(Icons.arrow_right),
  contents(Icons.toc);

  const _Command(this.icon);

  final IconData icon;

  String label(AppLocalizations l) => switch (this) {
    cite => l.notesCiteAPaper,
    equation => l.editorCmdEquation,
    footnote => l.footnotesCommand,
    date => l.remindersCommand,
    callout => l.calloutsCommand,
    toggle => l.blocksToggleCommand,
    contents => l.blocksContentsCommand,
    figure => l.editorCmdFigure,
    table => l.editorCmdTable,
    refer => l.editorCmdRefer,
    link => l.editorCmdLink,
    embed => l.linksCmdEmbed,
    draw => l.editorCmdDraw,
    insertTable => l.editorCmdInsertTable,
    heading => l.editorCmdHeading,
    checklist => l.editorCmdChecklist,
    attach => l.editorCmdAttach,
    voice => l.voiceNote,
    dictate => l.voiceDictate,
    template => l.editorCmdTemplate,
    insertTemplate => l.templatesInsert,
    bibliography => l.editorCmdBibliography,
  };

  String hint(AppLocalizations l) => switch (this) {
    cite => l.editorCmdCiteHint,
    equation => l.editorCmdEquationHint,
    footnote => l.footnotesCommandHint,
    date => l.remindersCommandHint,
    callout => l.calloutsCommandHint,
    toggle => l.blocksToggleHint,
    contents => l.blocksContentsHint,
    figure => l.editorCmdFigureHint,
    table => l.editorCmdTableHint,
    refer => l.editorCmdReferHint,
    link => l.editorCmdLinkHint,
    embed => l.linksCmdEmbedHint,
    draw => l.editorCmdDrawHint,
    insertTable => l.editorCmdInsertTableHint,
    heading => l.editorCmdHeadingHint,
    checklist => l.editorCmdChecklistHint,
    attach => l.editorCmdAttachHint,
    voice => l.editorCmdVoiceHint,
    dictate => l.editorCmdDictateHint,
    template => l.editorCmdTemplateHint,
    insertTemplate => l.templatesInsertHint,
    bibliography => l.editorCmdBibliographyHint,
  };
}
