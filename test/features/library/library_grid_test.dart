import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/library/library_grid.dart';
import 'package:corplex/features/library/library_screen.dart';
import 'package:corplex/features/library/paper_cover.dart';
import 'package:corplex/features/platform/mac_window.dart';
import 'package:corplex/features/settings/appearance_settings.dart';
import 'package:corplex/theme/app_theme.dart';
import 'package:corplex/theme/mac_list_row.dart';

import '../../support/mac_screenshot.dart';

void main() {
  late AppDatabase db;
  late AppearanceSettings settings;

  setUpAll(loadMacFonts);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    EditableText.debugDeterministicCursor = true;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
    settings = AppearanceSettings();
    await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(
            id: const Value('p1'),
            title: 'Attention Is All You Need',
            authors: const Value('Vaswani, Ashish'),
            year: const Value(2017),
          ),
        );
  });
  tearDown(() {
    EditableText.debugDeterministicCursor = false;
    db.close();
  });

  Widget app() => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      appearanceSettingsProvider.overrideWith((ref) => settings),
      coverRendererProvider.overrideWithValue((_) async => null),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MacWindowFrame(child: child!),
      home: const Scaffold(body: LibraryScreen()),
    ),
  );

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('pinch out shows a grid of covers, pinch in the rows', (
    tester,
  ) async {
    useMacWindow(tester, macWindowSizes['laptop13']!);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byType(MacListRow), findsOneWidget);
    expect(find.byType(LibraryGrid), findsNothing);

    final center = tester.getCenter(find.text('Attention Is All You Need'));
    final pad = await tester.createGesture(kind: PointerDeviceKind.trackpad);
    await pad.panZoomStart(center);
    await pad.panZoomUpdate(center, scale: 0.6);
    await pad.panZoomEnd();
    await tester.pumpAndSettle();
    expect(settings.libraryGrid, isTrue);
    expect(find.byType(LibraryGrid), findsOneWidget);
    expect(find.byType(MacListRow), findsNothing);
    expect(find.text('Attention Is All You Need'), findsOneWidget);

    await pad.panZoomStart(center);
    await pad.panZoomUpdate(center, scale: 1.5);
    await pad.panZoomEnd();
    await tester.pumpAndSettle();
    expect(settings.libraryGrid, isFalse);
    expect(find.byType(MacListRow), findsOneWidget);
    await close(tester);
  }, variant: macOnly);

  testWidgets('the grid setting is remembered', (tester) async {
    await settings.setLibraryGrid(true);
    final loaded = await AppearanceSettings.load();
    expect(loaded.libraryGrid, isTrue);
  });
}
