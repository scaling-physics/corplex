import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:corplex/app.dart';
import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/capture/quick_capture.dart';
import 'package:corplex/features/library/metadata_lookup.dart';
import 'package:corplex/features/notes/note_editor_screen.dart';
import 'package:corplex/features/platform/mac_window.dart';
import 'package:corplex/features/share/share_import.dart';

import '../../support/fake_audio_engine.dart';
import '../../support/mac_screenshot.dart';

class _Window implements MacWindow {
  final controller = StreamController<QuickCapture>.broadcast();
  final commands = StreamController<MenuCommand>.broadcast();
  final hotKeyCalls = <bool>[];
  final _full = ValueNotifier(false);

  @override
  Stream<MenuCommand> get menuCommands => commands.stream;
  @override
  Stream<QuickCapture> get captures => controller.stream;
  @override
  Future<bool> setQuickNoteHotKey(bool enabled) async {
    hotKeyCalls.add(enabled);
    return enabled;
  }

  @override
  ValueListenable<bool> get fullScreen => _full;
  @override
  Future<void> startDrag() async {}
  @override
  Future<void> zoom() async {}
  @override
  Future<bool> printPdf(Uint8List pdf, String title) async => false;
}

void main() {
  late AppDatabase db;
  late _Window window;

  setUpAll(loadMacFonts);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    EditableText.debugDeterministicCursor = true;
    db = AppDatabase.inMemoryForTesting();
    window = _Window();
  });
  tearDown(() async {
    EditableText.debugDeterministicCursor = false;
    await window.controller.close();
    await db.close();
  });

  Future<void> show(WidgetTester tester) async {
    useMacWindow(tester, macWindowSizes['laptop13']!);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          audioEngineProvider.overrideWithValue(FakeAudioEngine()),
          shareIntentSourceProvider.overrideWithValue(
            const NoShareIntentSource(),
          ),
          macWindowProvider.overrideWithValue(window),
          metadataLookupProvider.overrideWithValue(
            MetadataLookup(
              client: MockClient((_) async => http.Response('', 404)),
            ),
          ),
        ],
        child: const CorplexApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  test('capture messages decode', () {
    expect(quickCaptureFromMessage('newNote'), isA<NewNoteCapture>());
    expect((quickCaptureFromMessage({'text': 'hi'}) as TextCapture).text, 'hi');
    expect(quickCaptureFromMessage('other'), isNull);
    expect(quickCaptureFromMessage(null), isNull);
  });

  testWidgets('the hotkey is registered at startup', (tester) async {
    await show(tester);
    expect(window.hotKeyCalls, [true]);
    await dispose(tester);
  }, variant: macOnly);

  testWidgets('the setting registers and releases the hotkey', (tester) async {
    await show(tester);
    window.commands.add(MenuCommand.settings);
    await tester.pumpAndSettle();
    final row = find.text('Quick note shortcut (⌃⌥N)');
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(window.hotKeyCalls, [true, false]);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(window.hotKeyCalls, [true, false, true]);
    await dispose(tester);
  }, variant: macOnly);

  testWidgets('a new-note capture creates and opens a note', (tester) async {
    await show(tester);
    window.controller.add(const NewNoteCapture());
    await tester.pumpAndSettle();
    expect(await db.select(db.notes).get(), hasLength(1));
    expect(find.byType(NoteEditorScreen), findsOneWidget);
    await dispose(tester);
  }, variant: macOnly);

  testWidgets('captured text becomes a note', (tester) async {
    await show(tester);
    window.controller.add(const TextCapture('Remember to cite Smith 2019'));
    await tester.pumpAndSettle();
    final note = await db.select(db.notes).getSingle();
    expect(note.title, 'Remember to cite Smith 2019');
    expect(note.content, contains('Remember to cite Smith 2019'));
    await dispose(tester);
  }, variant: macOnly);

  testWidgets('a captured DOI takes the paper path', (tester) async {
    await show(tester);
    window.controller.add(const TextCapture('10.1038/nature14539'));
    await tester.pumpAndSettle();
    expect(await db.select(db.notes).get(), isEmpty);
    // Offline, the lookup fails and says so rather than making a note.
    expect(
      find.textContaining('nature14539', findRichText: true),
      findsWidgets,
    );
    await dispose(tester);
  }, variant: macOnly);
}
