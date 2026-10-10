import 'package:uuid/uuid.dart';

import '../../data/database.dart';
import '../library/metadata_lookup.dart';

final _prefix = RegExp(
  r'^(?:https?://(?:dx\.)?doi\.org/|https?://(?:www\.)?arxiv\.org/(?:abs|pdf)/|doi:|arxiv:)',
  caseSensitive: false,
);
final _suffix = RegExp(r'^(?:v\d+)?(?:\.pdf)?$', caseSensitive: false);

/// The identifier in [pasted] if the *whole* text is one: a DOI, a doi.org
/// link, an arXiv id or an arxiv.org link. A sentence or a URL that merely
/// contains one is not.
PaperIdentifier? wholeIdentifier(String pasted) {
  final text = pasted.trim().replaceFirst(RegExp(r'[.,;]+$'), '');
  if (text.isEmpty || RegExp(r'\s').hasMatch(text)) return null;
  final id = parseIdentifier(text);
  if (id == null) return null;
  final rest = text.replaceFirst(_prefix, '');
  final value = id.value.toLowerCase();
  if (!rest.toLowerCase().startsWith(value)) return null;
  return _suffix.hasMatch(rest.substring(value.length)) ? id : null;
}

/// The identifier a single local insertion pasted, or null for typing and
/// anything else. A paste arrives as one multi-character insert; typing
/// inserts one character at a time.
PaperIdentifier? pastedIdentifier(String inserted) =>
    inserted.length < 7 ? null : wholeIdentifier(inserted);

/// Finds the paper for [id] — the one already in the library if it's a
/// duplicate, otherwise a new one from a lookup — and returns its id.
/// Null when nothing was found; throws [LookupFailed] when offline.
Future<String?> paperIdForIdentifier(
  AppDatabase db,
  MetadataLookup lookup,
  PaperIdentifier id,
) async {
  final meta = await lookup.lookup(id);
  if (meta == null) return null;
  final result = await addPaperFromMetadata(db, meta, id: const Uuid().v4());
  return result.id ?? result.existing?.id;
}
