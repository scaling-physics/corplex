import 'dart:convert';

import 'package:corplex/app.dart';
import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/markdown_import/markdown_import_ui.dart';
import 'package:corplex/features/markdown_import/vault_source.dart';
import 'package:corplex/features/share/share_import.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../../support/fake_audio_engine.dart';

class _NoShares implements ShareIntentSource {
  @override
  Future<List<SharedMediaFile>> initial() async => const [];

  @override
  Stream<List<SharedMediaFile>> get stream => const Stream.empty();

  @override
  Future<void> reset() async {}
}

class _FakePicker implements MarkdownImportPicker {
  _FakePicker(this.files);
  final List<MdSourceFile>? files;
  final asked = <String>[];

  @override
  Future<List<MdSourceFile>?> pickFolder() async {
    asked.add('folder');
    return files;
  }

  @override
  Future<List<MdSourceFile>?> pickFiles() async {
    asked.add('files');
    return files;
  }

  @override
  Future<List<MdSourceFile>?> pickZip() async {
    asked.add('zip');
    return files;
  }
}

MemorySourceFile _md(String path, String text) =>
    MemorySourceFile(path, () => utf8.encode(text));

void main() {
  late AppDatabase db;

  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .implicitView!;
    view.physicalSize = const Size(1080, 2400);
    view.devicePixelRatio = 3;
    EditableText.debugDeterministicCursor = true;
    db = AppDatabase.inMemoryForTesting();
  });

  tearDown(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .implicitView!;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
    EditableText.debugDeterministicCursor = false;
    db.close();
  });

  Widget app(_FakePicker picker) => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      audioEngineProvider.overrideWithValue(FakeAudioEngine()),
      shareIntentSourceProvider.overrideWithValue(_NoShares()),
      markdownImportPickerProvider.overrideWithValue(picker),
    ],
    child: const CorplexApp(),
  );

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('the account sheet imports Markdown and summarises it', (
    tester,
  ) async {
    final picker = _FakePicker([
      _md('One.md', 'links to [[Two]] and [[Ghost]]'),
      _md('Two.md', 'body'),
    ]);
    await tester.pumpWidget(app(picker));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Import Markdown or Obsidian vault'), findsOneWidget);
    await tester.tap(find.text('Import Markdown or Obsidian vault'));
    await tester.pumpAndSettle();

    // Choose where from.
    expect(find.text('A folder (an Obsidian vault)'), findsOneWidget);
    expect(find.text('Markdown files'), findsOneWidget);
    expect(find.text('A zip of Markdown files'), findsOneWidget);
    await tester.tap(find.text('A folder (an Obsidian vault)'));
    await tester.pumpAndSettle();

    expect(picker.asked, ['folder']);
    expect(find.text('Import finished'), findsOneWidget);
    expect(find.text('2 notes imported'), findsOneWidget);
    expect(
      find.text('1 link matched nothing and was left as text'),
      findsOneWidget,
    );
    expect(await db.select(db.notes).get(), hasLength(2));

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await dispose(tester);
  });

  testWidgets('cancelling the picker imports nothing', (tester) async {
    final picker = _FakePicker(null);
    await tester.pumpWidget(app(picker));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Sign in'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import Markdown or Obsidian vault'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A zip of Markdown files'));
    await tester.pumpAndSettle();

    expect(picker.asked, ['zip']);
    expect(find.text('Import finished'), findsNothing);
    expect(await db.select(db.notes).get(), isEmpty);
    await dispose(tester);
  });

  testWidgets('a pick without Markdown says so', (tester) async {
    final picker = _FakePicker([_md('readme.txt', 'x')]);
    await tester.pumpWidget(app(picker));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Sign in'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import Markdown or Obsidian vault'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Markdown files'));
    await tester.pumpAndSettle();

    expect(find.text('No Markdown notes were found there.'), findsOneWidget);
    expect(find.text('Import finished'), findsNothing);
    await dispose(tester);
  });
}
