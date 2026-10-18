import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../ink/ink_model.dart';
import '../ink/sketch_render.dart';
import '../notes/note_table.dart';
import 'export_model.dart';

/// Pixel width drawings are rendered at for Word.
const docxSketchPixels = 1200;

/// [exportToDocx] with every drawing rendered to a PNG first (needs the
/// Flutter engine). A drawing that won't render is left as "[Sketch]".
Future<List<int>> exportToDocxWithImages(ExportDoc doc) async {
  final images = <ExportBlock, Uint8List>{};
  for (final b in doc.blocks) {
    if (b.kind != BlockKind.image) continue;
    try {
      images[b] = await renderSketchPng(
        b.sketch!,
        width: docxSketchPixels.toDouble(),
      );
    } catch (_) {
      // Falls back to the placeholder.
    }
  }
  return exportToDocx(doc, images: images);
}

/// A minimal but valid Word document (.docx): a zip of a few XML parts.
/// Headings, bullets, numbered items, quotes, and bold/italic/strike runs
/// are kept; links are written as `text (url)` since a real hyperlink
/// needs a relationship part and Word shows plain text just as well.
///
/// Drawings are pictures only when their PNG is in [images] (see
/// [exportToDocxWithImages]); otherwise they are a "[Sketch]" line.
List<int> exportToDocx(
  ExportDoc doc, {
  Map<ExportBlock, Uint8List> images = const {},
}) {
  final body = StringBuffer();
  final media = <Uint8List>[];
  if (doc.title.trim().isNotEmpty) {
    body.write(_para('Title', [Run(doc.title.trim())]));
  }
  for (final b in doc.blocks) {
    body.write(switch (b.kind) {
      BlockKind.heading1 => _para('Heading1', b.runs),
      BlockKind.heading2 => _para('Heading2', b.runs),
      BlockKind.heading3 => _para('Heading3', b.runs),
      BlockKind.bullet => _para('ListParagraph', [Run('•\t'), ...b.runs]),
      BlockKind.ordered => _para('ListParagraph', [
        Run('${b.ordinal}.\t'),
        ...b.runs,
      ]),
      BlockKind.quote => _para('Quote', b.runs),
      BlockKind.paragraph => _para(null, b.runs),
      BlockKind.caption => _para('Caption', b.runs),
      BlockKind.code => _para(null, b.runs, code: true),
      // Word can't take LaTeX directly; the source goes in as monospace
      // text, centred (Word's equation box accepts pasted LaTeX).
      BlockKind.image => _image(b, images[b], media),
      BlockKind.table => _table(b.table!),
      BlockKind.displayMath => _para(
        null,
        [Run('\$\$ ${b.text} \$\$', math: true)],
        centered: true,
        wrap: false,
      ),
    });
  }

  final archive = Archive()
    ..addFile(
      ArchiveFile.string(
        '[Content_Types].xml',
        _contentTypes(hasPng: media.isNotEmpty),
      ),
    )
    ..addFile(ArchiveFile.string('_rels/.rels', _rootRels))
    ..addFile(
      ArchiveFile.string(
        'word/_rels/document.xml.rels',
        _documentRels(media.length),
      ),
    )
    ..addFile(ArchiveFile.string('word/styles.xml', _styles))
    ..addFile(
      ArchiveFile.string(
        'word/document.xml',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<w:document xmlns:w="$_ns" xmlns:r="$_nsR" xmlns:wp="$_nsWp" '
            'xmlns:a="$_nsA" xmlns:pic="$_nsPic"><w:body>$body'
            '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
            '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" '
            'w:left="1440" w:header="720" w:footer="720" w:gutter="0"/>'
            '</w:sectPr></w:body></w:document>',
      ),
    );
  for (var i = 0; i < media.length; i++) {
    archive.addFile(
      ArchiveFile.bytes('word/media/image${i + 1}.png', media[i]),
    );
  }
  return ZipEncoder().encode(archive);
}

const _ns = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _nsR =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _nsWp =
    'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing';
const _nsA = 'http://schemas.openxmlformats.org/drawingml/2006/main';
const _nsPic = 'http://schemas.openxmlformats.org/drawingml/2006/picture';

