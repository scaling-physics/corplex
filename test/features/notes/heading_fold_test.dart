import 'package:flutter/widgets.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/features/notes/editor_document.dart';
import 'package:corplex/features/notes/heading_fold.dart';
import 'package:corplex/features/notes/heading_fold_controller.dart';
import 'package:corplex/features/notes/note_content.dart';
import 'package:corplex/features/notes/note_stats.dart';

/// A note: H1 One, two paragraphs, H2 Sub, a paragraph, H1 Two, a paragraph.
Delta sample() => Delta()
  ..insert('One')
  ..insert('\n', {'header': 1})
  ..insert('alpha\nbeta\n')
  ..insert('Sub')
  ..insert('\n', {'header': 2})
  ..insert('gamma\n')
  ..insert('Two')
  ..insert('\n', {'header': 1})
  ..insert('delta\n');

class Rig {
  Rig(Delta delta, {String noteId = 'n1'})
    : controller = QuillController(
        document: Document.fromDelta(delta),
        selection: const TextSelection.collapsed(offset: 0),
      ),
      folds = HeadingFolds(noteId: noteId, store: const _NoStore()) {
    folds.attach(controller);
    controller.document.changes.listen(folds.onChange);
    stored = storedFromEditor(controller.document);
  }

  final QuillController controller;
  final HeadingFolds folds;
  late final String stored;

  String get text => controller.document.toPlainText();
  String get nowStored => storedFromEditor(controller.document);
}

class _NoStore extends FoldStore {
  const _NoStore();
  @override
  Future<void> save(String noteId, Set<String> keys) async {}
}

