import 'package:drift/drift.dart';

import 'search_index.dart' show SearchKind;
import 'search_query.dart';

/// An SQL condition (`AND`-able, possibly empty) restricting one kind of
/// result by a query's filters.
class SearchFilterSql {
  const SearchFilterSql(this.where, this.variables);

  /// Empty when nothing restricts the kind. Otherwise a conjunction of
  /// `<id> [NOT] IN (subquery)` conditions, without a leading `AND`.
  final String where;
  final List<Variable> variables;

  bool get isEmpty => where.isEmpty;
}

String _escapeLike(String s) =>
    s.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

/// The condition for results of [kind] whose id is the SQL expression
/// [id], or null when no result of that kind can satisfy [query]'s filters
/// (a positive `tag:` leaves out papers, for instance). Filters read the
/// live tables, so changing a tag or folder needs no re-indexing.
SearchFilterSql? searchFilterSql(
  SearchQuery query,
  SearchKind kind,
  String id,
) {
  if (!query.allowsKind(kind)) return null;
  final parts = <String>[];
  final vars = <Variable>[];
  void add(bool negated, String subquery, List<Variable> v) {
    parts.add('$id ${negated ? 'NOT IN' : 'IN'} ($subquery)');
    vars.addAll(v);
  }

  for (final f in query.filters) {
    final isNote = kind == SearchKind.note;
    if (f.notesOnly && !isNote) {
      // Papers and highlights have no tags, folders or pin state.
      if (f.negated) continue;
      return null;
    }
    switch (f.field) {
      case SearchField.tag:
        add(
          f.negated,
          'SELECT nt.note_id FROM note_tags nt JOIN tags t ON t.id = nt.tag_id '
          "WHERE lower(t.name) = ? OR lower(t.name) LIKE ? ESCAPE '\\'",
          [
            Variable.withString(f.value),
            Variable.withString('${_escapeLike(f.value)}/%'),
          ],
        );
      case SearchField.folder:
        add(
          f.negated,
          'SELECT n.id FROM notes n JOIN folders f ON f.id = n.folder_id '
          "WHERE lower(f.name) = ? OR lower(f.name) LIKE ? ESCAPE '\\'",
          [
            Variable.withString(f.value),
            Variable.withString('${_escapeLike(f.value)} / %'),
          ],
        );
      case SearchField.project:
        const byName = 'WHERE lower(p.name) = ?';
        final name = [Variable.withString(f.value)];
        switch (kind) {
          case SearchKind.note:
            add(
              f.negated,
              'SELECT pn.note_id FROM project_notes pn '
              'JOIN projects p ON p.id = pn.project_id $byName',
              name,
            );
          case SearchKind.paper || SearchKind.pdfText:
            add(
              f.negated,
              'SELECT pp.paper_id FROM project_papers pp '
              'JOIN projects p ON p.id = pp.project_id $byName',
              name,
            );
          case SearchKind.highlight:
            add(
              f.negated,
              'SELECT h.id FROM highlights h '
              'JOIN project_papers pp ON pp.paper_id = h.paper_id '
              'JOIN projects p ON p.id = pp.project_id $byName',
              name,
            );
        }
      case SearchField.isPinned:
        add(f.negated, 'SELECT id FROM notes WHERE pinned = 1', const []);
      case SearchField.isTemplate:
        add(f.negated, 'SELECT id FROM notes WHERE is_template = 1', const []);
      case SearchField.isDaily:
        add(
          f.negated,
          'SELECT id FROM notes WHERE daily_date IS NOT NULL',
          const [],
        );
    }
  }
  return SearchFilterSql(parts.join(' AND '), vars);
}
