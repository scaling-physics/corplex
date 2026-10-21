import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../notes/note_sections.dart' show NoteHeading;
import '../platform/mac_window.dart' show MenuCommand;

/// What the quick switcher needs from the note editor that last had the
/// reader's attention: its headings (for `#`), jumping to one, and running
/// note-only commands.
abstract class NoteNavigator {
  String get noteId;
  String get title;

  /// The note's headings, offsets in the whole (unfolded) note.
  List<NoteHeading> headings();
  void jumpTo(NoteHeading heading);

  /// Runs a note-only command (Add bibliography, Lock note…); false if this
  /// editor doesn't take it.
  bool run(MenuCommand command);
}

/// The open editors, last registered first. Not reactive on purpose: editors
/// register while building and unregister while disposing.
class NoteNavigatorRegistry {
  final List<NoteNavigator> _list = [];

  NoteNavigator? get focused => _list.isEmpty ? null : _list.last;

  void register(NoteNavigator navigator) {
    _list.remove(navigator);
    _list.add(navigator);
  }

  void unregister(NoteNavigator navigator) => _list.remove(navigator);
}

final noteNavigatorRegistryProvider = Provider<NoteNavigatorRegistry>(
  (ref) => NoteNavigatorRegistry(),
);

/// Asks the home shell to open the quick switcher (the note editor's own
/// key, where ⌘K means "link a note").
final quickSwitcherRequestProvider = StateProvider<int>((ref) => 0);

/// A [NoteNavigator] made of closures, for the editor to register.
class CallbackNoteNavigator implements NoteNavigator {
  CallbackNoteNavigator({
    required this.noteId,
    required this.titleOf,
    required this.headingsOf,
    required this.jumpToHeading,
    required this.runCommand,
  });

  @override
  final String noteId;
  final String Function() titleOf;
  final List<NoteHeading> Function() headingsOf;
  final void Function(NoteHeading) jumpToHeading;
  final bool Function(MenuCommand) runCommand;

  @override
  String get title => titleOf();
  @override
  List<NoteHeading> headings() => headingsOf();
  @override
  void jumpTo(NoteHeading heading) => jumpToHeading(heading);
  @override
  bool run(MenuCommand command) => runCommand(command);
}
