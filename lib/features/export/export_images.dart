import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drift/drift.dart';

import '../../data/database.dart';
import '../../data/tables/attachments_table.dart';

/// An image attached to a note, as the export pipeline is handed it: the
/// file's current path (for a marked-up image that is the composite, never
/// the original kept beside it) and the attachment's title.
class ExportImage {
  const ExportImage(this.path, [this.title]);

  final String path;
  final String? title;
}

/// A note's image attachments in attachment order, skipping rows with no
/// local file path (links, or files not downloaded on this device).
Future<List<ExportImage>> noteExportImages(
  AppDatabase db,
  String noteId,
) async {
  final rows =
      await (db.select(db.attachments)
            ..where(
              (a) =>
                  a.noteId.equals(noteId) &
                  a.type.equalsValue(AttachmentType.image),
            )
            ..orderBy([(a) => OrderingTerm.asc(a.createdAt)]))
          .get();
  return [
    for (final a in rows)
      if (a.path case final path? when path.isNotEmpty)
        ExportImage(path, a.title),
  ];
}

/// An image ready to place in a document: PNG or JPEG bytes (anything else
/// was converted to PNG), its pixel size and an optional caption.
class ExportPhoto {
  const ExportPhoto({
    required this.bytes,
    required this.ext,
    required this.width,
    required this.height,
    this.caption,
    this.name = '',
  });

  final Uint8List bytes;

  /// `png` or `jpg`.
  final String ext;
  final int width;
  final int height;

  /// Null for a camera-style name: it says nothing to a reader.
  final String? caption;

  /// What to call it where an image can't be shown (Markdown share).
  final String name;

  double get aspect => width == 0 ? 1 : height / width;
}

/// Whether [title] is a name a camera, a paste or a screenshot tool made
/// (`IMG_1234.jpg`, `Pasted image`, `2026-10-18 09.30.12`), not a caption.
bool isCameraStyleName(String title) {
  var t = title.trim().replaceFirst(
    RegExp(r'\.(jpe?g|png|heic|heif|webp|gif)$', caseSensitive: false),
    '',
  );
  t = t.replaceFirst(RegExp(r'^\d{10,}_'), '');
  if (t.isEmpty) return true;
  if (RegExp(r'^pasted image\s*\d*$', caseSensitive: false).hasMatch(t)) {
    return true;
  }
  if (RegExp(
    r'^(img|dsc|dscn|dscf|pxl|mvimg|photo|image|pic|picture|screenshot|screen shot|scan|cam|wa)[\s_\-.]*[\d_\-\s.()a-z]*$',
    caseSensitive: false,
  ).hasMatch(t)) {
    // "Image of the apparatus" is a caption; "IMG_1234" is not. Camera
    // names hold no spaces between words.
    return !RegExp(r'[A-Za-z]{3,}\s+[A-Za-z]{3,}').hasMatch(t);
  }
  if (RegExp(r'^[\d\-_.:\sT()]+$').hasMatch(t)) return true;
  if (RegExp(r'^[0-9a-fA-F\-]{16,}$').hasMatch(t)) return true;
  return false;
}

/// Reads [image] for export, or null when the file is missing, isn't an
/// image or can't be decoded. Never throws.
Future<ExportPhoto?> loadExportPhoto(ExportImage image) async {
  try {
    final file = File(image.path);
    if (!file.existsSync()) return null;
    final bytes = await file.readAsBytes();
    final title = image.title?.trim() ?? '';
    final caption = title.isEmpty || isCameraStyleName(title) ? null : title;
    final name = title.isNotEmpty
        ? title
        : image.path.split(RegExp(r'[\\/]')).last;
    final kind = _sniff(bytes);
    final size = kind == null ? null : _size(kind, bytes);
    if (kind != null && size != null) {
      return ExportPhoto(
        bytes: bytes,
        ext: kind == _Kind.png ? 'png' : 'jpg',
        width: size.$1,
        height: size.$2,
        caption: caption,
        name: name,
      );
    }
    // HEIC, WebP, GIF, an odd JPEG: let the engine decode and re-encode.
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return null;
      return ExportPhoto(
        bytes: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        ext: 'png',
        width: frame.image.width,
        height: frame.image.height,
        caption: caption,
        name: name,
      );
    } finally {
      codec.dispose();
    }
  } on Object {
    return null;
  }
}

/// [loadExportPhoto] for each of [images], skipping the unreadable.
Future<List<ExportPhoto>> loadExportPhotos(List<ExportImage> images) async => [
  for (final i in images) ?await loadExportPhoto(i),
];

enum _Kind { png, jpeg }

_Kind? _sniff(Uint8List b) {
  if (b.length > 24 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4E &&
      b[3] == 0x47) {
    return _Kind.png;
  }
  if (b.length > 4 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
    return _Kind.jpeg;
  }
  return null;
}

(int, int)? _size(_Kind kind, Uint8List b) {
  if (kind == _Kind.png) {
    final d = ByteData.sublistView(b);
    final w = d.getUint32(16), h = d.getUint32(20);
    return w > 0 && h > 0 ? (w, h) : null;
  }
  var i = 2;
  while (i + 9 < b.length) {
    if (b[i] != 0xFF) {
      i++;
      continue;
    }
    final m = b[i + 1];
    if (m == 0xFF) {
      i++;
      continue;
    }
    if (m == 0xD8 || (m >= 0xD0 && m <= 0xD7) || m == 0x01 || m == 0) {
      i += 2;
      continue;
    }
    final len = (b[i + 2] << 8) | b[i + 3];
    if (m >= 0xC0 && m <= 0xCF && m != 0xC4 && m != 0xC8 && m != 0xCC) {
      final h = (b[i + 5] << 8) | b[i + 6];
      final w = (b[i + 7] << 8) | b[i + 8];
      return w > 0 && h > 0 ? (w, h) : null;
    }
    i += 2 + len;
  }
  return null;
}
