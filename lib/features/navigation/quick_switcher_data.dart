import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database_provider.dart';
import '../notes/note_aliases.dart' show parseAliases;
import 'switcher_rank.dart';

/// Everything the quick switcher can go to, read straight from the tables
/// (titles only: no note bodies, no FTS), so it is instant. Re-read each
/// time the switcher opens.
final switcherItemsProvider = FutureProvider.autoDispose<List<SwitcherItem>>((
  ref,
) async {
  final db = ref.watch(databaseProvider);
  final items = <SwitcherItem>[];

  final folders = {
    for (final f in await db.select(db.folders).get()) f.id: f.name,
  };

  final notes = await (db.selectOnly(db.notes)
        ..addColumns([
          db.notes.id,
          db.notes.title,
          db.notes.aliases,
          db.notes.folderId,
          db.notes.pinned,
          db.notes.updatedAt,
          db.notes.isTemplate,
        ])
        ..where(db.notes.isTemplate.equals(false)))
      .get();
  for (final r in notes) {
    final folder = folders[r.read(db.notes.folderId)];
    items.add(
      SwitcherItem(
        kind: SwitcherKind.note,
        id: r.read(db.notes.id)!,
        title: r.read(db.notes.title) ?? '',
        subtitle: folder ?? '',
        keywords: parseAliases(r.read(db.notes.aliases)),
        updatedAt: r.read(db.notes.updatedAt),
        pinned: r.read(db.notes.pinned) ?? false,
      ),
    );
  }

  for (final p in await db.select(db.papers).get()) {
    final venue = [
      if ((p.venue ?? '').isNotEmpty) p.venue!,
      if (p.year != null) '${p.year}',
    ].join(' ');
    items.add(
      SwitcherItem(
        kind: SwitcherKind.paper,
        id: p.id,
        title: p.title,
        subtitle: venue,
        keywords: [
          if (p.authors.isNotEmpty) p.authors,
          if ((p.citekey ?? '').isNotEmpty) p.citekey!,
        ],
        updatedAt: p.updatedAt,
        pdfPage: p.lastPage,
        hasPdf: p.pdfPath != null,
      ),
    );
  }

  for (final p in await db.select(db.projects).get()) {
    items.add(
      SwitcherItem(
        kind: SwitcherKind.project,
        id: p.id,
        title: p.name,
        updatedAt: p.updatedAt,
      ),
    );
  }
  for (final s in await db.select(db.savedSearches).get()) {
    items.add(
      SwitcherItem(
        kind: SwitcherKind.savedSearch,
        id: s.id,
        title: s.name,
        subtitle: s.query,
        query: s.query,
        updatedAt: s.updatedAt,
      ),
    );
  }
  for (final f in await db.select(db.folders).get()) {
    items.add(SwitcherItem(kind: SwitcherKind.folder, id: f.id, title: f.name));
  }
  for (final t in await db.select(db.tags).get()) {
    items.add(SwitcherItem(kind: SwitcherKind.tag, id: t.id, title: t.name));
  }
  return items;
});
