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

/// A paper's cover, keyed by paper id and local PDF path. Lives only while
/// something shows it: with 1,500 papers, keeping every cover ever scrolled
/// past (360 px PNGs) was hundreds of megabytes. Scrolling back is instant
/// anyway: the most recent covers sit in a small in-memory cache
/// ([peekCover]) and the rest on disk.
final paperCoverProvider = FutureProvider.autoDispose
    .family<Uint8List?, ({String paperId, String pdfPath})>((ref, key) {
      // Scrolled away before its turn: the queue skips the render.
      var wanted = true;
      ref.onDispose(() => wanted = false);
      return runZoned(
        () => ref.watch(coverRendererProvider)(key.pdfPath),
        zoneValues: {_wantedKey: () => wanted},
      );
    });

const _wantedKey = #corplexCoverWanted;

/// The cover for [pdfPath] if it was rendered or loaded recently, without
/// waiting for a future.
Uint8List? peekCover(String pdfPath) {
  final bytes = _recent.remove(pdfPath);
  if (bytes != null) _recent[pdfPath] = bytes;
  return bytes;
}

// Most recently used last. Bounded by count: a cover is up to ~100 KB.
final _recent = <String, Uint8List>{};
const _recentCovers = 120;

void _remember(String pdfPath, Uint8List bytes) {
  _recent.remove(pdfPath);
  _recent[pdfPath] = bytes;
  while (_recent.length > _recentCovers) {
    _recent.remove(_recent.keys.first);
  }
}

// One render at a time: a Library scroll shouldn't open fifty PDFs at once.
Future<void> _queue = Future.value();

Future<Uint8List?> _cachedCover(String pdfPath) {
  final recent = peekCover(pdfPath);
  if (recent != null) return Future.value(recent);
  final wanted = Zone.current[_wantedKey] as bool Function()?;
  final result = _queue.then((_) async {
    // A fast scroll queues hundreds of covers; skip the ones already gone.
    if (wanted != null && !wanted()) return null;
    final bytes = await _loadOrRender(pdfPath);
    if (bytes != null) _remember(pdfPath, bytes);
    return bytes;
  });
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
                  .value ??
              peekCover(path);
    // Decode at the size it's shown (the PNG is 360 px wide): a 48 px list
    // thumbnail otherwise holds a full-size bitmap in the image cache.
    final decodeWidth = (width * MediaQuery.devicePixelRatioOf(context))
        .ceil()
        .clamp(1, coverPixelWidth);
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
                  cacheWidth: decodeWidth,
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
