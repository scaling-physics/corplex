import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/notes/note_editor_screen.dart';

import '../support/fake_audio_engine.dart';
import '../support/l10n_app.dart';
import '../support/mac_screenshot.dart';

void main() {
  late AppDatabase db;

  setUpAll(() async {
    await initializeDateFormatting('de');
    await loadMacFonts();
  });
  setUp(() async {
    EditableText.debugDeterministicCursor = true;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n1'),
            title: const Value('Kapitel'),
          ),
        );
  });
  tearDown(() {
    EditableText.debugDeterministicCursor = false;
    db.close();
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          audioEngineProvider.overrideWithValue(FakeAudioEngine()),
        ],
        child: localizedApp(const NoteEditorScreen(noteId: 'n1')),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('phone: German format row fits 360 px; menus are German', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await open(tester);

    for (final tooltip in ['Zeichnen', 'Textstil']) {
      final rect = tester.getRect(find.byTooltip(tooltip));
      expect(rect.right, lessThanOrEqualTo(360), reason: tooltip);
    }

    await tester.tap(find.byTooltip('Textstil'));
    await tester.pumpAndSettle();
    expect(find.text('Fließtext'), findsOneWidget);
    expect(find.text('Zwischenüberschrift'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Mehr'));
    await tester.pumpAndSettle();
    expect(find.text('In Notiz suchen'), findsOneWidget);
    expect(find.text('Wortzahl'), findsOneWidget);
    expect(find.text('Duplizieren'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    // The "/" sheet.
    final c = tester.widget<QuillEditor>(find.byType(QuillEditor)).controller;
    c.replaceText(0, 0, '/', const TextSelection.collapsed(offset: 1));
    await tester.pumpAndSettle();
    expect(find.text('Paper zitieren'), findsOneWidget);
    expect(find.text('Sprachnotiz'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('Mac: German toolbar at the minimum window, no overflow', (
    tester,
  ) async {
    useMacWindow(tester, macWindowSizes['minimum']!);
    await open(tester);
    expect(find.byTooltip('Fett ⌘B'), findsOneWidget);
    expect(find.byTooltip('Checkliste ⇧⌘L'), findsOneWidget);
    expect(find.byTooltip('Zeichnen'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await close(tester);
  }, variant: macOnly);
}
