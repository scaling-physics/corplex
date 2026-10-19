import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/library/all_highlights_screen.dart';
import 'package:corplex/features/read_aloud/read_aloud_bar.dart';
import 'package:corplex/features/read_aloud/read_aloud_controller.dart';
import 'package:corplex/features/review/review_screen.dart';
import 'package:corplex/l10n/l10n.dart';

import '../features/read_aloud/fake_speaker.dart';
import '../support/l10n_app.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
  });
  tearDown(() => db.close());

  Future<void> show(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: localizedApp(child),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('all highlights, empty, in German', (tester) async {
    await show(tester, const AllHighlightsScreen());
    expect(find.text('Noch keine Markierungen'), findsOneWidget);
    expect(find.byTooltip('Markierungen wiederholen'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('the revisit screen, empty, in German', (tester) async {
    await show(tester, const ReviewScreen());
    expect(find.text('Markierungen wiederholen'), findsOneWidget);
    expect(find.text('Nichts zu wiederholen'), findsOneWidget);
    expect(find.text('Auf dem Home-Bildschirm erinnern'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('the read-aloud bar fits a 360 px phone in German', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final speaker = FakeSpeaker();
    final c = ReadAloudController(
      speaker: speaker,
      pageCount: 2,
      pageText: (p) async => const {
        1: 'Page one first. Page one second.',
        2: 'Page two first. Page two second.',
      }[p]!,
      startPage: 1,
    );
    addTearDown(c.dispose);
    await tester.runAsync(c.start);
    await tester.pumpWidget(
      localizedApp(
        Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ReadAloudBar(
              controller: c,
              away: true,
              onBackToReading: () {},
              onClose: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Zurück zur Vorlesestelle'), findsOneWidget);
    expect(find.byTooltip('Voriger Satz'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  test('find summary and counts are translated', () {
    final de = lookupAppLocalizations(const Locale('de'));
    expect(de.viewerFindCount(3, 41), '3 von 41');
    expect(de.viewerFindCountMore(1, 1), '1 von 1+');
    expect(de.viewerPagePill(3, 24), '3 / 24');
    expect(de.ocrReadingText(40), 'Text wird gelesen… 40 %');
    expect(de.reviewPrompt(1), '1 Markierung zum Wiederholen');
    expect(de.reviewPrompt(4), '4 Markierungen zum Wiederholen');
  });
}
