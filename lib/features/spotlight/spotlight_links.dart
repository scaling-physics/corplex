import '../navigation/nav_target.dart';

/// The `corplex://` link a Spotlight result opens, from the result's unique
/// id (a `NavTarget.key`: `note:<id>`, `paper:<id>`, `project:<id>`). Null
/// for anything else.
Uri? spotlightLinkFor(String uniqueId) {
  final colon = uniqueId.indexOf(':');
  if (colon <= 0 || colon == uniqueId.length - 1) return null;
  final kind = uniqueId.substring(0, colon);
  final id = uniqueId.substring(colon + 1);
  if (kind != 'note' && kind != 'paper' && kind != 'project') return null;
  return Uri(scheme: 'corplex', host: kind, pathSegments: [id]);
}

/// The place a `corplex://note/<id>`, `paper/<id>` or `project/<id>` link
/// names (the id is the first path segment). Null for other links.
NavTarget? navTargetForLink(Uri uri) {
  if (uri.scheme != 'corplex' || uri.pathSegments.isEmpty) return null;
  final id = uri.pathSegments.first;
  if (id.isEmpty) return null;
  return switch (uri.host) {
    'note' => NoteTarget(id),
    'paper' => PaperTarget(id),
    'project' => ProjectTarget(id),
    _ => null,
  };
}
