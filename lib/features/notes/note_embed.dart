import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../ink/sketch_embed.dart';
import '../lock/note_lock_service.dart';
import '../projects/readable_content.dart';
import '../home/adaptive.dart';
import 'block_ids.dart';
import 'callout_embed.dart';
import 'citation_embed.dart';
import 'editor_document.dart';
import 'figure_embed.dart';
import 'footnote_embed.dart';
import 'math_embed.dart';
import 'note_highlight.dart' show noteStyleFor;
import 'note_link_open.dart';
import 'note_links.dart';
import 'note_sections.dart';
import 'notes_providers.dart';
import 'table_embed.dart';

/// Another note shown inside a note (`![[Note]]`, `![[Note#Heading]]`,
/// `![[Note#^id]]`): a read-only card with the note — or just the section or
/// paragraph — that follows the target live. See [noteEmbedType] for how it
/// is stored.
class NoteEmbedBuilder extends EmbedBuilder {
  /// [nested]: this card is itself inside an embedded note, so it shows
  /// only the target's title (no recursion).
  const NoteEmbedBuilder({this.nested = false});

  final bool nested;

  @override
  String get key => noteEmbedType;

  @override
  bool get expanded => true;

  @override
  String toPlainText(Embed node) => '';

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final link = noteEmbedLink(embedContext.node.value.data as String);
    final target = link == null ? null : parseNoteLinkTarget(link);
    if (target == null) return const SizedBox.shrink();
    return NoteEmbedCard(target: target, nested: nested);
  }
}

/// What the cards inside a card use to draw an embedded note's content.
List<EmbedBuilder> _innerBuilders() => const [
  FigureDefEmbedBuilder(),
  FigureRefEmbedBuilder(),
  SketchEmbedBuilder(),
  TableEmbedBuilder(),
  CitationEmbedBuilder(),
  MathInlineEmbedBuilder(),
  MathBlockEmbedBuilder(),
  FootnoteEmbedBuilder(),
  CalloutEmbedBuilder(),
  BlockIdEmbedBuilder(),
  NoteEmbedBuilder(nested: true),
];

/// Embeds taller than this many lines or characters are cut off with
/// "Show all".
const _cardMaxHeight = 220.0;
const _cardLineLimit = 9;
const _cardCharLimit = 600;

class NoteEmbedCard extends ConsumerStatefulWidget {
  const NoteEmbedCard({super.key, required this.target, this.nested = false});

  final NoteLinkTarget target;
  final bool nested;

  @override
  ConsumerState<NoteEmbedCard> createState() => _NoteEmbedCardState();
}

class _NoteEmbedCardState extends ConsumerState<NoteEmbedCard> {
  QuillController? _controller;
  final _focus = FocusNode(skipTraversal: true, canRequestFocus: false);
  final _scroll = ScrollController();
  String? _shownKey;
  bool _expanded = false;
  bool _needsCap = false;
  bool _empty = false;
  bool _sectionMissing = false;

  // Decrypted body of a locked target we can read, with the envelope it
  // came from.
  String? _plainFor;
  String? _plain;
  Future<void>? _decrypting;

