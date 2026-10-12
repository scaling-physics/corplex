import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../theme/haptics.dart';
import '../ocr/ocr_engine.dart';
import '../ocr/ocr_service.dart';
import 'highlights.dart';

/// What the little menu after selecting recognised text can do.
enum OcrSelectionAction { highlight, quote, copy }

Rect _box(OcrWord w) => Rect.fromLTRB(w.left, w.top, w.right, w.bottom);

/// Index of the word nearest [p] (page fractions): the one under it, else
/// the closest box, counting vertical distance double so a point between
/// two lines picks a word on the nearer line.
int nearestWord(List<OcrWord> words, Offset p) {
  var best = 0;
  var bestD = double.infinity;
  for (var i = 0; i < words.length; i++) {
    final r = _box(words[i]);
    final dx = math.max(math.max(r.left - p.dx, p.dx - r.right), 0.0);
    final dy = math.max(math.max(r.top - p.dy, p.dy - r.bottom), 0.0);
    final d = dx * dx + 4 * dy * dy;
    if (d < bestD) {
      bestD = d;
      best = i;
    }
  }
  return best;
}

/// The words from the one nearest [from] to the one nearest [to], in
/// reading order, whichever way the drag went. Empty for a page with no
/// words.
List<OcrWord> selectOcrWords(List<OcrWord> words, Offset from, Offset to) {
  if (words.isEmpty) return const [];
  final a = nearestWord(words, from);
  final b = nearestWord(words, to);
  return words.sublist(math.min(a, b), math.max(a, b) + 1);
}

/// The selected words as the passage they spell.
String ocrQuote(List<OcrWord> words) =>
    words.map((w) => w.text).join(' ').trim();

/// One box per line, as page fractions — the same shape text highlights
/// store, so they paint, sweep and export identically.
List<Rect> ocrRects(List<OcrWord> words) =>
    lineRects(words.map(_box), const Size(1, 1));

/// Saves [words] on [page] as an ordinary highlight and returns its row.
Future<Highlight> createOcrHighlight(
  AppDatabase db, {
  required String paperId,
  required int page,
  required List<OcrWord> words,
  required Color color,
}) async {
  final id = await addHighlight(
    db,
    paperId: paperId,
    pageNumber: page,
    quote: ocrQuote(words),
    rects: ocrRects(words),
    color: color,
  );
  return (db.select(db.highlights)..where((h) => h.id.equals(id))).getSingle();
}

/// Long-press-and-drag selection of recognised words on a scanned page.
/// Present only for a page that has OCR text (so never on born-digital
/// pages, where pdfrx selects), and only outside ink mode. A quick drag
/// still pans and zooms the page: only a press that holds still starts it.
class OcrSelectionLayer extends ConsumerStatefulWidget {
  const OcrSelectionLayer({
    super.key,
    required this.paperId,
    required this.page,
    required this.onAction,
  });

  final String paperId;
  final int page;

  /// Called with the chosen action, the selected words and where the
  /// selection is on screen (global).
  final void Function(
    OcrSelectionAction action,
    List<OcrWord> words,
    Rect? from,
  )
  onAction;

  @override
  ConsumerState<OcrSelectionLayer> createState() => _OcrSelectionLayerState();
}

class _OcrSelectionLayerState extends ConsumerState<OcrSelectionLayer> {
  final _selected = ValueNotifier<List<OcrWord>>(const []);
  OcrPageText? _wordsFrom;
  List<OcrWord> _words = const [];
  Offset? _start;

  @override
  void dispose() {
    _selected.dispose();
    super.dispose();
  }

  Offset _fraction(Offset local) {
    final size = context.size ?? const Size(1, 1);
    return Offset(local.dx / size.width, local.dy / size.height);
  }

  void _update(Offset local) {
    final start = _start;
    if (start == null) return;
    final next = selectOcrWords(_words, start, _fraction(local));
    if (next.length != _selected.value.length ||
        (next.isNotEmpty && next.first != _selected.value.first)) {
      _selected.value = next;
    }
  }

  Rect? _globalRect(List<OcrWord> words) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || words.isEmpty) return null;
    final size = box.size;
    var r = _box(words.first);
    for (final w in words) {
      r = r.expandToInclude(_box(w));
    }
    return Rect.fromPoints(
      box.localToGlobal(Offset(r.left * size.width, r.top * size.height)),
      box.localToGlobal(Offset(r.right * size.width, r.bottom * size.height)),
    );
  }

  Future<void> _finish() async {
    final words = _selected.value;
    _start = null;
    if (words.isEmpty || !mounted) return;
    final from = _globalRect(words);
    final screen = MediaQuery.sizeOf(context);
    final anchor =
        from ?? Rect.fromLTWH(screen.width / 2, screen.height / 2, 0, 0);
    final choice = await showMenu<OcrSelectionAction>(
      context: context,
      position: RelativeRect.fromRect(anchor, Offset.zero & screen),
      items: const [
        PopupMenuItem(
          value: OcrSelectionAction.highlight,
          child: Text('Highlight'),
        ),
        PopupMenuItem(
          value: OcrSelectionAction.quote,
          child: Text('Quote to note'),
        ),
        PopupMenuItem(value: OcrSelectionAction.copy, child: Text('Copy')),
      ],
    );
    if (mounted) _selected.value = const [];
    if (choice == null) return;
    if (choice == OcrSelectionAction.copy) {
      await Clipboard.setData(ClipboardData(text: ocrQuote(words)));
      AppHaptics.selection();
      return;
    }
    widget.onAction(choice, words, from);
  }

  @override
  Widget build(BuildContext context) {
    final text = ref
        .watch(
          ocrPageTextProvider((paperId: widget.paperId, page: widget.page)),
        )
        .value;
    if (text == null || text.lines.isEmpty) return const SizedBox.shrink();
    if (!identical(text, _wordsFrom)) {
      _wordsFrom = text;
      _words = text.words.toList();
    }
    final tint = Theme.of(context).colorScheme.primary.withValues(alpha: 0.3);
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPressStart: (d) {
          AppHaptics.selection();
          _start = _fraction(d.localPosition);
          _update(d.localPosition);
        },
        onLongPressMoveUpdate: (d) => _update(d.localPosition),
        onLongPressEnd: (_) => _finish(),
        onLongPressCancel: () => _selected.value = const [],
        child: RepaintBoundary(
          child: CustomPaint(painter: _SelectionPainter(_selected, tint)),
        ),
      ),
    );
  }
}

class _SelectionPainter extends CustomPainter {
  _SelectionPainter(this.selected, this.tint) : super(repaint: selected);

  final ValueNotifier<List<OcrWord>> selected;
  final Color tint;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = tint;
    for (final r in ocrRects(selected.value)) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            r.left * size.width,
            r.top * size.height,
            r.right * size.width,
            r.bottom * size.height,
          ),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SelectionPainter old) => old.tint != tint;
}
