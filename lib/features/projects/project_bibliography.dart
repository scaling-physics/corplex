import 'package:drift/drift.dart' show innerJoin;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../library/citation_formatter.dart';
import '../csl/csl_format.dart';
import '../csl/style_picker.dart';

/// The reference list of every paper in [project], as plain text.
Future<String> projectBibliography(
  AppDatabase db,
  Project project,
  CitationStyle style,
) async {
  final papers =
      await (db.select(db.papers).join([
            innerJoin(
              db.projectPapers,
              db.projectPapers.paperId.equalsExp(db.papers.id),
            ),
          ])..where(db.projectPapers.projectId.equals(project.id)))
          .map((r) => r.readTable(db.papers))
          .get();
  return '${(await referenceLines(papers, style)).join('\n\n')}\n';
}

/// Asks for a style, then shares the project's bibliography.
Future<void> shareProjectBibliography(
  BuildContext context,
  WidgetRef ref,
  Project project,
) async {
  final style = await pickCitationStyle(context);
  if (style == null || !context.mounted) return;
  final text = await projectBibliography(
    ref.read(databaseProvider),
    project,
    style,
  );
  if (!context.mounted) return;
  if (text.trim().isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No papers in this project yet.')),
    );
    return;
  }
  await SharePlus.instance.share(
    ShareParams(text: text, subject: '${project.name} bibliography'),
  );
}
