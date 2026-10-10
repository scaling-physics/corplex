import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../theme/app_theme.dart';

/// Where a "flight" (a quote or figure travelling into the note) lands in
/// split view: the key of the note pane. Set by the split reader; null
/// everywhere else, where flights head for the bottom of the screen.
final pairedPaneKeyProvider = StateProvider<GlobalKey?>((ref) => null);

/// A small landing area inside the note pane (global coordinates), or null
/// when the reader isn't split.
Rect? paneLanding(GlobalKey? key, {Size size = const Size(120, 48)}) {
  final box = key?.currentContext?.findRenderObject();
  if (box is! RenderBox || !box.attached || !box.hasSize) return null;
  final pane = box.localToGlobal(Offset.zero) & box.size;
  return Rect.fromCenter(
    center: Offset(pane.center.dx, pane.top + pane.height * 0.7),
    width: size.width,
    height: size.height,
  );
}

/// Where a flight lands when there is no note pane: bottom centre, where
/// the snackbar appears.
Rect bottomLanding(BuildContext context, {Size size = const Size(120, 48)}) {
  final screen = MediaQuery.sizeOf(context);
  return Rect.fromCenter(
    center: Offset(screen.width / 2, screen.height - 72),
    width: size.width,
    height: size.height,
  );
}

/// Flies [child] (laid out at [size]) from [from], its centre in global
/// coordinates, into [to], shrinking as it goes and fading out as it
/// lands, in the root overlay; it removes itself afterwards. Does nothing
/// when the system asks for reduced motion. The future completes when the
/// flight is over.
Future<void> flyAcross(
  BuildContext context, {
  required Offset from,
  required Rect to,
  required Size size,
  required Widget child,
  Duration duration = AppMotion.long,
}) {
  if (AppMotion.reduced(context)) return Future.value();
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return Future.value();
  final done = Completer<void>();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _Flight(
      from: from,
      to: to,
      size: size,
      duration: duration,
      onLanded: () {
        entry.remove();
        entry.dispose();
        done.complete();
      },
      child: child,
    ),
  );
  overlay.insert(entry);
  return done.future;
}

class _Flight extends StatefulWidget {
  const _Flight({
    required this.from,
    required this.to,
    required this.size,
    required this.duration,
    required this.onLanded,
    required this.child,
  });

  final Offset from;
  final Rect to;
  final Size size;
  final Duration duration;
  final VoidCallback onLanded;
  final Widget child;

  @override
  State<_Flight> createState() => _FlightState();
}

class _FlightState extends State<_Flight> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(() {
      if (mounted) widget.onLanded();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final endScale = [
      widget.to.width / size.width,
      widget.to.height / size.height,
      1.0,
    ].reduce((a, b) => a < b ? a : b);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        child: SizedBox.fromSize(size: size, child: widget.child),
        builder: (context, child) {
          final t = AppMotion.enter.transform(_c.value);
          final center = Offset.lerp(widget.from, widget.to.center, t)!;
          final scale = 1 + (endScale - 1) * t;
          // Full strength for the first half, then fades as it lands.
          final opacity = 1 - ((_c.value - 0.5) / 0.5).clamp(0.0, 1.0);
          return Stack(
            children: [
              Positioned(
                left: center.dx - size.width / 2,
                top: center.dy - size.height / 2,
                width: size.width,
                height: size.height,
                child: Opacity(
                  opacity: opacity,
                  child: Transform.scale(scale: scale, child: child),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The small card that carries a quoted passage; lay it out at
/// [QuoteCard.size].
class QuoteCard extends StatelessWidget {
  const QuoteCard({super.key, required this.quote});

  static const size = Size(260, 84);

  final String quote;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final text = quote.length > 120 ? '${quote.substring(0, 120)}…' : quote;
    return Material(
      color: c.surfaceContainerHigh,
      elevation: 3,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Text(
          text,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}
