import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show TextSelection;
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'heading_fold.dart';

/// A heading as the editor shows it.
class LiveHeading {
  const LiveHeading({
    required this.line,
    required this.offset,
    required this.length,
    required this.level,
    required this.folded,
  });

  /// Index among the editor's lines.
  final int line;

  /// Where the heading line starts in the editor's document.
  final int offset;

  /// Characters in the line, newline included.
  final int length;
  final int level;

  /// Collapsed: the line under it is a fold.
  final bool folded;
}

/// Which headings are collapsed, per device and per note, kept as opaque
/// fingerprints in shared_preferences (never synced, and never heading text:
/// a locked note's headings must not sit there in the clear).
class FoldStore {
  const FoldStore();

  static String _key(String noteId) => 'notes.folds.$noteId';

  Future<Set<String>> load(String noteId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_key(noteId)) ?? const []).toSet();
    } catch (_) {
      return const {};
    }
  }

  Future<void> save(String noteId, Set<String> keys) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (keys.isEmpty) {
        await prefs.remove(_key(noteId));
      } else {
        await prefs.setStringList(_key(noteId), keys.toList()..sort());
      }
    } catch (_) {}
  }
}

/// Collapses and expands the sections of the open note's [QuillController]
/// (see `heading_fold.dart` for the model).
///
/// Folding is not an edit: it is composed with the history switched off
/// (and the history's stacks moved over it, as for a remote change), under
/// `ChangeSource.silent`, and it leaves the *stored* note byte-for-byte as
/// it was, so the editor's saved/echo comparisons see no change.
class HeadingFolds extends ChangeNotifier {
  HeadingFolds({required this.noteId, this.store = const FoldStore()});

  final String noteId;
  final FoldStore store;

  QuillController? _controller;
  List<FoldLine>? _lines;
  bool _applying = false;
  Set<String>? _persisted;

  /// The reader has folded or opened something themselves.
  bool touched = false;

  @override
  void dispose() {
    _controller = null;
    _pending.clear();
    super.dispose();
  }

  void attach(QuillController controller) {
    _controller = controller;
    _lines = null;
  }

  QuillController get _c => _controller!;

  List<Operation>? _ops;

  /// The editor's lines. Parsed again only when the document's operations
  /// differ from the ones last parsed (changes reach listeners after the
  /// fact, so an invalidation flag alone could be stale).
  List<FoldLine> get lines {
    final delta = _c.document.toDelta();
    final ops = delta.toList();
    final cached = _lines;
    final seen = _ops;
    if (cached != null && seen != null && seen.length == ops.length) {
      var same = true;
      for (var i = 0; i < ops.length && same; i++) {
        same = identical(ops[i], seen[i]) || ops[i] == seen[i];
      }
      if (same) return cached;
    }
    _ops = ops;
    return _lines = parseFoldLines(delta);
  }

  bool get hasFolds => lines.any((l) => l.isFold);

  /// The editor's headings that can fold or are folded.
  List<LiveHeading> headings() {
    final ls = lines;
    final out = <LiveHeading>[];
    var at = 0;
    for (var i = 0; i < ls.length; i++) {
      final l = ls[i];
      final level = l.isRoot ? (l.header ?? 7) : null;
      if (level != null) {
        final folded = i + 1 < ls.length && ls[i + 1].isFold;
        if (folded || canCollapse(ls, i)) {
          out.add(
            LiveHeading(
              line: i,
              offset: at,
              length: l.length,
              level: level,
              folded: folded,
            ),
          );
        }
      }
      at += l.length;
    }
    return out;
  }

  // ---- Changing the document ----

  void documentChanged() {
    _lines = null;
  }

  /// Puts the document into the shape [next], outside the undo history.
  void _apply(List<FoldLine> next, {int? selectionAt, bool byUser = true}) {
    if (byUser) touched = true;
    final change = lineReplacement(lines, next);
    if (change.isEmpty) return;
    final doc = _c.document;
    final selection = _c.selection;
    _applying = true;
    doc.history.ignoreChange = true;
    try {
      _c.compose(change, selection, ChangeSource.silent);
    } finally {
      doc.history.ignoreChange = false;
      _applying = false;
    }
    doc.history.transform(change);
    _lines = null;
    if (selectionAt != null) {
      final max = doc.length - 1;
      _c.updateSelection(
        TextSelection.collapsed(offset: selectionAt.clamp(0, max)),
        ChangeSource.silent,
      );
    }
    notifyListeners();
  }

