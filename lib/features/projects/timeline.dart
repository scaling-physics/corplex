import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/database.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../home/adaptive.dart' show ReadableColumn;
import 'chapters.dart';
import 'open_from_page.dart';
import 'project_page.dart' show projectByIdProvider;

/// Whether a project has anything for a timeline: chapters, and a due date
/// or at least one word target.
bool timelineApplies(Project project, List<Chapter> chapters) =>
    chapters.isNotEmpty &&
    (project.dueDate != null || chapters.any((c) => (c.wordTarget ?? 0) > 0));

/// Where the writing stands against the targets and the due date.
class TimelinePace {
  const TimelinePace({
    required this.words,
    required this.target,
    this.daysLeft,
    this.wordsPerDay,
  });

  final int words;

  /// Sum of the chapters' word targets (0 when none is set).
  final int target;

  /// Whole days from today to the due date (negative once past); null
  /// without a due date.
  final int? daysLeft;

  /// Words still to write per remaining day (rounded up), when there is a
  /// target, a due date still ahead and something left to write.
  final int? wordsPerDay;

  bool get pastDue => daysLeft != null && daysLeft! < 0 && words < target;
}

TimelinePace timelinePace(List<Chapter> chapters, DateTime? due, DateTime now) {
  final words = chapters.fold<int>(0, (s, c) => s + c.words);
  final target = chapters.fold<int>(0, (s, c) => s + (c.wordTarget ?? 0));
  int? daysLeft;
  int? perDay;
  if (due != null) {
    daysLeft = DateTime.utc(
      due.year,
      due.month,
      due.day,
    ).difference(DateTime.utc(now.year, now.month, now.day)).inDays;
    final left = target - words;
    if (target > 0 && left > 0 && daysLeft > 0) {
      perDay = (left / daysLeft).ceil();
    }
  }
  return TimelinePace(
    words: words,
    target: target,
    daysLeft: daysLeft,
    wordsPerDay: perDay,
  );
}

/// How far [now] is between [start] and [due], 0..1.
double todayFraction(DateTime start, DateTime due, DateTime now) {
  final total = due.difference(start).inMinutes;
  if (total <= 0) return 1;
  return (now.difference(start).inMinutes / total).clamp(0.0, 1.0);
}

String paceSummary(AppLocalizations l10n, TimelinePace p, DateTime? due) {
  final words = formatCount(p.words, l10n.localeName);
  if (p.target <= 0) return l10n.viewsTimelineWordsOnly(words);
  final target = formatCount(p.target, l10n.localeName);
  if (due != null && p.wordsPerDay != null) {
    final date = DateFormat(
      due.year == DateTime.now().year
          ? l10n.projectsDatePattern
          : l10n.projectsDatePatternYear,
      l10n.localeName == 'en' ? 'en_US' : l10n.localeName,
    ).format(due);
    return l10n.viewsTimelinePace(
      words,
      target,
      formatCount(p.wordsPerDay!, l10n.localeName),
      date,
    );
  }
  if (p.pastDue) return l10n.viewsTimelinePastDue(words, target);
  return l10n.viewsTimelineWords(words, target);
}

/// Opened from the project page; shows [ChapterTimeline].
class TimelineScreen extends ConsumerWidget {
  const TimelineScreen({super.key, required this.projectId, this.now});

  final String projectId;
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(projectByIdProvider(projectId)).value;
    final chapters =
        ref.watch(projectChaptersProvider(projectId)).value ?? const [];
    return Scaffold(
      appBar: AppBar(title: Text(project?.name ?? '')),
      body: project == null
          ? const SizedBox.shrink()
          : ReadableColumn(
              child: ChapterTimeline(
                project: project,
                chapters: chapters,
                now: now,
              ),
            ),
    );
  }
}

