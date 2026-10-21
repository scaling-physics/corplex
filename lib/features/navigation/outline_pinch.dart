import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Trackpad pinch (macOS delivers it as `PointerPanZoom` events): calls
/// [onPinchOut] once per gesture when the fingers close past
/// [outThreshold] (scale below it), [onPinchIn] when they open past
/// [inThreshold]. Only listens, never claims the pointer, so scrolling and
/// text selection underneath are untouched. Don't wrap the PDF viewer: it
/// has its own pinch.
class PinchDetector extends StatefulWidget {
  const PinchDetector({
    super.key,
    required this.child,
    this.onPinchOut,
    this.onPinchIn,
    this.outThreshold = 0.8,
    this.inThreshold = 1.25,
  });

  final Widget child;
  final VoidCallback? onPinchOut;
  final VoidCallback? onPinchIn;
  final double outThreshold;
  final double inThreshold;

  @override
  State<PinchDetector> createState() => _PinchDetectorState();
}

class _PinchDetectorState extends State<PinchDetector> {
  bool _fired = false;

  void _update(PointerPanZoomUpdateEvent event) {
    if (_fired) return;
    if (event.scale < widget.outThreshold && widget.onPinchOut != null) {
      _fired = true;
      widget.onPinchOut!();
    } else if (event.scale > widget.inThreshold && widget.onPinchIn != null) {
      _fired = true;
      widget.onPinchIn!();
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerPanZoomStart: (_) => _fired = false,
    onPointerPanZoomUpdate: _update,
    onPointerPanZoomEnd: (_) => _fired = false,
    child: widget.child,
  );
}
