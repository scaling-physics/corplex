import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Keeps every child alive (scroll position, text, state) like an
/// [IndexedStack], but switches between them with a Material "fade
/// through": the old page fades out quickly, then the new one fades in
/// while settling up from a slight scale. Inactive pages are [Offstage]
/// and their tickers paused.
class FadeThroughIndexedStack extends StatefulWidget {
  const FadeThroughIndexedStack({
    super.key,
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  State<FadeThroughIndexedStack> createState() =>
      _FadeThroughIndexedStackState();
}

class _FadeThroughIndexedStackState extends State<FadeThroughIndexedStack>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: AppMotion.medium,
    value: 1,
  );
  int? _previous;

  @override
  void didUpdateWidget(FadeThroughIndexedStack old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      _previous = old.index;
      _controller.forward(from: 0).whenComplete(() {
        if (mounted) setState(() => _previous = null);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Outgoing page is gone in the first third; incoming uses the rest.
    final fadeOut = ReverseAnimation(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.35, curve: Curves.easeOut),
      ),
    );
    final fadeIn = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.35, 1, curve: AppMotion.enter),
    );
    final scaleIn = Tween<double>(begin: 0.97, end: 1).animate(fadeIn);

    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          if (i == widget.index)
            FadeTransition(
              key: ValueKey(i),
              opacity: fadeIn,
              child: ScaleTransition(scale: scaleIn, child: widget.children[i]),
            )
          else if (i == _previous)
            IgnorePointer(
              key: ValueKey(i),
              child: FadeTransition(
                opacity: fadeOut,
                child: widget.children[i],
              ),
            )
          else
            Offstage(
              key: ValueKey(i),
              child: TickerMode(enabled: false, child: widget.children[i]),
            ),
      ],
    );
  }
}

/// Fades and slides a list item up into place the first time it's built.
/// [index] staggers neighbouring items slightly (capped, so long lists
/// don't take ages to appear).
class EntranceTransition extends StatefulWidget {
  const EntranceTransition({
    super.key,
    required this.index,
    required this.child,
  });

  final int index;
  final Widget child;

  @override
  State<EntranceTransition> createState() => _EntranceTransitionState();
}

class _EntranceTransitionState extends State<EntranceTransition>
    with SingleTickerProviderStateMixin {
  static const _stagger = 0.06;
  static const _maxStaggered = 8;

  late final AnimationController _controller;
  late final Animation<double> _curve;

  @override
  void initState() {
    super.initState();
    final slot = widget.index.clamp(0, _maxStaggered);
    final start = slot * _stagger;
    _controller = AnimationController(
      vsync: this,
      // Longer for later items, so each gets the same visible motion
      // after its delay.
      duration: AppMotion.medium * (1 + start),
    )..forward();
    _curve = CurvedAnimation(
      parent: _controller,
      curve: Interval(start / (1 + start), 1, curve: AppMotion.enter),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(_curve),
        child: widget.child,
      ),
    );
  }
}

/// A calm empty state: a soft icon disc, a short headline, one line of
/// guidance. Used wherever a list has nothing to show yet.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 64),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: c.primaryContainer.withValues(alpha: 0.7),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: c.onPrimaryContainer),
            ),
            const SizedBox(height: 20),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: c.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cross-fades between loading / empty / content states instead of
/// popping, keyed by [stateKey].
class StateSwitcher extends StatelessWidget {
  const StateSwitcher({super.key, required this.stateKey, required this.child});

  final Object stateKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotion.medium,
      switchInCurve: AppMotion.enter,
      switchOutCurve: Curves.easeOut,
      child: KeyedSubtree(key: ValueKey(stateKey), child: child),
    );
  }
}
