import '../../l10n/l10n.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../library/citation_formatter.dart';
import '../library/authors.dart';
import '../library/citations.dart';
import '../library/highlights.dart';
import '../../theme/haptics.dart';
import '../../theme/app_theme.dart';
import '../library/paper_detail_screen.dart';
import 'note_content.dart';

/// A citation shown as a chip in the editor — "(Vaswani et al., 2017)" —
/// instead of its stored text `[@vaswani2017]`.
///
/// Only the editor sees chips. A note is *stored* with plain `[@key]`
/// text, exactly as before, so export, bibliographies, search, sync and
/// merging never meet an embed: [citationsToEmbeds] turns the text into
/// chips when a note is loaded into the editor, and [citationEmbedsToText]
/// turns them back when it is saved. The chip's data is the original
/// marker text, so the round trip is exact.
const citationEmbedType = 'cite';

/// `[@a; @b]` groups whose keys are all well formed.
bool _isCitation(String marker) => citedKeys(marker).isNotEmpty;

final _marker = RegExp(r'\[@[^\]\n]+\]');

/// Stored note content → the editor's form, with citations as chips.
/// Content that isn't Delta JSON (an old plain-text note) is returned
/// unchanged.
String citationsToEmbeds(String stored) {
  final ops = _ops(stored);
  if (ops == null) return stored;
  final out = <Map<String, Object?>>[];
  for (final op in ops) {
    final insert = op['insert'];
    if (insert is! String || !insert.contains('[@')) {
      out.add(op);
      continue;
    }
    final attributes = op['attributes'];
    Map<String, Object?> make(Object value) => {
      'insert': value,
      'attributes': ?attributes,
    };
    var pos = 0;
    for (final m in _marker.allMatches(insert)) {
      if (!_isCitation(m.group(0)!)) continue;
      if (m.start > pos) out.add(make(insert.substring(pos, m.start)));
      out.add(make({citationEmbedType: m.group(0)!}));
      pos = m.end;
    }
    if (pos < insert.length) out.add(make(insert.substring(pos)));
  }
  return jsonEncode(out);
}

/// The editor's content → stored form: chips back to `[@key]` text,
/// normalised the way the editor saves notes.
String citationEmbedsToText(String editorContent) {
  final ops = _ops(editorContent);
  if (ops == null) return editorContent;
  final out = [
    for (final op in ops)
      if (op['insert'] case {citationEmbedType: final String marker})
        {'insert': marker, 'attributes': ?op['attributes']}
      else
        op,
  ];
  return encodeNoteContent(Document.fromJson(out));
}

/// The text of [delta] (up to [end], if given) with citation chips written
/// out as their `[@key]` markers, for finding which papers a note cites.
String textWithCitations(Delta delta, {int? end}) {
  final b = StringBuffer();
  var offset = 0;
  for (final op in delta.toList()) {
    if (!op.isInsert) continue;
    if (end != null && offset >= end) break;
    final data = op.data;
    if (data is String) {
      b.write(
        end == null
            ? data
            : data.substring(0, (end - offset).clamp(0, data.length)),
      );
      offset += data.length;
    } else {
      if (data case {citationEmbedType: final String marker}) b.write(marker);
      offset += 1;
    }
  }
  return b.toString();
}

/// Chips the user has just inserted, waiting to play their entrance.
///
/// Quill rebuilds embeds constantly, a note's chips all appear at once when
/// it opens, and Flutter may hand an old chip's state to a different chip,
/// so "is this chip new?" can't come from the build or `initState`. Instead
/// [insertCitation] marks the document *node* it created, and a chip that
/// is shown for a marked node takes the mark, exactly once. Chips in a
/// loaded or merged document are other nodes and are never marked.
class FreshCitations {
  FreshCitations._();

  static final _marked = Expando<bool>('fresh citation');

  static void mark(Node node) => _marked[node] = true;

  /// True once per [mark]ed node.
  static bool take(Node node) {
    if (_marked[node] != true) return false;
    _marked[node] = null;
    return true;
  }
}

/// Rewrites the chip [node] to show [marker], keeping the selection where
/// it was. The replacement is a plain node: it never plays the entrance.
void replaceCitationMarker(
  QuillController controller,
  Node node,
  String marker,
) {
  final offset = node.documentOffset;
  controller.replaceText(
    offset,
    1,
    Embeddable(citationEmbedType, marker),
    null,
  );
}

