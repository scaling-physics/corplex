import 'package:animations/animations.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'adaptive.dart';

/// A list card that, where a tap pushes a page (phone and tablet
/// portrait), grows into that page (a container transform, fading). Where
/// the home screen has a detail pane, it's an ordinary card that calls
/// [onOpenInPane] and is tinted while [selected].
///
/// The closed card takes its colour and shape from the card theme, so the
/// animation starts without a visual jump.
///
/// On iOS and macOS it pushes an ordinary page instead: the container
/// transform's route has no edge swipe-back, and on those platforms the
/// swipe is how people leave a page.
///
/// With a mouse or trackpad (iPad pointer, desktop) the card lifts a little
/// and the ink shows its hover tint; touch and pen never trigger either.
class OpenCard extends StatefulWidget {
  const OpenCard({
    super.key,
    required this.selected,
    required this.onOpenInPane,
    required this.pageBuilder,
    required this.child,
  });

  final bool selected;
  final VoidCallback onOpenInPane;
  final WidgetBuilder pageBuilder;
  final Widget child;

  /// How far a hovered card rises above the theme's card elevation.
  static const hoverLift = 2.0;

  @override
  State<OpenCard> createState() => _OpenCardState();
}

class _OpenCardState extends State<OpenCard> {
  bool _hovered = false;

  void _hover(PointerEvent event, bool inside) {
    final pointer =
        event.kind == PointerDeviceKind.mouse ||
        event.kind == PointerDeviceKind.trackpad;
    final next = inside && pointer;
    if (next != _hovered) setState(() => _hovered = next);
  }

  @override
  Widget build(BuildContext context) {
    final lift = TweenAnimationBuilder<double>(
      tween: Tween(end: _hovered ? OpenCard.hoverLift : 0),
      duration: AppMotion.of(context, AppMotion.short),
      curve: AppMotion.enter,
      builder: (context, lift, _) => _card(context, lift),
    );
    return MouseRegion(
      onEnter: (e) => _hover(e, true),
      onHover: (e) => _hover(e, true),
      onExit: (e) => _hover(e, false),
      child: lift,
    );
  }

  Widget _card(BuildContext context, double lift) {
    final theme = Theme.of(context);
    final child = widget.child;
    final card = theme.cardTheme;
    final elevation = (card.elevation ?? 0) + lift;
    if (hasDetailPane(context)) {
      return Card(
        elevation: elevation,
        color: widget.selected ? theme.colorScheme.secondaryContainer : null,
        child: InkWell(onTap: widget.onOpenInPane, child: child),
      );
    }
    if (theme.platform case TargetPlatform.iOS || TargetPlatform.macOS) {
      return Card(
        elevation: elevation,
        child: InkWell(
          onTap: () =>
              Navigator.of(context)
                  .push(MaterialPageRoute<void>(builder: widget.pageBuilder)),
          child: child,
        ),
      );
    }
    return OpenContainer<void>(
      transitionType: ContainerTransitionType.fade,
      transitionDuration: AppMotion.of(context, AppMotion.long),
      closedElevation: elevation,
      openElevation: 0,
      closedColor: card.color ?? theme.colorScheme.surface,
      middleColor: theme.colorScheme.surface,
      openColor: theme.scaffoldBackgroundColor,
      closedShape:
          card.shape ??
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      // Pages bring their own Scaffold (and its tint-free background).
      openShape: const RoundedRectangleBorder(),
      clipBehavior: Clip.antiAlias,
      // The transition re-hosts the closed card outside any Material, so
      // the ink needs its own; a see-through Card is that Material.
      closedBuilder: (context, open) => Card(
        color: Colors.transparent,
        shape: const RoundedRectangleBorder(),
        child: InkWell(onTap: open, child: child),
      ),
      openBuilder: (context, _) => widget.pageBuilder(context),
    );
  }
}