  /// Collapses the section under the heading on line [i], or expands it.
  void toggleHeading(int i) {
    final ls = lines;
    if (i < 0 || i >= ls.length) return;
    if (i + 1 < ls.length && ls[i + 1].isFold) {
      _apply(expandLine(ls, i + 1)!);
      unawaited(persist());
      return;
    }
    final next = collapseLine(ls, i);
    if (next == null) return;
    // A caret inside the hidden lines goes to the end of the heading.
    var start = 0;
    for (var k = 0; k <= i; k++) {
      start += ls[k].length;
    }
    var end = start;
    for (var k = i + 1; k < sectionEnd(ls, i); k++) {
      end += ls[k].length;
    }
    final sel = _c.selection;
    final inside =
        sel.isValid &&
        ((sel.start >= start && sel.start < end) ||
            (sel.end > start && sel.end <= end));
    _apply(next, selectionAt: inside ? start - 1 : null);
    unawaited(persist());
  }

  /// Expands the fold whose embed is at [offset].
  void expandFoldAt(int offset) {
    final ls = lines;
    var at = 0;
    for (var i = 0; i < ls.length; i++) {
      if (offset < at + ls[i].length) {
        if (ls[i].isFold) {
          _apply(expandLine(ls, i)!);
          unawaited(persist());
        }
        return;
      }
      at += ls[i].length;
    }
  }

  void collapseAll() {
    final full = expandLines(lines);
    final keys = {
      for (final h in headingsOf(full))
        foldFingerprint(noteId, h.text, h.occurrence),
    };
    _apply(applyFoldKeys(full, keys, noteId));
    unawaited(persist());
  }

  void expandAll() {
    if (!hasFolds) return;
    _apply(expandLines(lines));
    unawaited(persist());
  }

  /// Collapses exactly the sections named by [keys] (fingerprints), except
  /// the one holding [protectOffset] (an offset in the unfolded note) and,
  /// with [protectTail], those that run to the end of the note.
  void applyKeys(
    Set<String> keys, {
    int? protectOffset,
    bool protectTail = false,
  }) {
    final full = expandLines(lines);
    _apply(
      byUser: false,
      applyFoldKeys(
        full,
        keys,
        noteId,
        protectOffset: protectOffset,
        protectTail: protectTail,
      ),
    );
  }

  // ---- Reading the whole note ----

  /// The note with every fold expanded, as the editor would hold it.
  Document unfoldedDocument() => hasFolds
      ? Document.fromDelta(unfoldDelta(_c.document.toDelta()))
      : _c.document;

  String unfoldedText() => unfoldedDocument().toPlainText();

  /// Fingerprints of the collapsed headings.
  Set<String> collapsedKeys() =>
      hasFolds ? collapsedFingerprints(_c.document.toDelta(), noteId) : {};

  /// Where an offset in the unfolded note sits in the editor, expanding
  /// the folds that hide it first.
  int reveal(int unfolded) {
    for (var guard = 0; guard < 64; guard++) {
      final ls = lines;
      var live = 0;
      var u = 0;
      var expanded = false;
      for (var i = 0; i < ls.length; i++) {
        final l = ls[i];
        if (l.isFold) {
          final hidden = foldUnfoldedLength(l);
          if (unfolded < u + hidden) {
            _apply(expandLine(ls, i)!);
            expanded = true;
            break;
          }
          u += hidden;
          live += l.length;
        } else {
          if (unfolded < u + l.length) return live + (unfolded - u);
          u += l.length;
          live += l.length;
        }
      }
      if (!expanded) return live;
    }
    return _c.document.length - 1;
  }

  /// The unfolded-note offset of an editor offset (a fold counts as where
  /// its hidden lines start).
  int unfoldedOffset(int live) {
    var at = 0;
    var u = 0;
    for (final l in lines) {
      if (live < at + l.length) {
        return l.isFold ? u : u + (live - at);
      }
      at += l.length;
      u += l.isFold ? foldUnfoldedLength(l) : l.length;
    }
    return u;
  }

  // ---- Remembering ----

  /// Writes which headings are collapsed, if that changed.
  Future<void> persist() async {
    if (_controller == null) return;
    final keys = collapsedKeys();
    if (setEquals(keys, _persisted)) return;
    _persisted = keys;
    await store.save(noteId, keys);
  }

  /// What was last saved (or loaded), so an unchanged note isn't rewritten.
  void loaded(Set<String> keys) => _persisted = keys;

  // ---- Edits that touch a fold ----

  /// Called for every change to the editor's document. A fold that an edit
  /// removed (backspace, cut, typing over a selection) has its hidden lines
  /// put back — unless the edit deleted more than the fold's own line, an
  /// explicit selection reaching past the "…", in which case the hidden
  /// lines go with it (undo brings the fold, and so them, back). A fold
  /// pasted twice is expanded, so a paste carries its content.
  void onChange(DocChange change) {
    _lines = null;
    if (_applying || _controller == null) return;
    if (change.source != ChangeSource.local) return;
    if (!deltaHasFolds(change.before) && !deltaHasFolds(change.change)) return;
    // One edit can arrive as several changes (a paste inserts its parts one
    // by one); look at them together, once they have all landed.
    final first = _pending.isEmpty;
    _pending.add(change);
    if (first) scheduleMicrotask(_repair);
  }

