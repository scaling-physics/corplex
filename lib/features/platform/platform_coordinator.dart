import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../home/adaptive.dart';
import '../navigation/nav_history.dart';
import '../navigation/nav_target.dart';
import '../library/highlights.dart' show parsePaperPageLink;
import '../library/library_screen.dart';
import '../../data/database_provider.dart';
import '../library/papers_providers.dart';
import '../library/pdf_viewer_screen.dart';
import '../notes/daily_notes.dart' show openTodaysNote;
import '../notes/notes_screen.dart';
import '../spotlight/spotlight_channel.dart';
import '../spotlight/spotlight_links.dart';
import '../spotlight/spotlight_service.dart';
import '../projects/project_page.dart';
import 'quick_action_source.dart';
import 'widget_data.dart';

/// Invisible, like `ShareCoordinator`: turns app-icon shortcuts and
/// home-screen widget taps into the same actions the buttons use, and keeps
/// the widget's "continue reading" line fresh.
class PlatformCoordinator extends ConsumerStatefulWidget {
  const PlatformCoordinator({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PlatformCoordinator> createState() =>
      _PlatformCoordinatorState();
}

class _PlatformCoordinatorState extends ConsumerState<PlatformCoordinator> {
  StreamSubscription<Uri?>? _clicks;
  StreamSubscription<String>? _spotlight;
  Timer? _debounce;
  WidgetPayload? _published;

  @override
  void initState() {
    super.initState();
    ref.read(quickActionSourceProvider).start(_onQuickAction);
    final bridge = ref.read(homeWidgetBridgeProvider);
    _clicks = bridge.clicks.listen(_onLink);
    bridge.initialLaunch().then(_onLink);
    // A Spotlight result: its id becomes the same link a widget tap uses.
    _spotlight = ref.read(spotlightChannelProvider).opens.listen((id) {
      _onLink(spotlightLinkFor(id));
    });
  }

  /// Runs [action] once the first frame is up (the launch action can
  /// arrive before it), with a frame requested so it isn't left waiting.
  void _afterFrame(void Function() action) {
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (mounted) action();
      })
      ..scheduleFrame();
  }

  void _onQuickAction(String type) => _afterFrame(() {
    switch (type) {
      case quickNewNote:
        createNote(context, ref);
      case quickTodaysNote:
        openTodaysNote(context, ref);
      case quickImportPdf:
        importPaper(context, ref);
    }
  });

  void _onLink(Uri? uri) {
    if (uri == null) return;
    _afterFrame(() => openWidgetLink(context, ref, uri));
  }

  void _papersChanged(List<Paper> papers) {
    _debounce?.cancel();
    _debounce = Timer(ref.read(widgetDebounceProvider), () {
      final payload = widgetPayloadFor(pickContinueReading(papers));
      if (payload == _published) return;
      _published = payload;
      ref.read(homeWidgetBridgeProvider).publish(payload);
    });
  }

  @override
  void dispose() {
    _clicks?.cancel();
    _spotlight?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(spotlightStartupProvider);
    ref.listen(papersListProvider, (_, next) {
      final papers = next.value;
      if (papers != null) _papersChanged(papers);
    });
    return widget.child;
  }
}

/// Opens what a widget link points at: `corplex://new-note`,
/// `corplex://today` (today's note) or
/// `corplex://paper/<id>?page=N` (the PDF at that page, or the paper's
/// screen when the file isn't on this device).
Future<void> openWidgetLink(
  BuildContext context,
  WidgetRef ref,
  Uri uri,
) async {
  if (uri.scheme != 'corplex') return;
  if (uri.host == 'new-note') {
    await createNote(context, ref);
    return;
  }
  if (uri.host == 'today') {
    await openTodaysNote(context, ref);
    return;
  }
  // Places by id: Spotlight results, `corplex://note/<id>` and friends.
  switch (navTargetForLink(uri)) {
    case NoteTarget(:final noteId):
      openNote(context, ref, noteId);
      return;
    case ProjectTarget(:final projectId):
      final db = ref.read(databaseProvider);
      final exists = await (db.select(
        db.projects,
      )..where((p) => p.id.equals(projectId))).getSingleOrNull();
      if (exists == null || !context.mounted) return;
      if (hasDetailPane(context)) {
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
      recordNavVisit(ref, ProjectTarget(projectId));
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ProjectScreen(projectId: projectId),
        ),
      );
      return;
    case PaperTarget(:final paperId)
        when !uri.queryParameters.containsKey('page'):
      // No page named (a Spotlight result): the paper's own screen.
      openPaper(context, ref, paperId);
      return;
    case PaperTarget() || null:
      break;
  }
  final link = parsePaperPageLink(uri.toString());
  if (link == null) return;
  final db = ref.read(databaseProvider);
  final paper = await (db.select(
    db.papers,
  )..where((p) => p.id.equals(link.paperId))).getSingleOrNull();
  if (paper == null || !context.mounted) return;
  if (paper.pdfPath == null) {
    openPaper(context, ref, paper.id);
    return;
  }
  recordNavVisit(ref, PaperTarget(paper.id, page: link.page));
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PdfViewerScreen(
        paperId: paper.id,
        pdfPath: paper.pdfPath!,
        initialPage: link.page,
      ),
    ),
  );
}
