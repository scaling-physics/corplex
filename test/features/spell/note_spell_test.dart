import 'package:corplex/features/settings/appearance_settings.dart';
import 'package:corplex/features/spell/note_spell.dart';
import 'package:corplex/features/spell/spell_checker.dart';

import '../../support/mac_screenshot.dart';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Flags any word in [bad] (case-insensitive).
class FakeSpell implements SpellChecker {
  FakeSpell(this.bad);
  final Set<String> bad;
  int checks = 0;
  int guessCalls = 0;
  final learned = <String>[];

  @override
  bool get available => true;

  @override
  Future<List<List<TextRange>>> check(List<String> texts) async {
    checks++;
    return [
      for (final t in texts)
        [
          for (final m in RegExp(r"[A-Za-z0-9_]+").allMatches(t))
            if (bad.contains(m.group(0)!.toLowerCase()))
              TextRange(start: m.start, end: m.end),
        ],
    ];
  }

  @override
  Future<List<String>> guesses(String word) async {
    guessCalls++;
    return ['one', 'two', 'three', 'four', 'five', 'six'];
  }

  @override
  Future<void> learn(String word) async => learned.add(word);
}

QuillController controllerWith(String text) => QuillController(
  document: Document()..insert(0, text),
  selection: const TextSelection.collapsed(offset: 0),
);

