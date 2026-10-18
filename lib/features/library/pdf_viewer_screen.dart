import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/gestures.dart'
    show DragStartBehavior, PanGestureRecognizer, PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/context_menu.dart';
import '../../theme/haptics.dart';
import '../platform/mac_window.dart';
import 'viewer_keys.dart';
import '../notes/note_editor_screen.dart';
import 'annotations_providers.dart';
import 'flight.dart';
import 'highlight_sweep.dart';
import 'highlights.dart';
import 'pdf_search.dart';
import '../settings/appearance_settings.dart';
import '../ocr/ocr_engine.dart';
import '../ocr/ocr_service.dart';
import 'ocr_search.dart';
import 'ocr_selection.dart';
import '../read_aloud/read_aloud_bar.dart';
import '../read_aloud/read_aloud_controller.dart';
import '../read_aloud/speaker.dart';
import 'quote_to_note.dart';
import 'reading_progress.dart';
import 'snapshot.dart';
import 'viewer_navigation.dart';

/// Reads a paper's PDF. Two ways to mark it up:
///
/// * **Text highlights** (default): select text, then Highlight or Quote
///   to note. Highlights keep the real text, so they can be quoted into
///   notes with a link back to the page. Tap one to comment, recolor,
///   quote or delete it.
/// * **Ink** (pen button): freehand strokes, for figures, equations and
///   scanned PDFs without a text layer.
///
/// Reopens at the page you were last on.
class PdfViewerScreen extends ConsumerStatefulWidget {
  const PdfViewerScreen({
    super.key,
    required this.paperId,
    required this.pdfPath,
    this.initialPage,
    this.initialQuery,
    this.viewerBuilder,
    this.searchSourceBuilder,
    this.onSearchReveal,
    this.textProbe,
  });

  final String paperId;
  final String pdfPath;

  /// Page to open at; defaults to 1.
  final int? initialPage;

  /// Opens Find with this text once the document is ready (a search
  /// result inside the paper's text).
  final String? initialQuery;

  /// Replaces the PDF viewer itself (tests have no PDF engine).
  @visibleForTesting
  final Widget Function(
    BuildContext context,
    PdfViewerController controller,
    PdfViewerParams params,
  )?
  viewerBuilder;

  /// Replaces the text source behind Find (tests have no PDF engine).
  @visibleForTesting
  final PageTextSource Function(PdfViewerController controller)?
  searchSourceBuilder;

  /// Called whenever Find moves to a match, before the viewer scrolls.
  @visibleForTesting
  final void Function(SearchMatch match)? onSearchReveal;

  /// Replaces the PDF's own text layer when checking whether a page is a
  /// scan (tests have no PDF engine).
  @visibleForTesting
  final PageTextProbe? textProbe;

  @override
  ConsumerState<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

/// Page count and per-page text layer of the open document, for deciding
/// whether the current page is a scan.
@visibleForTesting
class PageTextProbe {
  const PageTextProbe({required this.pageCount, required this.text});

  final int pageCount;

  /// The text layer of a 1-based page.
  final Future<String> Function(int page) text;
}

class _PdfViewerScreenState extends ConsumerState<PdfViewerScreen>
    with SingleTickerProviderStateMixin {
  final _repaintKey = GlobalKey();
  final _controller = PdfViewerController();
  late final AppDatabase _db = ref.read(databaseProvider);

  bool _inkMode = false;
  Color _color = highlightInks.first;
  bool _extracting = false;

  /// Choosing the area for "Snapshot to a note".
  bool _snapping = false;
  Timer? _pageSave;
  int? _pendingPage;

  late final ValueNotifier<int> _page = ValueNotifier(widget.initialPage ?? 1);
  PdfDocument? _document;
  int? _pageCount;

  /// 1 = chrome shown, 0 = focus mode (everything but the page hidden).
  late final AnimationController _chrome = AnimationController(
    vsync: this,
    value: 1,
  );
  bool _focus = false;
  bool _immersive = false;
  bool _stripOpen = false;

  /// Read aloud; non-null while the reading bar is showing.
  ReadAloudController? _read;

  /// Whether the viewer follows the speech from page to page. Turns off when
  /// the reader scrolls to another page; "Back to reading" turns it on.
  bool _readFollow = true;
  DateTime _readJumpAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _readShown = 0;

  /// Find in document; non-null while the search bar is open.
  DocumentSearch? _search;
  final _findField = TextEditingController();
  final _findFocus = FocusNode();
  Timer? _findDebounce;

  /// Whether each checked page has no text layer, and whether the current
  /// one has none (offers "Recognise text" on papers not yet marked scanned).
  final _noTextLayer = <int, bool>{};
  bool _lacksText = false;

  @override
  void initState() {
    super.initState();
    if (widget.textProbe != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkTextLayer());
    }
  }

  Future<void> _checkTextLayer() async {
    final page = _page.value;
    var lacks = _noTextLayer[page];
    if (lacks == null) {
      try {
        final probe = widget.textProbe;
        final String text;
        if (probe != null) {
          text = await probe.text(page);
        } else if (_document case final doc?) {
          text = (await doc.pages[page - 1].loadStructuredText()).fullText;
        } else {
          return;
        }
        lacks = _noTextLayer[page] = pageLacksTextLayer(text);
      } catch (_) {
        return;
      }
    }
    if (!mounted || _page.value != page) return;
    if (lacks != _lacksText) setState(() => _lacksText = lacks!);
  }

  /// ⋮ → "Recognise text": reads the whole paper in the background.
  Future<void> _recogniseText() async {
    final count = _pageCount ?? widget.textProbe?.pageCount;
    if (count == null) return;
    final service = ref.read(ocrServiceProvider);
    await service.markScanned(widget.paperId, count);
    service.enqueue(widget.paperId);
  }

  /// Highlight or quote a selection of recognised words.
  Future<void> _onOcrSelection(
    int page,
    OcrSelectionAction action,
    List<OcrWord> words,
    Rect? from,
  ) async {
    final made = await createOcrHighlight(
      _db,
      paperId: widget.paperId,
      page: page,
      words: words,
      color: _color,
    );
    if (!mounted) return;
    AppHaptics.confirm();
    ref.read(freshHighlightsProvider).add(made.id);
    if (action == OcrSelectionAction.quote) {
      await showQuoteToNoteSheet(context, ref, made, from: from);
    }
  }

