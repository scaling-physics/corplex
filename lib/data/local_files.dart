import 'dart:io';

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