void main() {
  setUp(() => EditableText.debugDeterministicCursor = true);
  tearDown(() => EditableText.debugDeterministicCursor = false);

  group('keepMisspelling', () {
    bool keep(String text, String word) {
      final i = text.indexOf(word);
      return keepMisspelling(text, TextRange(start: i, end: i + word.length));
    }

    test('skips digits, ALL-CAPS, URLs and identifiers', () {
      expect(keep('a teh b', 'teh'), isTrue);
      expect(keep('see mPFC2 here', 'mPFC2'), isFalse);
      expect(keep('the NMDAR is', 'NMDAR'), isFalse);
      expect(keep('go to www.exmple.com now', 'exmple'), isFalse);
      expect(keep('go to https://foo.test/blarg now', 'blarg'), isFalse);
      expect(keep('ask @bobx today', 'bobx'), isFalse);
      expect(keep('a snake_cse b', 'snake_cse'), isFalse);
    });
  });

  group('span builder', () {
    Future<NoteSpell> prepared(
      WidgetTester tester,
      QuillController c,
      FakeSpell fake, {
      bool enabled = true,
    }) async {
      final spell = NoteSpell(controller: c, checker: () => fake)
        ..enabled = enabled;
      addTearDown(spell.dispose);
      return spell;
    }

    Widget editor(QuillController c, NoteSpell spell) => MaterialApp(
      localizationsDelegates: FlutterQuillLocalizations.localizationsDelegates,
      home: Scaffold(
        body: QuillEditor.basic(
          controller: c,
          focusNode: FocusNode(),
          config: QuillEditorConfig(
            textSpanBuilder: spell.spanBuilder,
            contextMenuBuilder: spell.contextMenu,
          ),
        ),
      ),
    );

    List<TextSpan> leaves(WidgetTester tester) {
      final out = <TextSpan>[];
      for (final rt in tester.widgetList<RichText>(find.byType(RichText))) {
        rt.text.visitChildren((s) {
          if (s is TextSpan && s.text != null) out.add(s);
          return true;
        });
      }
      return out;
    }

    testWidgets('underlines the misspelling and keeps underline + recognizer', (
      tester,
    ) async {
      final c = controllerWith('hello teh world\n');
      c.formatText(6, 3, Attribute.underline);
      final fake = FakeSpell({'teh'});
      final spell = await prepared(tester, c, fake);
      spell.addListener(() {});
      // Caret is at 0, away from the word.
      await tester.pumpWidget(editor(c, spell));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(fake.checks, 1);
      final marked = leaves(tester)
          .where((s) => s.style?.decorationStyle == TextDecorationStyle.wavy);
      expect(marked.map((s) => s.text), ['teh']);
      final d = marked.single.style!.decoration!;
      expect(d.contains(TextDecoration.underline), isTrue);
      expect(marked.single.style!.decorationColor, isNotNull);
      c.dispose();
    });

    testWidgets('keeps strikethrough and a tap recognizer', (tester) async {
      final c = controllerWith('hello teh world\n');
      c.formatText(6, 3, Attribute.strikeThrough);
      final fake = FakeSpell({'teh'});
      final spell = await prepared(tester, c, fake);
      await tester.pumpWidget(editor(c, spell));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      final rec = TapGestureRecognizer();
      addTearDown(rec.dispose);
      final line = c.document.queryChild(0).node! as Line;
      final leaf = line.children.elementAt(1);
      final span = spell.spanBuilder(
        tester.element(find.byType(Scaffold)),
        leaf,
        0,
        'teh',
        const TextStyle(decoration: TextDecoration.lineThrough),
        rec,
      ) as TextSpan;
      final piece = span.children!.single as TextSpan;
      expect(piece.text, 'teh');
      expect(piece.recognizer, same(rec));
      expect(
        piece.style!.decoration!.contains(TextDecoration.lineThrough),
        isTrue,
      );
      expect(piece.style!.decorationStyle, TextDecorationStyle.wavy);
      c.dispose();
    });

    testWidgets('the word under the caret is not underlined', (tester) async {
      final c = controllerWith('hello teh world\n');
      c.updateSelection(
        const TextSelection.collapsed(offset: 9),
        ChangeSource.local,
      );
      final fake = FakeSpell({'teh'});
      final spell = await prepared(tester, c, fake);
      await tester.pumpWidget(editor(c, spell));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(
        leaves(tester)
            .where((s) => s.style?.decorationStyle == TextDecorationStyle.wavy),
        isEmpty,
      );
      c.dispose();
    });

    testWidgets('links and code are skipped', (tester) async {
      final c = controllerWith('teh and teh\n');
      c.formatText(0, 3, LinkAttribute('corplex://note/1'));
      c.formatText(8, 3, Attribute.inlineCode);
      final fake = FakeSpell({'teh'});
      final spell = await prepared(tester, c, fake);
      await tester.pumpWidget(editor(c, spell));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(
        leaves(tester)
            .where((s) => s.style?.decorationStyle == TextDecorationStyle.wavy),
        isEmpty,
      );
      c.dispose();
    });

    testWidgets('disabled: no underlines and no channel calls', (tester) async {
      final c = controllerWith('hello teh world\n');
      final fake = FakeSpell({'teh'});
      final spell = await prepared(tester, c, fake, enabled: false);
      await tester.pumpWidget(editor(c, spell));
      await tester.pump(const Duration(seconds: 2));
      expect(fake.checks, 0);
      expect(
        leaves(tester)
            .where((s) => s.style?.decorationStyle == TextDecorationStyle.wavy),
        isEmpty,
      );
      c.dispose();
    });

    testWidgets('context menu lists guesses; choosing one is one edit', (
      tester,
    ) async {
      final c = controllerWith('hello teh world\n');
      final fake = FakeSpell({'teh'});
      final spell = await prepared(tester, c, fake);
      await tester.pumpWidget(editor(c, spell));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      c.updateSelection(
        const TextSelection.collapsed(offset: 8),
        ChangeSource.local,
      );
      await tester.pump();
      final m = spell.misspellingAtSelection();
      expect(m, isNotNull);
      expect(m!.word, 'teh');

      // Show the real menu through the editor's own raw state.
      tester
          .widget<QuillEditor>(find.byType(QuillEditor))
          .focusNode
          .requestFocus();
      await tester.pump();
      c.updateSelection(
        const TextSelection(baseOffset: 6, extentOffset: 9),
        ChangeSource.local,
      );
      await tester.pump();
      final raw = tester.state<QuillRawEditorState>(
        find.byType(QuillRawEditor),
      );
      expect(raw.showToolbar(), isTrue);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('one'), findsOneWidget);
      expect(find.text('five'), findsOneWidget);
      expect(find.text('six'), findsNothing);
      expect(find.text('Learn Spelling'), findsOneWidget);
      expect(find.text('Ignore Spelling'), findsOneWidget);

      c.document.history.clear();
      await tester.tap(find.text('two'));
      await tester.pump();
      expect(c.document.toPlainText().trim(), 'hello two world');
      expect(c.hasUndo, isTrue);
      c.undo();
      expect(c.document.toPlainText().trim(), 'hello teh world');
      expect(c.hasUndo, isFalse);
      await tester.pump(const Duration(seconds: 1));
      c.dispose();
    }, variant: macOnly);

    testWidgets('Ignore hides the word; Learn calls the checker', (
      tester,
    ) async {
      final c = controllerWith('hello teh world\n');
      final fake = FakeSpell({'teh'});
      final spell = await prepared(tester, c, fake);
      await tester.pumpWidget(editor(c, spell));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      spell.ignore('teh');
      c.updateSelection(
        const TextSelection.collapsed(offset: 8),
        ChangeSource.local,
      );
      expect(spell.misspellingAtSelection(), isNull);
      await spell.learn('teh');
      expect(fake.learned, ['teh']);
      c.dispose();
    });
  });

  group('ChannelSpellChecker', () {
    test('a missing plugin is silent and stops calling', () async {
      final checker = ChannelSpellChecker(const MethodChannel('corplex/nope'));
      expect(checker.available, isTrue);
      expect(await checker.check(['teh']), [<TextRange>[]]);
      expect(checker.available, isFalse);
      expect(await checker.guesses('teh'), isEmpty);
      await checker.learn('teh');
    });

    testWidgets('decodes offsets and lengths', (tester) async {
      const channel = MethodChannel('corplex/spell');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'check') {
          return [
            [
              [6, 3],
            ],
            <Object>[],
          ];
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final r = await ChannelSpellChecker().check(['hello teh', 'ok']);
      expect(r[0].single, const TextRange(start: 6, end: 9));
      expect(r[1], isEmpty);
    });
  });

  test('inert default and the setting default', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(spellCheckerProvider).available, isFalse);
    expect(AppearanceSettings().spellCheck, isTrue);
  });
}
