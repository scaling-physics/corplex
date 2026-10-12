import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull, Column;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/data/tables/attachments_table.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/library/add_attachment_sheet.dart';
import 'package:corplex/features/notes/note_editor_screen.dart';
import 'package:corplex/features/voice/voice_services.dart';

import '../../support/fake_audio_engine.dart';

class FakeRecorder implements VoiceRecorder {
  FakeRecorder({this.access = MicAccess.granted});

  MicAccess access;
  var started = false;
  var cancelled = false;
  var stopped = false;
  var disposed = false;
  final _levels = StreamController<double>.broadcast();

  /// The real plugin can't be used once disposed (1.5.x disposed it right
  /// after the sheet read it, and every recording failed).
  void _alive() {
    if (disposed) throw StateError('recorder used after dispose');
  }

  @override
  Future<MicAccess> ensureAccess() async {
    _alive();
    return access;
  }

  @override
  Future<void> start() async {
    _alive();
    started = true;
  }

  @override
  Stream<double> get levels => _levels.stream;

  void level(double v) => _levels.add(v);

  @override
  Future<String?> stop() async {
    _alive();
    stopped = true;
    return '/tmp/voice_note.m4a';
  }

  @override
  Future<void> cancel() async {
    _alive();
    cancelled = true;
  }

  @override
  Future<void> dispose() async => disposed = true;
}

class FakeTranscriber implements Transcriber {
  FakeTranscriber(this.result);
  Transcript result;
  var calls = 0;

  @override
  Future<Transcript> transcribeFile(String path) async {
    calls++;
    return result;
  }
}

class FakeDictation implements Dictation {
  @override
  Future<MicAccess> ensureAccess() async => MicAccess.granted;

  @override
  Future<void> start(void Function(String text) onText) async {
    onText('so far');
  }

  @override
  Stream<double> get levels => const Stream.empty();

  @override
  Future<String> stop() async => 'dictated words';

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  late AppDatabase db;
  late FakeRecorder recorder;
  late FakeTranscriber transcriber;
  late bool settingsOpened;
  var transcribes = true;

  setUp(() async {
    EditableText.debugDeterministicCursor = true;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
    recorder = FakeRecorder();
    transcriber = FakeTranscriber(
      const Transcript(TranscriptStatus.done, 'Attention scales badly.'),
    );
    settingsOpened = false;
    transcribes = true;
    await db
        .into(db.notes)
        .insert(NotesCompanion.insert(id: const Value('n1')));
    await db
        .into(db.papers)
        .insert(PapersCompanion.insert(id: const Value('p1'), title: 'P'));
  });
  tearDown(() {
    EditableText.debugDeterministicCursor = false;
    db.close();
  });

  List<Override> overrides() => [
    databaseProvider.overrideWithValue(db),
    audioEngineProvider.overrideWithValue(FakeAudioEngine()),
    // Like production: the provider disposes the recorder when released.
    voiceRecorderProvider.overrideWith((ref) {
      ref.onDispose(recorder.dispose);
      return recorder;
    }),
    transcriberProvider.overrideWithValue(transcriber),
    dictationProvider.overrideWithValue(FakeDictation()),
    dictationOfferedProvider.overrideWithValue(true),
    // Most tests stand in for iOS, where recordings are transcribed.
    transcribesRecordingsProvider.overrideWithValue(transcribes),
    openAppSettingsProvider.overrideWithValue(
      () async => settingsOpened = true,
    ),
  ];

