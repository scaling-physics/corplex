import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../theme/app_theme.dart';
import 'study_details.dart';

/// Distinct values of [field] used anywhere in the library, most used first
/// (ties alphabetical). Feeds the suggestions under each input.
final studyLibraryValuesProvider = StreamProvider.autoDispose
    .family<List<String>, StudyField>((ref, field) {
      final db = ref.watch(databaseProvider);
      return db.select(db.papers).watch().map((papers) {
        final counts = <String, int>{};
        final spelling = <String, String>{};
        for (final p in papers) {
          for (final v in studyValues(p, field)) {
            final k = v.toLowerCase();
            spelling.putIfAbsent(k, () => v);
            counts[k] = (counts[k] ?? 0) + 1;
          }
        }
        final keys = counts.keys.toList()
          ..sort((a, b) {
            final c = counts[b]!.compareTo(counts[a]!);
            return c != 0 ? c : a.compareTo(b);
          });
        return [for (final k in keys) spelling[k]!];
      });
    });

/// Suggestions for [field]: library values first, then the built-in ones,
/// minus [chosen] and filtered by [typed].
List<String> studySuggestionsFor(
  StudyField field,
  List<String> library,
  Iterable<String> chosen,
  String typed,
) {
  final skip = {for (final c in chosen) c.toLowerCase()};
  final q = typed.trim().toLowerCase();
  final seen = <String>{};
  return [
    for (final v in [...library, ...?studySuggestions[field]])
      if (!skip.contains(v.toLowerCase()) &&
          seen.add(v.toLowerCase()) &&
          (q.isEmpty || v.toLowerCase().contains(q)))
        v,
  ].take(8).toList();
}

/// The paper screen's "Study details": invisible (just a quiet text button)
/// until the paper has some or the reader asks to add them.
class StudyDetailsSection extends ConsumerStatefulWidget {
  const StudyDetailsSection({super.key, required this.paper});

  final Paper paper;

  @override
  ConsumerState<StudyDetailsSection> createState() =>
      _StudyDetailsSectionState();
}

class _StudyDetailsSectionState extends ConsumerState<StudyDetailsSection> {
  bool _asked = false;

  @override
  Widget build(BuildContext context) {
    final show = _asked || hasStudyDetails(widget.paper);
    final reduced = AppMotion.reduced(context);
    final theme = Theme.of(context);
    return AnimatedSize(
      duration: reduced ? const Duration(milliseconds: 1) : AppMotion.medium,
      curve: AppMotion.standard,
      alignment: Alignment.topCenter,
      child: !show
          ? Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _asked = true),
                child: const Text('Add study details'),
              ),
            )
          : Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 40,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Study details',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final f in StudyField.values) ...[
                            if (f != StudyField.values.first)
                              const SizedBox(height: 14),
                            _StudyFieldEditor(
                              key: ValueKey(f),
                              field: f,
                              paper: widget.paper,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _StudyFieldEditor extends ConsumerStatefulWidget {
  const _StudyFieldEditor({
    super.key,
    required this.field,
    required this.paper,
  });

  final StudyField field;
  final Paper paper;

  @override
  ConsumerState<_StudyFieldEditor> createState() => _StudyFieldEditorState();
}

class _StudyFieldEditorState extends ConsumerState<_StudyFieldEditor> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;

  /// The chips (list fields) as the reader sees them.
  List<String> _chips = [];

  /// What the database last held for this field, to tell an outside change
  /// from the reader's own edit.
  String _fromDb = '';

  StudyField get field => widget.field;

  @override
  void initState() {
    super.initState();
    _fromDb = studyValue(widget.paper, field);
    if (field.isList) {
      _chips = parseStudyList(_fromDb);
    } else {
      _controller.text = _fromDb;
      _controller.addListener(_scheduleSave);
    }
    _focus.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(_StudyFieldEditor old) {
    super.didUpdateWidget(old);
    final now = studyValue(widget.paper, field);
    if (now == _fromDb) return;
    final untouched = field.isList
        ? formatStudyList(_chips) == (formatStudyList(parseStudyList(_fromDb)))
        : _controller.text == _fromDb;
    _fromDb = now;
    if (!untouched) return;
    if (field.isList) {
      _chips = parseStudyList(now);
    } else {
      _controller.removeListener(_scheduleSave);
      _controller.text = now;
      _controller.addListener(_scheduleSave);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _saveText);
  }

  void _saveText() {
    final text = _controller.text.trim();
    // Our own write comes back as an "outside" change; remember it.
    _fromDb = field == StudyField.sampleSize && int.tryParse(text) == null
        ? _fromDb
        : text;
    setStudyValue(ref.read(databaseProvider), widget.paper.id, field, text);
  }

  void _saveChips() {
    final stored = formatStudyList(_chips) ?? '';
    _fromDb = stored;
    setStudyValue(ref.read(databaseProvider), widget.paper.id, field, stored);
  }

  void _add(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return;
    setState(() {
      _chips = parseStudyList(formatStudyList([..._chips, value]));
      _controller.clear();
    });
    _saveChips();
    _focus.requestFocus();
  }

  void _remove(String value) {
    setState(
      () => _chips = [
        for (final c in _chips)
          if (c != value) c,
      ],
    );
    _saveChips();
  }

  void _onChanged(String text) {
    if (field.isList && text.contains(',')) {
      final parts = text.split(',');
      for (final p in parts.take(parts.length - 1)) {
        _add(p);
      }
      _controller.text = parts.last;
      _controller.selection = TextSelection.collapsed(
        offset: parts.last.length,
      );
    } else {
      setState(() {});
    }
  }

  void _pick(String value) {
    if (field.isList) {
      _add(value);
    } else {
      _controller.text = value;
      _controller.selection = TextSelection.collapsed(offset: value.length);
      _saveText();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final library = ref.watch(studyLibraryValuesProvider(field)).value ?? [];
    final showSuggestions =
        field != StudyField.sampleSize &&
        (_focus.hasFocus || _controller.text.isNotEmpty);
    final suggestions = showSuggestions
        ? studySuggestionsFor(
            field,
            library,
            field.isList ? _chips : [_controller.text],
            _controller.text,
          )
        : const <String>[];
    // A paradigm already typed in full isn't suggested back to the reader.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (field.isList && _chips.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in _chips)
                  InputChip(
                    key: ValueKey('chip-${field.key}-$c'),
                    label: Text(c),
                    onDeleted: () => _remove(c),
                    deleteIconColor: scheme.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        TextField(
          key: ValueKey('input-${field.key}'),
          controller: _controller,
          focusNode: _focus,
          keyboardType: field == StudyField.sampleSize
              ? TextInputType.number
              : TextInputType.text,
          inputFormatters: field == StudyField.sampleSize
              ? [FilteringTextInputFormatter.digitsOnly]
              : null,
          textInputAction: TextInputAction.done,
          onChanged: field.isList ? _onChanged : (_) => setState(() {}),
          onSubmitted: field.isList
              ? (v) {
                  _add(v);
                }
              : null,
          decoration: InputDecoration(
            labelText: field.label,
            helperText: field.isList ? 'Press enter or comma to add' : null,
          ),
        ),
        if (suggestions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in suggestions)
                  ActionChip(
                    key: ValueKey('suggest-${field.key}-$s'),
                    label: Text(s),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _pick(s),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