  final _pending = <DocChange>[];

  void _repair() {
    final changes = [..._pending];
    _pending.clear();
    if (_controller == null || changes.isEmpty) return;
    final before = changes.first.before;
    var edit = changes.first.change;
    for (final c in changes.skip(1)) {
      edit = edit.compose(c.change);
    }
    final after = before.compose(edit);
    final foldsBefore = _foldsIn(before);
    final foldsAfter = _foldsIn(after);
    final insertedData = {for (final f in _foldsIn(edit)) f.data};

    int count(List<_FoldAt> list, String data) =>
        list.where((f) => f.data == data).length;

    final edits = <_Splice>[];
    for (final lost in foldsBefore) {
      if (insertedData.contains(lost.data)) continue; // moved
      if (count(foldsAfter, lost.data) >= count(foldsBefore, lost.data)) {
        continue;
      }
      final run = _deletedRun(edit, lost.offset);
      if (run == 0 || run >= 3) continue; // explicit: goes with the selection
      final at = edit.transformPosition(lost.offset, force: false);
      edits.add(_spliceFor(after, at, 0, lost.data));
    }
    for (final data in {for (final f in foldsAfter) f.data}) {
      final excess = count(foldsAfter, data) - count(foldsBefore, data);
      if (excess <= 0) continue;
      final copies = foldsAfter.where((f) => f.data == data).toList();
      for (final f in copies.reversed.take(excess)) {
        edits.add(_spliceFor(after, f.offset, 1, data));
      }
    }
    if (edits.isEmpty) return;
    edits.sort((a, b) => a.at.compareTo(b.at));
    final delta = Delta();
    var pos = 0;
    for (final e in edits) {
      if (e.at < pos) continue; // overlapping; leave for the next change
      if (e.at > pos) delta.retain(e.at - pos);
      for (final op in e.insert.toList()) {
        delta.insert(op.data, op.attributes);
      }
      if (e.remove > 0) delta.delete(e.remove);
      pos = e.at + e.remove;
    }
    if (delta.isEmpty) return;
    // Silent, so this change isn't looked at again (the stream delivers
    // changes after the fact, when no flag could mark them); the history
    // still records it, folded into the edit it repairs.
    _c.compose(delta, _c.selection, ChangeSource.silent);
    _lines = null;
    notifyListeners();
    unawaited(persist());
  }

  /// Puts the lines of the fold [data] at [at] in [doc], where [embeds] is
  /// 1 if the fold embed is still there (to be replaced) or 0 if an edit
  /// already removed it. The hidden lines go on lines of their own, and a
  /// blank line the fold itself leaves behind is removed.
  static _Splice _spliceFor(Delta doc, int at, int embeds, String data) {
    final prev = at == 0 ? '\n' : _charAt(doc, at - 1);
    final next = _charAt(doc, at + embeds);
    // The fold's own newline: remove it with the embed (or when only the
    // embed went), but only if the fold was alone on its line.
    final alone = prev == '\n' && next == '\n';
    final insert = Delta();
    if (prev != '\n') insert.insert('\n');
    for (final op in foldLinesToDelta(foldHiddenLines(data)).toList()) {
      insert.insert(op.data, op.attributes);
    }
    return _Splice(at, embeds + (alone ? 1 : 0), insert);
  }

  static List<_FoldAt> _foldsIn(Delta delta) {
    final out = <_FoldAt>[];
    var at = 0;
    for (final op in delta.toList()) {
      if (!op.isInsert) continue;
      final d = op.data;
      if (d is Map && d.containsKey(foldEmbedType)) {
        final v = d[foldEmbedType];
        out.add(_FoldAt(at, v is String ? v : jsonEncode(v)));
      }
      at += op.length ?? 1;
    }
    return out;
  }

  /// How many characters of the contiguous deletion in [edit] cover
  /// [offset] (an offset in the document before it), or 0.
  static int _deletedRun(Delta edit, int offset) {
    var at = 0;
    for (final op in edit.toList()) {
      if (op.isInsert) continue;
      final n = op.length ?? 0;
      if (op.isDelete) {
        if (offset >= at && offset < at + n) return n;
      }
      at += n;
    }
    return 0;
  }

  static String _charAt(Delta delta, int offset) {
    final slice = delta.slice(offset, offset + 1).toList();
    if (slice.isEmpty) return '';
    final d = slice.first.data;
    return d is String ? d : '￼';
  }
}

class _FoldAt {
  const _FoldAt(this.offset, this.data);
  final int offset;
  final String data;
}

class _Splice {
  const _Splice(this.at, this.remove, this.insert);
  final int at;
  final int remove;
  final Delta insert;
}
