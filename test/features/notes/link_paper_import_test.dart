import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:share_plus/share_plus.dart' show XFile;

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/library/metadata_lookup.dart';
import 'package:corplex/features/notes/link_paper_sheet.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProvider(this.dir);

  final String dir;

  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

/// Just enough of a picked file for the import flow (name and path).
base class _PickedFile extends PlatformFile {
  _PickedFile(this.filePath);

  final String filePath;

  @override
  String get name => filePath.split('/').last;

  @override
  Uri get uri => Uri.file(filePath);

  @override
  XFile get xFile => throw UnimplementedError();

  @override
  int? lengthSync() => File(filePath).lengthSync();

  @override
  Future<int?> length() async => File(filePath).lengthSync();

  @override
  Future<Uint8List> readAsBytes() => File(filePath).readAsBytes();

  @override
  Stream<Uint8List> readAsByteStream() =>
      File(filePath).openRead().map(Uint8List.fromList);
}

/// Answers the picker with a fixed file (or "cancelled" when [path] is null).
class _FakePicker extends FilePickerPlatform {
  _FakePicker(this.path);

  final String? path;
  int calls = 0;

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    calls++;
    final p = path;
    return p == null ? null : _PickedFile(p);
  }
}

class _OfflineClient extends Fake implements http.Client {}

void main() {
  late AppDatabase db;
  late Directory tmp;

  setUp(() async {
    EditableText.debugDeterministicCursor = true;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
    tmp = Directory.systemTemp.createTempSync('corplex_linkimport');
    PathProviderPlatform.instance = _FakePathProvider('${tmp.path}/docs');
    await db
        .into(db.notes)
        .insert(NotesCompanion.insert(id: const Value('n1')));
    await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(id: const Value('old'), title: 'Already here'),
        );
  });
  tearDown(() async {
    EditableText.debugDeterministicCursor = false;
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  Future<void> openSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          metadataLookupProvider.overrideWithValue(
            MetadataLookup(client: _OfflineClient()),
          ),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () => showLinkPaperSheet(context, ref, 'n1'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  // Real file IO never completes under the fake clock; alternate the two.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
    }
    await tester.pumpAndSettle();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('the sheet offers to import a PDF, and the new paper is linked', (
    tester,
  ) async {
    final pdf = File('${tmp.path}/Attention Is All You Need.pdf')
      ..writeAsBytesSync([37, 80, 68, 70]); // not a real PDF: no DOI to find
    final picker = _FakePicker(pdf.path);
    FilePickerPlatform.instance = picker;

    await openSheet(tester);
    expect(find.text('Import a PDF'), findsOneWidget);
    expect(find.text('Already here'), findsOneWidget);

    await tester.tap(find.text('Import a PDF'));
    await settle(tester);

    expect(picker.calls, 1);
    // Listed in the sheet, already ticked as linked.
    expect(find.text('Attention Is All You Need'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    await tester.runAsync(() async {
      final papers = await db.select(db.papers).get();
      final imported = papers.singleWhere((p) => p.id != 'old');
      expect(imported.title, 'Attention Is All You Need');
      expect(imported.pdfPath, startsWith('${tmp.path}/docs/papers/'));
      expect(File(imported.pdfPath!).existsSync(), isTrue);
      final links = await db.select(db.notePaperRefs).get();
      expect(links.map((l) => (l.noteId, l.paperId)), [('n1', imported.id)]);
    });
    await dispose(tester);
  });

  testWidgets('cancelling the picker changes nothing', (tester) async {
    final picker = _FakePicker(null);
    FilePickerPlatform.instance = picker;

    await openSheet(tester);
    await tester.tap(find.text('Import a PDF'));
    await settle(tester);

    expect(picker.calls, 1);
    await tester.runAsync(() async {
      expect(await db.select(db.papers).get(), hasLength(1));
      expect(await db.select(db.notePaperRefs).get(), isEmpty);
    });
    await dispose(tester);
  });
}
