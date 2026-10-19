import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../l10n/l10n.dart';

import 'spell_checker.dart';

/// Whether a misspelling the platform reported is worth showing. Skips
/// words with digits, ALL-CAPS abbreviations, identifiers (`snake_case`,
/// `@mentions`, `#tags`) and anything inside a URL.
bool keepMisspelling(String text, TextRange r) {
  if (r.start < 0 || r.end > text.length || r.isCollapsed) return false;
  final word = text.substring(r.start, r.end);
  if (word.contains(RegExp(r'[0-9_]'))) return false;
  if (word.length > 1 &&
      word == word.toUpperCase() &&
      word != word.toLowerCase()) {
    return false;
  }
  if (r.start > 0 && '@#\\/'.contains(text[r.start - 1])) return false;
  for (final m in _url.allMatches(text)) {
    if (r.start < m.end && r.end > m.start) return false;
  }
  return true;
}

final _url = RegExp(
  r'(?:[a-z][a-z0-9+.-]*://|www\.)\S+|\b[\w.-]+\.(?:com|org|net|edu|io|gov|ac\.uk)\b\S*',
  caseSensitive: false,
);

/// Spell check for one note editor: underlines (via
/// [QuillEditorConfig.textSpanBuilder]) and suggestions (via
/// [QuillEditorConfig.contextMenuBuilder]).
///
/// Results are cached per paragraph text (bounded LRU). A paragraph with no
/// cached result shows no underlines and is queued; ~[debounce] after the
/// last build asked for something new, the queue is checked in one channel
/// call and listeners are told to rebuild. Everything is a no-op while
/// [enabled] is false: no spans change and the checker is never called.
class NoteSpell extends ChangeNotifier {
  NoteSpell({
    required this.controller,
    required this.checker,
    this.debounce = const Duration(milliseconds: 400),
    this.cacheSize = 400,
  });

  final QuillController controller;
  final SpellChecker Function() checker;
  final Duration debounce;
  final int cacheSize;

