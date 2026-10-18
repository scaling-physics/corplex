import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:corplex/data/database.dart';
import 'package:corplex/data/tables/attachments_table.dart';
import 'package:corplex/features/export/docx_export.dart';
import 'package:corplex/features/export/export_images.dart';
import 'package:corplex/features/export/export_model.dart';
import 'package:corplex/features/export/latex_export.dart';
import 'package:corplex/features/export/markdown_export.dart';
import 'package:corplex/features/export/pdf_export.dart';
import 'package:corplex/features/export/vault_export.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Future<ByteData> _fromDisk(String asset) async =>
    ByteData.sublistView(File(asset).readAsBytesSync());

final _body = jsonEncode([
  {'insert': 'Some text\n'},
]);

void main() {
  late AppDatabase db;
  late Directory tmp;
  late Uint8List png;
  late Uint8List jpg;

  setUp(() {
    db = AppDatabase.inMemoryForTesting();
    tmp = Directory.systemTemp.createTempSync('note_images');
    png = Uint8List.fromList(img.encodePng(img.Image(width: 40, height: 20)));
    jpg = Uint8List.fromList(img.encodeJpg(img.Image(width: 30, height: 60)));
  });
  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  Future<void> note(String id, String content) => db
      .into(db.notes)
      .insert(
        NotesCompanion.insert(
          id: Value(id),
          title: Value('Note $id'),
          content: Value(content),
        ),
      );

  Future<void> attach(
    String id,
    String noteId,
    String path,
    String? title, {
    int order = 0,
  }) => db
      .into(db.attachments)
      .insert(
        AttachmentsCompanion.insert(
          id: Value(id),
          noteId: Value(noteId),
          type: AttachmentType.image,
          title: Value(title),
          path: Value(path),
          createdAt: Value(DateTime(2026, 1, 1, 0, 0, order)),
        ),
      );

  Future<ExportDoc> build() async {
    final images = await noteExportImages(db, 'n1');
    return buildExportDoc(db, [
      ExportNote('Note n1', _body, images: images),
    ], title: 'Note n1');
  }

  Future<void> twoImages() async {
    final a = File('${tmp.path}/1_a.png')..writeAsBytesSync(png);
    final b = File('${tmp.path}/2_b.jpg')..writeAsBytesSync(jpg);
    await note('n1', _body);
    await attach('a1', 'n1', a.path, 'Apparatus', order: 1);
    await attach('a2', 'n1', b.path, 'IMG_1234.jpg', order: 2);
  }

  test('images load in order; camera names get no caption', () async {
    await twoImages();
    final doc = await build();
    final photos = [
      for (final b in doc.blocks)
        if (b.kind == BlockKind.photo) b.photo!,
    ];
    expect(photos.map((p) => p.ext), ['png', 'jpg']);
    expect(photos.map((p) => (p.width, p.height)), [(40, 20), (30, 60)]);
    expect(photos[0].caption, 'Apparatus');
    expect(photos[1].caption, isNull);
    expect(doc.blocks.last.kind, BlockKind.photo);
  });

  test('camera-style names', () {
    for (final n in [
      'IMG_1234.jpg',
      'Pasted image',
      '2026-10-18 09.30.12',
      '1760000000000000_IMG_0001.HEIC',
      'PXL_20261018_093012345.jpg',
    ]) {
      expect(isCameraStyleName(n), isTrue, reason: n);
    }
    for (final n in ['Apparatus', 'Image of the rig', 'Figure 2 raw']) {
      expect(isCameraStyleName(n), isFalse, reason: n);
    }
  });

  test('PDF grows and parses', () async {
    await twoImages();
    final withImages = await exportToPdf(await build(), loadFont: _fromDisk);
    final without = await exportToPdf(
      ExportDoc(
        'Note n1',
        (await build()).blocks.where((b) => b.kind != BlockKind.photo).toList(),
      ),
      loadFont: _fromDisk,
    );
    expect(String.fromCharCodes(withImages.sublist(0, 5)), '%PDF-');
    expect(withImages.length, greaterThan(without.length));
    expect(latin1.decode(withImages), matches(RegExp(r'/Subtype\s*/Image')));
  });

  test('DOCX has both media parts, relationships and content types', () async {
    await twoImages();
    final zip = ZipDecoder().decodeBytes(
      Uint8List.fromList(await exportToDocxWithImages(await build())),
    );
    String text(String n) =>
        utf8.decode(zip.files.firstWhere((f) => f.name == n).content);
    final names = zip.files.map((f) => f.name).toList();
    expect(
      names,
      containsAll(['word/media/image1.png', 'word/media/image2.jpg']),
    );
    final rels = text('word/_rels/document.xml.rels');
    expect(rels, contains('Target="media/image1.png"'));
    expect(rels, contains('Target="media/image2.jpg"'));
    final types = text('[Content_Types].xml');
    expect(types, contains('Extension="png"'));
    expect(types, contains('Extension="jpg" ContentType="image/jpeg"'));
    final xml = text('word/document.xml');
    expect(xml, contains('r:embed="rId2"'));
    expect(xml, contains('r:embed="rId3"'));
    expect(xml, contains('Apparatus'));
  });

  test('LaTeX zip has figure files and includegraphics', () async {
    await twoImages();
    final zip = ZipDecoder().decodeBytes(
      Uint8List.fromList(await exportToLatexZip(await build())),
    );
    expect(
      zip.files.map((f) => f.name),
      containsAll(['figures/image-1.png', 'figures/image-2.jpg']),
    );
    final tex = utf8.decode(
      zip.files.firstWhere((f) => f.name == 'main.tex').content,
    );
    expect(tex, contains('{figures/image-1.png}'));
    expect(tex, contains('{figures/image-2.jpg}'));
    expect(tex, contains('\\caption{Apparatus}'));
    expect(RegExp(r'\\caption').allMatches(tex).length, 1);
  });

  test('Markdown lists the images it leaves out', () async {
    await twoImages();
    final md = exportToMarkdown(await build());
    expect(md, contains('Image not included: Apparatus'));
  });

  test('the vault embeds images at the end of the note', () async {
    await twoImages();
    final t = {
      for (final f in (await buildVaultArchive(db)).archive.files)
        if (f.isFile) f.name: f.content,
    };
    final md = utf8.decode(t['Corplex/Notes/Note n1.md']! as List<int>);
    expect(md, contains('## Attachments'));
    expect(RegExp(r'!\[\[Attachments/[^\]]+\]\]').allMatches(md).length, 2);
    expect(md.trimRight(), endsWith(']]'));
  });

  test('missing and undecodable files are skipped quietly', () async {
    final bad = File('${tmp.path}/3_bad.png')..writeAsBytesSync([1, 2, 3]);
    await note('n1', _body);
    await attach('m1', 'n1', '${tmp.path}/gone.png', 'Gone', order: 1);
    await attach('m2', 'n1', bad.path, 'Bad', order: 2);
    final doc = await build();
    expect(doc.blocks.where((b) => b.kind == BlockKind.photo), isEmpty);
    expect(exportToMarkdown(doc), contains('Some text'));
  });

  test('a locked note exports no images', () async {
    await twoImages();
    final images = await noteExportImages(db, 'n1');
    final doc = await buildExportDoc(db, [
      ExportNote('Locked', 'corplex-locked:v1:k:AAAA', images: images),
    ], title: 'Locked');
    expect(doc.blocks.where((b) => b.kind == BlockKind.photo), isEmpty);
  });

  test('a project export puts images at the end of their chapter', () async {
    await twoImages();
    final images = await noteExportImages(db, 'n1');
    final doc = await buildExportDoc(db, [
      ExportNote('One', _body, images: images),
      ExportNote('Two', _body),
    ], title: 'P');
    final kinds = doc.blocks.map((b) => b.kind).toList();
    final second = doc.blocks.indexWhere(
      (b) => b.chapterTitle && b.text == 'Two',
    );
    expect(kinds.indexOf(BlockKind.photo), lessThan(second));
    expect(kinds.lastIndexOf(BlockKind.photo), lessThan(second));
  });
}
