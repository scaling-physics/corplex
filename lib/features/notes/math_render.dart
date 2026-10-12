import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_math_fork/flutter_math.dart';

/// An equation drawn to a PNG, for exports that can't use Flutter widgets.
class MathImage {
  const MathImage(this.png, this.width, this.height, this.descent);

  final Uint8List png;

  /// Size in logical units (PDF points when rendered at the font size).
  final double width;
  final double height;

  /// Distance from the bottom of the image up to the text baseline.
  final double descent;
}

/// Draws [tex] black on transparent at [fontSize], [pixelRatio] times
/// sharper than its logical size (4 is about 290 dpi in a PDF). Returns
/// null for LaTeX that doesn't parse or any rendering failure: callers fall
/// back to the source text, so a bad equation can never fail an export.
///
/// Needs a Flutter binding (always there in the app and in widget tests).
Future<MathImage?> renderMathPng(
  String tex, {
  bool display = false,
  double fontSize = 11,
  double pixelRatio = 4,
}) async {
  try {
    if (tex.trim().isEmpty || Math.tex(tex).parseError != null) return null;
    final binding = WidgetsBinding.instance;
    final view = binding.platformDispatcher.views.first;

    final boundary = RenderRepaintBoundary();
    final probe = _BaselineHolder();
    final pipeline = PipelineOwner();
    final renderView = RenderView(
      view: view,
      configuration: ViewConfiguration(
        logicalConstraints: const BoxConstraints(
          maxWidth: 4000,
          maxHeight: 4000,
        ),
        physicalConstraints: const BoxConstraints(
          maxWidth: 4000,
          maxHeight: 4000,
        ),
        devicePixelRatio: 1,
      ),
      child: RenderPositionedBox(alignment: Alignment.topLeft, child: boundary),
    );
    pipeline.rootNode = renderView;
    renderView.prepareInitialFrame();

    final owner = BuildOwner(focusManager: FocusManager());
    final root = RenderObjectToWidgetAdapter<RenderBox>(
      container: boundary,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: _BaselineProbe(
          holder: probe,
          child: Math.tex(
            tex,
            mathStyle: display ? MathStyle.display : MathStyle.text,
            textStyle: TextStyle(fontSize: fontSize, color: Colors.black),
            onErrorFallback: (e) => throw e,
          ),
        ),
      ),
    ).attachToRenderTree(owner);
    owner.buildScope(root);
    owner.finalizeTree();
    pipeline
      ..flushLayout()
      ..flushCompositingBits()
      ..flushPaint();

    final size = boundary.size;
    if (size.isEmpty) return null;
    final baseline = probe.baseline;
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    owner.finalizeTree();
    if (data == null) return null;
    return MathImage(
      data.buffer.asUint8List(),
      size.width,
      size.height,
      baseline == null ? 0 : (size.height - baseline).clamp(0, size.height),
    );
  } catch (e, st) {
    debugPrint('math render: $e\n$st');
    return null;
  }
}

class _BaselineHolder {
  double? baseline;
}

/// Records its child's baseline while it is laid out (the only time Flutter
/// lets anyone ask).
class _BaselineProbe extends SingleChildRenderObjectWidget {
  const _BaselineProbe({required this.holder, required Widget super.child});

  final _BaselineHolder holder;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBaselineProbe(holder);

  @override
  void updateRenderObject(BuildContext context, _RenderBaselineProbe r) =>
      r.holder = holder;
}

class _RenderBaselineProbe extends RenderProxyBox {
  _RenderBaselineProbe(this.holder);

  _BaselineHolder holder;

  @override
  void performLayout() {
    super.performLayout();
    holder.baseline = child?.getDistanceToBaseline(TextBaseline.alphabetic);
  }
}
