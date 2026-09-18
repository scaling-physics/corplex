import 'dart:ui';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/features/library/annotations_providers.dart';

void main() {
  late AppDatabase db;
  late int paperId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    paperId = await db
        .into(db.papers)
        .insert(PapersCompanion.insert(title: 'A paper'));
  });

  tearDown(() => db.close());

  test('a saved stroke round-trips its points and color', () async {
    const points = [Offset(0.1, 0.2), Offset(0.3, 0.4), Offset(0.5, 0.6)];
    await saveHighlightStroke(
      db,
      paperId: paperId,
      pageNumber: 1,
      normalizedPoints: points,
      color: const Color(0xFFFFEB3B),
    );

    final saved = await db.select(db.annotations).getSingle();
    expect(decodeStrokePoints(saved.pointsJson), points);
    expect(colorFromHex(saved.colorHex), const Color(0xFFFFEB3B));
  });

  test('a stroke with fewer than 2 points is not saved', () async {
    await saveHighlightStroke(
      db,
      paperId: paperId,
      pageNumber: 1,
      normalizedPoints: const [Offset(0.1, 0.2)],
      color: const Color(0xFFFFEB3B),
    );

    final all = await db.select(db.annotations).get();
    expect(all, isEmpty);
  });

  test('strokes are scoped to their page number', () async {
    await saveHighlightStroke(
      db,
      paperId: paperId,
      pageNumber: 1,
      normalizedPoints: const [Offset(0, 0), Offset(1, 1)],
      color: const Color(0xFFFFEB3B),
    );
    await saveHighlightStroke(
      db,
      paperId: paperId,
      pageNumber: 2,
      normalizedPoints: const [Offset(0, 0), Offset(1, 1)],
      color: const Color(0xFFFFEB3B),
    );

    final page1 = await (db.select(
      db.annotations,
    )..where((a) => a.pageNumber.equals(1))).get();
    expect(page1, hasLength(1));
  });
}