void main() {
  test('collapse hides exactly the section, to the next heading of the '
      'same or a higher level', () {
    final r = Rig(sample());
    final heads = r.folds.headings();
    expect(heads.map((h) => h.level), [1, 2, 1]);
    r.folds.toggleHeading(heads[0].line);
    expect(r.text.startsWith('One\n￼\nTwo\ndelta'), isTrue);
    expect(r.text, 'One\n￼\nTwo\ndelta\n');
    expect(r.nowStored, r.stored);

    r.folds.toggleHeading(r.folds.headings()[0].line);
    expect(r.text, 'One\nalpha\nbeta\nSub\ngamma\nTwo\ndelta\n');
    expect(r.nowStored, r.stored);
  });

  test('a sub-heading section ends at the next heading of its level', () {
    final r = Rig(sample());
    r.folds.toggleHeading(r.folds.headings()[1].line);
    expect(r.text, 'One\nalpha\nbeta\nSub\n￼\nTwo\ndelta\n');
    expect(r.nowStored, r.stored);
  });

  test('the last section runs to the end; an empty heading cannot fold', () {
    final r = Rig(sample());
    r.folds.toggleHeading(r.folds.headings()[2].line);
    expect(r.text, 'One\nalpha\nbeta\nSub\ngamma\nTwo\n￼\n');
    expect(r.nowStored, r.stored);

    final empty = Rig(
      Delta()
        ..insert('A')
        ..insert('\n', {'header': 1})
        ..insert('B')
        ..insert('\n', {'header': 1})
        ..insert('text\n'),
    );
    expect(empty.folds.headings().map((h) => h.line), [1]);
  });

  test('nested: outer holds the inner fold, expanding keeps it folded', () {
    final r = Rig(sample());
    r.folds.toggleHeading(r.folds.headings()[1].line); // Sub
    r.folds.toggleHeading(r.folds.headings()[0].line); // One
    expect(r.text, 'One\n￼\nTwo\ndelta\n');
    expect(r.nowStored, r.stored);
    r.folds.toggleHeading(r.folds.headings()[0].line);
    expect(r.text, 'One\nalpha\nbeta\nSub\n￼\nTwo\ndelta\n');
    expect(r.nowStored, r.stored);
    r.folds.expandAll();
    expect(r.text, 'One\nalpha\nbeta\nSub\ngamma\nTwo\ndelta\n');
  });

  test('folding is not an undo step and never marks the note changed', () {
    final r = Rig(sample());
    expect(r.controller.hasUndo, isFalse);
    r.folds.toggleHeading(r.folds.headings()[0].line);
    expect(r.controller.hasUndo, isFalse);
    r.folds.collapseAll();
    r.folds.expandAll();
    expect(r.controller.hasUndo, isFalse);
    expect(r.nowStored, r.stored);
  });

  test('earlier typing can still be undone across a fold', () {
    final r = Rig(sample());
    r.controller.replaceText(0, 0, 'X', null);
    expect(r.controller.hasUndo, isTrue);
    r.folds.toggleHeading(r.folds.headings()[1].line);
    r.controller.undo();
    expect(r.text.startsWith('One\n'), isTrue);
    expect(r.nowStored.contains('"X'), isFalse);
  });

  test('editing the visible part keeps hidden text', () {
    final r = Rig(sample());
    r.folds.toggleHeading(r.folds.headings()[0].line);
    // Retitle "Two" while One is folded.
    r.controller.replaceText(r.text.indexOf('Two') + 3, 0, '!', null);
    final doc = decodeNoteContent(r.nowStored).toPlainText();
    expect(doc, 'One\nalpha\nbeta\nSub\ngamma\nTwo!\ndelta\n');
  });

  test(
    'a lone backspace on the fold expands instead of dropping text',
    () async {
      final r = Rig(sample());
      r.folds.toggleHeading(r.folds.headings()[0].line);
      final at = r.text.indexOf('￼');
      r.controller.replaceText(at, 1, '', null);
      await Future<void>.delayed(Duration.zero);
      expect(
        decodeNoteContent(r.nowStored).toPlainText(),
        'One\nalpha\nbeta\nSub\ngamma\nTwo\ndelta\n',
      );
      expect(r.text.contains('￼'), isFalse);
      expect(r.text, 'One\nalpha\nbeta\nSub\ngamma\nTwo\ndelta\n');
    },
  );

  test(
    'select all and type removes the hidden text too, undo restores it',
    () async {
      final r = Rig(sample());
      r.folds.toggleHeading(r.folds.headings()[0].line);
      r.controller.replaceText(
        0,
        r.controller.document.length - 1,
        'new',
        null,
      );
      await Future<void>.delayed(Duration.zero);
      expect(decodeNoteContent(r.nowStored).toPlainText(), 'new\n');
      r.controller.undo();
      expect(
        decodeNoteContent(r.nowStored).toPlainText(),
        'One\nalpha\nbeta\nSub\ngamma\nTwo\ndelta\n',
      );
    },
  );

  test('a fold pasted twice is expanded in place', () async {
    final r = Rig(sample());
    r.folds.toggleHeading(r.folds.headings()[0].line);
    final foldDelta = r.controller.document.toDelta().slice(4, 6);
    final end = r.controller.document.length - 1;
    r.controller.replaceText(end, 0, foldDelta, null);
    await Future<void>.delayed(Duration.zero);
    final stored = decodeNoteContent(r.nowStored).toPlainText();
    expect(stored.split('alpha').length - 1, 2);
    expect(r.text.split('￼').length - 1, 1);
  });

  test('word count counts hidden text', () {
    final r = Rig(sample());
    final all = noteStats(r.folds.unfoldedDocument()).words;
    r.folds.collapseAll();
    expect(noteStats(r.folds.unfoldedDocument()).words, all);
    expect(all, 7);
  });

  test('fingerprints restore folds, per heading text and occurrence', () {
    final r = Rig(sample());
    r.folds.toggleHeading(r.folds.headings()[1].line);
    r.folds.toggleHeading(r.folds.headings()[0].line);
    final keys = r.folds.collapsedKeys();
    expect(keys, hasLength(2));
    expect(keys.join(), isNot(contains('One')));

    final again = Rig(sample());
    again.folds.applyKeys(keys);
    expect(again.text, r.text);
    expect(again.nowStored, again.stored);

    // The section holding a selection stays open.
    final open = Rig(sample());
    open.folds.applyKeys(keys, protectOffset: 12);
    expect(open.text, 'One\nalpha\nbeta\nSub\n￼\nTwo\ndelta\n');
  });

  test('same-named headings are told apart by occurrence', () {
    final d = Delta()
      ..insert('Notes')
      ..insert('\n', {'header': 1})
      ..insert('a\n')
      ..insert('Notes')
      ..insert('\n', {'header': 1})
      ..insert('b\n');
    final r = Rig(d);
    r.folds.toggleHeading(r.folds.headings()[1].line);
    final again = Rig(d);
    again.folds.applyKeys(r.folds.collapsedKeys());
    expect(again.text, 'Notes\na\nNotes\n￼\n');
  });

  test('reveal maps unfolded offsets and expands what hides them', () {
    final r = Rig(sample());
    r.folds.collapseAll(); // One holds the rest of its text
    final u = sample().toList().map((o) => o.data).join().indexOf('gamma');
    final at = r.folds.reveal(u);
    expect(r.text.substring(at, at + 5), 'gamma');
    expect(r.nowStored, r.stored);
  });

  test('selection inside a section that folds moves to its heading', () {
    final r = Rig(sample());
    r.controller.updateSelection(
      TextSelection.collapsed(offset: r.text.indexOf('beta')),
      ChangeSource.local,
    );
    r.folds.toggleHeading(r.folds.headings()[0].line);
    expect(r.controller.selection.baseOffset, 3);
  });

  test('unfoldedOffset is the inverse for visible text', () {
    final r = Rig(sample());
    r.folds.toggleHeading(r.folds.headings()[0].line);
    final live = r.text.indexOf('delta');
    final u = r.folds.unfoldedOffset(live);
    expect(r.folds.unfoldedText().substring(u, u + 5), 'delta');
  });

  test('fingerprints are opaque and differ between notes', () {
    final a = foldFingerprint('note-a', 'Secret chapter', 0);
    expect(a, isNot(contains('Secret')));
    expect(a, hasLength(24));
    expect(a, isNot(foldFingerprint('note-b', 'Secret chapter', 0)));
    expect(a, isNot(foldFingerprint('note-a', 'Secret chapter', 1)));
    expect(a, foldFingerprint('note-a', 'Secret chapter', 0));
  });
}
