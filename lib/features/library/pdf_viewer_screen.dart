import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../theme/app_theme.dart';
import '../notes/note_editor_screen.dart';
import 'annotations_providers.dart';
import 'highlights.dart';
import '../settings/appearance_settings.dart';
import 'quote_to_note.dart';
import 'snapshot.dart';

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
  });

  final String paperId;
  final String pdfPath;

  /// Page to open at; defaults to 1.
  final int? initialPage;

  @override
  ConsumerState<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends ConsumerState<PdfViewerScreen> {
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

  @override
  void dispose() {
    // Flush the reading position on the way out.
    _pageSave?.cancel();
    if (_pendingPage case final page?) saveLastPage(_db, widget.paperId, page);
    super.dispose();
  }

  void _onPageChanged(int? page) {
    if (page == null) return;
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
    return (_db.select(_db.highlights)..where((h) => h.id.isIn(ids))).get();
  }

  void _customizeMenu(
    PdfViewerContextMenuBuilderParams params,
    List<ContextMenuButtonItem> items,
  ) {
    final selection = params.textSelectionDelegate;
    if (!selection.hasSelectedText) return;
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
            await showQuoteToNoteSheet(context, ref, _merge(made));
          }
        },
      ),
    ]);
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
    // While choosing a snapshot area, back (or a swipe in from the edge,
    // easy to start by accident when dragging the box) cancels the
    // snapshot instead of leaving the paper.
    return PopScope(
      canPop: !_snapping,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _snapping = false);
      },
      child: Scaffold(
        appBar: AppBar(
          actions: [
            IconButton(
              icon: const Icon(Icons.format_quote_outlined),
              tooltip: 'Highlights',
              onPressed: _showHighlightsList,
            ),
            IconButton(
              isSelected: _inkMode,
              icon: const Icon(Icons.draw_outlined),
              selectedIcon: const Icon(Icons.draw),
              tooltip: _inkMode ? 'Stop drawing' : 'Draw on the page',
              onPressed: () => setState(() => _inkMode = !_inkMode),
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) {
                if (v == 'snapshot') setState(() => _snapping = true);
                if (v == 'contents') _showContents();
                if (v.startsWith('read:')) {
                  ref
                      .read(appearanceSettingsProvider)
                      .setReading(ReadingTheme.values.byName(v.substring(5)));
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'contents',
                  child: ListTile(
                    leading: Icon(Icons.toc),
                    title: Text('Contents'),
                  ),
                ),
                for (final theme in ReadingTheme.values)
                  CheckedPopupMenuItem(
                    value: 'read:${theme.name}',
                    checked:
                        ref.read(appearanceSettingsProvider).reading == theme,
                    child: Text('${theme.label} page'),
                  ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'snapshot',
                  enabled: !_extracting,
                  child: const ListTile(
                    leading: Icon(Icons.crop_free),
                    title: Text('Snapshot to a note'),
                    subtitle: Text('For figures and tables'),
                  ),
                ),
              ],
            ),
          ],
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            // The reading theme sits outside the boundary, so a snapshot
            // keeps the figure's real colors.
            ColorFiltered(
              colorFilter:
                  ref.watch(appearanceSettingsProvider).reading.filter ??
                  const ColorFilter.mode(Colors.transparent, BlendMode.dst),
              child: RepaintBoundary(
                key: _repaintKey,
                child: PdfViewer.file(
                  widget.pdfPath,
                  controller: _controller,
                  initialPageNumber: widget.initialPage ?? 1,
                  params: PdfViewerParams(
                    backgroundColor: c.surfaceContainer,
                    onPageChanged: _onPageChanged,
                    textSelectionParams: PdfTextSelectionParams(
                      enabled: !_inkMode,
                      buildSelectionHandle: (context, anchor, state) =>
                          SelectionHandle(
                            // pdfrx places handle A above-left of the first
                            // character and B below-right of the last; each
                            // teardrop points at its corner of the selection.
                            pointsTo:
                                (anchor.type == PdfTextSelectionAnchorType.a) ==
                                    (anchor.direction != PdfTextDirection.rtl &&
                                        anchor.direction !=
                                            PdfTextDirection.vrtl)
                                ? Alignment.bottomRight
                                : Alignment.topLeft,
                            active:
                                state !=
                                PdfViewerTextSelectionAnchorHandleState.normal,
                          ),
                    ),
                    customizeContextMenuItems: _customizeMenu,
                    pageOverlaysBuilder: (context, pageRect, page) => [
                      _PageOverlay(
                        paperId: widget.paperId,
                        pageNumber: page.pageNumber,
                        pageRect: pageRect,
                        inkMode: _inkMode,
                        color: _color,
                      ),
                    ],
                  ),
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
          ],
        ),
        // One palette for both kinds of marking: the ink for new strokes,
        // and the color the next text highlight gets.
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final ink in highlightInks)
                  GestureDetector(
                    onTap: () => setState(() => _color = ink),
                    child: AnimatedContainer(
                      duration: AppMotion.short,
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: ink,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: ink == _color ? c.primary : c.outlineVariant,
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
    );
  }

  /// Saves [area] of the reader (or all of it, when null) as an image in
  /// a new note linked to this paper and page, and opens the note.
  Future<void> _extractToNote(Rect? area) async {
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
class _PageOverlay extends ConsumerStatefulWidget {
  const _PageOverlay({
    required this.paperId,
    required this.pageNumber,
    required this.pageRect,
    required this.inkMode,
    required this.color,
  });

  final String paperId;
  final int pageNumber;
  final Rect pageRect;
  final bool inkMode;
  final Color color;

  @override
  ConsumerState<_PageOverlay> createState() => _PageOverlayState();
}

class _PageOverlayState extends ConsumerState<_PageOverlay> {
  List<Offset>? _liveStroke;

  Offset _normalize(Offset local) => Offset(
    local.dx / widget.pageRect.width,
    local.dy / widget.pageRect.height,
  );

  @override
  Widget build(BuildContext context) {
    final key = (paperId: widget.paperId, pageNumber: widget.pageNumber);
    final strokes =
        ref.watch(annotationsForPageProvider(key)).value ?? const [];
    final highlights =
        ref.watch(_highlightsForPageProvider(key)).value ?? const [];
    final size = widget.pageRect.size;

    return SizedBox.fromSize(
      size: size,
      child: Stack(
        children: [
          // Highlights sit under the text, like marker on paper.
          IgnorePointer(
            child: CustomPaint(
              size: size,
              painter: _TextHighlightPainter(highlights),
            ),
          ),
          if (!widget.inkMode)
            for (final h in highlights)
              for (final r in decodeRects(h.rectsJson))
                Positioned(
                  left: r.left * size.width,
                  top: r.top * size.height,
                  width: r.width * size.width,
                  height: r.height * size.height,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => HighlightSheet(highlightId: h.id),
                    ),
                  ),
                ),
          IgnorePointer(
            ignoring: !widget.inkMode,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (d) =>
                  setState(() => _liveStroke = [_normalize(d.localPosition)]),
              onPanUpdate: (d) =>
                  setState(() => _liveStroke!.add(_normalize(d.localPosition))),
              onPanEnd: (_) => _commitStroke(),
              child: CustomPaint(
                size: size,
                painter: _InkPainter(
                  saved: strokes,
                  live: _liveStroke,
                  liveColor: widget.color,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _commitStroke() async {
    final stroke = _liveStroke;
    setState(() => _liveStroke = null);
    if (stroke == null) return;
    await saveHighlightStroke(
      ref.read(databaseProvider),
      paperId: widget.paperId,
      pageNumber: widget.pageNumber,
      normalizedPoints: stroke,
      color: widget.color,
    );
  }
}

class _TextHighlightPainter extends CustomPainter {
  _TextHighlightPainter(this.highlights);

  final List<Highlight> highlights;

  @override
  void paint(Canvas canvas, Size size) {
    for (final h in highlights) {
      final paint = Paint()
        ..color = colorFromHex(h.colorHex).withValues(alpha: 0.45)
        ..blendMode = BlendMode.multiply;
      for (final r in decodeRects(h.rectsJson)) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(
              r.left * size.width - 1,
              r.top * size.height,
              r.right * size.width + 1,
              r.bottom * size.height,
            ),
            const Radius.circular(2),
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_TextHighlightPainter old) => old.highlights != highlights;
}

class _InkPainter extends CustomPainter {
  _InkPainter({required this.saved, this.live, required this.liveColor});

  final List<Annotation> saved;
  final List<Offset>? live;
  final Color liveColor;

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

  @override
  void paint(Canvas canvas, Size size) {
    for (final annotation in saved) {
      _paintStroke(
        canvas,
        size,
        decodeStrokePoints(annotation.pointsJson),
        colorFromHex(annotation.colorHex),
      );
    }
    if (live != null) _paintStroke(canvas, size, live!, liveColor);
  }

  @override
  bool shouldRepaint(covariant _InkPainter oldDelegate) =>
      oldDelegate.saved != saved || oldDelegate.live != live;
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
