import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// What the PDF viewer's keys do. The viewer wires these to its
/// `PdfViewerController`; tests wire them to counters.
class ViewerKeyActions {
  const ViewerKeyActions({
    required this.zoomIn,
    required this.zoomOut,
    required this.fit,
    required this.nextPage,
    required this.previousPage,
    required this.firstPage,
    required this.lastPage,
  });

  final VoidCallback zoomIn;
  final VoidCallback zoomOut;
  final VoidCallback fit;
  final VoidCallback nextPage;
  final VoidCallback previousPage;
  final VoidCallback firstPage;
  final VoidCallback lastPage;
}

/// The Mac reader's keyboard: ⌘+ / ⌘− / ⌘0 zoom in, out and to fit;
/// Page Down / Space and Page Up / Shift+Space page; Home / End jump.
///
/// pdfrx already handles most of these once its own viewer has focus; these
/// bindings catch the same keys when focus sits elsewhere in the reader
/// (after closing Find, say), where they would otherwise do nothing. Paging
/// is guarded by [enabled] so typing a space into the Find field never
/// turns a page.
Map<ShortcutActivator, VoidCallback> viewerKeyBindings(
  ViewerKeyActions a, {
  bool Function()? enabled,
}) {
  VoidCallback guard(VoidCallback f) =>
      () => (enabled?.call() ?? true) ? f() : null;
  return {
    const SingleActivator(LogicalKeyboardKey.equal, meta: true): a.zoomIn,
    const SingleActivator(LogicalKeyboardKey.equal, meta: true, shift: true):
        a.zoomIn,
    const SingleActivator(LogicalKeyboardKey.numpadAdd, meta: true): a.zoomIn,
    const SingleActivator(LogicalKeyboardKey.minus, meta: true): a.zoomOut,
    const SingleActivator(LogicalKeyboardKey.numpadSubtract, meta: true):
        a.zoomOut,
    const SingleActivator(LogicalKeyboardKey.digit0, meta: true): a.fit,
    const SingleActivator(LogicalKeyboardKey.numpad0, meta: true): a.fit,
    const SingleActivator(LogicalKeyboardKey.pageDown): guard(a.nextPage),
    const SingleActivator(LogicalKeyboardKey.space): guard(a.nextPage),
    const SingleActivator(LogicalKeyboardKey.pageUp): guard(a.previousPage),
    const SingleActivator(LogicalKeyboardKey.space, shift: true): guard(
      a.previousPage,
    ),
    const SingleActivator(LogicalKeyboardKey.home): guard(a.firstPage),
    const SingleActivator(LogicalKeyboardKey.end): guard(a.lastPage),
  };
}
