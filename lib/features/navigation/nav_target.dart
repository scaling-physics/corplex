/// Somewhere in the app a link, a citation, a search result or the history
/// can lead: the one currency every navigation feature trades in (panes,
/// the quick switcher, back/forward, hover peek, Spotlight).
sealed class NavTarget {
  const NavTarget();

  /// A stable key: two targets with the same key are the same place.
  String get key;
}

/// A note, optionally at a selection (document offsets on the editor's
/// document, as `openNoteAtSelection` takes them).
class NoteTarget extends NavTarget {
  const NoteTarget(this.noteId, {this.selectionStart, this.selectionEnd});

  final String noteId;
  final int? selectionStart;
  final int? selectionEnd;

  @override
  String get key => 'note:$noteId';

  @override
  bool operator ==(Object other) =>
      other is NoteTarget &&
      other.noteId == noteId &&
      other.selectionStart == selectionStart &&
      other.selectionEnd == selectionEnd;

  @override
  int get hashCode => Object.hash(noteId, selectionStart, selectionEnd);

  @override
  String toString() => 'NoteTarget($noteId, $selectionStart–$selectionEnd)';
}

/// A paper's screen, or its PDF at [page] (1-based) when [page] is set.
class PaperTarget extends NavTarget {
  const PaperTarget(this.paperId, {this.page});

  final String paperId;
  final int? page;

  @override
  String get key => 'paper:$paperId';

  @override
  bool operator ==(Object other) =>
      other is PaperTarget && other.paperId == paperId && other.page == page;

  @override
  int get hashCode => Object.hash(paperId, page);

  @override
  String toString() => 'PaperTarget($paperId, p$page)';
}

/// A project's page.
class ProjectTarget extends NavTarget {
  const ProjectTarget(this.projectId);

  final String projectId;

  @override
  String get key => 'project:$projectId';

  @override
  bool operator ==(Object other) =>
      other is ProjectTarget && other.projectId == projectId;

  @override
  int get hashCode => projectId.hashCode;

  @override
  String toString() => 'ProjectTarget($projectId)';
}
