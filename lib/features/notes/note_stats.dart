import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:intl/intl.dart';

import '../../l10n/l10n.dart';
import '../library/citations.dart';
import 'citation_embed.dart';
import 'footnote_markers.dart';
import 'note_table.dart';

/// Reading speed for the estimate, in words per minute.
const wordsPerMinute = 230;

class NoteStats {
  const NoteStats({
    required this.words,
    required this.characters,
    required this.paragraphs,
    required this.citations,
    this.footnoteWords = 0,
  });

  final int words;
  final int characters;
  final int paragraphs;

  /// Citations in the text (a chip citing two papers counts twice).
  final int citations;

  /// Words inside footnotes, which [words] leaves out.
  final int footnoteWords;

  /// Whole minutes, rounded up; 0 for an empty note.
  int get readingMinutes => (words / wordsPerMinute).ceil();
}

final _markerPattern = RegExp(r'\[@[^\]\n]+\]');

/// Counts what the reader wrote. Citation chips are read through
/// [textWithCitations] (so a chip is its marker, not a stray `￼`) and
/// then left out of the prose counts; sketches and other embeds have no
/// text and are ignored.
NoteStats noteStats(Document document) {
  final text = textWithCitations(document.toDelta());
  var citations = 0;
  final prose = text.replaceAllMapped(_markerPattern, (m) {
    final n = citedKeys(m.group(0)!).length;
    citations += n;
    return n == 0 ? m.group(0)! : ' ';
  });
  final lines = prose.split('\n');
  final wordPattern = RegExp(r'\S*[\p{L}\p{N}]\S*', unicode: true);
  // Words in table cells count too.
  var tableWords = 0;
  var footnoteWords = 0;
  for (final op in document.toDelta().toList()) {
    final data = op.data;
    if (data is Map && data[footnoteEmbedType] is String) {
      // A footnote's citations are not words, as in the body.
      footnoteWords += wordPattern
          .allMatches(
            footnoteDisplayText(data[footnoteEmbedType] as String)
                .replaceAll(_markerPattern, ' '),
          )
          .length;
    }
    if (data is Map && data[tableEmbedType] is String) {
      tableWords += wordPattern
          .allMatches(
            NoteTable.decode(data[tableEmbedType] as String).plainText,
          )
          .length;
    }
  }
  return NoteStats(
    words: wordPattern.allMatches(prose).length + tableWords,
    characters: lines.fold(0, (sum, l) => sum + l.runes.length),
    paragraphs: lines.where((l) => l.trim().isNotEmpty).length,
    citations: citations,
    footnoteWords: footnoteWords,
  );
}

String readingTimeLabel(NoteStats stats, [AppLocalizations? l10n]) {
  if (l10n == null) {
    if (stats.words == 0) return '0 min';
    if (stats.readingMinutes <= 1) return '< 1 min';
    return '${stats.readingMinutes} min';
  }
  if (stats.words == 0) return l10n.notesMinutes(0);
  if (stats.readingMinutes <= 1) return l10n.notesLessThanAMinute;
  return l10n.notesMinutes(stats.readingMinutes);
}

/// A small sheet of numbers about the note; nothing of it shows on the
/// editor itself.
Future<void> showNoteStatsSheet(
  BuildContext context,
  NoteStats stats, {
  required int linkedPapers,
}) {
  final text = Theme.of(context).textTheme;
  final l10n = context.l10n;
  final fmt = NumberFormat.decimalPattern(
    Localizations.localeOf(context).toString(),
  );
  Widget tile(String key, String label, String value, {String? note}) =>
      SizedBox(
        key: ValueKey(key),
        width: 104,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: text.titleLarge),
            Text(
              label,
              style: text.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
            if (note != null)
              Text(
                note,
                style: text.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
          ],
        ),
      );
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Wrap(
          spacing: 16,
          runSpacing: 20,
          children: [
            tile(
              'Words',
              l10n.notesStatsWords,
              fmt.format(stats.words),
              note: stats.footnoteWords > 0
                  ? l10n.footnotesStatsInFootnotes(
                      fmt.format(stats.footnoteWords),
                    )
                  : null,
            ),
            tile(
              'Characters',
              l10n.notesStatsCharacters,
              fmt.format(stats.characters),
            ),
            tile(
              'Paragraphs',
              l10n.notesStatsParagraphs,
              fmt.format(stats.paragraphs),
            ),
            tile(
              'Reading time',
              l10n.notesStatsReadingTime,
              readingTimeLabel(stats, l10n),
            ),
            tile(
              'Citations',
              l10n.notesStatsCitations,
              fmt.format(stats.citations),
            ),
            tile(
              'Linked papers',
              l10n.notesStatsLinkedPapers,
              fmt.format(linkedPapers),
            ),
          ],
        ),
      ),
    ),
  );
}
