import 'package:flutter/widgets.dart';

/// Where the share sheet should point from, for `ShareParams.sharePositionOrigin`.
/// macOS (and iPad) anchor the share picker to this rect; without it the
/// picker appears in the window's corner. Pass the context of the button
/// that was pressed; a context that covers most of the screen (a whole
/// page) anchors to a small spot near the top centre instead, since a
/// picker pointing at a page-sized rect sits at its far edge.
Rect shareOrigin(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  final fallback = Rect.fromCenter(
    center: Offset(size.width / 2, size.height / 4),
    width: 1,
    height: 1,
  );
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize || !box.attached) return fallback;
  final rect = box.localToGlobal(Offset.zero) & box.size;
  final tooBig = rect.width > size.width / 2 || rect.height > size.height / 2;
  return tooBig || rect.isEmpty ? fallback : rect;
}
