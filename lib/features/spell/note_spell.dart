import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../l10n/l10n.dart';

import 'spell_checker.dart';

/// Whether a misspelling the platform reported is worth showing. Grammar
/// issues are kept unless they touch a URL. Misspellings skip words with
/// digits, ALL-CAPS abbreviations, identifiers (`snake_case`,
/// `@mentions`, `#tags`) and anything inside a URL.
bool keepMisspelling(String text, TextRange r) {
  if (r.start < 0 || r.end > text.length || r.isCollapsed) return false;
  if (r is SpellIssue && r.grammar) {
    // Grammar spans words; only a URL inside it disqualifies it.
    return !_url
        .allMatches(text)
        .any((m) => r.start < m.end && r.end > m.start);
  }
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

/// A flagged range under the selection: its text, where it is in the
/// document and in its paragraph, and the checker's detail if any.
typedef Misspelling = ({
  String word,
  int docStart,
  int length,
  String lineText,
  int lineStart,
  SpellIssue? issue,
});

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
    final marks = <(TextRange, bool)>[
      for (final r in ranges)
        // The word being typed is left alone, as macOS does.
        if (r.end > start &&
            r.start < end &&
            !(caret >= r.start && caret <= r.end))
          (
            TextRange(
              start: (r.start - start).clamp(0, text.length),
              end: (r.end - start).clamp(0, text.length),
            ),
            r is SpellIssue && r.grammar,
          ),
    ];
    // Overlaps (a misspelling inside a grammar issue) keep the first.
    marks.sort((a, b) => a.$1.start.compareTo(b.$1.start));
    for (var i = 1; i < marks.length; i++) {
      if (marks[i].$1.start < marks[i - 1].$1.end) marks.removeAt(i--);
    }
    if (marks.isEmpty) return plain();

    final base = style ?? const TextStyle();
    final scheme = Theme.of(context).colorScheme;
    TextStyle underline(bool grammar) => base.copyWith(
      decoration: TextDecoration.combine([
        if (base.decoration != null && base.decoration != TextDecoration.none)
          base.decoration!,
        TextDecoration.underline,
      ]),
      // Misspellings wavy red, grammar dotted in the accent, like macOS's
      // two kinds of marks.
      decorationStyle: grammar
          ? TextDecorationStyle.dotted
          : TextDecorationStyle.wavy,
      decorationColor: grammar ? scheme.primary : scheme.error,
    );
    final spellingMark = underline(false);
    final grammarMark = underline(true);
    MouseCursor? cursor = recognizer != null ? SystemMouseCursors.click : null;
    TextSpan piece(int a, int b, TextStyle? s) => TextSpan(
      text: text.substring(a, b),
      style: s,
      recognizer: recognizer,
      mouseCursor: cursor,
    );
    final children = <InlineSpan>[];
    var at = 0;
    for (final (m, grammar) in marks) {
      if (m.start > at) children.add(piece(at, m.start, null));
      children.add(piece(m.start, m.end, grammar ? grammarMark : spellingMark));
      at = m.end;
    }
    if (at < text.length) children.add(piece(at, text.length, null));
    return TextSpan(style: style, children: children);
  }

  /// The misspelling under the selection, if any: its text and document
  /// range.
  Misspelling? misspellingAtSelection() {
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
          lineText: text,
          lineStart: r.start,
          issue: r is SpellIssue ? r : null,
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

  /// Suggestions for [m], best first: a grammar issue's own corrections,
  /// else the checker's guesses for the word in its paragraph (context
  /// ranks them and picks the paragraph's language).
  Future<List<String>> guessesFor(Misspelling m) async {
    final grammar = m.issue?.grammar ?? false;
    if (grammar) return m.issue!.corrections.take(5).toList();
    final key = '${m.word}\u0000${m.lineText}';
    final hit = _guessCache[key];
    if (hit != null) return hit;
    final g = await checker().guesses(
      m.word,
      text: m.lineText,
      start: m.lineStart,
    );
    while (_guessCache.length > 100) {
      _guessCache.remove(_guessCache.keys.first);
    }
    return _guessCache[key] = g.take(5).toList();
  }

  /// One undoable edit.
  void replaceWord(Misspelling m, String with_) {
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

  /// Ignores [m] in every note until the app quits. Misspellings also go to
  /// the platform's ignore list, so its later checks skip them too.
  void ignore(Misspelling m) {
    _ignored.add(m.word.toLowerCase());
    if (!(m.issue?.grammar ?? false)) unawaited(checker().ignore(m.word));
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
  final Misspelling miss;

  @override
  State<_SpellMenu> createState() => _SpellMenuState();
}

class _SpellMenuState extends State<_SpellMenu> {
  List<String> _guesses = const [];

  @override
  void initState() {
    super.initState();
    widget.spell.guessesFor(widget.miss).then((g) {
      if (mounted) setState(() => _guesses = g);
    });
  }

  @override
  Widget build(BuildContext context) {
    final spell = widget.spell;
    final miss = widget.miss;
    void done() => widget.state.hideToolbar();
    final grammar = miss.issue?.grammar ?? false;
    final message = miss.issue?.message;
    final items = <ContextMenuButtonItem>[
      // The checker's explanation, as macOS shows it; not a button.
      if (grammar && message != null && message.isNotEmpty)
        ContextMenuButtonItem(label: message, onPressed: null),
      for (final g in _guesses)
        ContextMenuButtonItem(
          label: g,
          onPressed: () {
            spell.replaceWord(miss, g);
            done();
          },
        ),
      if (!grammar)
        ContextMenuButtonItem(
          label: context.l10n.spellLearn,
          onPressed: () {
            spell.learn(miss.word);
            done();
          },
        ),
      ContextMenuButtonItem(
        label: grammar
            ? context.l10n.spellIgnoreGrammar
            : context.l10n.spellIgnore,
        onPressed: () {
          spell.ignore(miss);
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
