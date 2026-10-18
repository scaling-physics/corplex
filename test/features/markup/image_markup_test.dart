import 'dart:io';
import 'dart:ui' as ui;

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/data/tables/attachments_table.dart';
import 'package:corplex/features/ink/ink_canvas.dart';
import 'package:corplex/features/markup/image_markup.dart';
import 'package:corplex/features/markup/image_markup_screen.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProvider(this.dir);
  final String dir;

  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

void main() {
  late Directory tmp;
  late AppDatabase db;
  late String original;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('markup_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    db = AppDatabase.inMemoryForTesting();
  });

  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
    }
    await tester.pump();
  }

  Future<Attachment> seed(WidgetTester tester) async {
    await tester.runAsync(() async {
      final rec = ui.PictureRecorder();
      Canvas(rec).drawRect(
        const Rect.fromLTWH(0, 0, 40, 20),
        Paint()..color = const Color(0xFF2266CC),
      );
      final img = await rec.endRecording().toImage(40, 20);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      original = '${tmp.path}/pic.png';
      File(original).writeAsBytesSync(data!.buffer.asUint8List());
      await db
          .into(db.attachments)
          .insert(
            AttachmentsCompanion.insert(
              id: const Value('a1'),
              type: AttachmentType.image,
              path: Value(original),
              storageKey: const Value('user/attachments/a1.png'),
            ),
          );
    });
    return (await tester.runAsync(
      () => db.select(db.attachments).getSingle(),
    ))!;
  }

  Future<void> open(WidgetTester tester, Attachment a) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(home: ImageMarkupScreen(attachment: a)),
      ),
    );
    await settle(tester);
  }

  Future<void> drawStroke(WidgetTester tester) async {
    final origin = tester.getTopLeft(find.byType(InkCanvas));
    final g = await tester.startGesture(
      origin + const Offset(40, 40),
      kind: PointerDeviceKind.stylus,
    );
    for (var i = 1; i <= 8; i++) {
      await g.moveTo(origin + Offset(40.0 + i * 20, 40));
    }
    await g.up();
    await tester.pump();
  }

  Future<Attachment> row(WidgetTester tester) async =>
      (await tester.runAsync(() => db.select(db.attachments).getSingle()))!;

  testWidgets('Done saves a PNG and repoints the attachment', (tester) async {
    final a = await seed(tester);
    await open(tester, a);
    await drawStroke(tester);
    expect(
      tester.widget<InkCanvas>(find.byType(InkCanvas)).sketch.strokes,
      hasLength(1),
    );

    await tester.tap(find.text('Done'));
    await settle(tester);

    final saved = await row(tester);
    expect(saved.path, isNot(original));
    expect(saved.storageKey, isNull);
    expect(File(saved.path!).existsSync(), isTrue);
    expect(File(original).existsSync(), isTrue);
    final size = await tester.runAsync(() => imageSizeOf(saved.path!));
    expect(size, const Size(40, 20));
  });

  testWidgets('Cancel changes nothing', (tester) async {
    final a = await seed(tester);
    await open(tester, a);
    await drawStroke(tester);
    await tester.tap(find.byTooltip('Cancel'));
    await settle(tester);

    final after = await row(tester);
    expect(after.path, original);
    expect(after.storageKey, 'user/attachments/a1.png');
  });

  testWidgets('marking up again reopens the earlier strokes', (tester) async {
    final a = await seed(tester);
    await open(tester, a);
    await drawStroke(tester);
    await tester.tap(find.text('Done'));
    await settle(tester);

    final saved = await row(tester);
    final first = saved.path!;
    await tester.pumpWidget(const SizedBox.shrink());
    await open(tester, saved);
    final sketch = tester.widget<InkCanvas>(find.byType(InkCanvas)).sketch;
    expect(sketch.strokes, hasLength(1));

    // Add a second stroke and save: the old composite is replaced.
    await drawStroke(tester);
    await tester.tap(find.text('Done'));
    await settle(tester);
    final again = await row(tester);
    expect(again.path, isNot(first));
    expect(File(first).existsSync(), isFalse);
    expect(File(original).existsSync(), isTrue);
    final source = await tester.runAsync(() => loadMarkupSource(again.path!));
    expect(source!.originalPath, original);
    expect(source.sketch!.strokes, hasLength(2));
  });
}
