import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../l10n/l10n.dart';
import '../../data/database.dart';
import 'papers_providers.dart';
import 'study_details.dart';

/// The Library's filter on study details: within a field the chosen values
/// are OR, across fields they are AND, and [minSampleSize] keeps papers
/// whose n is at least that (papers with no n are dropped while it's set).
class StudyFilter {
  const StudyFilter({this.values = const {}, this.minSampleSize});

  final Map<StudyField, Set<String>> values;
  final int? minSampleSize;

  bool get isActive => count > 0;

  /// What the chip shows: chosen values, plus one for a minimum n.
  int get count =>
      values.values.fold(0, (n, s) => n + s.length) +
      (minSampleSize == null ? 0 : 1);

  bool isSelected(StudyField field, String value) =>
      values[field]?.any((v) => v.toLowerCase() == value.toLowerCase()) ??
      false;

  StudyFilter toggled(StudyField field, String value) {
    final current = {...?values[field]};
    final existing = current.where(
      (v) => v.toLowerCase() == value.toLowerCase(),
    );
    if (existing.isNotEmpty) {
      current.removeAll(existing.toList());
    } else {
      current.add(value);
    }
    final next = {...values};
    if (current.isEmpty) {
      next.remove(field);
    } else {
      next[field] = current;
    }
    return StudyFilter(values: next, minSampleSize: minSampleSize);
  }

  StudyFilter withMinSampleSize(int? n) => StudyFilter(
    values: values,
    minSampleSize: (n == null || n <= 0) ? null : n,
  );

  bool matches(Paper paper) {
    final min = minSampleSize;
    if (min != null && (paper.sampleSize ?? -1) < min) return false;
    for (final entry in values.entries) {
      if (entry.value.isEmpty) continue;
      final wanted = {for (final v in entry.value) v.toLowerCase()};
      final has = studyValues(paper, entry.key).map((v) => v.toLowerCase());
      if (!has.any(wanted.contains)) return false;
    }
    return true;
  }
}

final studyFilterProvider = StateProvider.autoDispose<StudyFilter>(
  (ref) => const StudyFilter(),
);

/// True once any paper has study details; until then the Library shows no
/// Study chip.
final anyStudyDetailsProvider = Provider.autoDispose<bool>(
  (ref) =>
      (ref.watch(papersListProvider).value ?? const []).any(hasStudyDetails),
);

/// The values in use across the library per field, sorted, case-insensitive
/// duplicates merged (first spelling wins).
final studyOptionsProvider =
    Provider.autoDispose<Map<StudyField, List<String>>>((ref) {
      final papers = ref.watch(papersListProvider).value ?? const <Paper>[];
      final result = <StudyField, List<String>>{};
      for (final field in StudyField.values) {
        if (field == StudyField.sampleSize) continue;
        final seen = <String, String>{};
        for (final p in papers) {
          for (final v in studyValues(p, field)) {
            seen.putIfAbsent(v.toLowerCase(), () => v);
          }
        }
        final list = seen.values.toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        if (list.isNotEmpty) result[field] = list;
      }
      return result;
    });

/// The Library's "Study" chip: opens the filter sheet; shows a count and a
/// clear (×) while active.
class StudyFilterChip extends ConsumerWidget {
  const StudyFilterChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(studyFilterProvider);
    return InputChip(
      avatar: const Icon(Icons.science_outlined, size: 18),
      label: Text(
        filter.isActive
            ? context.l10n.studyChipCount(filter.count)
            : context.l10n.studyChip,
      ),
      selected: filter.isActive,
      onPressed: () => showStudyFilterSheet(context),
      onDeleted: filter.isActive
          ? () => ref.read(studyFilterProvider.notifier).state =
                const StudyFilter()
          : null,
      deleteButtonTooltipMessage: context.l10n.studyClearFilter,
    );
  }
}

Future<void> showStudyFilterSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _StudyFilterSheet(),
    );

class _StudyFilterSheet extends ConsumerStatefulWidget {
  const _StudyFilterSheet();

  @override
  ConsumerState<_StudyFilterSheet> createState() => _StudyFilterSheetState();
}

class _StudyFilterSheetState extends ConsumerState<_StudyFilterSheet> {
  late final _n = TextEditingController(
    text: ref.read(studyFilterProvider).minSampleSize?.toString() ?? '',
  );

  @override
  void dispose() {
    _n.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filter = ref.watch(studyFilterProvider);
    final options = ref.watch(studyOptionsProvider);
    final notifier = ref.read(studyFilterProvider.notifier);
    ref.listen(studyFilterProvider, (_, next) {
      if (next.minSampleSize == null && _n.text.isNotEmpty && !next.isActive) {
        _n.clear();
      }
    });
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.studyChip,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (filter.isActive)
                  TextButton(
                    onPressed: () => notifier.state = const StudyFilter(),
                    child: Text(context.l10n.studyClear),
                  ),
              ],
            ),
            for (final entry in options.entries) ...[
              const SizedBox(height: 12),
              Text(
                entry.key.labelFor(context.l10n),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final v in entry.value)
                    FilterChip(
                      label: Text(v),
                      selected: filter.isSelected(entry.key, v),
                      onSelected: (_) =>
                          notifier.state = filter.toggled(entry.key, v),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _n,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: context.l10n.studyMinSampleSize,
              ),
              onChanged: (v) => notifier.state = ref
                  .read(studyFilterProvider)
                  .withMinSampleSize(int.tryParse(v)),
            ),
          ],
        ),
      ),
    );
  }
}
