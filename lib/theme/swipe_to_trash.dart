import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'haptics.dart';

/// Swipe a card away (either direction) to move it to the trash. The
/// caller offers Undo, so there's no confirmation step to slow it down.
///
/// While dragging, the trash icon grows and fades in with the drag; past
/// the point where letting go will trash the card it is emphasised and a
/// single haptic tick fires (again each time the drag crosses back in).
/// After the swipe the card folds closed instead of snapping away.
class SwipeToTrash extends StatefulWidget {
  const SwipeToTrash({
    super.key,
    required this.dismissKey,
    required this.onTrash,
    required this.child,
  });

  final Key dismissKey;
  final VoidCallback onTrash;
  final Widget child;

  /// Dismissible's default: the fraction of the width at which a release
  /// dismisses.
  static const threshold = 0.4;

  @override
  State<SwipeToTrash> createState() => _SwipeToTrashState();
}

class _SwipeToTrashState extends State<SwipeToTrash> {
  /// Drag progress as a fraction of the threshold (1 = will trash).
  final _progress = ValueNotifier<double>(0);

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  void _onUpdate(DismissUpdateDetails d) {
    if (d.reached && !d.previousReached) AppHaptics.threshold();
    _progress.value = d.progress / SwipeToTrash.threshold;
  }

  Widget _background(Alignment alignment) {
    final c = Theme.of(context).colorScheme;
    final reduced = AppMotion.reduced(context);
    final short = AppMotion.of(context, AppMotion.short);
    return ValueListenableBuilder<double>(
      valueListenable: _progress,
      builder: (context, value, _) {
        final armed = value >= 1;
        final t = value.clamp(0.0, 1.0);
        return AnimatedContainer(
          duration: short,
          curve: AppMotion.standard,
          alignment: alignment,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            color: armed ? c.error : c.errorContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Opacity(
            opacity: reduced ? 1 : t,
            child: AnimatedScale(
              duration: short,
              curve: AppMotion.enter,
              scale: reduced ? 1 : (armed ? 1.2 : 0.6 + 0.4 * t),
              child: Icon(
                Icons.delete_outline,
                color: armed ? c.onError : c.onErrorContainer,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: widget.dismissKey,
      background: _background(Alignment.centerLeft),
      secondaryBackground: _background(Alignment.centerRight),
      // How long the gap closes after the swipe (Dismissible runs this
      // linearly; it has no curve parameter).
      resizeDuration: AppMotion.of(context, AppMotion.medium),
      movementDuration: AppMotion.of(context, AppMotion.short),
      onUpdate: _onUpdate,
      onDismissed: (_) => widget.onTrash(),
      child: widget.child,
    );
  }
}