// Text width on A4 with 1" margins: 9026 twips; 1 twip = 635 EMU.
const _textWidthTwips = 9026;
const _textWidthEmu = _textWidthTwips * 635;
// Keep a tall drawing inside one page (text height 13958 twips).
const _maxImageHeightEmu = 8000000;

String _attr(String s) => _escape(s).replaceAll('"', '&quot;');

/// An inline picture for a drawing, full text width. Registers the PNG in
/// [media]; its relationship id is `rId${index + 2}` (rId1 is the styles).
String _image(ExportBlock b, Uint8List? png, List<Uint8List> media) {
  if (png == null) return _para(null, [const Run('[Sketch]')]);
  media.add(png);
  final n = media.length;
  final sketch = b.sketch!;
  final heightPx = (docxSketchPixels * sketch.aspect).ceil();
  var cx = _textWidthEmu;
  var cy = (cx * heightPx / docxSketchPixels).round();
  if (cy > _maxImageHeightEmu) {
    cx = (cx * _maxImageHeightEmu / cy).round();
    cy = _maxImageHeightEmu;
  }
  final alt = (sketch.text ?? '').trim().isEmpty
      ? 'Sketch'
      : sketch.text!.trim();
  return '<w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:drawing>'
      '<wp:inline distT="0" distB="0" distL="0" distR="0">'
      '<wp:extent cx="$cx" cy="$cy"/>'
      '<wp:docPr id="$n" name="Sketch $n" descr="${_attr(alt)}"/>'
      '<wp:cNvGraphicFramePr>'
      '<a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr>'
      '<a:graphic><a:graphicData uri="$_nsPic">'
      '<pic:pic><pic:nvPicPr><pic:cNvPr id="$n" name="image$n.png"/>'
      '<pic:cNvPicPr/></pic:nvPicPr>'
      '<pic:blipFill><a:blip r:embed="rId${n + 1}"/>'
      '<a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
      '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/>'
      '</a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
      '</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>'
      '</w:p>';
}

/// A bordered table; a header row is bold, shaded and repeats across pages.
/// An empty paragraph follows (a table can't end the body).
String _table(NoteTable t) {
  final cols = t.columns < 1 ? 1 : t.columns;
  final w = _textWidthTwips ~/ cols;
  const border = 'w:val="single" w:sz="4" w:space="0" w:color="999999"';
  final out = StringBuffer(
    '<w:tbl><w:tblPr><w:tblW w:w="${w * cols}" w:type="dxa"/>'
    '<w:tblBorders>'
    '<w:top $border/><w:left $border/><w:bottom $border/><w:right $border/>'
    '<w:insideH $border/><w:insideV $border/></w:tblBorders>'
    '<w:tblLayout w:type="fixed"/>'
    '<w:tblCellMar><w:left w:w="100" w:type="dxa"/>'
    '<w:right w:w="100" w:type="dxa"/></w:tblCellMar></w:tblPr>'
    '<w:tblGrid>${'<w:gridCol w:w="$w"/>' * cols}</w:tblGrid>',
  );
  for (final (i, row) in t.rows.indexed) {
    final head = t.header && i == 0;
    out.write('<w:tr>${head ? '<w:trPr><w:tblHeader/></w:trPr>' : ''}');
    for (final cell in row) {
      out.write(
        '<w:tc><w:tcPr><w:tcW w:w="$w" w:type="dxa"/>'
        '${head ? '<w:shd w:val="clear" w:color="auto" w:fill="EFEBE4"/>' : ''}'
        '</w:tcPr>',
      );
      final lines = cell.split(RegExp(r'\r?\n'));
      for (final line in lines) {
        out.write(
          '<w:p><w:pPr><w:spacing w:after="0"/></w:pPr>'
          '${_run(Run(line, bold: head))}</w:p>',
        );
      }
      out.write('</w:tc>');
    }
    out.write('</w:tr>');
  }
  out.write('</w:tbl><w:p/>');
  return out.toString();
}

