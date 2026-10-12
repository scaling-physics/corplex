import 'dart:io';

import 'package:corplex/data/database.dart';
import 'package:corplex/features/graph/graph_model.dart';
import 'package:corplex/features/library/openalex.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'cites edges come from cached reference lists, never the network',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final db = AppDatabase.inMemoryForTesting();
      addTearDown(db.close);
      Future<void> paper(String id, String doi) => db
          .into(db.papers)
          .insert(
            PapersCompanion.insert(id: Value(id), title: id, doi: Value(doi)),
          );
      await paper('a', '10.1000/a');
      await paper('b', '10.1000/b');
      await paper('c', '10.1000/c');
      final dir = await Directory.systemTemp.createTemp('oa-graph');
      addTearDown(() => dir.delete(recursive: true));
      final cache = CitationCache(() async => dir);
      await cache.write(
        CitationRecord(
          doi: '10.1000/a',
          fetchedAt: DateTime.utc(2020), // expired, still usable for the map
          workId: 'W1',
          references: const [
            OpenAlexWork(id: 'W2', title: 'B', doi: '10.1000/b'),
            OpenAlexWork(id: 'W9', title: 'Elsewhere', doi: '10.9000/z'),
          ],
          referenceCount: 2,
          cited: const [],
          citedTotal: 0,
        ),
      );
      var calls = 0;
      final net = CitationNetwork(
        OpenAlexClient(
          client: MockClient((_) async {
            calls++;
            return http.Response('{}', 500);
          }),
        ),
        cache,
      );

      final without = await buildGraph(db);
      expect(without.edges, isEmpty);

      final g = await buildGraph(db, citations: net);
      final ids = [for (final n in g.nodes) n.id];
      final a = ids.indexOf('a'), b = ids.indexOf('b');
      final edge = a < b ? (a, b) : (b, a);
      expect(g.edges, [edge]);
      expect(g.citationEdges, {edge});
      expect(g.degrees[ids.indexOf('c')], 0);
      expect(calls, 0);
    },
  );
}