  /// ⋮ → "Read aloud": reads from the current page onward.
  Future<void> _toggleReadAloud() async {
    if (_read != null) {
      _closeReadAloud();
      return;
    }
    final speaker = ref.read(speakerProvider);
    final count = _pageCount ?? widget.textProbe?.pageCount;
    if (count == null) return;
    if (!speaker.available) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Reading aloud isn't available here")),
      );
      return;
    }
    final service = ref.read(ocrServiceProvider);
    Future<String> pageText(int page) async {
      final probe = widget.textProbe;
      final String text;
      if (probe != null) {
        text = await probe.text(page);
      } else if (_document case final doc?) {
        text = (await doc.pages[page - 1].loadStructuredText()).fullText;
      } else {
        text = '';
      }
      if (!pageLacksTextLayer(text)) return text;
      // A scan: the recognised text, if it has been read.
      return (await service.storedPage(widget.paperId, page))?.text ?? text;
    }

    final start =
        (_controller.isReady ? _controller.pageNumber : null) ?? _page.value;
    final read = ReadAloudController(
      speaker: speaker,
      pageCount: count,
      pageText: pageText,
      startPage: start,
    )..addListener(_onReadChanged);
    setState(() {
      _read = read;
      _readFollow = true;
      _readShown = start;
      _stripOpen = false;
    });
    read.start();
  }

  void _closeReadAloud() {
    final read = _read;
    if (read == null) return;
    setState(() => _read = null);
    // Let the bar's listener go before the notifier does.
    WidgetsBinding.instance.addPostFrameCallback((_) => read.dispose());
  }

  void _onReadChanged() {
    final read = _read;
    if (read == null || !mounted) return;
    final page = read.page;
    if (page == _readShown) return;
    _readShown = page;
    if (_readFollow) {
      _readJumpAt = DateTime.now();
      _jumpTo(page);
    } else {
      setState(() {});
    }
  }

  void _backToReading() {
    final read = _read;
    if (read == null) return;
    setState(() => _readFollow = true);
    _readJumpAt = DateTime.now();
    _jumpTo(read.page);
  }

  @override
  void dispose() {
    _read?.dispose();
    _findDebounce?.cancel();
    _search?.dispose();
    _findField.dispose();
    _findFocus.dispose();
    if (_immersive) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _chrome.dispose();
    _page.dispose();
    // Flush the reading position on the way out.
    _pageSave?.cancel();
    if (_pendingPage case final page?) saveLastPage(_db, widget.paperId, page);
    super.dispose();
  }

  void _onViewerReady(PdfDocument document, PdfViewerController controller) {
    final count = document.pages.length;
    setState(() {
      _document = document;
      _pageCount = count;
    });
    savePageCountIfChanged(_db, widget.paperId, count);
    _checkTextLayer();
    final query = widget.initialQuery?.trim() ?? '';
    if (query.isNotEmpty && _search == null) {
      _openSearch();
      _findField.text = query;
      _onFindChanged(query);
    }
  }

  /// Hides (or brings back) everything but the page. On a phone the
  /// system bars go too; a tablet keeps them, there is room.
  void _setFocus(bool focus) {
    if (_focus == focus) return;
    setState(() {
      _focus = focus;
      if (focus) _stripOpen = false;
    });
    _chrome.animateTo(
      focus ? 0 : 1,
      duration: AppMotion.of(context, AppMotion.short),
      curve: focus ? AppMotion.exit : AppMotion.enter,
    );
    // Never on a desktop window, however short: it has no system bars.
    final phone =
        !isDesktop(context) && MediaQuery.sizeOf(context).shortestSide < 600;
    if (focus && phone) {
      _immersive = true;
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else if (!focus && _immersive) {
      _immersive = false;
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  /// A tap on bare page toggles focus mode. Taps that mean something else
  /// (a selection to dismiss, ink, choosing a snapshot box) are left alone.
  bool _onGeneralTap(
    BuildContext context,
    PdfViewerController controller,
    PdfViewerGeneralTapHandlerDetails details,
  ) {
    if (details.type != PdfViewerGeneralTapType.tap) return false;
    if (_inkMode || _snapping) return false;
    if (details.tapOn == PdfViewerPart.selectedText) return false;
    try {
      if (controller.textSelectionDelegate.hasSelectedText) return false;
    } catch (_) {}
    if (_stripOpen) {
      setState(() => _stripOpen = false);
      return false;
    }
    _setFocus(!_focus);
    return false;
  }

  /// Opens Find (or, when already open, refocuses and selects the field).
  void _openSearch() {
    if (_inkMode || _snapping) return;
    if (_search == null) {
      PageTextSource source =
          widget.searchSourceBuilder?.call(_controller) ??
          PdfrxTextSource(_controller);
      final service = ref.read(ocrServiceProvider);
      final scanned = ref.read(isScannedPaperProvider(widget.paperId));
      if (scanned) {
        source = OcrFallbackSource(
          source,
          (page) => service.storedPage(widget.paperId, page),
        );
      }
      setState(() {
        _search = DocumentSearch(source, incomplete: _ocrRunning)
          ..onReveal = _reveal;
        _stripOpen = false;
      });
      _setFocus(false);
    }
    _findFocus.requestFocus();
    _findField.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _findField.text.length,
    );
  }

  bool _ocrRunning() {
    final p = ref.read(ocrProgressProvider(widget.paperId)).value;
    return p != null && !p.isDone;
  }

  void _closeSearch() {
    if (_search == null) return;
    _findDebounce?.cancel();
    final search = _search!;
    setState(() => _search = null);
    _findField.clear();
    // Let the marks' listeners go before the notifier does.
    WidgetsBinding.instance.addPostFrameCallback((_) => search.dispose());
  }

  void _onFindChanged(String text) {
    _findDebounce?.cancel();
    final search = _search;
    if (search == null) return;
    if (text.trim().isEmpty) {
      search.search('');
      return;
    }
    _findDebounce = Timer(
      const Duration(milliseconds: 250),
      () => search.search(text),
    );
  }

  /// Enter: the next match (the query is applied first if still pending).
  void _findStep(int delta) {
    final search = _search;
    if (search == null) return;
    if (_findDebounce?.isActive ?? false) {
      _findDebounce!.cancel();
      search.search(_findField.text);
      return;
    }
    if (delta > 0) {
      search.next();
    } else {
      search.previous();
    }
    AppHaptics.selection();
  }

  void _reveal(SearchMatch m) {
    widget.onSearchReveal?.call(m);
    try {
      final box = _controller.layout.pageLayouts[m.page - 1];
      final target = Rect.fromLTWH(
        box.left + m.rect.left * box.width,
        box.top + m.rect.top * box.height,
        m.rect.width * box.width,
        m.rect.height * box.height,
      );
      _controller.ensureVisible(target, margin: 60).catchError((_) {});
      _controller.setCurrentPageNumber(m.page);
    } catch (_) {
      _jumpTo(m.page);
    }
  }

  /// Zoom a step; nothing to do before the document has loaded.
  void _zoom(
    Future<void> Function({bool loop, Offset? zoomCenter, Duration duration})
    step,
  ) {
    try {
      step();
    } catch (_) {}
  }

  /// ⌘0: the page fills the window's width again.
  void _fitWidth() {
    try {
      final rect = _controller.visibleRect;
      _controller.setZoom(rect.center, _controller.coverScale);
    } catch (_) {}
  }

  void _stepPage(int delta) {
    final count = _pageCount;
    if (count == null) return;
    final target = ((_controller.pageNumber ?? _page.value) + delta).clamp(
      1,
      count,
    );
    _jumpTo(target);
  }

  Future<void> _jumpTo(int page) async {
    try {
      await _controller.goToPage(pageNumber: page);
    } catch (_) {}
  }

  void _onPageChanged(int? page) {
    if (page == null) return;
    _page.value = page;
    if (_read case final read?) {
      final settling =
          DateTime.now().difference(_readJumpAt) < const Duration(seconds: 1);
      if (page == read.page) {
        if (!_readFollow) setState(() => _readFollow = true);
      } else if (_readFollow && !settling) {
        setState(() => _readFollow = false);
      }
    }
    _checkTextLayer();
    _pendingPage = page;
    _pageSave?.cancel();
    _pageSave = Timer(const Duration(seconds: 2), () {
      saveLastPage(_db, widget.paperId, page);
      _pendingPage = null;
    });
  }

  /// Turns the current text selection into highlights (one per page it
  /// spans) and returns them.
  Future<List<Highlight>> _highlightSelection(
    PdfTextSelectionDelegate selection,
  ) async {
    final document = _controller.document;
    final ranges = await selection.getSelectedTextRanges();
    final ids = <String>[];
    for (final range in ranges) {
      if (range.text.trim().isEmpty) continue;
      final page = document.pages[range.pageNumber - 1];
      final pageSize = PdfRect(
        0,
        page.height,
        page.width,
        0,
      ).toRect(page: page).size;
      final chars = range.pageText.charRects
          .sublist(range.start, range.end)
          .map((r) => r.toRect(page: page));
      ids.add(
        await addHighlight(
          _db,
          paperId: widget.paperId,
          pageNumber: range.pageNumber,
          quote: range.text,
          rects: lineRects(chars, pageSize),
          color: _color,
        ),
      );
    }
    await selection.clearTextSelection();
    if (ids.isNotEmpty && mounted) {
      AppHaptics.confirm();
      final fresh = ref.read(freshHighlightsProvider);
      ids.forEach(fresh.add);
    }
    return (_db.select(_db.highlights)..where((h) => h.id.isIn(ids))).get();
  }

  void _customizeMenu(
    PdfViewerContextMenuBuilderParams params,
    List<ContextMenuButtonItem> items,
  ) {
    final selection = params.textSelectionDelegate;
    if (!selection.hasSelectedText) return;
    // Where the selection is on screen, for the quote's flight into a
    // paired note.
    final from = _globalRect(params.anchorA, params.anchorB);
    items.insertAll(0, [
      ContextMenuButtonItem(
        label: 'Highlight',
        onPressed: () {
          params.dismissContextMenu();
          _highlightSelection(selection);
        },
      ),
      ContextMenuButtonItem(
        label: 'Quote to note',
        onPressed: () async {
          params.dismissContextMenu();
          final made = await _highlightSelection(selection);
          if (made.isNotEmpty && mounted) {
            await showQuoteToNoteSheet(context, ref, _merge(made), from: from);
          }
        },
      ),
    ]);
  }

  /// [a] and [b], given in the reader's coordinates, as a global rect.
  Rect? _globalRect(Offset a, Offset? b) {
    final box = _repaintKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return null;
    final p = box.localToGlobal(a);
    final q = b == null ? p : box.localToGlobal(b);
    return Rect.fromPoints(p, q);
  }

  /// A selection across a page break becomes one highlight per page, but
  /// is quoted as one passage (cited at its first page).
  static Highlight _merge(List<Highlight> parts) => parts.length == 1
      ? parts.single
      : parts.first.copyWith(quote: parts.map((h) => h.quote).join(' '));

  /// The PDF's own table of contents (bookmarks), if it has one.
  Future<void> _showContents() async {
    final List<PdfOutlineNode> outline;
    try {
      outline = await _controller.document.loadOutline();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    if (outline.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This PDF has no table of contents.')),
      );
      return;
    }
    final page = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ContentsSheet(outline: outline),
    );
    if (page != null) await _controller.goToPage(pageNumber: page);
  }

  Future<void> _showHighlightsList() async {
    final page = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _HighlightsList(paperId: widget.paperId),
    );
    if (page != null) await _controller.goToPage(pageNumber: page);
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final params = PdfViewerParams(
      backgroundColor: c.surfaceContainer,
      onPageChanged: _onPageChanged,
      onViewerReady: _onViewerReady,
      onGeneralTap: _onGeneralTap,
      // On a desktop the page takes the keys (arrows, Page Up/Down, Space,
      // Home/End, ⌘+/⌘−) from the start, without a click first.
      keyHandlerParams: PdfViewerKeyHandlerParams(
        autofocus: isDesktop(context),
      ),
      textSelectionParams: PdfTextSelectionParams(
        enabled: !_inkMode,
        buildSelectionHandle: (context, anchor, state) => SelectionHandle(
          // pdfrx places handle A above-left of the first
          // character and B below-right of the last; each
          // teardrop points at its corner of the selection.
          pointsTo:
              (anchor.type == PdfTextSelectionAnchorType.a) ==
                  (anchor.direction != PdfTextDirection.rtl &&
                      anchor.direction != PdfTextDirection.vrtl)
              ? Alignment.bottomRight
              : Alignment.topLeft,
          active: state != PdfViewerTextSelectionAnchorHandleState.normal,
        ),
      ),
      customizeContextMenuItems: _customizeMenu,
      pageOverlaysBuilder: (context, pageRect, page) => [
        PageOverlay(
          paperId: widget.paperId,
          pageNumber: page.pageNumber,
          pageRect: pageRect,
          inkMode: _inkMode,
          color: _color,
          onOcrSelection: (action, words, from) =>
              _onOcrSelection(page.pageNumber, action, words, from),
        ),
        if (_search case final search?)
          SearchMarks(
            search: search,
            page: page.pageNumber,
            pageRect: pageRect,
          ),
      ],
    );
    final marks =
        ref.watch(paperMarksProvider(widget.paperId)).value ?? const [];
    final pageCount = _pageCount;
    final document = _document;
    final ocr = ref.watch(ocrProgressProvider(widget.paperId)).value;
    final reading = ocr != null && !ocr.isDone
        ? 'Reading text… ${(ocr.fraction * 100).floor()}%'
        : null;

    final body = Stack(
      fit: StackFit.expand,
      children: [
        // The reading theme sits outside the boundary, so a snapshot
        // keeps the figure's real colors.
        ReadingFilter(
          theme: ref.watch(appearanceSettingsProvider).reading,
          child: RepaintBoundary(
            key: _repaintKey,
            child: widget.viewerBuilder != null
                ? widget.viewerBuilder!(context, _controller, params)
                : PdfViewer.file(
                    widget.pdfPath,
                    controller: _controller,
                    initialPageNumber: widget.initialPage ?? 1,
                    params: params,
                  ),
          ),
        ),
        if (_snapping)
          SnapshotOverlay(
            onSelected: (area) {
              setState(() => _snapping = false);
              _extractToNote(area);
            },
            onCancel: () => setState(() => _snapping = false),
          ),
        // Everything below is chrome: it goes with focus mode.
        if (pageCount != null && marks.isNotEmpty)
          Positioned.fill(
            child: _Chrome(
              animation: _chrome,
              child: HighlightMinimap(
                pageCount: pageCount,
                marks: marks,
                onJump: _jumpTo,
              ),
            ),
          ),
        if ((pageCount != null && pageCount > 1) || reading != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 8,
            child: _Chrome(
              animation: _chrome,
              child: Center(
                child: AnimatedOpacity(
                  duration: AppMotion.of(context, AppMotion.short),
                  opacity: _stripOpen ? 0 : 1,
                  child: IgnorePointer(
                    ignoring: _stripOpen,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (reading != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              reading,
                              key: const ValueKey('ocr-progress'),
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: c.onSurfaceVariant),
                            ),
                          ),
                        if (pageCount != null && pageCount > 1)
                          PageIndicator(
                            page: _page,
                            pageCount: pageCount,
                            onTap: () => setState(() => _stripOpen = true),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (_read case final read?)
          Positioned(
            left: 0,
            right: 0,
            bottom: 52,
            child: Center(
              child: ReadAloudBar(
                controller: read,
                onClose: _closeReadAloud,
                away: !_readFollow,
                onBackToReading: _backToReading,
              ),
            ),
          ),
        if (pageCount != null && document != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedSlide(
              duration: AppMotion.of(context, AppMotion.medium),
              curve: _stripOpen ? AppMotion.enter : AppMotion.exit,
              offset: _stripOpen ? Offset.zero : const Offset(0, 1),
              child: Offstage(
                offstage: !_stripOpen,
                child: PageStrip(
                  pageCount: pageCount,
                  current: _page,
                  marks: marks,
                  onJump: _jumpTo,
                  thumbnail: (context, page) => PdfPageView(
                    document: document,
                    pageNumber: page,
                    maximumDpi: 96,
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    // While choosing a snapshot area, back (or a swipe in from the edge,
    // easy to start by accident when dragging the box) cancels the
    // snapshot instead of leaving the paper. In focus mode back brings the
    // chrome back first.
    return MenuCommandHandler(
      // The menu bar's Find, Zoom and Actual Size act on this document
      // whatever holds focus inside the viewer (pdfrx, the Find field).
      commands: {
        MenuCommand.find: _openSearch,
        MenuCommand.findNext: () =>
            _search == null ? _openSearch() : _findStep(1),
        MenuCommand.findPrevious: _search == null ? null : () => _findStep(-1),
        MenuCommand.zoomIn: () => _zoom(_controller.zoomUp),
        MenuCommand.zoomOut: () => _zoom(_controller.zoomDown),
        MenuCommand.actualSize: _fitWidth,
      },
      child: CallbackShortcuts(
        bindings: {
          if (_search != null) ...{
            const SingleActivator(LogicalKeyboardKey.keyG, meta: true): () =>
                _findStep(1),
            const SingleActivator(
              LogicalKeyboardKey.keyG,
              meta: true,
              shift: true,
            ): () =>
                _findStep(-1),
          },
          const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
              _openSearch,
          const SingleActivator(LogicalKeyboardKey.keyF, control: true):
              _openSearch,
          if (_search != null)
            const SingleActivator(LogicalKeyboardKey.escape): _closeSearch
          else if (_focus)
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                _setFocus(false),
          if (isDesktop(context))
            ...viewerKeyBindings(
              ViewerKeyActions(
                zoomIn: () => _zoom(_controller.zoomUp),
                zoomOut: () => _zoom(_controller.zoomDown),
                fit: _fitWidth,
                nextPage: () => _stepPage(1),
                previousPage: () => _stepPage(-1),
                firstPage: () => _jumpTo(1),
                lastPage: () => _jumpTo(_pageCount ?? 1),
              ),
              enabled: () => !_findFocus.hasFocus && _search == null,
            ),
        },
        child: Focus(
          autofocus: !isDesktop(context) || widget.viewerBuilder != null,
          child: PopScope(
            canPop: !_snapping && !_focus && !_stripOpen && _search == null,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;
              if (_search != null) {
                _closeSearch();
              } else if (_snapping) {
                setState(() => _snapping = false);
              } else if (_stripOpen) {
                setState(() => _stripOpen = false);
              } else {
                _setFocus(false);
              }
            },
            // Only the bars follow the animation; the body is built once.
            child: AnimatedBuilder(
              animation: _chrome,
              child: body,
              builder: (context, body) {
                final t = _chrome.value;
                final inset = MediaQuery.paddingOf(context).top;
                final barHeight =
                    Theme.of(context).appBarTheme.toolbarHeight ??
                    kToolbarHeight;
                return Scaffold(
                  appBar: t <= 0
                      // Focus mode on a Mac still leaves the title bar band
                      // empty: clicks there drag the window.
                      ? (isMac(context)
                            ? PreferredSize(
                                preferredSize: Size.zero,
                                child: SizedBox(
                                  height: inset,
                                  width: double.infinity,
                                ),
                              )
                            : null)
                      : PreferredSize(
                          preferredSize: Size.fromHeight(barHeight * t),
                          child: ClipRect(
                            child: OverflowBox(
                              alignment: Alignment.bottomCenter,
                              minHeight: 0,
                              maxHeight: barHeight + inset,
                              child: Opacity(
                                opacity: t,
                                child: AppBar(
                                  title: _search == null
                                      ? null
                                      : ConstrainedBox(
                                          // Not stretched across a 27" window.
                                          constraints: const BoxConstraints(
                                            maxWidth: 520,
                                          ),
                                          child: FindField(
                                            search: _search!,
                                            controller: _findField,
                                            focusNode: _findFocus,
                                            onChanged: _onFindChanged,
                                            onStep: _findStep,
                                          ),
                                        ),
                                  actions: _search != null
                                      ? [
                                          IconButton(
                                            icon: const Icon(
                                              Icons.keyboard_arrow_up,
                                            ),
                                            tooltip: 'Previous match',
                                            onPressed: () => _findStep(-1),
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.keyboard_arrow_down,
                                            ),
                                            tooltip: 'Next match',
                                            onPressed: () => _findStep(1),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.close),
                                            tooltip: 'Close search',
                                            onPressed: _closeSearch,
                                          ),
                                        ]
                                      : [
                                          IconButton(
                                            icon: const Icon(Icons.search),
                                            tooltip: 'Find in document',
                                            onPressed: _openSearch,
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.format_quote_outlined,
                                            ),
                                            tooltip: 'Highlights',
                                            onPressed: _showHighlightsList,
                                          ),
                                          IconButton(
                                            isSelected: _inkMode,
                                            icon: const Icon(
                                              Icons.draw_outlined,
                                            ),
                                            selectedIcon: const Icon(
                                              Icons.draw,
                                            ),
                                            tooltip: _inkMode
                                                ? 'Stop drawing'
                                                : 'Draw on the page',
                                            onPressed: () {
                                              AppHaptics.selection();
                                              setState(
                                                () => _inkMode = !_inkMode,
                                              );
                                            },
                                          ),
                                          PopupMenuButton<String>(
                                            tooltip: 'More',
                                            onSelected: (v) {
                                              if (v == 'snapshot') {
                                                setState(
                                                  () => _snapping = true,
                                                );
                                              }
                                              if (v == 'find') _openSearch();
                                              if (v == 'readaloud') {
                                                _toggleReadAloud();
                                              }
                                              if (v == 'focus') _setFocus(true);
                                              if (v == 'ocr') _recogniseText();
                                              if (v == 'pages') {
                                                setState(
                                                  () => _stripOpen = true,
                                                );
                                              }
                                              if (v == 'contents') {
                                                _showContents();
                                              }
                                              if (v.startsWith('read:')) {
                                                ref
                                                    .read(
                                                      appearanceSettingsProvider,
                                                    )
                                                    .setReading(
                                                      ReadingTheme.values
                                                          .byName(
                                                            v.substring(5),
                                                          ),
                                                    );
                                              }
                                            },
                                            itemBuilder: (_) => [
                                              if (_pageCount != null &&
                                                  _pageCount! > 1)
                                                const PopupMenuItem(
                                                  value: 'pages',
                                                  child: ListTile(
                                                    leading: Icon(
                                                      Icons
                                                          .view_carousel_outlined,
                                                    ),
                                                    title: Text('Page strip'),
                                                  ),
                                                ),
                                              const PopupMenuItem(
                                                value: 'find',
                                                child: ListTile(
                                                  leading: Icon(Icons.search),
                                                  title: Text(
                                                    'Find in document',
                                                  ),
                                                ),
                                              ),
                                              const PopupMenuItem(
                                                value: 'focus',
                                                child: ListTile(
                                                  leading: Icon(
                                                    Icons.fullscreen,
                                                  ),
                                                  title: Text('Focus'),
                                                  subtitle: Text(
                                                    'Tap the page to bring back',
                                                  ),
                                                ),
                                              ),
                                              PopupMenuItem(
                                                value: 'readaloud',
                                                child: ListTile(
                                                  leading: Icon(
                                                    _read == null
                                                        ? Icons
                                                              .record_voice_over_outlined
                                                        : Icons.voice_over_off,
                                                  ),
                                                  title: Text(
                                                    _read == null
                                                        ? 'Read aloud'
                                                        : 'Stop reading aloud',
                                                  ),
                                                ),
                                              ),
                                              const PopupMenuItem(
                                                value: 'contents',
                                                child: ListTile(
                                                  leading: Icon(Icons.toc),
                                                  title: Text('Contents'),
                                                ),
                                              ),
                                              if (_lacksText && ocr == null)
                                                const PopupMenuItem(
                                                  value: 'ocr',
                                                  child: ListTile(
                                                    leading: Icon(
                                                      Icons
                                                          .document_scanner_outlined,
                                                    ),
                                                    title: Text(
                                                      'Recognise text',
                                                    ),
                                                    subtitle: Text(
                                                      'Search and highlight a scan',
                                                    ),
                                                  ),
                                                ),
                                              for (final theme
                                                  in ReadingTheme.values)
                                                CheckedPopupMenuItem(
                                                  value: 'read:${theme.name}',
                                                  checked:
                                                      ref
                                                          .read(
                                                            appearanceSettingsProvider,
                                                          )
                                                          .reading ==
                                                      theme,
                                                  child: Text(
                                                    '${theme.label} page',
                                                  ),
                                                ),
                                              const PopupMenuDivider(),
                                              PopupMenuItem(
                                                value: 'snapshot',
                                                enabled: !_extracting,
                                                child: const ListTile(
                                                  leading: Icon(
                                                    Icons.crop_free,
                                                  ),
                                                  title: Text(
                                                    'Snapshot to a note',
                                                  ),
                                                  subtitle: Text(
                                                    'For figures and tables',
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                ),
                              ),
                            ),
                          ),
                        ),
                  body: body,
                  // One palette for both kinds of marking: the ink for new
                  // strokes, and the color the next text highlight gets.
                  bottomNavigationBar: t <= 0
                      ? null
                      : ClipRect(
                          child: Align(
                            heightFactor: t,
                            alignment: Alignment.topCenter,
                            child: Opacity(
                              opacity: t,
                              child: SafeArea(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      for (final ink in highlightInks)
                                        _InkSwatchTap(
                                          onTap: () =>
                                              setState(() => _color = ink),
                                          child: AnimatedContainer(
                                            duration: AppMotion.short,
                                            margin: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                            ),
                                            width: 28,
                                            height: 28,
                                            decoration: BoxDecoration(
                                              color: ink,
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: ink == _color
                                                    ? c.primary
                                                    : c.outlineVariant,
                                                width: ink == _color ? 3 : 1,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Saves [area] of the reader (or all of it, when null) as an image in
  /// a new note linked to this paper and page, and opens the note.
  Future<void> _extractToNote(Rect? area) async {
    final c = Theme.of(context).colorScheme;
    setState(() => _extracting = true);
    try {
      final boundary =
          _repaintKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      // Sharp enough to read a table's small print once zoomed in.
      final ratio = MediaQuery.devicePixelRatioOf(context).clamp(2.0, 3.0);
      final image = await boundary.toImage(pixelRatio: ratio);
      final Uint8List png;
      try {
        png = await cropToPng(
          image,
          area ?? Offset.zero & boundary.size,
          ratio,
        );
      } finally {
        image.dispose();
      }
      AppHaptics.confirm();
      if (mounted) {
        // The crop lifts off the page and heads for the note (the paired
        // pane in split view, else the bottom, where the snackbar sits).
        final box = area ?? Offset.zero & boundary.size;
        final from = boundary.localToGlobal(box.topLeft) & box.size;
        flyAcross(
          context,
          from: from.center,
          to:
              paneLanding(
                ref.read(pairedPaneKeyProvider),
                size: const Size(96, 72),
              ) ??
              bottomLanding(context, size: const Size(96, 72)),
          size: from.size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: c.shadow.withValues(alpha: 0.25),
                  blurRadius: 12,
                ),
              ],
            ),
            child: Image.memory(png, fit: BoxFit.fill, gaplessPlayback: true),
          ),
        );
      }
      final noteId = await createSnapshotNote(
        _db,
        paperId: widget.paperId,
        page: _controller.pageNumber ?? 1,
        png: png,
      );
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => NoteEditorScreen(noteId: noteId)),
      );
    } finally {
      if (mounted) setState(() => _extracting = false);
    }
  }
}

final _highlightsForPageProvider = StreamProvider.autoDispose
    .family<List<Highlight>, ({String paperId, int pageNumber})>((ref, key) {
      final db = ref.watch(databaseProvider);
      return (db.select(db.highlights)
            ..where((h) => h.paperId.equals(key.paperId))
            ..where((h) => h.pageNumber.equals(key.pageNumber)))
          .watch();
    });

/// Everything drawn on one page: text highlights (tappable), ink strokes,
/// and — in ink mode — the surface that captures new strokes.
///
/// Built for every visible page on every frame of a zoom, so marks are
/// decoded once when they change (not in `paint`), and a stroke being
/// drawn repaints only its own layer instead of rebuilding the page.
@visibleForTesting
class PageOverlay extends ConsumerStatefulWidget {
  const PageOverlay({
    super.key,
    required this.paperId,
    required this.pageNumber,
    required this.pageRect,
    required this.inkMode,
    required this.color,
    this.onOcrSelection,
  });

  final String paperId;
  final int pageNumber;
  final Rect pageRect;
  final bool inkMode;
  final Color color;

  /// Makes recognised words on a scanned page selectable; null leaves the
  /// page alone.
  final void Function(
    OcrSelectionAction action,
    List<OcrWord> words,
    Rect? from,
  )?
  onOcrSelection;

  @override
  ConsumerState<PageOverlay> createState() => _PageOverlayState();
}

typedef _DecodedStroke = ({List<Offset> points, Color color});
typedef _DecodedHighlight = ({Highlight highlight, List<Rect> rects});

/// A mark being animated: a new highlight sweeping in (`from == null`) or
/// a recolored one cross-fading from its old color.
class _MarkAnim {
  _MarkAnim(this.mark, this.controller, this.from);

  final _DecodedHighlight mark;
  final AnimationController controller;
  final Color? from;
}

class _PageOverlayState extends ConsumerState<PageOverlay>
    with TickerProviderStateMixin {
  final _live = _LiveStroke();
  late final FreshHighlights _fresh = ref.read(freshHighlightsProvider);
  final _anims = <String, _MarkAnim>{};

  /// What the static painter draws: every highlight not being animated.
  /// Rebuilt only when the marks or the animations change, so the painter
  /// stays cheap to compare while the page is zoomed.
  List<_DecodedHighlight> _still = const [];
  List<_MarkAnim> _active = const [];

  List<Annotation>? _strokesFrom;
  List<_DecodedStroke> _strokes = const [];
  List<Highlight>? _highlightsFrom;
  List<_DecodedHighlight> _highlights = const [];

  @override
  void initState() {
    super.initState();
    _fresh.addListener(_onFresh);
  }

  @override
  void dispose() {
    _fresh.removeListener(_onFresh);
    for (final a in _anims.values) {
      a.controller.dispose();
    }
    _live.dispose();
    super.dispose();
  }

  void _onFresh() {
    if (_startAnimations(const {}) && mounted) setState(() {});
  }

  void _refreshLayers() {
    _still = [
      for (final h in _highlights)
        if (!_anims.containsKey(h.highlight.id)) h,
    ];
    _active = _anims.values.toList();
  }

  /// Starts the sweep for highlights made this session and the cross-fade
  /// for recolored ones ([before] maps id -> previous color). Returns
  /// whether anything started.
  bool _startAnimations(Map<String, String> before) {
    final reduced = AppMotion.reduced(context);
    var started = false;
    for (final h in _highlights) {
      final id = h.highlight.id;
      if (_anims.containsKey(id)) continue;
      final Color? from;
      final Duration duration;
      if (_fresh.claim(id)) {
        from = null;
        duration = sweepDuration(h.rects.length);
      } else if (before[id] case final old? when old != h.highlight.colorHex) {
        from = colorFromHex(old);
        duration = AppMotion.medium;
      } else {
        continue;
      }
      if (reduced) continue;
      final controller = AnimationController(vsync: this, duration: duration);
      final anim = _MarkAnim(h, controller, from);
      _anims[id] = anim;
      controller.forward().whenComplete(() {
        if (!mounted || _anims[id] != anim) return;
        _anims.remove(id);
        controller.dispose();
        setState(_refreshLayers);
      });
      started = true;
    }
    if (started) _refreshLayers();
    return started;
  }

  void _openHighlight(String id) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => HighlightSheet(highlightId: id),
  );

  Offset _normalize(Offset local) => Offset(
    local.dx / widget.pageRect.width,
    local.dy / widget.pageRect.height,
  );

  /// Decodes the stored JSON only when the query returns new rows.
  void _decode(List<Annotation> strokes, List<Highlight> highlights) {
    if (!identical(strokes, _strokesFrom)) {
      _strokesFrom = strokes;
      _strokes = [
        for (final a in strokes)
          (
            points: decodeStrokePoints(a.pointsJson),
            color: colorFromHex(a.colorHex),
          ),
      ];
    }
    if (!identical(highlights, _highlightsFrom)) {
      final before = {
        for (final h in _highlights) h.highlight.id: h.highlight.colorHex,
      };
      _highlightsFrom = highlights;
      _highlights = [
        for (final h in highlights)
          (highlight: h, rects: decodeRects(h.rectsJson)),
      ];
      // An animation in flight keeps the mark it started with.
      for (final id in _anims.keys.toList()) {
        if (!highlights.any((h) => h.id == id)) {
          _anims.remove(id)!.controller.dispose();
        }
      }
      _refreshLayers();
      _startAnimations(before);
    }
  }

  @override
  Widget build(BuildContext context) {
    final key = (paperId: widget.paperId, pageNumber: widget.pageNumber);
    _decode(
      ref.watch(annotationsForPageProvider(key)).value ?? const [],
      ref.watch(_highlightsForPageProvider(key)).value ?? const [],
    );
    final size = widget.pageRect.size;

    return SizedBox.fromSize(
      size: size,
      child: Stack(
        children: [
          // Highlights sit under the text, like marker on paper.
          IgnorePointer(
            child: CustomPaint(
              size: size,
              painter: _TextHighlightPainter(_still),
            ),
          ),
          if (_active.isNotEmpty)
            IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(size: size, painter: _SweepPainter(_active)),
              ),
            ),
          if (!widget.inkMode && widget.onOcrSelection != null)
            OcrSelectionLayer(
              key: const ValueKey('ocr-selection'),
              paperId: widget.paperId,
              page: widget.pageNumber,
              onAction: widget.onOcrSelection!,
            ),
          if (!widget.inkMode)
            for (final (:highlight, :rects) in _highlights)
              for (final r in rects)
                Positioned(
                  left: r.left * size.width,
                  top: r.top * size.height,
                  width: r.width * size.width,
                  height: r.height * size.height,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => _openHighlight(highlight.id),
                    // A right-click is the desktop's long-press: the same
                    // actions, as a menu at the pointer.
                    onSecondaryTapUp: isDesktop(context)
                        ? (d) => showContextMenuAt(
                            context,
                            d.globalPosition,
                            highlightContextActions(
                              context,
                              ref,
                              highlight,
                              onComment: () => _openHighlight(highlight.id),
                            ),
                          )
                        : null,
                  ),
                ),
          IgnorePointer(
            ignoring: !widget.inkMode,
            child: _inkGestures(
              context,
              child: Stack(
                children: [
                  CustomPaint(size: size, painter: _InkPainter(_strokes)),
                  RepaintBoundary(
                    child: CustomPaint(
                      size: size,
                      painter: _LiveInkPainter(_live, widget.color),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Captures strokes. A mouse drag draws like a pen; on a desktop a
  /// trackpad's two-finger scroll is left to the reader (it would
  /// otherwise count as a drag and draw).
  Widget _inkGestures(BuildContext context, {required Widget child}) {
    void start(DragStartDetails d) => _live.start(_normalize(d.localPosition));
    void update(DragUpdateDetails d) => _live.add(_normalize(d.localPosition));
    if (!isDesktop(context)) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Start the stroke where the pen touched down, not where the
        // drag was recognised a few pixels later.
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: start,
        onPanUpdate: update,
        onPanEnd: (_) => _commitStroke(),
        onPanCancel: _live.clear,
        child: child,
      );
    }
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        PanGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
              () => PanGestureRecognizer(
                supportedDevices: const {
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.touch,
                  PointerDeviceKind.stylus,
                  PointerDeviceKind.invertedStylus,
                  PointerDeviceKind.unknown,
                },
              ),
              (r) => r
                ..dragStartBehavior = DragStartBehavior.down
                ..onStart = start
                ..onUpdate = update
                ..onEnd = (_) {
                  _commitStroke();
                }
                ..onCancel = _live.clear,
            ),
      },
      child: child,
    );
  }

  Future<void> _commitStroke() async {
    final stroke = _live.points;
    if (stroke == null) return;
    await saveHighlightStroke(
      ref.read(databaseProvider),
      paperId: widget.paperId,
      pageNumber: widget.pageNumber,
      normalizedPoints: stroke,
      color: widget.color,
    );
    // Cleared after the save, so the stroke never blinks out before the
    // saved copy arrives.
    if (identical(_live.points, stroke)) _live.clear();
  }
}

/// The stroke under the pen, in normalized page coordinates. Repaints its
/// painter directly; nothing rebuilds while drawing.
class _LiveStroke extends ChangeNotifier {
  List<Offset>? points;

  void start(Offset p) {
    points = [p];
    notifyListeners();
  }

  void add(Offset p) {
    final current = points;
    if (current == null) return;
    current.add(p);
    notifyListeners();
  }

  void clear() {
    if (points == null) return;
    points = null;
    notifyListeners();
  }
}

/// One line's marker box, [fraction] of the way across.
void _paintLine(Canvas canvas, Size size, Rect r, Paint paint, [double f = 1]) {
  final left = r.left * size.width - 1;
  final right = r.right * size.width + 1;
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTRB(
        left,
        r.top * size.height,
        left + (right - left) * f,
        r.bottom * size.height,
      ),
      const Radius.circular(2),
    ),
    paint,
  );
}

Paint _markerPaint(Color color, [double opacity = 1]) => Paint()
  ..color = color.withValues(alpha: 0.45 * opacity)
  ..blendMode = BlendMode.multiply;

class _TextHighlightPainter extends CustomPainter {
  _TextHighlightPainter(this.highlights);

  final List<_DecodedHighlight> highlights;

  @override
  void paint(Canvas canvas, Size size) {
    for (final (:highlight, :rects) in highlights) {
      final paint = _markerPaint(colorFromHex(highlight.colorHex));
      for (final r in rects) {
        _paintLine(canvas, size, r, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_TextHighlightPainter old) => old.highlights != highlights;
}

/// Highlights being animated, on a layer of their own that repaints from
/// the animation controllers alone: nothing else rebuilds or repaints.
class _SweepPainter extends CustomPainter {
  _SweepPainter(this.anims)
    : super(repaint: Listenable.merge([for (final a in anims) a.controller]));

  final List<_MarkAnim> anims;

  @override
  void paint(Canvas canvas, Size size) {
    for (final a in anims) {
      final color = colorFromHex(a.mark.highlight.colorHex);
      final t = a.controller.value;
      final rects = a.mark.rects;
      if (a.from case final old?) {
        final eased = AppMotion.standard.transform(t);
        for (final r in rects) {
          _paintLine(canvas, size, r, _markerPaint(old, 1 - eased));
          _paintLine(canvas, size, r, _markerPaint(color, eased));
        }
        continue;
      }
      final paint = _markerPaint(color);
      for (var i = 0; i < rects.length; i++) {
        final f = sweepLineProgress(t, i, rects.length);
        if (f > 0) _paintLine(canvas, size, rects[i], paint, f);
      }
    }
  }

  @override
  bool shouldRepaint(_SweepPainter old) => old.anims != anims;
}

void _paintStroke(
  Canvas canvas,
  Size size,
  List<Offset> normalized,
  Color color,
) {
  if (normalized.length < 2) return;
  final paint = Paint()
    ..color = color.withValues(alpha: 0.4)
    ..strokeWidth = size.width * 0.025
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  final path = Path()
    ..moveTo(
      normalized.first.dx * size.width,
      normalized.first.dy * size.height,
    );
  for (final point in normalized.skip(1)) {
    path.lineTo(point.dx * size.width, point.dy * size.height);
  }
  canvas.drawPath(path, paint);
}

class _InkPainter extends CustomPainter {
  _InkPainter(this.strokes);

  final List<_DecodedStroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final (:points, :color) in strokes) {
      _paintStroke(canvas, size, points, color);
    }
  }

  @override
  bool shouldRepaint(_InkPainter old) => old.strokes != strokes;
}

class _LiveInkPainter extends CustomPainter {
  _LiveInkPainter(this.live, this.color) : super(repaint: live);

  final _LiveStroke live;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (live.points case final points?) {
      _paintStroke(canvas, size, points, color);
    }
  }

  @override
  bool shouldRepaint(_LiveInkPainter old) =>
      old.live != live || old.color != color;
}

/// Details for one highlight: the quote, recolor, a comment, and actions.
class HighlightSheet extends ConsumerStatefulWidget {
  const HighlightSheet({super.key, required this.highlightId});

  final String highlightId;

  @override
  ConsumerState<HighlightSheet> createState() => _HighlightSheetState();
}

class _HighlightSheetState extends ConsumerState<HighlightSheet> {
  final _comment = TextEditingController();
  late final AppDatabase _db = ref.read(databaseProvider);
  Highlight? _h;

  @override
  void initState() {
    super.initState();
    (_db.select(_db.highlights)..where((h) => h.id.equals(widget.highlightId)))
        .getSingleOrNull()
        .then((h) {
          if (!mounted || h == null) return;
          setState(() {
            _h = h;
            _comment.text = h.comment ?? '';
          });
        });
  }

  @override
  void dispose() {
    // Comments save when the sheet closes, whichever way it closes.
    final h = _h;
    if (h != null && _comment.text.trim() != (h.comment ?? '')) {
      updateHighlight(_db, h.id, comment: _comment.text);
    }
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = _h;
    final theme = Theme.of(context);
    if (h == null) return const SizedBox(height: 120);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.only(left: 12),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: colorFromHex(h.colorHex), width: 4),
                  ),
                ),
                child: Text(
                  h.quote,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text('Page ${h.pageNumber}', style: theme.textTheme.labelMedium),
              const SizedBox(height: 16),
              Row(
                children: [
                  for (final ink in highlightInks)
                    GestureDetector(
                      onTap: () async {
                        await updateHighlight(_db, h.id, color: ink);
                        setState(
                          () => _h = h.copyWith(colorHex: colorToHex(ink)),
                        );
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 12),
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: ink,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: colorToHex(ink) == h.colorHex.toLowerCase()
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outlineVariant,
                            width: colorToHex(ink) == h.colorHex.toLowerCase()
                                ? 3
                                : 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _comment,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'Add a comment'),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.note_add_outlined),
                    label: const Text('Quote to note'),
                    onPressed: () async {
                      final comment = _comment.text.trim();
                      await updateHighlight(_db, h.id, comment: comment);
                      final updated = h.copyWith(
                        comment: Value(comment.isEmpty ? null : comment),
                      );
                      _h = updated;
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      await showQuoteToNoteSheet(context, ref, updated);
                    },
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('Copy'),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: h.quote));
                      Navigator.pop(context);
                    },
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                    onPressed: () async {
                      _h = null; // nothing left to save on close
                      await deleteHighlight(_db, h.id);
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// All of a paper's highlights; picking one returns its page number.
class _HighlightsList extends ConsumerWidget {
  const _HighlightsList({required this.paperId});

  final String paperId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final highlights =
        ref.watch(highlightsForPaperProvider(paperId)).value ?? const [];
    final theme = Theme.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: highlights.isEmpty
            ? Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                child: Text(
                  'Select text on a page, then tap Highlight.',
                  style: theme.textTheme.bodyMedium,
                ),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final h in highlights)
                    ListTile(
                      leading: Container(
                        width: 6,
                        height: 36,
                        decoration: BoxDecoration(
                          color: colorFromHex(h.colorHex),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      title: Text(
                        h.quote,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        ['p. ${h.pageNumber}', ?h.comment].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => Navigator.pop(context, h.pageNumber),
                    ),
                ],
              ),
      ),
    );
  }
}

/// A flattened, indented view of a PDF's outline. Pops with the page number
/// of the chosen entry.
class ContentsSheet extends StatelessWidget {
  const ContentsSheet({super.key, required this.outline});

  final List<PdfOutlineNode> outline;

  static List<({String title, int depth, int? page})> flatten(
    List<PdfOutlineNode> nodes, [
    int depth = 0,
  ]) => [
    for (final n in nodes) ...[
      (title: n.title, depth: depth, page: n.dest?.pageNumber),
      ...flatten(n.children, depth + 1),
    ],
  ];

  @override
  Widget build(BuildContext context) {
    final entries = flatten(outline);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final e in entries)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.only(
                  left: 20.0 + e.depth * 18,
                  right: 20,
                ),
                title: Text(
                  e.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: e.page == null ? null : Text('${e.page}'),
                enabled: e.page != null,
                onTap: () => Navigator.pop(context, e.page),
              ),
          ],
        ),
      ),
    );
  }
}

/// A small teardrop selection handle in the theme's primary color: a circle
/// with one square corner, which touches the selected text. (pdfrx's own
/// is a 30 px triangle that sits over neighbouring lines.)
class SelectionHandle extends StatelessWidget {
  const SelectionHandle({
    super.key,
    required this.pointsTo,
    this.active = false,
  });

  /// [Alignment.bottomRight] or [Alignment.topLeft]: the pointed corner.
  final Alignment pointsTo;
  final bool active;

  static const size = 24.0;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    const r = Radius.circular(size / 2);
    final bottomRight = pointsTo == Alignment.bottomRight;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: active ? color : color.withValues(alpha: 0.85),
        borderRadius: BorderRadius.only(
          topLeft: bottomRight ? r : Radius.zero,
          topRight: r,
          bottomLeft: r,
          bottomRight: bottomRight ? Radius.zero : r,
        ),
        boxShadow: active
            ? null
            : const [BoxShadow(color: Colors.black26, blurRadius: 3)],
      ),
    );
  }
}

/// Wraps overlay chrome so focus mode fades it out and stops it taking
/// touches once it is gone.
class _Chrome extends StatelessWidget {
  const _Chrome({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (context, child) => animation.value <= 0
        ? const SizedBox.shrink()
        : Opacity(opacity: animation.value, child: child),
  );
}

/// The compact search field that replaces the app bar title: the query,
/// then "3 of 41" as its suffix. Enter goes to the next match,
/// Shift+Enter to the previous.
@visibleForTesting
class FindField extends StatelessWidget {
  const FindField({
    super.key,
    required this.search,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onStep,
  });

  final DocumentSearch search;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final void Function(int delta) onStep;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Focus(
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.enter &&
            HardwareKeyboard.instance.isShiftPressed) {
          onStep(-1);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TextField(
        key: const ValueKey('find-field'),
        controller: controller,
        focusNode: focusNode,
        autofocus: true,
        textInputAction: TextInputAction.search,
        style: t.titleMedium,
        onChanged: onChanged,
        onSubmitted: (_) {
          onStep(1);
          focusNode.requestFocus();
        },
        decoration: InputDecoration(
          hintText: 'Find in document',
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          isDense: true,
          suffixIcon: ListenableBuilder(
            listenable: search,
            builder: (context, _) => Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Center(
                widthFactor: 1,
                child: Text(
                  search.summary,
                  key: const ValueKey('find-count'),
                  style: t.labelMedium?.copyWith(color: c.onSurfaceVariant),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A colour swatch in the viewer's bottom bar: a hand cursor and a label
/// with a mouse.
class _InkSwatchTap extends StatelessWidget {
  const _InkSwatchTap({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tap = GestureDetector(onTap: onTap, child: child);
    if (!isDesktop(context)) return tap;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Tooltip(message: 'Highlight colour', child: tap),
    );
  }
}

/// A highlight's right-click menu: recolour, comment, copy, delete.
List<ContextMenuAction?> highlightContextActions(
  BuildContext context,
  WidgetRef ref,
  Highlight highlight, {
  required VoidCallback onComment,
}) {
  final db = ref.read(databaseProvider);
  final current = highlight.colorHex.toLowerCase();
  const names = ['Butter', 'Sage', 'Rose', 'Mist'];
  return [
    for (final (i, ink) in highlightInks.indexed)
      ContextMenuAction(
        label: '${names[i]} highlight',
        icon: colorToHex(ink) == current
            ? Icons.check_circle
            : Icons.circle_outlined,
        onSelected: () => updateHighlight(db, highlight.id, color: ink),
      ),
    null,
    ContextMenuAction(
      label: highlight.comment == null ? 'Add a comment…' : 'Edit comment…',
      icon: Icons.comment_outlined,
      onSelected: onComment,
    ),
    ContextMenuAction(
      label: 'Copy',
      icon: Icons.copy_outlined,
      onSelected: () => Clipboard.setData(ClipboardData(text: highlight.quote)),
    ),
    null,
    ContextMenuAction(
      label: 'Delete highlight',
      icon: Icons.delete_outline,
      destructive: true,
      onSelected: () => deleteHighlight(db, highlight.id),
    ),
  ];
}
