import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../library/citations.dart';
import 'citation_embed.dart';

/// Reading speed for the estimate, in words per minute.
const wordsPerMinute = 230;

class NoteStats {
  const NoteStats({
    required this.words,
    required this.characters,
    required this.paragraphs,
    required this.citations,
  });

  final int words;
  final int characters;
  final int paragraphs;

  /// Citations in the text (a chip citing two papers counts twice).
  final int citations;

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
  return NoteStats(
    words: RegExp(
      r'\S*[\p{L}\p{N}]\S*',
      unicode: true,
    ).allMatches(prose).length,
    characters: lines.fold(0, (sum, l) => sum + l.runes.length),
    paragraphs: lines.where((l) => l.trim().isNotEmpty).length,
    citations: citations,
  );
}

String readingTimeLabel(NoteStats stats) {
  if (stats.words == 0) return '0 min';
  if (stats.readingMinutes <= 1) return '< 1 min';
  return '${stats.readingMinutes} min';
}

/// A small sheet of numbers about the note; nothing of it shows on the
/// editor itself.
Future<void> showNoteStatsSheet(
  BuildContext context,
  NoteStats stats, {
  required int linkedPapers,
}) {
  final text = Theme.of(context).textTheme;
  Widget tile(String label, String value) => SizedBox(
    key: ValueKey(label),
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
            tile('Words', '${stats.words}'),
            tile('Characters', '${stats.characters}'),
            tile('Paragraphs', '${stats.paragraphs}'),
            tile('Reading time', readingTimeLabel(stats)),
            tile('Citations', '${stats.citations}'),
            tile('Linked papers', '$linkedPapers'),
          ],
        ),
      ),
    ),
  );
}
