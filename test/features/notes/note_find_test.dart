import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/features/notes/note_find.dart';

void main() {
  setUp(() => EditableText.debugDeterministicCursor = true);
  tearDown(() => EditableText.debugDeterministicCursor = false);

  test('matches ignore case and may overlap nothing', () {
    expect(findMatches('Rat rats RAT', 'rat'), [0, 4, 9]);
    expect(findMatches('abc', ''), isEmpty);
    expect(findMatches('abc', 'x'), isEmpty);
  });

  QuillController controllerWith(Delta delta) => QuillController(
    document: Document.fromDelta(delta),
    selection: const TextSelection.collapsed(offset: 0),
  );

  Future<void> pumpBar(WidgetTester tester, QuillController controller) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteFindBar(controller: controller, onClose: () {}),
          ),
        ),
      );

  testWidgets('finds, steps and replaces, embeds counted as one', (
    tester,
  ) async {
    // A sketch-like embed sits before the text: offsets must still line up.
    final controller = controllerWith(
      Delta()
        ..insert({'sketch': '{}'})
        ..insert('mice and Mice and men\n'),
    );
    addTearDown(controller.dispose);
    await pumpBar(tester, controller);

    await tester.enterText(find.byType(TextField).first, 'mice');
    await tester.pump();
    expect(find.text('1 of 2'), findsOneWidget);
    expect(
      controller.selection,
      const TextSelection(baseOffset: 1, extentOffset: 5),
    );

    await tester.tap(find.byTooltip('Next'));
    await tester.pump();
    expect(find.text('2 of 2'), findsOneWidget);
    expect(controller.selection.baseOffset, 10);

    await tester.tap(find.byTooltip('Replace'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, 'rats');
    await tester.tap(find.text('All'));
    await tester.pump();
    expect(controller.document.toPlainText(), '￼rats and rats and men\n');
    expect(find.text('Not found'), findsOneWidget);
  });

  testWidgets('Replace changes only the current match', (tester) async {
    final controller = controllerWith(Delta()..insert('cat cat cat\n'));
    addTearDown(controller.dispose);
    await pumpBar(tester, controller);
    await tester.enterText(find.byType(TextField).first, 'cat');
    await tester.pump();
    await tester.tap(find.byTooltip('Replace'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, 'dog');
    await tester.tap(find.text('Replace'));
    await tester.pump();
    expect(controller.document.toPlainText(), 'dog cat cat\n');
    expect(find.text('1 of 2'), findsOneWidget);
  });
}
