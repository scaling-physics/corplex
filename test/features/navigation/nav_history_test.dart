import 'package:corplex/features/navigation/nav_history.dart';
import 'package:corplex/features/navigation/nav_target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const a = NoteTarget('a');
  const b = PaperTarget('b');
  const c = NoteTarget('c');

  test('back and forward walk the visits', () {
    final h = NavHistory()
      ..visit(a)
      ..visit(b)
      ..visit(c);
    expect(h.current!.target, c);
    expect(h.back()!.target, b);
    expect(h.back()!.target, a);
    expect(h.back(), isNull);
    expect(h.forward()!.target, b);
    expect(h.canGoForward, isTrue);
  });

  test('visiting from the middle drops what was ahead', () {
    final h = NavHistory()
      ..visit(a)
      ..visit(b)
      ..visit(c);
    h.back();
    h.visit(const ProjectTarget('p'));
    expect(h.canGoForward, isFalse);
    expect(h.entries.map((e) => e.target.key), [
      'note:a',
      'paper:b',
      'project:p',
    ]);
  });

  test('revisiting the current place refreshes it and keeps the scroll', () {
    final h = NavHistory()..visit(a);
    h.reportScroll(0.4);
    h.visit(const NoteTarget('a', selectionStart: 10, selectionEnd: 14));
    expect(h.entries, hasLength(1));
    expect(h.current!.scroll, 0.4);
    expect((h.current!.target as NoteTarget).selectionStart, 10);
  });

  test('forget removes a deleted place and keeps the position sensible', () {
    final h = NavHistory()
      ..visit(a)
      ..visit(b)
      ..visit(c)
      ..visit(b);
    h.forget('paper:b');
    expect(h.entries.map((e) => e.target.key), ['note:a', 'note:c']);
    expect(h.current!.target, c);
    h.forget('note:c');
    expect(h.current!.target, a);
    h.forget('note:a');
    expect(h.current, isNull);
    expect(h.canGoBack, isFalse);
  });

  test('the limit drops the oldest', () {
    final h = NavHistory(limit: 3);
    for (final id in ['1', '2', '3', '4']) {
      h.visit(NoteTarget(id));
    }
    expect(h.entries.map((e) => e.target.key), ['note:2', 'note:3', 'note:4']);
    expect(h.index, 2);
  });
}