  @override
  void dispose() {
    _controller?.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Rebuilds the read-only controller when the section's text changed.
  void _show(String body) {
    final key = '${widget.target}\n$body';
    if (key == _shownKey) return;
    _shownKey = key;
    final section = sectionOf(editorDocument(body).toDelta(), widget.target);
    _controller?.dispose();
    _controller = null;
    _sectionMissing = section == null;
    if (section == null) {
      _empty = false;
      _needsCap = false;
      return;
    }
    final lines = docLines(section);
    final chars = lines.fold<int>(0, (a, l) => a + l.length);
    _empty = lines.every((l) => !l.hasText && l.length == 0);
    _needsCap = lines.length > _cardLineLimit || chars > _cardCharLimit;
    final doc = Document.fromDelta(section);
    _controller = QuillController(
      document: doc,
      selection: const TextSelection.collapsed(offset: 0),
      readOnly: true,
    );
  }

  void _openTarget() {
    if (widget.target.heading != null || widget.target.block != null) {
      unawaited(openNoteLink(context, ref, widget.target));
    } else {
      openNote(context, ref, widget.target.noteId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.target;
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    final l10n = context.l10n;
    final note = ref.watch(noteByIdProvider(target.noteId));
    // Rebuild when notes lock or unlock.
    final lock = ref.watch(noteLockServiceProvider);

    Widget frame(Widget header, [Widget? body]) => Semantics(
      container: true,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: c.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(color: c.primary.withValues(alpha: 0.5), width: 3),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [header, ?body],
        ),
      ),
    );

    Widget titleRow(String title, {String? trailing, Color? tone}) {
      final label = Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelLarge?.copyWith(
          color: tone ?? c.primary,
          fontWeight: FontWeight.w600,
        ),
      );
      return Semantics(
        button: true,
        label: l10n.linksEmbedOpen(title),
        child: InkWell(
          onTap: _openTarget,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(
                  Icons.subdirectory_arrow_right,
                  size: 16,
                  color: tone ?? c.primary,
                ),
                const SizedBox(width: 6),
                Expanded(child: label),
                if (trailing != null)
                  Text(
                    trailing,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tone ?? c.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return note.when(
      loading: () => const SizedBox(height: 40),
      error: (_, _) => frame(
        Text(
          l10n.linksEmbedMissing,
          style: theme.textTheme.bodySmall?.copyWith(color: c.error),
        ),
      ),
      data: (n) {
        if (n == null) {
          return frame(
            Text(
              l10n.linksEmbedMissing,
              style: theme.textTheme.bodyMedium?.copyWith(color: c.error),
            ),
          );
        }
        final base = n.title.trim().isEmpty
            ? l10n.commonUntitled
            : n.title.trim();
        final part = target.heading;
        final title = part == null ? base : '$base › $part';
        if (widget.nested) return frame(titleRow(title));

        String? body;
        if (isLockedContent(n.content)) {
          if (!lock.canRead(n.content)) {
            return frame(
              titleRow(
                title,
                trailing: l10n.linksEmbedLocked,
                tone: c.onSurfaceVariant,
              ),
            );
          }
          if (_plainFor == n.content) {
            body = _plain;
          } else {
            _decrypting ??= () async {
              final text = await readableNoteContent(lock, n.id, n.content);
              if (!mounted) return;
              setState(() {
                _plainFor = n.content;
                _plain = text;
                _decrypting = null;
              });
            }();
            return frame(titleRow(title));
          }
          if (body == null) {
            return frame(
              titleRow(
                title,
                trailing: l10n.linksEmbedLocked,
                tone: c.onSurfaceVariant,
              ),
            );
          }
        } else {
          body = n.content;
        }
        _show(body);
        if (_sectionMissing) {
          return frame(
            titleRow(title),
            Text(
              l10n.linksEmbedSectionMissing,
              style: theme.textTheme.bodySmall?.copyWith(color: c.error),
            ),
          );
        }
        if (_empty) {
          return frame(
            titleRow(title),
            Text(
              l10n.linksEmbedEmpty,
              style: theme.textTheme.bodySmall?.copyWith(
                color: c.onSurfaceVariant,
              ),
            ),
          );
        }
        final capped = _needsCap && !_expanded;
        final editor = QuillEditor.basic(
          controller: _controller!,
          focusNode: _focus,
          scrollController: _scroll,
          config: QuillEditorConfig(
            scrollable: false,
            padding: EdgeInsets.zero,
            showCursor: false,
            enableInteractiveSelection: false,
            enableSelectionToolbar: false,
            customStyleBuilder: noteStyleFor,
            embedBuilders: _innerBuilders(),
            unknownEmbedBuilder: const _QuietEmbedBuilder(),
            customRecognizerBuilder: (attribute, leaf) {
              if (attribute.key != Attribute.link.key) return null;
              final link = attribute.value?.toString() ?? '';
              if (parseNoteLinkTarget(link) case final t?) {
                return TapGestureRecognizer()
                  ..onTap = () => unawaited(openNoteLink(context, ref, t));
              }
              return null;
            },
          ),
        );
        return frame(
          titleRow(title),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (capped)
                  Stack(
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxHeight: _cardMaxHeight,
                        ),
                        child: ClipRect(
                          child: SingleChildScrollView(
                            physics: const NeverScrollableScrollPhysics(),
                            child: editor,
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 36,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  c.surfaceContainerLow.withValues(alpha: 0),
                                  c.surfaceContainerLow,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  editor,
                if (_needsCap)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => setState(() => _expanded = !_expanded),
                      child: Text(
                        _expanded
                            ? l10n.linksEmbedShowLess
                            : l10n.linksEmbedShowAll,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// An embed type this card doesn't know draws nothing rather than failing.
class _QuietEmbedBuilder extends EmbedBuilder {
  const _QuietEmbedBuilder();

  @override
  String get key => 'unknown';

  @override
  bool get expanded => false;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) =>
      const SizedBox.shrink();
}

/// Inserts an embed of [link] on a line of its own at the cursor — newlines
/// are added around it only where needed (Quill adds them for videos alone).
void insertNoteEmbed(QuillController controller, String link) {
  final doc = controller.document;
  final cursor = controller.selection.baseOffset;
  final at = (cursor < 0 || cursor > doc.length - 1 ? doc.length - 1 : cursor)
      .clamp(0, doc.length - 1);
  final plain = doc.toPlainText();
  final lineStart = at == 0 || plain[at - 1] == '\n';
  final lineEnd = at >= plain.length || plain[at] == '\n';
  final delta = Delta()..retain(at);
  if (!lineStart) delta.insert('\n');
  delta.insert(CustomBlockEmbed(noteEmbedType, noteEmbedData(link)).toJson());
  if (!lineEnd) delta.insert('\n');
  // An embed at the very end gets a line after it to type on.
  if (lineEnd && at == doc.length - 1) delta.insert('\n');
  final landed = at + (lineStart ? 0 : 1) + 2;
  controller.ignoreFocusOnTextChange = true;
  try {
    controller.compose(
      delta,
      const TextSelection.collapsed(offset: 0),
      ChangeSource.local,
    );
  } finally {
    controller.ignoreFocusOnTextChange = false;
  }
  controller.updateSelection(
    TextSelection.collapsed(
      offset: landed.clamp(0, controller.document.length - 1),
    ),
    ChangeSource.local,
  );
}
