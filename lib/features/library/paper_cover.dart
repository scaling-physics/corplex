import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../theme/app_theme.dart';

/// Width in pixels a cover is rendered at: sharp on a 3x phone card and
/// on the paper screen's header, small enough to cache hundreds of.
const coverPixelWidth = 360;

/// A US Letter page; used for the placeholder before (or without) a cover.
const coverAspectRatio = 8.5 / 11;

/// Turns a PDF's first page into PNG bytes, or null if it can't. Behind a
/// provider so tests (where pdfium doesn't run) can swap it.
typedef CoverRenderer = Future<Uint8List?> Function(String pdfPath);

final coverRendererProvider = Provider<CoverRenderer>((ref) => _cachedCover);

/// A paper's cover, keyed by paper id and local PDF path. Kept for the
/// session once loaded, so scrolling back up the Library doesn't flash.
final paperCoverProvider =
    FutureProvider.family<Uint8List?, ({String paperId, String pdfPath})>(
      (ref, key) => ref.watch(coverRendererProvider)(key.pdfPath),
    );

// One render at a time: a Library scroll shouldn't open fifty PDFs at once.
Future<void> _queue = Future.value();

Future<Uint8List?> _cachedCover(String pdfPath) {
  final result = _queue.then((_) => _loadOrRender(pdfPath));
  _queue = result.then((_) {}, onError: (_) {});
  return result;
}

/// Covers are derived data: cached in the OS cache folder (not the backup,
/// not synced), keyed by the file and its modification time, so a replaced
/// PDF gets a new cover.
Future<Uint8List?> _loadOrRender(String pdfPath) async {
  try {
    final pdf = File(pdfPath);
    if (!await pdf.exists()) return null;
    final stamp = (await pdf.lastModified()).millisecondsSinceEpoch;
    final name =
        '${pdfPath.hashCode.toUnsigned(32)}-${await pdf.length()}-$stamp';
    final cacheDir = Directory(
      '${(await getApplicationCacheDirectory()).path}/covers',
    );
    final cached = File('${cacheDir.path}/$name.png');
    if (await cached.exists()) return await cached.readAsBytes();

    final bytes = await renderFirstPage(pdfPath);
    if (bytes == null) return null;
    await cacheDir.create(recursive: true);
    await cached.writeAsBytes(bytes);
    return bytes;
  } catch (_) {
    // Unreadable or encrypted PDF: the placeholder stays.
    return null;
  }
}

/// Renders page 1 of [pdfPath] [coverPixelWidth] wide on white, as PNG.
Future<Uint8List?> renderFirstPage(String pdfPath) async {
  final document = await PdfDocument.openFile(pdfPath);
  try {
    if (document.pages.isEmpty) return null;
    final page = document.pages.first;
    const width = coverPixelWidth;
    final height = (width * page.height / page.width).round();
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
  } finally {
    await document.dispose();
  }
}

/// A paper's first page as a small cover, fading in once rendered. Shows a
/// quiet page-shaped placeholder when there's no PDF or it can't render.
class PaperCover extends ConsumerWidget {
  const PaperCover({
    super.key,
    required this.paperId,
    required this.pdfPath,
    this.width = 48,
    this.borderRadius = const BorderRadius.all(Radius.circular(6)),
  });

  final String paperId;
  final String? pdfPath;
  final double width;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).colorScheme;
    final path = pdfPath;
    final bytes = path == null
        ? null
        : ref
              .watch(paperCoverProvider((paperId: paperId, pdfPath: path)))
              .value;
    final placeholder = ColoredBox(
      color: c.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.description_outlined,
          size: width * 0.4,
          color: c.onSurfaceVariant.withValues(alpha: 0.6),
        ),
      ),
    );
    return SizedBox(
      width: width,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            border: Border.all(color: c.outlineVariant.withValues(alpha: 0.6)),
          ),
          child: bytes == null
              ? AspectRatio(aspectRatio: coverAspectRatio, child: placeholder)
              : Image.memory(
                  bytes,
                  width: width,
                  fit: BoxFit.fitWidth,
                  gaplessPlayback: true,
                  frameBuilder: (context, child, frame, sync) => sync
                      ? child
                      : AnimatedOpacity(
                          opacity: frame == null ? 0 : 1,
                          duration: AppMotion.of(context, AppMotion.medium),
                          curve: AppMotion.enter,
                          child: child,
                        ),
                ),
        ),
      ),
    );
  }
}
