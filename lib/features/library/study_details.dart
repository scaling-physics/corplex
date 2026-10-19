import 'package:drift/drift.dart';

import '../../data/database.dart';
import '../../l10n/l10n.dart';

/// A paper's optional study details (schema v15): what was studied and how.
/// Shared by the paper screen, Library filters, search, the synthesis
/// matrix (columns bound to a field) and exports.
enum StudyField {
  species('species', 'Species / model'),
  brainRegions('brain_regions', 'Brain regions'),
  techniques('techniques', 'Techniques'),
  sampleSize('sample_size', 'Sample size (n)'),
  paradigm('paradigm', 'Task / paradigm');

  const StudyField(this.key, this.label);

  /// The SQL / sync column name, also stored in `matrix_columns.paper_field`.
  final String key;
  final String label;

  /// [label] in the reader's language.
  String labelFor(AppLocalizations l10n) => switch (this) {
    species => l10n.studyFieldSpecies,
    brainRegions => l10n.studyFieldBrainRegions,
    techniques => l10n.studyFieldTechniques,
    sampleSize => l10n.studyFieldSampleSize,
    paradigm => l10n.studyFieldParadigm,
  };

  /// Fields that hold several values (`a; b`).
  bool get isList =>
      this == species || this == brainRegions || this == techniques;

  static StudyField? byKey(String? key) {
    for (final f in values) {
      if (f.key == key) return f;
    }
    return null;
  }
}

/// `"mouse; Human ;; rat"` → `['mouse', 'Human', 'rat']`.
List<String> parseStudyList(String? stored) => [
  for (final part in (stored ?? '').split(';'))
    if (part.trim().isNotEmpty) part.trim(),
];

/// The stored form of a list (null when empty); duplicates are dropped
/// case-insensitively, keeping the first spelling.
String? formatStudyList(Iterable<String> values) {
  final seen = <String>{};
  final kept = [
    for (final v in values.map((v) => v.trim()))
      if (v.isNotEmpty && seen.add(v.toLowerCase())) v,
  ];
  return kept.isEmpty ? null : kept.join('; ');
}

/// The field as display text ('' when unset).
String studyValue(Paper paper, StudyField field) => switch (field) {
  StudyField.species => paper.species ?? '',
  StudyField.brainRegions => paper.brainRegions ?? '',
  StudyField.techniques => paper.techniques ?? '',
  StudyField.sampleSize => paper.sampleSize?.toString() ?? '',
  StudyField.paradigm => paper.paradigm ?? '',
};

/// The field's values as a list (one item for the single-value fields).
List<String> studyValues(Paper paper, StudyField field) => field.isList
    ? parseStudyList(studyValue(paper, field))
    : [if (studyValue(paper, field).isNotEmpty) studyValue(paper, field)];

bool hasStudyDetails(Paper paper) =>
    StudyField.values.any((f) => studyValue(paper, f).isNotEmpty);

/// Writes [text] (as typed: `a; b` for lists, digits for n; blank clears)
/// into [field] of the paper. A sample size that isn't a whole number is
/// ignored.
Future<void> setStudyValue(
  AppDatabase db,
  String paperId,
  StudyField field,
  String text,
) {
  final trimmed = text.trim();
  final list = formatStudyList(parseStudyList(trimmed));
  final companion = switch (field) {
    StudyField.species => PapersCompanion(species: Value(list)),
    StudyField.brainRegions => PapersCompanion(brainRegions: Value(list)),
    StudyField.techniques => PapersCompanion(techniques: Value(list)),
    StudyField.sampleSize => PapersCompanion(
      sampleSize: Value(trimmed.isEmpty ? null : int.tryParse(trimmed)),
    ),
    StudyField.paradigm => PapersCompanion(
      paradigm: Value(trimmed.isEmpty ? null : trimmed),
    ),
  };
  if (field == StudyField.sampleSize &&
      trimmed.isNotEmpty &&
      int.tryParse(trimmed) == null) {
    return Future.value();
  }
  return (db.update(
    db.papers,
  )..where((p) => p.id.equals(paperId))).write(companion);
}

/// Common values offered before the reader has typed their own (which are
/// then suggested first). Neuroscience-leaning on purpose.
const studySuggestions = <StudyField, List<String>>{
  StudyField.species: [
    'human',
    'mouse',
    'rat',
    'macaque',
    'marmoset',
    'zebrafish',
    'Drosophila',
    'C. elegans',
    'organoid',
    'computational model',
  ],
  StudyField.brainRegions: [
    'hippocampus',
    'CA1',
    'CA3',
    'dentate gyrus',
    'entorhinal cortex',
    'prefrontal cortex',
    'mPFC',
    'V1',
    'S1',
    'M1',
    'striatum',
    'amygdala',
    'thalamus',
    'cerebellum',
    'VTA',
  ],
  StudyField.techniques: [
    'patch clamp',
    'extracellular recording',
    'Neuropixels',
    '2-photon imaging',
    'fiber photometry',
    'optogenetics',
    'chemogenetics',
    'fMRI',
    'EEG',
    'MEG',
    'lesion',
    'pharmacology',
    'behaviour',
    'histology',
    'computational modelling',
  ],
  StudyField.paradigm: [
    'fear conditioning',
    'Morris water maze',
    'spatial navigation',
    'go/no-go',
    'working memory',
    'resting state',
    'sleep',
  ],
};
