import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../l10n/l10n.dart';
import '../home/adaptive.dart';
import '../notes/daily_notes.dart';
import 'projects_providers.dart';

enum CalendarKind { daily, note, paper, due }

class CalendarItem {
  const CalendarItem(this.kind, this.id, this.title);
  final CalendarKind kind;
  final String id;
  final String title;
}

/// What a calendar needs of a note (no body).
typedef CalendarNote = ({
  String id,
  String title,
  DateTime createdAt,
  String? dailyDate,
});

/// Items per local day (key `YYYY-MM-DD`): daily notes on their own day,
/// other notes and papers on the day they were created, project due dates.
/// A daily note shows once, as a daily note.
Map<String, List<CalendarItem>> collectCalendarItems({
  required Iterable<CalendarNote> notes,
  required Iterable<Paper> papers,
  required Iterable<Project> projects,
}) {
  final out = <String, List<CalendarItem>>{};
  void add(String key, CalendarItem item) =>
      (out[key] ??= <CalendarItem>[]).add(item);
  for (final n in notes) {
    final daily = n.dailyDate;
    if (daily != null && parseDailyKey(daily) != null) {
      add(daily, CalendarItem(CalendarKind.daily, n.id, n.title));
    } else {
      add(
        dailyKey(n.createdAt),
        CalendarItem(CalendarKind.note, n.id, n.title),
      );
    }
  }
  for (final p in papers) {
    add(dailyKey(p.createdAt), CalendarItem(CalendarKind.paper, p.id, p.title));
  }
  for (final p in projects) {
    final due = p.dueDate;
    if (due != null) {
      add(dailyKey(due), CalendarItem(CalendarKind.due, p.id, p.name));
    }
  }
  return out;
}

/// The days shown for [month]: whole weeks, starting on [firstWeekday]
/// (0 = Sunday … 6 = Saturday, as `MaterialLocalizations.firstDayOfWeekIndex`).
List<DateTime> monthGrid(DateTime month, int firstWeekday) {
  final first = DateTime(month.year, month.month);
  final lead = (first.weekday % 7 - firstWeekday + 7) % 7;
  final last = DateTime(month.year, month.month + 1, 0);
  final total = ((lead + last.day) / 7).ceil() * 7;
  return [
    for (var i = 0; i < total; i++)
      DateTime(month.year, month.month, 1 - lead + i),
  ];
}

final _calendarProvider = StreamProvider.autoDispose
    .family<Map<String, List<CalendarItem>>, String?>((ref, projectId) {
      final db = ref.watch(databaseProvider);
      final noteIds = projectId == null
          ? null
          : ref.watch(projectNoteIdsProvider(projectId)).value ?? const {};
      final paperIds = projectId == null
          ? null
          : ref.watch(projectPaperIdsProvider(projectId)).value ?? const {};
      final notes = db.selectOnly(db.notes)
        ..addColumns([
          db.notes.id,
          db.notes.title,
          db.notes.createdAt,
          db.notes.dailyDate,
        ]);
      return notes.watch().asyncMap((rows) async {
        final ns = <CalendarNote>[
          for (final r in rows)
            if (noteIds == null || noteIds.contains(r.read(db.notes.id)))
              (
                id: r.read(db.notes.id)!,
                title: r.read(db.notes.title) ?? '',
                createdAt: r.read(db.notes.createdAt)!,
                dailyDate: r.read(db.notes.dailyDate),
              ),
        ];
        final papers = [
          for (final p in await db.select(db.papers).get())
            if (paperIds == null || paperIds.contains(p.id)) p,
        ];
        final projects = [
          for (final p in await db.select(db.projects).get())
            if (projectId == null || p.id == projectId) p,
        ];
        return collectCalendarItems(
          notes: ns,
          papers: papers,
          projects: projects,
        );
      });
    });

