import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Copies a picked file into the app's own document storage so it survives
/// independently of wherever the user originally picked it from, and
/// returns the new local path.
Future<String> copyIntoAppStorage(String sourcePath, String subfolder) async {
  final docsDir = await getApplicationDocumentsDirectory();
  final destDir = Directory(p.join(docsDir.path, subfolder));
  await destDir.create(recursive: true);

  final uniqueName =
      '${DateTime.now().microsecondsSinceEpoch}_${p.basename(sourcePath)}';
  final destPath = p.join(destDir.path, uniqueName);
  await File(sourcePath).copy(destPath);
  return destPath;
}

/// Writes in-memory bytes (e.g. a captured screenshot) to the app's own
/// document storage and returns the new local path.
Future<String> saveBytesToAppStorage(
  Uint8List bytes,
  String subfolder,
  String fileName,
) async {
  final docsDir = await getApplicationDocumentsDirectory();
  final destDir = Directory(p.join(docsDir.path, subfolder));
  await destDir.create(recursive: true);

  final uniqueName = '${DateTime.now().microsecondsSinceEpoch}_$fileName';
  final destPath = p.join(destDir.path, uniqueName);
  await File(destPath).writeAsBytes(bytes);
  return destPath;
}

/// A readable title from a file name: `Audio_Overview_Attention.m4a` →
/// "Audio Overview Attention", `attention-is-all-you-need.pdf` →
/// "attention is all you need". Hyphens only count as spaces when the
/// name has no spaces of its own (so "state-of-the-art review" keeps
/// them).
String titleFromFileName(String name) {
  var title = p.basenameWithoutExtension(name).replaceAll('_', ' ');
  if (!title.contains(' ')) title = title.replaceAll('-', ' ');
  title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
  return title.isEmpty ? name : title;
}