String _para(
  String? style,
  List<Run> runs, {
  bool centered = false,
  bool wrap = true,
  bool code = false,
}) {
  final pPr = style == null && !centered && !code
      ? ''
      : '<w:pPr>${style == null ? '' : '<w:pStyle w:val="$style"/>'}'
            '${code ? '<w:shd w:val="clear" w:color="auto" w:fill="F0EDE8"/>'
                      '<w:spacing w:after="0" w:line="240" w:lineRule="auto"/>' : ''}'
            '${centered ? '<w:jc w:val="center"/>' : ''}</w:pPr>';
  return '<w:p>$pPr${runs.map((r) => _run(r.math && wrap ? Run('\$${r.text}\$', math: true, bold: r.bold) : r, mono: code)).join()}</w:p>';
}

String _run(Run r, {bool mono = false}) {
  if (r.text.isEmpty) return '';
  final text = r.math || r.link == null ? r.text : '${r.text} (${r.link})';
  final props = [
    if (r.math || mono)
      '<w:rFonts w:ascii="Consolas" w:hAnsi="Consolas" w:cs="Consolas"/>',
    if (r.bold) '<w:b/>',
    if (r.italic) '<w:i/>',
    if (r.strike) '<w:strike/>',
    if (mono) '<w:sz w:val="20"/>',
    if (r.highlight != null)
      '<w:shd w:val="clear" w:color="auto" w:fill="${r.highlight}"/>',
  ].join();
  final rPr = props.isEmpty ? '' : '<w:rPr>$props</w:rPr>';
  // A tab in the text (list markers) needs its own element.
  final pieces = text.split('\t');
  final inner = [
    for (var i = 0; i < pieces.length; i++) ...[
      if (i > 0) '<w:tab/>',
      if (pieces[i].isNotEmpty)
        '<w:t xml:space="preserve">${_escape(pieces[i])}</w:t>',
    ],
  ].join();
  return '<w:r>$rPr$inner</w:r>';
}

String _escape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    // Control characters aren't allowed in XML 1.0.
    .replaceAll(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F]'), '');

String _contentTypes({required bool hasPng}) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '${hasPng ? '<Default Extension="png" ContentType="image/png"/>' : ''}'
    '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
    '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
    '</Types>';

const _rootRels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
    '</Relationships>';

/// Ties document.xml to its styles part and its pictures (`rId2…`).
String _documentRels(int images) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
    '${[for (var i = 1; i <= images; i++) '<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image$i.png"/>'].join()}'
    '</Relationships>';

const _styles =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<w:styles xmlns:w="$_ns">'
    '<w:docDefaults><w:rPrDefault><w:rPr>'
    '<w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/>'
    '<w:sz w:val="22"/></w:rPr></w:rPrDefault>'
    '<w:pPrDefault><w:pPr><w:spacing w:after="160" w:line="276" w:lineRule="auto"/></w:pPr></w:pPrDefault>'
    '</w:docDefaults>'
    '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>'
    '<w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/>'
    '<w:pPr><w:spacing w:after="240"/></w:pPr><w:rPr><w:b/><w:sz w:val="48"/></w:rPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/>'
    '<w:pPr><w:keepNext/><w:spacing w:before="360" w:after="120"/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:sz w:val="36"/></w:rPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/>'
    '<w:pPr><w:keepNext/><w:spacing w:before="280" w:after="100"/><w:outlineLvl w:val="1"/></w:pPr><w:rPr><w:b/><w:sz w:val="30"/></w:rPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="heading 3"/><w:basedOn w:val="Normal"/>'
    '<w:pPr><w:keepNext/><w:spacing w:before="200" w:after="80"/><w:outlineLvl w:val="2"/></w:pPr><w:rPr><w:b/><w:sz w:val="26"/></w:rPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="ListParagraph"><w:name w:val="List Paragraph"/><w:basedOn w:val="Normal"/>'
    '<w:pPr><w:tabs><w:tab w:val="left" w:pos="720"/></w:tabs><w:spacing w:after="60"/><w:ind w:left="720" w:hanging="360"/></w:pPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote"/><w:basedOn w:val="Normal"/>'
    '<w:pPr><w:ind w:left="720"/></w:pPr><w:rPr><w:i/></w:rPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="Caption"><w:name w:val="caption"/><w:basedOn w:val="Normal"/>'
    '<w:pPr><w:spacing w:before="60" w:after="200"/></w:pPr><w:rPr><w:sz w:val="20"/></w:rPr></w:style>'
    '</w:styles>';