Color _statusTone(ColorScheme c, ChapterStatus? s) => switch (s) {
  null || ChapterStatus.outline => c.outlineVariant,
  ChapterStatus.draft => c.primary.withValues(alpha: 0.35),
  ChapterStatus.withSupervisor => c.primary.withValues(alpha: 0.55),
  ChapterStatus.revised => c.primary.withValues(alpha: 0.75),
  ChapterStatus.finished => c.primary,
};

/// One bar per chapter (project order): words against target, tinted by
/// status, above a strip marking today and the due date.
class ChapterTimeline extends ConsumerWidget {
  const ChapterTimeline({
    super.key,
    required this.project,
    required this.chapters,
    this.now,
  });

  final Project project;
  final List<Chapter> chapters;
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    final l10n = context.l10n;
    final today = now ?? DateTime.now();
    final due = project.dueDate;
    final pace = timelinePace(chapters, due, today);
    final maxScale = chapters.fold<int>(
      1,
      (m, ch) =>
          [m, ch.words, ch.wordTarget ?? 0].reduce((a, b) => a > b ? a : b),
    );
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: c.onSurfaceVariant,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text(
          paceSummary(l10n, pace, due),
          key: const ValueKey('timeline-pace'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: c.onSurfaceVariant,
          ),
        ),
        if (due != null) ...[
          const SizedBox(height: 16),
          _DateStrip(
            start: project.createdAt,
            due: due,
            now: today,
            label: dueLabel(due, today, l10n),
          ),
        ],
        const SizedBox(height: 16),
        for (final ch in chapters)
          InkWell(
            key: ValueKey('timeline-${ch.note.id}'),
            borderRadius: BorderRadius.circular(8),
            onTap: () => openNoteFromPage(context, ref, ch.note.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          ch.titleIn(l10n),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge,
                        ),
                      ),
                      Text(
                        [
                          if (ch.status != null)
                            chapterStatusLabel(ch.status!, l10n),
                          if (ch.locked)
                            l10n.viewsLocked
                          else if ((ch.wordTarget ?? 0) > 0)
                            '${formatCount(ch.words, l10n.localeName)} / '
                                '${formatCount(ch.wordTarget!, l10n.localeName)}'
                          else
                            formatCount(ch.words, l10n.localeName),
                        ].join(' · '),
                        style: muted,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _Bar(
                    value: ch.words / maxScale,
                    target: (ch.wordTarget ?? 0) / maxScale,
                    tone: _statusTone(c, ch.status),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.target, required this.tone});

  final double value;
  final double target;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.clamp(0.0, 1.0)),
      duration: AppMotion.of(context, AppMotion.long),
      curve: AppMotion.enter,
      builder: (context, v, _) => LayoutBuilder(
        builder: (context, box) => SizedBox(
          height: 8,
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: c.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              if (target > 0)
                Positioned(
                  left: 0,
                  width: box.maxWidth * target.clamp(0.0, 1.0),
                  top: 0,
                  bottom: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: c.outlineVariant),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              Positioned(
                left: 0,
                width: box.maxWidth * v,
                top: 0,
                bottom: 0,
                child: Container(
                  key: const ValueKey('timeline-fill'),
                  decoration: BoxDecoration(
                    color: tone,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateStrip extends StatelessWidget {
  const _DateStrip({
    required this.start,
    required this.due,
    required this.now,
    required this.label,
  });

  final DateTime start;
  final DateTime due;
  final DateTime now;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    final f = todayFraction(start, due, now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, box) => SizedBox(
            height: 16,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 7,
                  child: Container(height: 2, color: c.outlineVariant),
                ),
                Positioned(
                  left: (box.maxWidth * f - 1).clamp(0.0, box.maxWidth - 2),
                  top: 0,
                  child: Container(
                    key: const ValueKey('timeline-today'),
                    width: 2,
                    height: 16,
                    color: c.primary,
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: Icon(
                    Icons.flag,
                    key: const ValueKey('timeline-due'),
                    size: 16,
                    color: c.tertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant),
        ),
      ],
    );
  }
}
