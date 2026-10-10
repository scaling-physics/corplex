import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/tables/papers_table.dart';
import '../../theme/app_theme.dart';

/// How far through a paper the reader is (0..1), or null when there is
/// nothing worth showing: the paper isn't started, is finished (a full bar
/// on every finished card would be noise), or its page count is unknown.
double? readingProgress(Paper paper) {
  final total = paper.pageCount;
  if (total == null || total <= 0) return null;
  if (paper.readingStatus == ReadingStatus.done) return null;
  final page = paper.lastPage ?? 1;
  final started = page > 1 || paper.readingStatus == ReadingStatus.reading;
  if (!started) return null;
  return (page / total).clamp(0.0, 1.0);
}

/// A thin bar under a Library card's text; absent until the paper is started.
class ReadingProgressBar extends StatelessWidget {
  const ReadingProgressBar({super.key, required this.paper});

  final Paper paper;

  @override
  Widget build(BuildContext context) {
    final progress = readingProgress(paper);
    if (progress == null) return const SizedBox.shrink();
    final c = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: progress),
        duration: AppMotion.of(context, AppMotion.medium),
        curve: AppMotion.enter,
        builder: (context, value, _) => ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            key: const ValueKey('reading-progress'),
            value: value,
            minHeight: 3,
            backgroundColor: c.outlineVariant.withValues(alpha: 0.5),
            valueColor: AlwaysStoppedAnimation(c.primary),
          ),
        ),
      ),
    );
  }
}

/// Records the PDF's page count, only when it differs from what's stored
/// (so reopening a paper doesn't count as an edit that syncs).
Future<void> savePageCountIfChanged(
  AppDatabase db,
  String paperId,
  int pageCount,
) async {
  if (pageCount <= 0) return;
  await (db.update(db.papers)..where(
        (p) =>
            p.id.equals(paperId) &
            (p.pageCount.isNull() | p.pageCount.equals(pageCount).not()),
      ))
      .write(PapersCompanion(pageCount: Value(pageCount)));
}