/// A small dialog to set, change or clear the pinpoint of [item]: the page
/// (or chapter, section, …) and its kind. Returns the new item (with no
/// locator when cleared), or null when cancelled.
Future<CiteItem?> showLocatorDialog(BuildContext context, CiteItem item) {
  return showDialog<CiteItem>(
    context: context,
    builder: (_) => _LocatorDialog(item: item),
  );
}

class _LocatorDialog extends StatefulWidget {
  const _LocatorDialog({required this.item});

  final CiteItem item;

  @override
  State<_LocatorDialog> createState() => _LocatorDialogState();
}

class _LocatorDialogState extends State<_LocatorDialog> {
  late final _text = TextEditingController(text: widget.item.locator ?? '');
  late String _label = widget.item.label ?? 'page';

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    final value = _text.text.trim();
    Navigator.pop(
      context,
      value.isEmpty
          ? CiteItem(widget.item.key)
          : CiteItem(
              widget.item.key,
              locator: value.replaceAllMapped(
                RegExp(r'(\d)\s*-\s*(?=\d)'),
                (m) => '${m[1]}–',
              ),
              label: _label,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.item.hasLocator
            ? context.l10n.notesChangePage
            : context.l10n.notesPage,
      ),
      content: Row(
        children: [
          DropdownButton<String>(
            value: _label,
            underline: const SizedBox.shrink(),
            items: [
              for (final l in locatorLabels)
                DropdownMenuItem(
                  value: l,
                  child: Text(locatorLabelName(context.l10n, l)),
                ),
            ],
            onChanged: (v) => setState(() => _label = v ?? 'page'),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _text,
              autofocus: true,
              decoration: InputDecoration(hintText: context.l10n.notesPageHint),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
            ),
          ),
        ],
      ),
      actions: [
        if (widget.item.hasLocator)
          TextButton(
            onPressed: () => Navigator.pop(context, CiteItem(widget.item.key)),
            child: Text(context.l10n.notesClear),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.commonCancel),
        ),
        FilledButton(onPressed: _save, child: Text(context.l10n.notesSet)),
      ],
    );
  }
}

/// Inserts a citation chip for [citekey] at [index], followed by a space,
/// and puts the cursor after it.
void insertCitation(QuillController controller, int index, String citekey) {
  controller.replaceText(
    index,
    0,
    Embeddable(citationEmbedType, citationMarker(citekey)),
    null,
  );
  final at = controller.document.queryChild(index);
  final line = at.node;
  if (line is Line) {
    final leaf = line.queryChild(at.offset, false).node;
    if (leaf != null) FreshCitations.mark(leaf);
  }
  controller.replaceText(
    index + 1,
    0,
    ' ',
    TextSelection.collapsed(offset: index + 2),
  );
}

List<Map<String, Object?>>? _ops(String content) {
  try {
    final decoded = jsonDecode(content);
    if (decoded is! List) return null;
    return [for (final op in decoded) (op as Map).cast<String, Object?>()];
  } on FormatException {
    return null;
  }
}

/// The papers a citation marker names, kept up to date (a paper's authors
/// or year can change after it's cited).
final _citedPapersProvider = StreamProvider.autoDispose
    .family<Map<String, Paper>, String>((ref, marker) {
      final db = ref.watch(databaseProvider);
      final keys = citedKeys(marker);
      return (db.select(db.papers)..where((p) => p.citekey.isIn(keys)))
          .watch()
          .map((rows) => {for (final p in rows) p.citekey!: p});
    });

/// Renders citation chips in the note editor. Tap one to open the paper.
class CitationEmbedBuilder extends EmbedBuilder {
  const CitationEmbedBuilder();

  @override
  String get key => citationEmbedType;

  @override
  bool get expanded => false;

  @override
  String toPlainText(Embed node) => node.value.data as String;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final marker = embedContext.node.value.data as String;
    return _CitationChip(
      node: embedContext.node,
      controller: embedContext.controller,
      marker: marker,
      textStyle: embedContext.textStyle,
    );
  }
}

class _CitationChip extends ConsumerStatefulWidget {
  const _CitationChip({
    required this.node,
    required this.controller,
    required this.marker,
    required this.textStyle,
  });

  final Node node;
  final QuillController controller;
  final String marker;
  final TextStyle textStyle;

  @override
  ConsumerState<_CitationChip> createState() => _CitationChipState();
}

