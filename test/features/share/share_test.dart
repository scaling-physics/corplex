import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:drift/drift.dart' show Value;
import 'package:http/http.dart' as http;
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'package:corplex/app.dart';
import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/library/metadata_lookup.dart';
import 'package:corplex/features/share/share_import.dart';
import 'package:corplex/features/share/shared_items.dart';

import '../../support/fake_audio_engine.dart';

SharedMediaFile _file(String path, {String? mime}) =>
    SharedMediaFile(path: path, type: SharedMediaType.file, mimeType: mime);

SharedMediaFile _text(String text) =>
    SharedMediaFile(path: text, type: SharedMediaType.text);

/// App storage inside a temp folder.
class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProvider(this.dir);

  final String dir;

  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

class _FakeShareSource implements ShareIntentSource {
  _FakeShareSource(this.launch);

  final List<SharedMediaFile> launch;
  final controller = StreamController<List<SharedMediaFile>>.broadcast();
  bool wasReset = false;

  @override
  Future<List<SharedMediaFile>> initial() async => launch;

  @override
  Stream<List<SharedMediaFile>> get stream => controller.stream;

  @override
  Future<void> reset() async => wasReset = true;
}

void main() {
  group('classifyShared', () {
    test('PDFs by extension or mime type', () {
      final items = classifyShared([
        _file('/x/paper.PDF'),
        _file('/x/download', mime: 'application/pdf'),
      ]);
      expect(items, everyElement(isA<SharedPdf>()));
      expect(items, hasLength(2));
      expect((items.first as SharedPdf).name, 'paper');
    });

    test('audio by extension or mime type', () {
      final items = classifyShared([
        _file('/x/overview.m4a'),
        _file('/x/clip', mime: 'audio/mpeg'),
      ]);
      expect(items, everyElement(isA<SharedAudio>()));
    });

    test('DOIs and arXiv links — bare or inside a shared page', () {
      final items = classifyShared([
        _text('10.1038/nature14539'),
        _text('Attention Is All You Need\nhttps://arxiv.org/abs/1706.03762'),
        _text('https://doi.org/10.5555/3295222.3295349'),
      ]);
      expect(items, everyElement(isA<SharedIdentifier>()));
      expect((items[1] as SharedIdentifier).identifier.value, '1706.03762');
    });

    test('other links and plain text', () {
      final items = classifyShared([
        _text('Interesting read: https://example.com/post?id=3'),
        _text('remember to cite Smith'),
      ]);
      expect((items[0] as SharedLink).url.host, 'example.com');
      expect((items[1] as SharedText).text, 'remember to cite Smith');
    });

    test('images, videos, unknown files and empty text are ignored', () {
      expect(
        classifyShared([
          SharedMediaFile(path: '/x/a.png', type: SharedMediaType.image),
          SharedMediaFile(path: '/x/a.mp4', type: SharedMediaType.video),
          _file('/x/archive.zip'),
          _text('   '),
        ]),
        isEmpty,
      );
    });
  });

  group('receiving a share', () {
    late AppDatabase db;
    late Directory tmp;

    setUp(() {
      db = AppDatabase.inMemoryForTesting();
      tmp = Directory.systemTemp.createTempSync('corplex_share');
      PathProviderPlatform.instance = _FakePathProvider('${tmp.path}/docs');
      EditableText.debugDeterministicCursor = true;
    });
    tearDown(() async {
      EditableText.debugDeterministicCursor = false;
      await db.close();
      tmp.deleteSync(recursive: true);
    });

    Widget app(_FakeShareSource source) => ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        audioEngineProvider.overrideWithValue(FakeAudioEngine()),
        shareIntentSourceProvider.overrideWithValue(source),
        // Never touch the network from a test.
        metadataLookupProvider.overrideWithValue(
          MetadataLookup(client: _OfflineClient()),
        ),
      ],
      child: const CorplexApp(),
    );

    /// Shows the app, then lets real file IO (which never completes under
    /// the test's fake clock) finish before settling the UI.
    Future<void> settle(WidgetTester tester) async {
      // Alternate: run fake-clock work (starts the next step), then let
      // real file IO finish.
      // Each awaited file operation needs one round trip.
      for (var i = 0; i < 12; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
      }
      await tester.pumpAndSettle();
    }

    Future<void> launch(WidgetTester tester, _FakeShareSource source) async {
      await tester.pumpWidget(app(source));
      await settle(tester);
    }

    Future<void> dispose(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    }

    testWidgets(
      'a shared link becomes a note, and the launch share is cleared',
      (tester) async {
        final source = _FakeShareSource([_text('https://example.com/post')]);
        await tester.pumpWidget(app(source));
        await tester.pumpAndSettle();

        final note = await db.select(db.notes).getSingle();
        expect(note.title, 'example.com');
        expect(note.content, contains('https://example.com/post'));
        expect(
          jsonDecode(note.content).first['attributes']['link'],
          'https://example.com/post',
        );
        expect(find.text('Saved link as a note'), findsOneWidget);
        expect(source.wasReset, isTrue);
        await dispose(tester);
      },
    );

    testWidgets('plain text arriving while running becomes a note', (
      tester,
    ) async {
      final source = _FakeShareSource(const []);
      await tester.pumpWidget(app(source));
      await tester.pumpAndSettle();

      source.controller.add([_text('Cite Smith 2019 for this claim')]);
      await tester.pumpAndSettle();

      final note = await db.select(db.notes).getSingle();
      expect(note.title, 'Cite Smith 2019 for this claim');
      await dispose(tester);
    });

    testWidgets('a shared PDF becomes a paper in the library', (tester) async {
      final pdf = File('${tmp.path}/Some Paper.pdf')
        ..writeAsBytesSync([37, 80, 68, 70]);
      final source = _FakeShareSource([_file(pdf.path)]);
      await launch(tester, source);

      final paper = await db.select(db.papers).getSingle();
      expect(paper.title, 'Some Paper');
      expect(paper.pdfPath, isNotNull);
      expect(File(paper.pdfPath!).existsSync(), isTrue);
      await dispose(tester);
    });

    testWidgets('shared audio asks where to attach it', (tester) async {
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: const Value('n1'),
              title: const Value('Lecture'),
            ),
          );
      final audio = File('${tmp.path}/overview.m4a')
        ..writeAsBytesSync([1, 2, 3]);
      final source = _FakeShareSource([_file(audio.path)]);
      await launch(tester, source);

      expect(find.textContaining('Attach “overview” to'), findsOneWidget);
      await tester.tap(find.text('Lecture').last);
      await settle(tester);

      final attachment = await db.select(db.attachments).getSingle();
      expect(attachment.noteId, 'n1');
      expect(attachment.title, 'overview');
      expect(File(attachment.path!).readAsBytesSync(), [1, 2, 3]);
      await dispose(tester);
    });

    testWidgets('dismissing the audio question attaches nothing', (
      tester,
    ) async {
      final audio = File('${tmp.path}/overview.m4a')..writeAsBytesSync([1]);
      await launch(tester, _FakeShareSource([_file(audio.path)]));
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(await db.select(db.attachments).get(), isEmpty);
      expect(await db.select(db.notes).get(), isEmpty);
      await dispose(tester);
    });
  });
}

/// An HTTP client that is always offline.
class _OfflineClient extends Fake implements http.Client {}
