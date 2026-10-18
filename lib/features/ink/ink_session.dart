import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';

import '../../theme/app_theme.dart';
import '../../theme/haptics.dart';
import '../platform/mac_window.dart' show isDesktop;
import 'ink_canvas.dart';
import 'ink_model.dart';
import 'ink_tools.dart';
import 'pencil_taps.dart';
import 'sketch_editor_screen.dart';

/// Quill embed type for a drawing inside a note. The embed's data is the
/// encoded [Sketch], so drawings live in the note's content and sync, copy
/// and version with the text around them.
const sketchEmbedType = 'sketch';

/// `const Sketch().encode()`, as a compile-time constant (checked by a test).
@visibleForTesting
const emptySketchData = '{"v":1,"a":0.6,"s":[]}';

/// The height of a drawing made with the Draw button, as a fraction of its
/// width: a few lines' worth, growing as you write near its end.
const newDrawingAspect = 0.35;

/// A drawing shown inline in the note, as the [InkCatcher] needs to see it:
/// where it is on screen and what it holds.
abstract class InlineDrawing {
  int get offset;
  Sketch get sketch;
  Rect? get globalRect;
}

/// Pen input for one open note, like Apple Notes: drawings sit inline among
/// the text and are drawn on in place. A pen draws on any drawing, and
/// writing anywhere else in the note opens a new one there; a finger or
/// mouse draws on the drawing that is *chosen* (tapped, or just drawn on),
/// which also shows the floating tools. Every stroke is written straight
/// into the note's document — one Quill edit, so ⌘Z and the editor's undo
/// take strokes back like typing.
class InkSession extends InkTools {
  InkSession({required this.controller, this.onInkStart, this.onQuietEdit}) {
    _pencilTaps = PencilTaps.instance.doubleTaps.listen((action) {
      if (action != PencilAction.ignore) AppHaptics.selection();
      applyPencilTap(action);
    });
  }

  final QuillController controller;

  /// Called as a stroke begins: the editor hides the keyboard.
  VoidCallback? onInkStart;

  /// Called after each pen edit. Pen edits tell Quill to leave focus and
  /// the keyboard alone, and on that path Quill doesn't rebuild the editor
  /// — the owner must (`setState`), or new ink and new drawings stay
  /// invisible until something else redraws the note.
  VoidCallback? onQuietEdit;

  StreamSubscription<PencilAction>? _pencilTaps;
  int? _active;
  final drawings = <InlineDrawing>{};

  /// The document offset of the chosen drawing, if any.
  int? get active => _active;

  bool isActive(int offset) => _active == offset;

  /// Redraws everything showing this session (after a policy change).
  void refresh() => notifyListeners();

  @override
  void dispose() {
    _pencilTaps?.cancel();
    super.dispose();
  }

  /// Chooses the drawing at [offset] (showing the tools). The previously
  /// chosen one is removed if nothing was drawn in it.
  void activate(int offset) {
    if (_active == offset) return;
    final previous = _active;
    _active = offset;
    if (previous != null && _removeIfEmpty(previous) && previous < offset) {
      _active = offset - 1;
    }
    notifyListeners();
  }

  /// Puts the tools away (tapping into the text, Done). A drawing left
  /// empty — Draw tapped by mistake — leaves no trace.
  void deactivate() {
    final previous = _active;
    if (previous == null) return;
    _active = null;
    _removeIfEmpty(previous);
    notifyListeners();
  }

  /// Writes [sketch] into the drawing at [offset]. False (nothing written)
  /// if no drawing is there any more — the note changed meanwhile.
  bool write(int offset, Sketch sketch) {
    if (sketchOffsetNear(controller.document, offset) != offset) return false;
    controller.replaceText(
      offset,
      1,
      CustomBlockEmbed(sketchEmbedType, sketch.encode()),
      null,
      ignoreFocus: true,
    );
    onQuietEdit?.call();
    return true;
  }

  /// Inserts a drawing holding [sketch] at [index] on a line of its own
  /// (splitting the line there if needed) and chooses it. Returns where it
  /// landed.
  int? insertDrawing(int index, Sketch sketch) {
    final doc = controller.document;
    final at = index.clamp(0, doc.length - 1);
    // Offsets match: an embed is one character in the plain text.
    final plain = doc.toPlainText();
    final lineStart = at == 0 || plain[at - 1] == '\n';
    final lineEnd = plain[at] == '\n';
    // Quill only adds the newlines around a block embed for videos, so a
    // drawing gets them here: alone on its line, the text around it on
    // lines of their own.
    final delta = Delta()..retain(at);
    if (!lineStart) delta.insert('\n');
    delta.insert(CustomBlockEmbed(sketchEmbedType, sketch.encode()).toJson());
    if (!lineEnd) delta.insert('\n');
    final added = delta.length - at;
    final sel = controller.selection;
    TextSelection shifted(TextSelection s) => s.copyWith(
      baseOffset: s.baseOffset >= at ? s.baseOffset + added : s.baseOffset,
      extentOffset: s.extentOffset >= at
          ? s.extentOffset + added
          : s.extentOffset,
    );
    controller.ignoreFocusOnTextChange = true;
    try {
      controller.compose(
        delta,
        sel.isValid ? shifted(sel) : const TextSelection.collapsed(offset: 0),
        ChangeSource.local,
      );
    } finally {
      controller.ignoreFocusOnTextChange = false;
    }
    onQuietEdit?.call();
    final landed = sketchOffsetNear(
      controller.document,
      lineStart ? at : at + 1,
    );
    if (landed != null) activate(landed);
    return landed;
  }

