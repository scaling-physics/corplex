import 'dart:convert';
import 'dart:ui';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';

typedef PageKey = ({String paperId, int pageNumber});

final annotationsForPageProvider = StreamProvider.autoDispose
    .family<List<Annotation>, PageKey>((ref, key) {
      final db = ref.watch(databaseProvider);
      return (db.select(db.annotations)..where(
            (a) =>
                a.paperId.equals(key.paperId) &
                a.pageNumber.equals(key.pageNumber),
          ))
          .watch();
    });

/// Decodes a stroke's stored JSON into normalized (0..1) points.
List<Offset> decodeStrokePoints(String pointsJson) {
  final raw = jsonDecode(pointsJson) as List;
  return raw
      .map((p) => Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()))
      .toList();
}

String _encodeStrokePoints(List<Offset> points) {
  return jsonEncode(points.map((p) => [p.dx, p.dy]).toList());
}

String colorToHex(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';

Color colorFromHex(String hex) {
  final value = int.parse(hex.replaceFirst('#', ''), radix: 16);
  return Color(0xFF000000 | value);
}

Future<void> saveHighlightStroke(
  AppDatabase db, {
  required String paperId,
  required int pageNumber,
  required List<Offset> normalizedPoints,
  required Color color,
}) {
  if (normalizedPoints.length < 2) return Future.value();
  return db
      .into(db.annotations)
      .insert(
        AnnotationsCompanion.insert(
          paperId: paperId,
          pageNumber: pageNumber,
          pointsJson: _encodeStrokePoints(normalizedPoints),
          colorHex: Value(colorToHex(color)),
        ),
      );
}
