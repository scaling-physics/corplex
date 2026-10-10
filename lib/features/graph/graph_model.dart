import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../library/citations.dart' show citedKeys;
import '../notes/note_content.dart' show notePlainTextPreview;

enum GraphNodeKind { note, paper }

class GraphNode {
  const GraphNode({required this.kind, required this.id, required this.label});

  final GraphNodeKind kind;
  final String id;
  final String label;
}

/// Notes and papers as nodes; an edge for each note-to-note link, each
/// paper a note is linked to, and each paper a note cites with `[@key]`.
/// Edges are undirected pairs of node indexes, `a < b`, without duplicates.
class GraphData {
  GraphData(this.nodes, this.edges) : degrees = List.filled(nodes.length, 0) {
    for (final (a, b) in edges) {
      degrees[a]++;
      degrees[b]++;
    }
  }

  final List<GraphNode> nodes;
  final List<(int, int)> edges;
  final List<int> degrees;
}

final _noteLink = RegExp(r'corplex://note/([A-Za-z0-9\-]+)');

/// Builds the graph. With [projectId] only that project's notes and papers
/// (and the edges between them) are included.
Future<GraphData> buildGraph(AppDatabase db, {String? projectId}) async {
  var notes = await db.select(db.notes).get();
  var papers = await db.select(db.papers).get();
  if (projectId != null) {
    final noteIds = {
      for (final r in await (db.select(
        db.projectNotes,
      )..where((r) => r.projectId.equals(projectId))).get())
        r.noteId,
    };
    final paperIds = {
      for (final r in await (db.select(
        db.projectPapers,
      )..where((r) => r.projectId.equals(projectId))).get())
        r.paperId,
    };
    notes = [
      for (final n in notes)
        if (noteIds.contains(n.id)) n,
    ];
    papers = [
      for (final p in papers)
        if (paperIds.contains(p.id)) p,
    ];
  }

  final nodes = <GraphNode>[];
  final index = <String, int>{};
  for (final n in notes) {
    index['n:${n.id}'] = nodes.length;
    nodes.add(
      GraphNode(
        kind: GraphNodeKind.note,
        id: n.id,
        label: n.title.trim().isEmpty
            ? _firstWords(notePlainTextPreview(n.content))
            : n.title.trim(),
      ),
    );
  }
  final byCitekey = <String, int>{};
  for (final p in papers) {
    index['p:${p.id}'] = nodes.length;
    if (p.citekey != null && p.citekey!.isNotEmpty) {
      byCitekey[p.citekey!] = nodes.length;
    }
    nodes.add(
      GraphNode(
        kind: GraphNodeKind.paper,
        id: p.id,
        label: p.title.trim().isEmpty ? 'Untitled paper' : p.title.trim(),
      ),
    );
  }

  final edges = <(int, int)>{};
  void connect(int a, int? b) {
    if (b == null || a == b) return;
    edges.add(a < b ? (a, b) : (b, a));
  }

  for (final n in notes) {
    final from = index['n:${n.id}']!;
    for (final m in _noteLink.allMatches(n.content)) {
      connect(from, index['n:${m.group(1)}']);
    }
    for (final key in citedKeys(n.content)) {
      connect(from, byCitekey[key]);
    }
  }
  final refs = await db.select(db.notePaperRefs).get();
  for (final r in refs) {
    final a = index['n:${r.noteId}'];
    if (a != null) connect(a, index['p:${r.paperId}']);
  }
  return GraphData(
    nodes,
    edges.toList()..sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2),
  );
}

String _firstWords(String text) {
  final t = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.isEmpty) return 'Untitled';
  return t.length > 40 ? '${t.substring(0, 40)}…' : t;
}

/// A graph with a position for every node, in a canvas of [size].
class GraphLayout {
  const GraphLayout(this.data, this.positions, this.size);

  final GraphData data;
  final List<Offset> positions;
  final Size size;
}