  bool _enabled = false;
  bool get enabled => _enabled;
  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (!value) {
      _timer?.cancel();
      _pending.clear();
    }
  }

  final _cache = <String, List<TextRange>>{};
  final _pending = <String>{};
  final _ignored = <String>{};
  final _guessCache = <String, List<String>>{};
  Timer? _timer;
  bool _disposed = false;

  /// The text of [line] as the checker should see it: embeds (citations,
  /// maths, figure chips, sketches) become spaces, so offsets are unchanged.
  static String lineText(Line line) {
    final b = StringBuffer();
    for (final c in line.children) {
      b.write(c is QuillText ? c.value : ' ');
    }
    return b.toString();
  }

  /// Cached misspellings for [text], after ignoring; null if not checked yet
  /// (and then queued).
  List<TextRange>? _lookup(String text) {
    final hit = _cache.remove(text);
    if (hit != null) {
      _cache[text] = hit;
      if (_ignored.isEmpty) return hit;
      return [
        for (final r in hit)
          if (!_ignored.contains(text.substring(r.start, r.end).toLowerCase()))
            r,
      ];
    }
    if (text.trim().isNotEmpty && _pending.add(text) ||
        _pending.contains(text)) {
      _timer?.cancel();
      _timer = Timer(debounce, _flush);
    }
    return null;
  }

  Future<void> _flush() async {
    if (_disposed || !_enabled || _pending.isEmpty) return;
    final texts = _pending.toList();
    _pending.clear();
    final c = checker();
    if (!c.available) return;
    List<List<TextRange>> results;
    try {
      results = await c.check(texts);
    } catch (_) {
      return;
    }
    if (_disposed || !_enabled) return;
    for (var i = 0; i < texts.length; i++) {
      final ranges = i < results.length ? results[i] : const <TextRange>[];
      _cache[texts[i]] = [
        for (final r in ranges)
          if (keepMisspelling(texts[i], r)) r,
      ];
      while (_cache.length > cacheSize) {
        _cache.remove(_cache.keys.first);
      }
    }
    notifyListeners();
  }

  bool _insideCode(Node node) {
    for (Node? n = node; n != null; n = n.parent) {
      final a = n.style.attributes;
      if (a.containsKey(Attribute.codeBlock.key) ||
          a.containsKey(Attribute.inlineCode.key)) {
        return true;
      }
    }
    return false;
  }

  /// The [TextSpanBuilder] for the editor.
  InlineSpan spanBuilder(
    BuildContext context,
    Node node,
    int nodeOffset,
    String text,
    TextStyle? style,
    GestureRecognizer? recognizer,
  ) {
    InlineSpan plain() =>
        defaultSpanBuilder(context, node, nodeOffset, text, style, recognizer);
    final line = node.parent;
    if (!_enabled ||
        text.isEmpty ||
        line is! Line ||
        node.style.attributes.containsKey(Attribute.link.key) ||
        _insideCode(node)) {
      return plain();
    }
    final lineStr = lineText(line);
    final ranges = _lookup(lineStr);
    if (ranges == null || ranges.isEmpty) return plain();

    final start = node.offset + nodeOffset;
    final end = start + text.length;
    final sel = controller.selection;
    final caret = sel.isValid && sel.isCollapsed
        ? sel.baseOffset - line.documentOffset
        : -1;
    final marks = <TextRange>[
      for (final r in ranges)
        // The word being typed is left alone, as macOS does.
        if (r.end > start &&
            r.start < end &&
            !(caret >= r.start && caret <= r.end))
          TextRange(
            start: (r.start - start).clamp(0, text.length),
            end: (r.end - start).clamp(0, text.length),
          ),
    ];
    if (marks.isEmpty) return plain();

    final base = style ?? const TextStyle();
    final mark = base.copyWith(
      decoration: TextDecoration.combine([
        if (base.decoration != null && base.decoration != TextDecoration.none)
          base.decoration!,
        TextDecoration.underline,
      ]),
      decorationStyle: TextDecorationStyle.wavy,
      decorationColor: Theme.of(context).colorScheme.error,
    );
    MouseCursor? cursor = recognizer != null ? SystemMouseCursors.click : null;
    TextSpan piece(int a, int b, TextStyle? s) => TextSpan(
      text: text.substring(a, b),
      style: s,
      recognizer: recognizer,
      mouseCursor: cursor,
    );
    final children = <InlineSpan>[];
    var at = 0;
    for (final m in marks) {
      if (m.start > at) children.add(piece(at, m.start, null));
      children.add(piece(m.start, m.end, mark));
      at = m.end;
    }
    if (at < text.length) children.add(piece(at, text.length, null));
    return TextSpan(style: style, children: children);
  }

  /// The misspelling under the selection, if any: its text and document
  /// range.
  ({String word, int docStart, int length})? misspellingAtSelection() {
    final sel = controller.selection;
    if (!_enabled || !sel.isValid) return null;
    final line = _lineAt(sel.start);
    if (line == null) return null;
    final ranges = _lookup(lineText(line));
    if (ranges == null) return null;
    final a = sel.start - line.documentOffset;
    final b = sel.end - line.documentOffset;
    final text = lineText(line);
    for (final r in ranges) {
      if (a >= r.start && b <= r.end) {
        return (
          word: text.substring(r.start, r.end),
          docStart: line.documentOffset + r.start,
          length: r.end - r.start,
        );
      }
    }
    return null;
  }

  Line? _lineAt(int offset) {
    final len = controller.document.length;
    if (offset < 0 || offset >= len) return null;
    final n = controller.document.queryChild(offset).node;
    return n is Line ? n : null;
  }

  Future<List<String>> guessesFor(String word) async {
    final hit = _guessCache[word];
    if (hit != null) return hit;
    final g = await checker().guesses(word);
    return _guessCache[word] = g.take(5).toList();
  }

  /// One undoable edit.
  void replaceWord(({String word, int docStart, int length}) m, String with_) {
    controller.replaceText(
      m.docStart,
      m.length,
      with_,
      TextSelection.collapsed(offset: m.docStart + with_.length),
    );
  }

  Future<void> learn(String word) async {
    await checker().learn(word);
    _cache.clear();
    _guessCache.clear();
    notifyListeners();
  }

  void ignore(String word) {
    _ignored.add(word.toLowerCase());
    notifyListeners();
  }

  /// The [QuillEditorContextMenuBuilder]: suggestions on top when the
  /// selection is on a misspelled word, then the editor's normal items.
  Widget contextMenu(BuildContext context, QuillRawEditorState state) {
    final m = misspellingAtSelection();
    if (m == null) {
      return QuillRawEditorConfig.defaultContextMenuBuilder(context, state);
    }
    return _SpellMenu(spell: this, state: state, miss: m);
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

class _SpellMenu extends StatefulWidget {
  const _SpellMenu({
    required this.spell,
    required this.state,
    required this.miss,
  });

  final NoteSpell spell;
  final QuillRawEditorState state;
  final ({String word, int docStart, int length}) miss;

  @override
  State<_SpellMenu> createState() => _SpellMenuState();
}

class _SpellMenuState extends State<_SpellMenu> {
  List<String> _guesses = const [];

  @override
  void initState() {
    super.initState();
    widget.spell.guessesFor(widget.miss.word).then((g) {
      if (mounted) setState(() => _guesses = g);
    });
  }

  @override
  Widget build(BuildContext context) {
    final spell = widget.spell;
    final miss = widget.miss;
    void done() => widget.state.hideToolbar();
    final items = <ContextMenuButtonItem>[
      for (final g in _guesses)
        ContextMenuButtonItem(
          label: g,
          onPressed: () {
            spell.replaceWord(miss, g);
            done();
          },
        ),
      ContextMenuButtonItem(
        label: context.l10n.spellLearn,
        onPressed: () {
          spell.learn(miss.word);
          done();
        },
      ),
      ContextMenuButtonItem(
        label: context.l10n.spellIgnore,
        onPressed: () {
          spell.ignore(miss.word);
          done();
        },
      ),
      ...widget.state.contextMenuButtonItems,
    ];
    return TextFieldTapRegion(
      child: AdaptiveTextSelectionToolbar.buttonItems(
        buttonItems: items,
        anchors: widget.state.contextMenuAnchors,
      ),
    );
  }
}
