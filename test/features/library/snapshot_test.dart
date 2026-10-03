import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/features/library/snapshot.dart';
import 'package:corplex/features/notes/note_content.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProvider(this.dir);

  final String dir;

  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

/// A [width]×[height] image, red on the left half and blue on the right.
Future<ui.Image> _halves(int width, int height) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width / 2, height.toDouble()),
    Paint()..color = const Color(0xFFFF0000),
  );
  canvas.drawRect(
    Rect.fromLTWH(width / 2, 0, width / 2, height.toDouble()),
    Paint()..color = const Color(0xFF0000FF),
  );
  return recorder.endRecording().toImage(width, height);
}

void main() {
  testWidgets('cropping keeps just the chosen area, at full resolution', (
    tester,
  ) async {
    await tester.runAsync(() async {
      // A 100×50 view captured at 2×.
      final image = await _halves(200, 100);
      final png = await cropToPng(
        image,
        const Rect.fromLTWH(60, 10, 30, 20),
        2,
      );
      final codec = await ui.instantiateImageCodec(png);
      final cropped = (await codec.getNextFrame()).image;
      expect((cropped.width, cropped.height), (60, 40));
      final pixels = (await cropped.toByteData())!;
      // RGBA of the first pixel: pure blue, none of the red half.
      expect(pixels.getUint32(0), 0x0000FFFF);

      // A box dragged past the edge is clipped to the image.
      final edge = await cropToPng(
        image,
        const Rect.fromLTWH(80, 40, 50, 50),
        2,
      );
      final edgeImage = (await (await ui.instantiateImageCodec(
        edge,
      )).getNextFrame()).image;
      expect((edgeImage.width, edgeImage.height), (40, 20));
    });
  });

  test('a snapshot becomes a note linked to its paper and page', () async {
    final tmp = Directory.systemTemp.createTempSync('snapshot');
    addTearDown(() => tmp.deleteSync(recursive: true));
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    final db = AppDatabase.inMemoryForTesting();
    addTearDown(db.close);
    await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(id: const Value('p1'), title: 'Attention'),
        );

    final noteId = await createSnapshotNote(
      db,
      paperId: 'p1',
      page: 4,
      png: Uint8List.fromList([1, 2, 3]),
    );

    final note = await (db.select(
      db.notes,
    )..where((n) => n.id.equals(noteId))).getSingle();
    expect(note.title, 'Figure from Attention, p. 4');
    expect(notePlainTextPreview(note.content), 'From p. 4');
    expect(note.content, contains('corplex://paper/p1?page=4'));

    final image = await (db.select(
      db.attachments,
    )..where((a) => a.noteId.equals(noteId))).getSingle();
    expect(File(image.path!).readAsBytesSync(), [1, 2, 3]);

    final refs = await db.select(db.notePaperRefs).get();
    expect(refs.single.paperId, 'p1');
  });

  testWidgets('drag a box to choose an area; a tap is not a choice', (
    tester,
  ) async {
    final chosen = <Rect?>[];
    var cancelled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SnapshotOverlay(
            onSelected: chosen.add,
            onCancel: () => cancelled = true,
          ),
        ),
      ),
    );

    await tester.tapAt(const Offset(300, 400));
    await tester.pump();
    expect(chosen, isEmpty);

    final gesture = await tester.startGesture(const Offset(100, 200));
    await gesture.moveBy(const Offset(20, 20));
    await gesture.moveTo(const Offset(300, 350));
    await gesture.up();
    await tester.pump();
    expect(chosen.single, const Rect.fromLTRB(100, 200, 300, 350));

    await tester.tap(find.text('Whole view'));
    expect(chosen.last, isNull);

    await tester.tap(find.byTooltip('Cancel'));
    expect(cancelled, isTrue);
  });
}