/// Force-directed layout (Fruchterman-Reingold) of the connected nodes, run
/// a bounded number of rounds and then left alone: nothing keeps ticking.
/// Nodes without edges are not simulated; they are set out in a grid below.
/// Deterministic for a given graph.
GraphLayout layoutGraph(GraphData data, {int maxRounds = 300}) {
  final n = data.nodes.length;
  final connected = [
    for (var i = 0; i < n; i++)
      if (data.degrees[i] > 0) i,
  ];
  final isolated = [
    for (var i = 0; i < n; i++)
      if (data.degrees[i] == 0) i,
  ];
  final m = connected.length;
  final side = math.max(600.0, math.sqrt(math.max(m, 1)) * 110);
  final pos = List<Offset>.filled(n, Offset.zero);

  if (m > 0) {
    final local = {for (final (i, g) in connected.indexed) g: i};
    final rng = math.Random(7);
    final x = List<double>.generate(m, (_) => rng.nextDouble() * side);
    final y = List<double>.generate(m, (_) => rng.nextDouble() * side);
    final links = [for (final (a, b) in data.edges) (local[a]!, local[b]!)];
    final k = math.sqrt(side * side / m) * 0.8;
    // Keep n^2 * rounds bounded (about 40M pair checks), so ~500 nodes stay
    // well under a second.
    final rounds = math.min(maxRounds, math.max(30, 40000000 ~/ (m * m)));
    var temperature = side / 8;
    final dx = List<double>.filled(m, 0);
    final dy = List<double>.filled(m, 0);
    for (var round = 0; round < rounds; round++) {
      dx.fillRange(0, m, 0);
      dy.fillRange(0, m, 0);
      for (var i = 0; i < m; i++) {
        for (var j = i + 1; j < m; j++) {
          var ex = x[i] - x[j];
          var ey = y[i] - y[j];
          var d2 = ex * ex + ey * ey;
          if (d2 < 0.01) {
            ex = 0.1 * (i - j);
            ey = 0.1;
            d2 = ex * ex + ey * ey;
          }
          final f = k * k / d2; // repulsion k^2/d, as a share of the vector
          dx[i] += ex * f;
          dy[i] += ey * f;
          dx[j] -= ex * f;
          dy[j] -= ey * f;
        }
      }
      for (final (a, b) in links) {
        final ex = x[a] - x[b];
        final ey = y[a] - y[b];
        final d = math.sqrt(ex * ex + ey * ey) + 0.01;
        final f = d / k; // attraction d^2/k, as a share of the vector
        dx[a] -= ex * f;
        dy[a] -= ey * f;
        dx[b] += ex * f;
        dy[b] += ey * f;
      }
      final c = side / 2;
      for (var i = 0; i < m; i++) {
        // A weak pull to the middle keeps separate clusters on the canvas.
        dx[i] += (c - x[i]) * 0.05;
        dy[i] += (c - y[i]) * 0.05;
        final len = math.sqrt(dx[i] * dx[i] + dy[i] * dy[i]) + 0.01;
        final step = math.min(len, temperature);
        x[i] += dx[i] / len * step;
        y[i] += dy[i] / len * step;
      }
      temperature *= 0.97;
    }
    // Normalise into the canvas with a margin.
    var minX = x.reduce(math.min), maxX = x.reduce(math.max);
    var minY = y.reduce(math.min), maxY = y.reduce(math.max);
    final w = math.max(maxX - minX, 1.0), h = math.max(maxY - minY, 1.0);
    const margin = 60.0;
    final scale = math.min((side - 2 * margin) / w, (side - 2 * margin) / h);
    final offX = (side - w * scale) / 2, offY = (side - h * scale) / 2;
    for (final (i, g) in connected.indexed) {
      pos[g] = Offset(
        (x[i] - minX) * scale + offX,
        (y[i] - minY) * scale + offY,
      );
    }
  }

  var height = side;
  if (isolated.isNotEmpty) {
    const cell = 90.0;
    final cols = math.max(1, ((side - 120) / cell).floor());
    final top = (m > 0 ? side : 0) + 40.0;
    for (final (i, g) in isolated.indexed) {
      pos[g] = Offset(60 + (i % cols) * cell, top + (i ~/ cols) * cell);
    }
    height = top + ((isolated.length - 1) ~/ cols + 1) * cell;
  }
  if (m == 0) {
    height = math.max(height, 300);
  }
  return GraphLayout(data, pos, Size(side, height));
}

/// The map's data, laid out; [projectId] null means the whole library.
final graphLayoutProvider = FutureProvider.autoDispose
    .family<GraphLayout, String?>((ref, projectId) async {
      final db = ref.watch(databaseProvider);
      final data = await buildGraph(db, projectId: projectId);
      // Let the screen paint its loading state before the layout work.
      await Future<void>.delayed(Duration.zero);
      return layoutGraph(data);
    });
