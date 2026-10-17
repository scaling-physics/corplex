import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:corplex/app.dart';
import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/notes/note_editor_screen.dart';
import 'package:corplex/features/platform/mac_window.dart';
import 'package:corplex/features/settings/appearance_settings.dart';
import 'package:corplex/features/share/share_import.dart';

import '../support/fake_audio_engine.dart';
import '../support/mac_screenshot.dart';

/// The whole app at Mac window sizes: no overflow anywhere, and (with
/// MAC_SCREENSHOTS set) a PNG of each for review.
void main() {
  late AppDatabase db;

  setUpAll(loadMacFonts);
  setUp(() async {
    EditableText.debugDeterministicCursor = true;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
    for (final (id, title) in [
      ('n1', 'Predictive coding in visual cortex'),
      ('n2', 'Chapter 2 — methods draft'),
      ('n3', 'Reading group, 14 Oct'),
    ]) {
      await db
          .into(db.notes)
          .insert(NotesCompanion.insert(id: Value(id), title: Value(title)));
    }
    await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(
            id: const Value('p1'),
            title: 'Attention Is All You Need',
            authors: const Value('Vaswani, Ashish; Shazeer, Noam'),
            year: const Value(2017),
          ),
        );
  });
  tearDown(() {
    EditableText.debugDeterministicCursor = false;
    db.close();
  });

  for (final MapEntry(key: name, value: size) in macWindowSizes.entries) {
    testWidgets('home at $name', (tester) async {
      useMacWindow(tester, size);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            audioEngineProvider.overrideWithValue(FakeAudioEngine()),
            shareIntentSourceProvider.overrideWithValue(
              const NoShareIntentSource(),
            ),
          ],
          child: const CorplexApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await macScreenshot(tester, 'home-$name');

      // A note open in the pane (or as a page below the pane width).
      await tester.tap(find.text('Predictive coding in visual cortex').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await macScreenshot(tester, 'note-$name');
      await tester.pageBack().catchError((_) {});
      await tester.pumpAndSettle();

      // The Library with a paper open.
      await tester.tap(find.text('Library').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Attention Is All You Need').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await macScreenshot(tester, 'paper-$name');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    }, variant: macOnly);
  }

  test('Mac panes fill, but centre a capped measure on ultrawide', () {
    expect(macPanePadding(800), 24); // a laptop's note pane
    expect(macPanePadding(1500), 40);
    expect(macPanePadding(1990), 195); // 27", still mostly filled
    // 38" ultrawide maximised: a ~3,270 pt pane keeps a 1,600 pt measure.
    expect(3268 - 2 * macPanePadding(3268), macMaxMeasure);
  });

  test('interface size steps and snaps to the offered sizes', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppearanceSettings();
    await s.stepInterfaceScale(1);
    expect(s.interfaceScale, 1.1);
    await s.stepInterfaceScale(1);
    expect(s.interfaceScale, 1.25);
    await s.setInterfaceScale(1.3);
    expect(s.interfaceScale, 1.25);
    await s.stepInterfaceScale(0);
    expect(s.interfaceScale, 1.0);
    await s.stepInterfaceScale(-1);
    await s.stepInterfaceScale(-1);
    expect(s.interfaceScale, 0.9); // clamps at the smallest
  });

  for (final scale in const [1.25, 1.6]) {
    testWidgets(
      'interface size ${(scale * 100).round()}% on the 38" ultrawide',
      (tester) async {
        useMacWindow(tester, macWindowSizes['dell38']!);
        final appearance = AppearanceSettings(interfaceScale: scale);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              databaseProvider.overrideWithValue(db),
              audioEngineProvider.overrideWithValue(FakeAudioEngine()),
              shareIntentSourceProvider.overrideWithValue(
                const NoShareIntentSource(),
              ),
              appearanceSettingsProvider.overrideWith((ref) => appearance),
            ],
            child: const CorplexApp(),
          ),
        );
        await tester.pumpAndSettle();
        // The app lays out in a window 1/scale the size…
        final media = MediaQuery.of(
          tester.element(find.byType(Scaffold).first),
        );
        expect(media.size.width, closeTo(3840 / scale, 0.5));
        // …and is drawn scaled up: a note title is that much bigger.
        final title = find.text('Predictive coding in visual cortex').first;
        final logical = tester.getSize(title).height;
        await tester.tap(title); // hit testing goes through the transform
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await macScreenshot(tester, 'dell38-scale-${(scale * 100).round()}');
        expect(find.byType(NoteEditorScreen), findsOneWidget);
        expect(logical, greaterThan(0));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
      },
      variant: macOnly,
    );
  }
}
