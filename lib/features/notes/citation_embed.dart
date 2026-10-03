import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../library/citation_formatter.dart';
import '../library/citations.dart';
import '../library/paper_detail_screen.dart';
import 'note_content.dart';

/// A citation shown as a chip in the editor — "(Vaswani et al., 2017)" —
/// instead of its stored text `[@vaswani2017]`.
///
/// Only the editor sees chips. A note is *stored* with plain `[@key]`
/// text, exactly as before, so export, bibliographies, search, sync and
/// merging never meet an embed: [citationsToEmbeds] turns the text into
/// chips when a note is loaded into the editor, and [citationEmbedsToText]
/// turns them back when it is saved. The chip's data is the original
/// marker text, so the round trip is exact.
const citationEmbedType = 'cite';

/// `[@a; @b]` groups whose keys are all well formed.
bool _isCitation(String marker) => citedKeys(marker).isNotEmpty;

final _marker = RegExp(r'\[@[^\]\n]+\]');

/// Stored note content → the editor's form, with citations as chips.
/// Content that isn't Delta JSON (an old plain-text note) is returned
/// unchanged.
String citationsToEmbeds(String stored) {
  final ops = _ops(stored);
  if (ops == null) return stored;
  final out = <Map<String, Object?>>[];
  for (final op in ops) {
    final insert = op['insert'];
    if (insert is! String || !insert.contains('[@')) {
      out.add(op);
      continue;
    }
    final attributes = op['attributes'];
    Map<String, Object?> make(Object value) => {
      'insert': value,
      'attributes': ?attributes,
    };
    var pos = 0;
    for (final m in _marker.allMatches(insert)) {
      if (!_isCitation(m.group(0)!)) continue;
      if (m.start > pos) out.add(make(insert.substring(pos, m.start)));
      out.add(make({citationEmbedType: m.group(0)!}));
      pos = m.end;
    }
    if (pos < insert.length) out.add(make(insert.substring(pos)));
  }
  return jsonEncode(out);
}

/// The editor's content → stored form: chips back to `[@key]` text,
/// normalised the way the editor saves notes.
String citationEmbedsToText(String editorContent) {
  final ops = _ops(editorContent);
  if (ops == null) return editorContent;
  final out = [
    for (final op in ops)
      if (op['insert'] case {citationEmbedType: final String marker})
        {'insert': marker, 'attributes': ?op['attributes']}
      else
        op,
  ];
  return encodeNoteContent(Document.fromJson(out));
}

/// The text of [delta] (up to [end], if given) with citation chips written
/// out as their `[@key]` markers, for finding which papers a note cites.
String textWithCitations(Delta delta, {int? end}) {
  final b = StringBuffer();
  var offset = 0;
  for (final op in delta.toList()) {
    if (!op.isInsert) continue;
    if (end != null && offset >= end) break;
    final data = op.data;
    if (data is String) {
      b.write(
        end == null
            ? data
            : data.substring(0, (end - offset).clamp(0, data.length)),
      );
      offset += data.length;
    } else {
      if (data case {citationEmbedType: final String marker}) b.write(marker);
      offset += 1;
    }
  }
  return b.toString();
}

/// Inserts a citation chip for [citekey] at [index], followed by a space,
/// and puts the cursor after it.
void insertCitation(QuillController controller, int index, String citekey) {
  controller.replaceText(
    index,
    0,
    Embeddable(citationEmbedType, citationMarker(citekey)),
    null,
  );
  controller.replaceText(
    index + 1,
    0,
    ' ',
    TextSelection.collapsed(offset: index + 2),
  );
}

List<Map<String, Object?>>? _ops(String content) {
  try {
    final decoded = jsonDecode(content);
    if (decoded is! List) return null;
    return [for (final op in decoded) (op as Map).cast<String, Object?>()];
  } on FormatException {
    return null;
  }
}

/// The papers a citation marker names, kept up to date (a paper's authors
/// or year can change after it's cited).
final _citedPapersProvider = StreamProvider.autoDispose
    .family<Map<String, Paper>, String>((ref, marker) {
      final db = ref.watch(databaseProvider);
      final keys = citedKeys(marker);
      return (db.select(db.papers)..where((p) => p.citekey.isIn(keys)))
          .watch()
          .map((rows) => {for (final p in rows) p.citekey!: p});
    });

/// Renders citation chips in the note editor. Tap one to open the paper.
class CitationEmbedBuilder extends EmbedBuilder {
  const CitationEmbedBuilder();

  @override
  String get key => citationEmbedType;

  @override
  bool get expanded => false;

  @override
  String toPlainText(Embed node) => node.value.data as String;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final marker = embedContext.node.value.data as String;
    return _CitationChip(marker: marker, textStyle: embedContext.textStyle);
  }
}

class _CitationChip extends ConsumerWidget {
  const _CitationChip({required this.marker, required this.textStyle});

  final String marker;
  final TextStyle textStyle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).colorScheme;
    final byKey = ref.watch(_citedPapersProvider(marker)).value;
    final keys = citedKeys(marker);
    final known = byKey != null && keys.every(byKey.containsKey);
    // The editor shows author–date; the reference style is chosen when the
    // bibliography is added or the note exported.
    final label = known
        ? CitationResolver(byKey, CitationStyle.apa).replace(marker)
        : marker;
    final first = known ? byKey[keys.first] : null;

    return Semantics(
      button: first != null,
      label: known ? 'Citation $label' : 'Citation $marker, paper not found',
      child: GestureDetector(
        onTap: first == null
            ? null
            : () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PaperDetailScreen(paperId: first.id),
                ),
              ),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: known
                ? c.primaryContainer.withValues(alpha: 0.6)
                : c.errorContainer.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: textStyle.copyWith(
              color: known ? c.onPrimaryContainer : c.onErrorContainer,
            ),
          ),
        ),
      ),
    );
  }
}
