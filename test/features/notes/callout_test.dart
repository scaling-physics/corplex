import 'dart:convert';

import 'package:corplex/features/notes/callout_embed.dart';
import 'package:corplex/features/notes/callout_markers.dart';
import 'package:corplex/features/notes/editor_document.dart';
import 'package:corplex/features/notes/note_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

String _delta(List<Map<String, Object?>> ops) => jsonEncode(ops);

const _quote = {'blockquote': true};

void main() {
  group('markers', () {
    test('parses the type, title and fold sign', () {
      final h = parseCalloutLine('[!Warning] Mind the gap')!;
      expect(
        (h.marker, h.type, h.title),
        ('[!Warning]', 'warning', 'Mind the gap'),
      );
      expect(parseCalloutLine('[!faq]- Folded')!.marker, '[!faq]-');
      expect(parseCalloutLine('[!note]')!.title, '');
      expect(parseCalloutLine('plain [!note]'), isNull);
      expect(parseCalloutLine('[! note]'), isNull);
      expect(parseCalloutLine('[@cite]'), isNull);
      expect(parseCalloutMarker('[!tip]'), 'tip');
      expect(parseCalloutMarker('[!tip] more'), isNull);
    });

    test('tones follow the design table; other words read as notes', () {
      expect(calloutToneOf('note'), CalloutTone.primary);
      expect(calloutToneOf('INFO'), CalloutTone.primary);
      expect(calloutToneOf('tip'), CalloutTone.tertiary);
      expect(calloutToneOf('example'), CalloutTone.tertiary);
      expect(calloutToneOf('question'), CalloutTone.secondary);
      expect(calloutToneOf('bug'), CalloutTone.error);
      expect(calloutToneOf('faq'), CalloutTone.primary);
    });
  });

  group('stored <-> editor', () {
    test('only a block-quote line starting with a marker is a callout', () {
      final stored = _delta([
        {'insert': 'Intro\n[!note] Not quoted\n'},
        {'insert': '[!tip] Quoted title'},
        {'insert': '\n', 'attributes': _quote},
        {'insert': 'Body line'},
        {'insert': '\n', 'attributes': _quote},
        {'insert': 'a [!x] in the middle'},
        {'insert': '\n', 'attributes': _quote},
      ]);
      final doc = editorDocument(stored);
      expect(
        doc.toPlainText(),
        'Intro\n[!note] Not quoted\n￼ Quoted title\nBody line\na [!x] in the middle\n'
            .replaceFirst('￼ Quoted', '￼ Quoted'),
      );
      final embeds = [
        for (final op in doc.toDelta().toList())
          if (op.data is Map) op.data,
      ];
      expect(embeds, [
        {calloutEmbedType: '[!tip]'},
      ]);
      expect(
        storedFromEditor(doc),
        encodeNoteContent(decodeNoteContent(stored)),
      );
    });

    test('a marker on the first line of the note, with formatting after', () {
      final stored = _delta([
        {'insert': '[!warning] '},
        {
          'insert': 'bold',
          'attributes': {'bold': true},
        },
        {'insert': '\n', 'attributes': _quote},
      ]);
      final doc = editorDocument(stored);
      expect(doc.toPlainText(), '￼ bold\n');
      expect(
        storedFromEditor(doc),
        encodeNoteContent(decodeNoteContent(stored)),
      );
    });

    test('content without callouts is untouched', () {
      final s = _delta([
        {'insert': 'hello\n'},
      ]);
      expect(calloutsToEmbeds(s), s);
      expect(calloutsToEmbeds('[!note] not json'), '[!note] not json');
      expect(calloutEmbedsToText(s), s);
    });

    test('previews drop the marker and keep the title', () {
      final stored = _delta([
        {'insert': '[!tip] Try this'},
        {'insert': '\n', 'attributes': _quote},
      ]);
      expect(notePlainTextPreview(stored), 'Try this');
    });
  });

  group('editor', () {
    EditableText.debugDeterministicCursor = true;

    Future<void> pump(WidgetTester tester, QuillController c) =>
        tester.pumpWidget(
          MaterialApp(
            localizationsDelegates:
                FlutterQuillLocalizations.localizationsDelegates,
            supportedLocales: FlutterQuillLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: [
                    Expanded(
                      child: QuillEditor.basic(
                        controller: c,
                        config: const QuillEditorConfig(
                          embedBuilders: [CalloutEmbedBuilder()],
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => insertCallout(context, c),
                      child: const Text('callout'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

    testWidgets(
      'the Callout command quotes the line and starts it with a chip',
      (tester) async {
        final c = QuillController.basic();
        c.replaceText(
          0,
          0,
          'Watch out',
          const TextSelection.collapsed(offset: 9),
        );
        await pump(tester, c);
        await tester.tap(find.text('callout'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('callout-warning')));
        await tester.pumpAndSettle();
        final stored = jsonDecode(storedFromEditor(c.document)) as List;
        expect(stored.first['insert'], '[!warning] Watch out');
        expect(stored.last['attributes'], {'blockquote': true});
        expect(find.text('Warning'), findsOneWidget);
        c.dispose();
      },
    );

    testWidgets('tapping the chip changes the type, or removes the callout', (
      tester,
    ) async {
      final c = QuillController(
        document: editorDocument(
          _delta([
            {'insert': '[!note] Title'},
            {'insert': '\n', 'attributes': _quote},
          ]),
        ),
        selection: const TextSelection.collapsed(offset: 0),
      );
      await pump(tester, c);
      await tester.tap(find.text('Note'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('callout-danger')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('callout-danger')));
      await tester.pumpAndSettle();
      expect(
        (jsonDecode(storedFromEditor(c.document)) as List).first['insert'],
        '[!danger] Title',
      );
      await tester.tap(find.text('Danger'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('callout-remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('callout-remove')));
      await tester.pumpAndSettle();
      expect(c.document.toPlainText(), 'Title\n');
      c.dispose();
    });
  });
}
