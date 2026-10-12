import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

/// The little of a PDF that OCR needs, behind an interface so tests don't
/// need a real PDF engine. Page indexes are 0-based.
abstract class PdfPages {
  int get pageCount;

  /// The page's text layer (empty for a scan).
  Future<String> text(int index);

  /// The page rendered at about [scale]x its point size, as PNG on white.
  Future<Uint8List?> renderPng(int index, {double scale = 2});

  Future<void> dispose();
}

typedef PdfPagesOpener = Future<PdfPages> Function(String path);

/// Longest edge rendered for recognition; bigger adds time, not accuracy.
const _maxEdge = 3200;

class PdfrxPages implements PdfPages {
  PdfrxPages._(this._doc);

  final PdfDocument _doc;

  static Future<PdfPages> open(String path) async =>
      PdfrxPages._(await PdfDocument.openFile(path));

  @override
  int get pageCount => _doc.pages.length;

  @override
  Future<String> text(int index) async =>
      (await _doc.pages[index].loadStructuredText()).fullText;

  @override
  Future<Uint8List?> renderPng(int index, {double scale = 2}) async {
    final page = _doc.pages[index];
    var s = scale;
    final longest = page.width > page.height ? page.width : page.height;
    if (longest * s > _maxEdge) s = _maxEdge / longest;
    final width = (page.width * s).round();
    final height = (page.height * s).round();
    final rendered = await page.render(
      width: width,
      height: height,
      fullWidth: width.toDouble(),
      fullHeight: height.toDouble(),
      backgroundColor: 0xffffffff,
    );
    if (rendered == null) return null;
    final ui.Image image;
    try {
      image = await rendered.createImage();
    } finally {
      rendered.dispose();
    }
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      return png?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  @override
  Future<void> dispose() => _doc.dispose();
}

/// Tests override this to avoid opening real PDFs.
final pdfPagesOpenerProvider = Provider<PdfPagesOpener>(
  (ref) => PdfrxPages.open,
);
