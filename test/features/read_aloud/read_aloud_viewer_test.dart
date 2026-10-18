import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/library/pdf_viewer_screen.dart';
import 'package:corplex/features/read_aloud/speaker.dart';

import 'fake_speaker.dart';

void main() {
  Future<AppDatabase> pump(WidgetTester tester, Speaker? speaker) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase.inMemoryForTesting();
    addTearDown(db.close);
    await db
        .into(db.papers)
        .insert(PapersCompanion.insert(id: const Value('p'), title: 't'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          if (speaker != null) speakerProvider.overrideWithValue(speaker),
        ],
        child: MaterialApp(
          home: PdfViewerScreen(
            paperId: 'p',
            pdfPath: '/none.pdf',
            viewerBuilder: (context, controller, params) =>
                const SizedBox.expand(),
            textProbe: PageTextProbe(
              pageCount: 2,
              text: (page) async => page == 1
                  ? 'The first page has plenty of words to read aloud today.'
                  : 'The second page also has some words to read aloud.',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return db;
  }

  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('More → Read aloud opens the bar and speaks', (tester) async {
    final speaker = FakeSpeaker();
    await pump(tester, speaker);
    expect(find.byKey(const ValueKey('read-toggle')), findsNothing);

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Read aloud'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.byKey(const ValueKey('read-toggle')), findsOneWidget);
    expect(speaker.spoken, isNotEmpty);
    expect(speaker.spoken.first, startsWith('The first page'));

    await tester.tap(find.byKey(const ValueKey('read-toggle')));
    await tester.pump();
    expect(speaker.pauses, 1);

    await tester.tap(find.byKey(const ValueKey('read-close')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('read-toggle')), findsNothing);
    expect(speaker.stops, greaterThan(0));
    await teardown(tester);
  });

  testWidgets('says so when speech is unavailable', (tester) async {
    await pump(tester, null);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Read aloud'));
    await tester.pump();
    expect(find.text("Reading aloud isn't available here"), findsOneWidget);
    expect(find.byKey(const ValueKey('read-toggle')), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    await teardown(tester);
  });
}