  /// The Draw button (and `/` → Draw): a new, empty drawing at the cursor,
  /// chosen so a finger or mouse can draw in it straight away.
  void insertAtCursor() {
    final doc = controller.document;
    final cursor = controller.selection.baseOffset;
    final index = cursor < 0 || cursor > doc.length - 1
        ? doc.length - 1
        : cursor;
    insertDrawing(index, const Sketch(aspect: newDrawingAspect));
  }

  /// Opens the chosen drawing full screen ("Expand"), for a big diagram on
  /// a small screen; the result is written back.
  Future<void> expand(BuildContext context) async {
    final offset = _active;
    if (offset == null) return;
    final sketch = sketchAt(controller.document, offset);
    if (sketch == null) return;
    final edited = await Navigator.of(context).push<Sketch>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => SketchEditorScreen(initial: sketch, tools: this),
      ),
    );
    if (edited != null) write(offset, edited);
  }

  bool _removeIfEmpty(int offset) {
    if (sketchOffsetNear(controller.document, offset) != offset) return false;
    if (!(sketchAt(controller.document, offset)?.isEmpty ?? false)) {
      return false;
    }
    // Take its line with it (the newline after it), so no blank line is
    // left where it was.
    final plain = controller.document.toPlainText();
    final ownLine = offset + 1 < plain.length - 1 && plain[offset + 1] == '\n';
    controller.replaceText(
      offset,
      ownLine ? 2 : 1,
      '',
      null,
      ignoreFocus: true,
    );
    onQuietEdit?.call();
    return true;
  }
}

/// The offset of a sketch embed at or right after [offset], if any (mid-line,
/// Quill first splits the line, so an embed can land one position later
/// than asked).
int? sketchOffsetNear(Document doc, int offset) {
  for (final candidate in [offset, offset + 1]) {
    if (candidate < 0 || candidate >= doc.length) continue;
    final leaf = doc.querySegmentLeafNode(candidate).leaf;
    if (leaf is Embed &&
        leaf.value.type == sketchEmbedType &&
        leaf.documentOffset == candidate) {
      return candidate;
    }
  }
  return null;
}

/// The drawing at exactly [offset], if one is there.
Sketch? sketchAt(Document doc, int offset) {
  if (offset < 0 || offset >= doc.length) return null;
  final leaf = doc.querySegmentLeafNode(offset).leaf;
  if (leaf is! Embed || leaf.value.type != sketchEmbedType) return null;
  if (leaf.documentOffset != offset) return null;
  return Sketch.decode(leaf.value.data as String);
}

/// Makes a note's [InkSession] available to its inline drawings.
class InkSessionScope extends InheritedNotifier<InkSession> {
  const InkSessionScope({
    super.key,
    required InkSession session,
    required super.child,
  }) : super(notifier: session);

  static InkSession? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<InkSessionScope>()?.notifier;
}

/// The floating tools while a drawing is chosen: pen, highlighter, eraser,
/// inks and thickness, then undo / redo (the note's own history), the
/// finger switch on touch screens, Expand and Done. Nothing while no
/// drawing is chosen.
class InlineInkToolbar extends StatelessWidget {
  const InlineInkToolbar({super.key, required this.session});

  final InkSession session;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([session, session.controller]),
      builder: (context, _) {
        final show = session.active != null;
        final controller = session.controller;
        final desktop = isDesktop(context);
        final fingersDraw = inkPolicy.fingersDraw;
        return AnimatedSwitcher(
          duration: AppMotion.of(context, AppMotion.short),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.3),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: !show
              ? const SizedBox.shrink()
              : InkPalette(
                  key: const ValueKey('inline-ink-toolbar'),
                  tools: session,
                  trailing: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.undo),
                      tooltip: 'Undo',
                      onPressed: controller.hasUndo ? controller.undo : null,
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.redo),
                      tooltip: 'Redo',
                      onPressed: controller.hasRedo ? controller.redo : null,
                    ),
                  ],
                  // Kept in reach on a phone, where the rest scrolls.
                  end: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PopupMenuButton<String>(
                        tooltip: 'More drawing options',
                        icon: const Icon(Icons.more_horiz),
                        onSelected: (v) {
                          switch (v) {
                            case 'expand':
                              session.expand(context);
                            case 'fingers':
                              inkPolicy.fingerDrawsOverride = !fingersDraw;
                              session.refresh();
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'expand',
                            child: ListTile(
                              leading: Icon(Icons.open_in_full),
                              title: Text('Expand'),
                            ),
                          ),
                          if (!desktop)
                            PopupMenuItem(
                              value: 'fingers',
                              child: ListTile(
                                leading: Icon(
                                  fingersDraw
                                      ? Icons.pan_tool_outlined
                                      : Icons.gesture,
                                ),
                                title: Text(
                                  fingersDraw
                                      ? 'Scroll with fingers'
                                      : 'Draw with fingers',
                                ),
                              ),
                            ),
                        ],
                      ),
                      FilledButton.tonal(
                        onPressed: session.deactivate,
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}