class _CitationChipState extends ConsumerState<_CitationChip>
    with SingleTickerProviderStateMixin {
  static const _popDuration = Duration(milliseconds: 600);

  // At 1 a chip is at rest. A freshly inserted one runs 0 → 1: it scales
  // and fades in over the first part while the tint fades over all of it.
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: _popDuration,
    value: 1,
  );

  bool _pending = false;

  final _link = LayerLink();
  OverlayEntry? _card;
  Timer? _hoverIn;
  Timer? _hoverOut;
  bool _overChip = false;
  bool _overCard = false;

  void _openPaper(String paperId) {
    _closeCard();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PaperDetailScreen(paperId: paperId)),
    );
  }

  /// Shows the paper(s) this chip cites in a small popover under (or over)
  /// the chip. Long-press, or resting a pointer on it.
  void _showCard() {
    if (_card != null || !mounted) return;
    final overlay = Overlay.maybeOf(context);
    final box = context.findRenderObject();
    if (overlay == null || box is! RenderBox || !box.hasSize) return;
    final anchor = box.localToGlobal(Offset.zero) & box.size;
    final marker = widget.marker;
    final entry = OverlayEntry(
      builder: (_) => _CitationCardOverlay(
        anchor: anchor,
        marker: marker,
        onOpen: _openPaper,
        onPage: _editLocator,
        onDismiss: _closeCard,
        onHover: (over) {
          _overCard = over;
          _maybeCloseAfterHover();
        },
      ),
    );
    _card = entry;
    overlay.insert(entry);
  }

  /// Asks for a page (or chapter, …) for the [index]th paper of this chip
  /// and rewrites the chip in place. The new chip is another node that
  /// nobody [FreshCitations.mark]ed, so it doesn't animate.
  Future<void> _editLocator(int index) async {
    _closeCard();
    final items = parseCitationGroup(widget.marker);
    if (index >= items.length) return;
    final node = widget.node;
    final result = await showLocatorDialog(context, items[index]);
    if (result == null || result == items[index]) return;
    if (node.parent == null) return; // the chip was deleted meanwhile
    items[index] = result;
    replaceCitationMarker(widget.controller, node, citationMarkerFor(items));
  }

  void _closeCard() {
    _hoverIn?.cancel();
    _hoverOut?.cancel();
    _card?.remove();
    _card?.dispose();
    _card = null;
    _overCard = false;
  }

  void _maybeCloseAfterHover() {
    _hoverOut?.cancel();
    if (_overChip || _overCard) return;
    _hoverOut = Timer(const Duration(milliseconds: 250), () {
      if (!_overChip && !_overCard) _closeCard();
    });
  }

  /// Plays the entrance once a freshly inserted chip has a context to ask
  /// about reduced motion (not available in `initState`).
  void _start() {
    if (!_pending) return;
    _pending = false;
    if (!AppMotion.reduced(context)) _pop.forward(from: 0);
  }

  @override
  void initState() {
    super.initState();
    _pending = FreshCitations.take(widget.node);
  }

  @override
  void didUpdateWidget(_CitationChip old) {
    super.didUpdateWidget(old);
    if (!identical(old.node, widget.node) && FreshCitations.take(widget.node)) {
      _pending = true;
      _start();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _start();
  }

  @override
  void dispose() {
    _closeCard();
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final marker = widget.marker;
    final c = Theme.of(context).colorScheme;
    final byKey = ref.watch(_citedPapersProvider(marker)).value;
    final keys = citedKeys(marker);
    final known = byKey != null && keys.every(byKey.containsKey);
    // The editor shows author–date; the reference style is chosen when the
    // bibliography is added or the note exported.
    final label = known
        ? CitationResolver(byKey, CitationStyle.apa).replace(marker)
        : marker;
    final first = known ? byKey[keys.first] : null;

    final rest = known
        ? c.primaryContainer.withValues(alpha: 0.6)
        : c.errorContainer.withValues(alpha: 0.6);
    final flash = known
        ? Color.alphaBlend(c.primary.withValues(alpha: 0.3), c.primaryContainer)
        : Color.alphaBlend(c.error.withValues(alpha: 0.3), c.errorContainer);
    final entrance = CurvedAnimation(
      parent: _pop,
      curve: const Interval(0, 0.35, curve: AppMotion.enter),
    );

    return Semantics(
      button: first != null,
      label: known
          ? context.l10n.notesCitationLabel(label)
          : context.l10n.notesCitationMissingLabel(marker),
      onLongPress: _showCard,
      child: MouseRegion(
        onEnter: (_) {
          _overChip = true;
          _hoverOut?.cancel();
          _hoverIn?.cancel();
          _hoverIn = Timer(const Duration(milliseconds: 500), _showCard);
        },
        onExit: (_) {
          _overChip = false;
          _hoverIn?.cancel();
          _maybeCloseAfterHover();
        },
        child: CompositedTransformTarget(
          link: _link,
          child: GestureDetector(
            onLongPress: () {
              AppHaptics.selection();
              _showCard();
            },
            onTap: first == null
                ? null
                : () {
                    _closeCard();
                    _openPaper(first.id);
                  },
            child: FadeTransition(
              opacity: entrance,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.9, end: 1).animate(entrance),
                child: AnimatedBuilder(
                  animation: _pop,
                  builder: (context, child) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Color.lerp(flash, rest, _pop.value),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: child,
                  ),
                  child: Text(
                    label,
                    style: widget.textStyle.copyWith(
                      color: known ? c.onPrimaryContainer : c.onErrorContainer,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The popover: for each cited key, the paper's title, authors, year and
/// venue, up to three of its highlights, and "Open paper"; or a line saying
/// the key isn't in the library.
class _CitationCardOverlay extends ConsumerWidget {
  const _CitationCardOverlay({
    required this.anchor,
    required this.marker,
    required this.onOpen,
    required this.onPage,
    required this.onDismiss,
    required this.onHover,
  });

  final Rect anchor;
  final String marker;
  final void Function(String paperId) onOpen;
  final void Function(int index) onPage;
  final VoidCallback onDismiss;
  final void Function(bool over) onHover;

  static const _width = 320.0;
  static const _maxHeight = 360.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final screen = MediaQuery.sizeOf(context);
    final c = Theme.of(context).colorScheme;
    final byKey = ref.watch(_citedPapersProvider(marker)).value ?? const {};
    final items = parseCitationGroup(marker);
    final width = _width.clamp(0.0, screen.width - 24);
    final left = (anchor.left).clamp(12.0, screen.width - width - 12);
    final below =
        anchor.bottom + 8 + _maxHeight < screen.height ||
        anchor.top < _maxHeight / 2;

    final card = MouseRegion(
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: AppMotion.of(context, AppMotion.short),
        curve: AppMotion.enter,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (below ? -6 : 6) * (1 - t)),
            child: child,
          ),
        ),
        child: Material(
          color: c.surfaceContainerHigh,
          elevation: 3,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width, maxHeight: _maxHeight),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (i, key) in [
                    for (final it in items) it.key,
                  ].indexed) ...[
                    if (i > 0) const Divider(height: 20),
                    if (byKey[key] case final paper?)
                      _CitedPaperSection(
                        paper: paper,
                        item: items[i],
                        onOpen: onOpen,
                        onPage: () => onPage(i),
                      )
                    else
                      Text(
                        context.l10n.notesCitationNotInLibrary(key),
                        style: TextStyle(color: c.error),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return Stack(
      children: [
        // Anything outside the card dismisses it (a scroll is a pointer
        // down or a wheel event), without swallowing the gesture.
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => onDismiss(),
            onPointerSignal: (_) => onDismiss(),
          ),
        ),
        Positioned(
          left: left,
          top: below ? anchor.bottom + 6 : null,
          bottom: below ? null : screen.height - anchor.top + 6,
          child: card,
        ),
      ],
    );
  }
}

class _CitedPaperSection extends ConsumerWidget {
  const _CitedPaperSection({
    required this.paper,
    required this.item,
    required this.onOpen,
    required this.onPage,
  });

  final Paper paper;
  final CiteItem item;
  final void Function(String paperId) onOpen;
  final VoidCallback onPage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final highlights =
        (ref.watch(highlightsForPaperProvider(paper.id)).value ?? const [])
            .take(3);
    final authors = paper.authors.isEmpty ? '' : displayAuthors(paper.authors);
    final meta = [
      if (paper.year != null) '${paper.year}',
      if ((paper.venue ?? '').isNotEmpty) paper.venue!,
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(paper.title, style: text.titleSmall),
        if (authors.isNotEmpty)
          Text(authors, style: text.bodySmall?.copyWith(color: c.secondary)),
        if (meta.isNotEmpty)
          Text(meta, style: text.bodySmall?.copyWith(color: c.secondary)),
        for (final h in highlights)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              padding: const EdgeInsets.only(left: 8),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: c.outlineVariant, width: 2),
                ),
              ),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: h.quote),
                    TextSpan(
                      text: '  ${context.l10n.notesPageShort(h.pageNumber)}',
                      style: text.bodySmall?.copyWith(color: c.secondary),
                    ),
                  ],
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall,
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            children: [
              TextButton(
                onPressed: onPage,
                child: Text(
                  item.hasLocator
                      ? context.l10n.notesChangePage
                      : context.l10n.notesPageEllipsis,
                ),
              ),
              TextButton(
                onPressed: () => onOpen(paper.id),
                child: Text(context.l10n.notesOpenPaper),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
