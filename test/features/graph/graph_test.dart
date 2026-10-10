import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show FlutterQuillLocalizations;
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/graph/graph_model.dart';
import 'package:corplex/features/graph/graph_screen.dart';
import 'package:corplex/features/notes/note_editor_screen.dart';
import 'package:corplex/features/projects/projects_providers.dart';

import '../../support/fake_audio_engine.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    EditableText.debugDeterministicCursor = true;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
    Future<void> note(String id, String title, [String content = '']) => db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: Value(id),
            title: Value(title),
            content: Value(content),
          ),
        );
    await note(
      'n1',
      'Lecture',
      '[{"insert":"see ","attributes":{"link":"corplex://note/n2"}}]',
    );
    await note('n2', 'Ideas');
    await note('n3', 'Review', '[{"insert":"as shown [@vaswani2017]\\n"}]');
    await note('n4', 'Loner');
    await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(id: const Value('p1'), title: 'Attention'),
        );
    await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(
            id: const Value('p2'),
            title: 'Transformers',
            citekey: const Value('vaswani2017'),
          ),
        );
    await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(id: const Value('p3'), title: 'Unrelated'),
        );
    await db
        .into(db.notePaperRefs)
        .insert(NotePaperRefsCompanion.insert(noteId: 'n1', paperId: 'p1'));
  });
  tearDown(() {
    EditableText.debugDeterministicCursor = false;
    db.close();
  });

  Set<String> edgeNames(GraphData g) => {
    for (final (a, b) in g.edges)
      ([g.nodes[a].id, g.nodes[b].id]..sort()).join('-'),
  };

  test('edges come from note links, paper references and citations', () async {
    final g = await buildGraph(db);
    expect(g.nodes, hasLength(7));
    expect(edgeNames(g), {'n1-n2', 'n1-p1', 'n3-p2'});
    final n1 = g.nodes.indexWhere((n) => n.id == 'n1');
    expect(g.degrees[n1], 2);
    final loner = g.nodes.indexWhere((n) => n.id == 'n4');
    expect(g.degrees[loner], 0);
  });

  test('a project scopes nodes and edges to its items', () async {
    final id = await findOrCreateProject(db, 'Review');
    await addNoteToProject(db, projectId: id, noteId: 'n1');
    await addNoteToProject(db, projectId: id, noteId: 'n2');
    await addPaperToProject(db, projectId: id, paperId: 'p3');
    final g = await buildGraph(db, projectId: id);
    expect(g.nodes.map((n) => n.id).toSet(), {'n1', 'n2', 'p3'});
    expect(edgeNames(g), {'n1-n2'});
  });

  test('layout is bounded, finite, deterministic and fast at 500 nodes', () {
    final nodes = [
      for (var i = 0; i < 500; i++)
        GraphNode(
          kind: i.isEven ? GraphNodeKind.note : GraphNodeKind.paper,
          id: '$i',
          label: '$i',
        ),
    ];
    final edges = <(int, int)>{for (var i = 1; i < 450; i++) (i ~/ 2, i)}
        .toList();
    final data = GraphData(nodes, edges);
    final watch = Stopwatch()..start();
    final a = layoutGraph(data);
    watch.stop();
    final b = layoutGraph(data);
    expect(watch.elapsedMilliseconds, lessThan(5000));
    for (final p in a.positions) {
      expect(p.dx.isFinite && p.dy.isFinite, isTrue);
      expect(p.dx, inInclusiveRange(0, a.size.width));
      expect(p.dy, inInclusiveRange(0, a.size.height));
    }
    expect(a.positions, b.positions);
  });

  Widget app() => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      audioEngineProvider.overrideWithValue(FakeAudioEngine()),
    ],
    child: const MaterialApp(
      localizationsDelegates: [
        FlutterQuillLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: GraphScreen(),
    ),
  );

  testWidgets('settles, hides unconnected items, and a tap opens a note', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle(); // layout runs once and everything stops
    final canvas = find.byKey(const ValueKey('graph-canvas'));
    expect(canvas, findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(GraphScreen)),
    );
    final layout = container.read(graphLayoutProvider(null)).requireValue;
    final n1 = layout.data.nodes.indexWhere((n) => n.id == 'n1');

    final topLeft = tester.getTopLeft(canvas);
    final scale =
        (tester.getBottomRight(canvas).dx - topLeft.dx) / layout.size.width;
    expect(scale, greaterThan(0));

    // The unconnected note is not drawn: tapping where it sits does nothing.
    final loner = layout.data.nodes.indexWhere((n) => n.id == 'n4');
    await tester.tapAt(topLeft + layout.positions[loner] * scale);
    await tester.pumpAndSettle();
    expect(find.byType(NoteEditorScreen), findsNothing);

    await tester.tapAt(topLeft + layout.positions[n1] * scale);
    await tester.pumpAndSettle();
    expect(find.byType(NoteEditorScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('says so when nothing is connected', (tester) async {
    await db.delete(db.notePaperRefs).go();
    await db.delete(db.notes).go();
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('Nothing connected'), findsOneWidget);
    await tester.tap(find.byTooltip('Show unconnected items'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('graph-canvas')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