  Future<QuillController> openNote(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: const MaterialApp(
          localizationsDelegates: [
            FlutterQuillLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: NoteEditorScreen(noteId: 'n1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.widget<QuillEditor>(find.byType(QuillEditor)).controller;
  }

  void type(QuillController c, String text) {
    final at = c.selection.baseOffset.clamp(0, c.document.length - 1);
    c.replaceText(
      at,
      0,
      text,
      TextSelection.collapsed(offset: at + text.length),
    );
  }

  Future<void> closeEditor(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  Future<List<Attachment>> attachments() => db.select(db.attachments).get();

  Future<void> record(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('voice-record-button')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byKey(const Key('voice-record-button')));
    await tester.pumpAndSettle();
  }

  testWidgets('/ offers Voice note; stopping adds the link and transcript', (
    tester,
  ) async {
    final c = await openNote(tester);
    type(c, 'Idea ');
    type(c, '/');
    await tester.pumpAndSettle();
    expect(find.text('Dictate'), findsOneWidget);
    await tester.tap(find.text('Voice note'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('voice-level-meter')), findsOneWidget);

    await record(tester);

    expect(recorder.started, isTrue);
    expect(recorder.stopped, isTrue);
    expect(transcriber.calls, 1);
    final rows = await attachments();
    expect(rows, hasLength(1));
    expect(rows.single.noteId, 'n1');
    expect(rows.single.type, AttachmentType.podcast);
    expect(rows.single.path, '/tmp/voice_note.m4a');
    expect(
      c.document.toPlainText(),
      'Idea ▸ 0:00 Voice note\nAttention scales badly.\n\n',
    );
    final link = c.document.toDelta().toList().firstWhere(
      (op) => op.attributes?['link'] != null,
    );
    expect(link.attributes!['link'], 'corplex://audio/${rows.single.id}?t=0');
    await closeEditor(tester);
  });

  testWidgets('cancelling mid-recording leaves nothing behind', (tester) async {
    final c = await openNote(tester);
    type(c, '/');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voice note'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('voice-record-button')));
    await tester.pump(const Duration(milliseconds: 300));
    recorder.level(0.7);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byKey(const Key('voice-cancel-button')));
    await tester.pumpAndSettle();

    expect(recorder.cancelled, isTrue);
    expect(await attachments(), isEmpty);
    expect(transcriber.calls, 0);
    expect(c.document.toPlainText(), '\n');
    await closeEditor(tester);
  });

  testWidgets('a refused microphone explains and offers Settings', (
    tester,
  ) async {
    recorder.access = MicAccess.denied;
    final c = await openNote(tester);
    type(c, '/');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voice note'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('voice-record-button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('needs the microphone'), findsOneWidget);
    expect(recorder.started, isFalse);
    await tester.tap(find.byKey(const Key('voice-open-settings')));
    expect(settingsOpened, isTrue);
    await tester.tap(find.byKey(const Key('voice-cancel-button')));
    await tester.pumpAndSettle();
    expect(await attachments(), isEmpty);
    await closeEditor(tester);
  });

  testWidgets('without transcription the audio is still saved', (tester) async {
    transcriber.result = const Transcript(TranscriptStatus.unavailable);
    final c = await openNote(tester);
    type(c, '/');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voice note'));
    await tester.pumpAndSettle();
    await record(tester);

    expect(await attachments(), hasLength(1));
    expect(c.document.toPlainText(), '▸ 0:00 Voice note\n\n');
    expect(find.textContaining('can’t transcribe'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await closeEditor(tester);
  });

  testWidgets('where recordings are not transcribed, it just saves quietly', (
    tester,
  ) async {
    transcribes = false;
    final c = await openNote(tester);
    type(c, '/');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voice note'));
    await tester.pumpAndSettle();
    await record(tester);

    expect(await attachments(), hasLength(1));
    expect(transcriber.calls, 0);
    expect(c.document.toPlainText(), '▸ 0:00 Voice note\n\n');
    expect(find.byType(SnackBar), findsNothing);
    await closeEditor(tester);
  });

  testWidgets('the attach sheet records audio into the note', (tester) async {
    final c = await openNote(tester);
    await tester.tap(find.byTooltip('Attach audio, image or file'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record audio'));
    await tester.pumpAndSettle();
    // The attach sheet closes; the recorder takes its place.
    expect(find.text('Podcast link'), findsNothing);
    await record(tester);

    expect((await attachments()).single.noteId, 'n1');
    // Released (and so disposed) once the sheet closed, not before.
    expect(recorder.disposed, isTrue);
    expect(c.document.toPlainText(), contains('▸ 0:00 Voice note'));
    expect(c.document.toPlainText(), contains('Attention scales badly.'));
    await closeEditor(tester);
  });

  testWidgets('dictation types text without keeping audio', (tester) async {
    final c = await openNote(tester);
    type(c, 'Say: ');
    type(c, '/');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dictate'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('voice-record-button')));
    await tester.pumpAndSettle();
    expect(find.text('so far'), findsOneWidget);
    await tester.tap(find.byKey(const Key('voice-record-button')));
    await tester.pumpAndSettle();

    expect(await attachments(), isEmpty);
    expect(c.document.toPlainText(), 'Say: dictated words \n');
    await closeEditor(tester);
  });

  testWidgets('a paper gets the recording as audio only', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () =>
                    showAddAttachmentSheet(context, ref, paperId: 'p1'),
                child: const Text('Attach'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Attach'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record audio'));
    await tester.pumpAndSettle();
    await record(tester);

    final rows = await attachments();
    expect(rows.single.paperId, 'p1');
    expect(rows.single.noteId, isNull);
    expect(transcriber.calls, 0);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
