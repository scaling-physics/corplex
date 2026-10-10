import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import 'sync_service.dart';

/// A thin arc turning around [child] while a sync is running, and nothing
/// at all otherwise (no badge, no dot). Under reduced motion the arc holds
/// still instead of turning.
class SyncRing extends ConsumerWidget {
  const SyncRing({super.key, required this.child, this.size = 36});

  final Widget child;

  /// Diameter of the ring; it may be larger than [child].
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncing = ref.watch(syncingProvider).value ?? false;
    return Stack(
      alignment: Alignment.center,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: OverflowBox(
              maxWidth: size,
              maxHeight: size,
              child: AnimatedSwitcher(
                duration: AppMotion.of(context, AppMotion.short),
                child: syncing
                    ? SizedBox.square(
                        key: const ValueKey('sync-ring'),
                        dimension: size,
                        child: const _Arc(),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Arc extends StatefulWidget {
  const _Arc();

  @override
  State<_Arc> createState() => _ArcState();
}

class _ArcState extends State<_Arc> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return RotationTransition(
      turns: _c,
      child: CustomPaint(painter: _ArcPainter(color)),
    );
  }
}

class _ArcPainter extends CustomPainter {
  _ArcPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 2.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.75);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 1.5, false, paint);
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.color != color;
}