/// A month grid of what happened when: daily notes, notes and papers by
/// creation day, project due dates. Library ⋮ → Calendar, or a project's
/// page (then only that project's things). [today] is for tests.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key, this.projectId, this.today});

  final String? projectId;
  final DateTime? today;

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _month;
  late DateTime _selected;

  DateTime get _today {
    final t = widget.today ?? DateTime.now();
    return DateTime(t.year, t.month, t.day);
  }

  @override
  void initState() {
    super.initState();
    _selected = _today;
    _month = DateTime(_today.year, _today.month);
  }

  void _shift(int months) =>
      setState(() => _month = DateTime(_month.year, _month.month + months));

  void _open(CalendarItem item) {
    switch (item.kind) {
      case CalendarKind.daily || CalendarKind.note:
        openNote(context, ref, item.id);
      case CalendarKind.paper:
        openPaper(context, ref, item.id);
      case CalendarKind.due:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    final locale = l10n.localeName;
    final items =
        ref.watch(_calendarProvider(widget.projectId)).value ?? const {};
    final mat = MaterialLocalizations.of(context);
    final days = monthGrid(_month, mat.firstDayOfWeekIndex);
    final dayItems = items[dailyKey(_selected)] ?? const <CalendarItem>[];
    final isToday = _selected == _today;
    final hasDaily = dayItems.any((i) => i.kind == CalendarKind.daily);

    Widget cell(DateTime d) {
      final inMonth = d.month == _month.month;
      final list = items[dailyKey(d)] ?? const <CalendarItem>[];
      final selected = d == _selected;
      final today = d == _today;
      Widget dot(Color color, {bool hollow = false}) => Container(
        width: 6,
        height: 6,
        margin: const EdgeInsets.symmetric(horizontal: 1.5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: hollow ? null : color,
          border: hollow ? Border.all(color: color, width: 1) : null,
        ),
      );
      bool has(CalendarKind k) => list.any((i) => i.kind == k);
      return InkWell(
        key: ValueKey('cal-day-${dailyKey(d)}'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => _selected = d),
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: selected ? c.primaryContainer.withValues(alpha: 0.6) : null,
            border: today ? Border.all(color: c.primary) : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${d.day}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: inMonth ? c.onSurface : c.outline,
                  fontWeight: today ? FontWeight.w600 : null,
                ),
              ),
              const SizedBox(height: 3),
              SizedBox(
                height: 10,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (has(CalendarKind.daily)) dot(c.primary),
                    if (has(CalendarKind.note)) dot(c.onSurfaceVariant),
                    if (has(CalendarKind.paper))
                      dot(c.onSurfaceVariant, hollow: true),
                    if (has(CalendarKind.due))
                      Icon(Icons.flag, size: 10, color: c.tertiary),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final weekdays = [
      for (var i = 0; i < 7; i++)
        DateFormat.E(locale).format(
          // 2023-01-01 was a Sunday.
          DateTime(2023, 1, 1 + (mat.firstDayOfWeekIndex + i) % 7),
        ),
    ];

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft, meta: true): () =>
            _shift(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight, meta: true): () =>
            _shift(1),
        const SingleActivator(
          LogicalKeyboardKey.arrowLeft,
          control: true,
        ): () =>
            _shift(-1),
        const SingleActivator(
          LogicalKeyboardKey.arrowRight,
          control: true,
        ): () =>
            _shift(1),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: Text(l10n.viewsCalendar),
            actions: [
              IconButton(
                key: const ValueKey('cal-prev'),
                tooltip: l10n.viewsPreviousMonth,
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _shift(-1),
              ),
              IconButton(
                key: const ValueKey('cal-next'),
                tooltip: l10n.viewsNextMonth,
                icon: const Icon(Icons.chevron_right),
                onPressed: () => _shift(1),
              ),
            ],
          ),
          body: ReadableColumn(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      DateFormat.yMMMM(locale).format(_month),
                      key: const ValueKey('cal-month'),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      for (final w in weekdays)
                        Expanded(
                          child: Center(
                            child: Text(
                              w,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: c.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 7,
                    childAspectRatio: 1.25,
                    children: [for (final d in days) cell(d)],
                  ),
                ),
                const Divider(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          DateFormat.yMMMMEEEEd(locale).format(_selected),
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      TextButton(
                        key: const ValueKey('cal-open-day'),
                        onPressed: () =>
                            openNoteForDay(context, ref, _selected),
                        child: Text(
                          hasDaily
                              ? (isToday
                                    ? l10n.viewsOpenTodaysNote
                                    : l10n.viewsOpenDayNote)
                              : (isToday
                                    ? l10n.viewsNewTodaysNote
                                    : l10n.viewsNewDayNote),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final i in dayItems)
                        ListTile(
                          dense: true,
                          key: ValueKey('cal-item-${i.kind.name}-${i.id}'),
                          leading: Icon(switch (i.kind) {
                            CalendarKind.daily => Icons.today_outlined,
                            CalendarKind.note => Icons.notes,
                            CalendarKind.paper => Icons.description_outlined,
                            CalendarKind.due => Icons.flag_outlined,
                          }, size: 20),
                          title: Text(
                            i.title.trim().isEmpty
                                ? l10n.commonUntitled
                                : i.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(switch (i.kind) {
                            CalendarKind.daily => l10n.viewsKindDaily,
                            CalendarKind.note => l10n.viewsKindNote,
                            CalendarKind.paper => l10n.viewsKindPaper,
                            CalendarKind.due => l10n.viewsKindDue,
                          }),
                          onTap: i.kind == CalendarKind.due
                              ? null
                              : () => _open(i),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
