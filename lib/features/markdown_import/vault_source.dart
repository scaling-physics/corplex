import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../../data/local_files.dart';

/// A file of a Markdown vault being imported: a folder on disk, an entry of
/// a zip, or a single picked `.md`.
abstract class MdSourceFile {
  /// Vault-relative path, `/`-separated.
  String get path;

  /// When the file was last changed, if known.
  DateTime? get modified;

  Future<String> readText();

  /// Copies the file into the app's storage (like an attached file) and
  /// returns the new local path.
  Future<String> copyToAppStorage(String subfolder);
}

class DiskSourceFile implements MdSourceFile {
  DiskSourceFile(this.path, this.fullPath, this.modified);

  @override
  final String path;
  final String fullPath;
  @override
  final DateTime? modified;

  @override
  Future<String> readText() async =>
      utf8.decode(await File(fullPath).readAsBytes(), allowMalformed: true);

  @override
  Future<String> copyToAppStorage(String subfolder) =>
      copyIntoAppStorage(fullPath, subfolder);
}

class MemorySourceFile implements MdSourceFile {
  MemorySourceFile(this.path, this._bytes, {this.modified});

  @override
  final String path;
  final Uint8List Function() _bytes;
  @override
  final DateTime? modified;

  @override
  Future<String> readText() async =>
      utf8.decode(_bytes(), allowMalformed: true);

  @override
  Future<String> copyToAppStorage(String subfolder) =>
      saveBytesToAppStorage(_bytes(), subfolder, p.posix.basename(path));
}

/// Paths the importer never reads: hidden files and folders (`.obsidian`,
/// `.trash`, `.git`, `.DS_Store`) and the zip metadata folder.
bool isIgnoredVaultPath(String relative) {
  for (final seg in relative.split('/')) {
    if (seg.isEmpty) continue;
    if (seg.startsWith('.') || seg == '__MACOSX') return true;
  }
  return false;
}

bool isMarkdownPath(String path) {
  final l = path.toLowerCase();
  return l.endsWith('.md') || l.endsWith('.markdown');
}

/// Every non-hidden file under [dir].
Future<List<MdSourceFile>> loadVaultDirectory(Directory dir) async {
  final out = <MdSourceFile>[];
  final root = dir.path;
  await for (final e in dir.list(recursive: true, followLinks: false)) {
    if (e is! File) continue;
    final rel = p.relative(e.path, from: root).replaceAll('\\', '/');
    if (isIgnoredVaultPath(rel)) continue;
    DateTime? modified;
    try {
      modified = await e.lastModified();
    } on FileSystemException {
      modified = null;
    }
    out.add(DiskSourceFile(rel, e.path, modified));
  }
  out.sort((a, b) => a.path.compareTo(b.path));
  return out;
}

/// Every non-hidden file of the zip at [zip]. A single top-level folder
/// (how a zipped vault usually looks) is not part of the paths.
List<MdSourceFile> loadVaultZip(File zip) =>
    loadVaultArchive(ZipDecoder().decodeBytes(zip.readAsBytesSync()));

List<MdSourceFile> loadVaultArchive(Archive archive) {
  final files = [
    for (final f in archive.files)
      if (f.isFile && !isIgnoredVaultPath(f.name.replaceAll('\\', '/'))) f,
  ];
  final names = [for (final f in files) f.name.replaceAll('\\', '/')];
  String? top;
  if (names.isNotEmpty && names.every((n) => n.contains('/'))) {
    final first = names.first.split('/').first;
    if (names.every((n) => n.split('/').first == first)) top = first;
  }
  final out = <MdSourceFile>[];
  for (var i = 0; i < files.length; i++) {
    final f = files[i];
    var name = names[i];
    if (top != null) name = name.substring(top.length + 1);
    out.add(MemorySourceFile(name, () => f.readBytes() ?? Uint8List(0)));
  }
  out.sort((a, b) => a.path.compareTo(b.path));
  return out;
}

/// Single files picked from anywhere: they sit side by side in the vault.
List<MdSourceFile> loadMarkdownFiles(List<String> paths) => [
  for (final path in paths)
    if (isMarkdownPath(path) && File(path).existsSync())
      DiskSourceFile(p.basename(path), path, File(path).lastModifiedSync()),
];
