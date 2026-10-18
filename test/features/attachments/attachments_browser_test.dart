import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/data/tables/attachments_table.dart';
import 'package:corplex/features/attachments/attachments_browser.dart';
import 'package:corplex/features/attachments/attachments_providers.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/lock/note_crypto.dart';
import 'package:corplex/features/lock/note_lock_service.dart';

import '../../support/fake_audio_engine.dart';
import '../../support/mac_screenshot.dart';

void main() {
  late AppDatabase db;

  setUpAll(loadMacFonts);
  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n1'),
            title: const Value('Grant'),
          ),
        );
    await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(
            id: const Value('p1'),
            title: 'Attention paper',
          ),
        );
  });
  tearDown(() => db.close());

  Future<void> add(
    String id,
    AttachmentType type, {
    String? noteId,
    String? paperId,
    String? title,
    String? path,
    String? url,
    required int minute,
  }) => db
      .into(db.attachments)
      .insert(
        AttachmentsCompanion.insert(
          id: Value(id),
          type: type,
          noteId: Value(noteId),
          paperId: Value(paperId),
          title: Value(title),
          path: Value(path),
          url: Value(url),
          createdAt: Value(DateTime(2026, 1, 1, 10, minute)),
        ),
      );

  NoteLockService lockService() => NoteLockService(
    db,
    crypto: NoteCrypto(iterations: 1000),
    inlineKdf: true,
  );

  Future<ProviderContainer> container({NoteLockService? lock}) async {
    final c = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        if (lock != null) noteLockServiceProvider.overrideWith((_) => lock),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<List<AttachmentEntry>> read(ProviderContainer c) async {
    c.listen(allAttachmentsProvider, (_, _) {});
    return c.read(allAttachmentsProvider.future);
  }

  test('newest first, with parent titles and kinds', () async {
    await add(
      'a1',
      AttachmentType.image,
      noteId: 'n1',
      path: '/x/a.png',
      minute: 1,
    );
    await add(
      'a2',
      AttachmentType.link,
      paperId: 'p1',
      url: 'https://e.org',
      minute: 3,
    );
    await add(
      'a3',
      AttachmentType.file,
      noteId: 'n1',
      path: '/x/1_data.csv',
      minute: 2,
    );
    final list = await read(await container());
    expect(list.map((e) => e.attachment.id), ['a2', 'a3', 'a1']);
    expect(list[0].parentTitle, 'Attention paper');
    expect(list[0].kind, AttachmentKind.link);
    expect(list[1].parentTitle, 'Grant');
    expect(list[1].kind, AttachmentKind.file);
    expect(list[2].kind, AttachmentKind.image);
  });

  test('attachments of locked notes are hidden until unlocked', () async {
    await add(
      'a1',
      AttachmentType.image,
      noteId: 'n1',
      path: '/x/a.png',
      minute: 1,
    );
    await add(
      'a2',
      AttachmentType.link,
      paperId: 'p1',
      url: 'https://e.org',
      minute: 2,
    );
    final lock = lockService();
    await lock.setPassword('secret');
    await lock.lockNote('n1');
    final c = await container(lock: lock);
    c.listen(allAttachmentsProvider, (_, _) {});
    expect((await c.read(allAttachmentsProvider.future)).length, 2);
    lock.lockNow();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(
      (await c.read(allAttachmentsProvider.future)).map((e) => e.attachment.id),
      ['a2'],
    );
    expect(await lock.unlock('secret'), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect((await c.read(allAttachmentsProvider.future)).length, 2);
  });

  Future<void> pump(WidgetTester tester, {FakeAudioEngine? audio}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          audioEngineProvider.overrideWithValue(audio ?? FakeAudioEngine()),
        ],
        child: MaterialApp(home: const AttachmentsBrowserScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('empty state', (tester) async {
    await pump(tester);
    expect(find.text('No attachments yet'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('filter chips only for existing kinds; hidden for one kind', (
    tester,
  ) async {
    await add(
      'a1',
      AttachmentType.link,
      paperId: 'p1',
      url: 'https://e.org',
      minute: 1,
    );
    await pump(tester);
    expect(find.byType(ChoiceChip), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));

    await add(
      'a2',
      AttachmentType.podcast,
      noteId: 'n1',
      url: 'https://e.org/a.mp3',
      title: 'Overview',
      minute: 2,
    );
    await pump(tester);
    expect(find.widgetWithText(ChoiceChip, 'Links'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Audio'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Images'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Audio'));
    await tester.pump();
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('https://e.org'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('tapping an audio row plays it', (tester) async {
    await add(
      'a2',
      AttachmentType.podcast,
      noteId: 'n1',
      url: 'https://e.org/a.mp3',
      title: 'Overview',
      minute: 2,
    );
    final audio = FakeAudioEngine();
    await pump(tester, audio: audio);
    await tester.tap(find.text('Overview'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(audio.loads.single.url, 'https://e.org/a.mp3');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('search filters by label and parent', (tester) async {
    await add(
      'a1',
      AttachmentType.link,
      paperId: 'p1',
      url: 'https://e.org',
      minute: 1,
    );
    await add(
      'a2',
      AttachmentType.podcast,
      noteId: 'n1',
      url: 'https://e.org/a.mp3',
      title: 'Overview',
      minute: 2,
    );
    await pump(tester);
    await tester.enterText(
      find.byKey(const ValueKey('attachments-search')),
      'attention',
    );
    await tester.pump();
    expect(find.text('https://e.org'), findsOneWidget);
    expect(find.text('Overview'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    EditableText.debugDeterministicCursor = false;
  });

  for (final entry in [
    ('laptop13', macWindowSizes['laptop13']!),
    ('dell38', macWindowSizes['dell38']!),
  ]) {
    testWidgets('Mac layout ${entry.$1} without overflow', (tester) async {
      EditableText.debugDeterministicCursor = true;
      useMacWindow(tester, entry.$2);
      await add(
        'a1',
        AttachmentType.image,
        noteId: 'n1',
        path: '/missing/a.png',
        minute: 1,
      );
      await add(
        'a2',
        AttachmentType.link,
        paperId: 'p1',
        url: 'https://e.org',
        minute: 2,
      );
      await add(
        'a3',
        AttachmentType.file,
        noteId: 'n1',
        path: '/x/1_data.csv',
        minute: 3,
      );
      await pump(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(GridView), findsNothing); // sliver grid
      expect(find.text('Attachments'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
      EditableText.debugDeterministicCursor = false;
    }, variant: macOnly);
  }

  testWidgets('phone layout without overflow', (tester) async {
    EditableText.debugDeterministicCursor = true;
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await add(
      'a1',
      AttachmentType.image,
      noteId: 'n1',
      path: '/missing/a.png',
      minute: 1,
    );
    await add(
      'a2',
      AttachmentType.link,
      paperId: 'p1',
      url: 'https://e.org',
      minute: 2,
    );
    await pump(tester);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    EditableText.debugDeterministicCursor = false;
  });
}
