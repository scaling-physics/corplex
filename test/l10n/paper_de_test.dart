import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/library/paper_cover.dart';
import 'package:corplex/features/library/paper_detail_screen.dart';

import '../support/fake_audio_engine.dart';
import '../support/l10n_app.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    EditableText.debugDeterministicCursor = true;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
    await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(
            id: const Value('p1'),
            title: 'Attention is all you need',
            doi: const Value('10.1000/x'),
          ),
        );
  });
  tearDown(() {
    EditableText.debugDeterministicCursor = false;
    db.close();
  });

  testWidgets('paper screen in German fits a 360 px phone', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          audioEngineProvider.overrideWithValue(FakeAudioEngine()),
          coverRendererProvider.overrideWithValue((_) async => null),
        ],
        child: localizedApp(const PaperDetailScreen(paperId: 'p1')),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Zu lesen'), findsOneWidget);
    expect(find.text('Am Lesen'), findsOneWidget);
    expect(find.text('Gelesen'), findsOneWidget);
    expect(find.text('Anhänge'), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);
    expect(find.text('Suchen'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
