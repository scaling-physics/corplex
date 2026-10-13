import 'package:archive/archive.dart';

import 'export_model.dart';

/// A minimal but valid Word document (.docx): a zip of a few XML parts.
/// Headings, bullets, numbered items, quotes, and bold/italic/strike runs
/// are kept; links are written as `text (url)` since a real hyperlink
/// needs a relationship part and Word shows plain text just as well.
List<int> exportToDocx(ExportDoc doc) {
  final body = StringBuffer();
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
      // Word can't take LaTeX directly; the source goes in as monospace
      // text, centred (Word's equation box accepts pasted LaTeX).
      BlockKind.displayMath => _para(
        null,
        [Run('\$\$ ${b.text} \$\$', math: true)],
        centered: true,
        wrap: false,
      ),
    });
  }

  final archive = Archive()
    ..addFile(ArchiveFile.string('[Content_Types].xml', _contentTypes))
    ..addFile(ArchiveFile.string('_rels/.rels', _rootRels))
    ..addFile(ArchiveFile.string('word/_rels/document.xml.rels', _documentRels))
    ..addFile(ArchiveFile.string('word/styles.xml', _styles))
    ..addFile(
      ArchiveFile.string(
        'word/document.xml',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<w:document xmlns:w="$_ns"><w:body>$body'
            '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
            '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" '
            'w:left="1440" w:header="720" w:footer="720" w:gutter="0"/>'
            '</w:sectPr></w:body></w:document>',
      ),
    );
  return ZipEncoder().encode(archive);
}

const _ns = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

String _para(
  String? style,
  List<Run> runs, {
  bool centered = false,
  bool wrap = true,
}) {
  final pPr = style == null && !centered
      ? ''
      : '<w:pPr>${style == null ? '' : '<w:pStyle w:val="$style"/>'}'
            '${centered ? '<w:jc w:val="center"/>' : ''}</w:pPr>';
  return '<w:p>$pPr${runs.map((r) => _run(r.math && wrap ? Run('\$${r.text}\$', math: true, bold: r.bold) : r)).join()}</w:p>';
}

String _run(Run r) {
  if (r.text.isEmpty) return '';
  final text = r.math || r.link == null ? r.text : '${r.text} (${r.link})';
  final props = [
    if (r.math)
      '<w:rFonts w:ascii="Consolas" w:hAnsi="Consolas" w:cs="Consolas"/>',
    if (r.bold) '<w:b/>',
    if (r.italic) '<w:i/>',
    if (r.strike) '<w:strike/>',
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

const _contentTypes =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
    '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
    '</Types>';

const _rootRels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
    '</Relationships>';

/// Ties document.xml to its styles part.
const _documentRels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
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
