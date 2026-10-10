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
    if (AppMotion.reduced(context)) return widget.child;
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
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;

  /// An optional single next step, e.g. a button.
  final Widget? action;

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
            if (action != null) ...[const SizedBox(height: 20), action!],
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

/// Remembers which list items have been shown, so [ListItemMotion] can tell
/// an item that is new to the list (an Undo restore, a freshly made note)
/// from one that was there all along. Put it around the list, passing the
/// ids currently in it.
class NewItemScope extends StatefulWidget {
  const NewItemScope({super.key, required this.ids, required this.child});

  final Iterable<Object> ids;
  final Widget child;

  @override
  State<NewItemScope> createState() => _NewItemScopeState();
}

class _NewItemScopeState extends State<NewItemScope> {
  late final Set<Object> _known;
  Set<Object> _fresh = const {};

  @override
  void initState() {
    super.initState();
    _known = widget.ids.toSet();
  }

  @override
  void didUpdateWidget(NewItemScope old) {
    super.didUpdateWidget(old);
    final ids = widget.ids.toSet();
    _fresh = ids.difference(_known);
    _known.addAll(ids);
  }

  @override
  Widget build(BuildContext context) =>
      _NewItems(isFresh: _fresh.contains, child: widget.child);
}

class _NewItems extends InheritedWidget {
  const _NewItems({required this.isFresh, required super.child});

  final bool Function(Object id) isFresh;

  // Read once, when an item is built; never needs to notify.
  @override
  bool updateShouldNotify(_NewItems old) => false;
}

/// A list item's motion. Items present when the list first built, or
/// scrolled into view later, fade and slide up (staggered by [index]);
/// an item that joins an already-shown list (see [NewItemScope]) unfolds
/// in place: its height opens while it fades in.
class ListItemMotion extends StatefulWidget {
  const ListItemMotion({
    super.key,
    required this.id,
    required this.index,
    required this.child,
  });

  final Object id;
  final int index;
  final Widget child;

  @override
  State<ListItemMotion> createState() => _ListItemMotionState();
}

class _ListItemMotionState extends State<ListItemMotion>
    with SingleTickerProviderStateMixin {
  late final bool _unfold =
      context.getInheritedWidgetOfExactType<_NewItems>()?.isFresh(widget.id) ??
      false;
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (_unfold) {
      _controller = AnimationController(
        vsync: this,
        duration: AppMotion.medium,
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = _controller;
    if (controller != null &&
        !controller.isCompleted &&
        !controller.isAnimating) {
      if (AppMotion.reduced(context)) {
        controller.value = 1;
      } else {
        controller.forward();
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return EntranceTransition(index: widget.index, child: widget.child);
    }
    final curve = CurvedAnimation(parent: controller, curve: AppMotion.enter);
    return SizeTransition(
      sizeFactor: curve,
      alignment: Alignment.topCenter,
      child: FadeTransition(opacity: curve, child: widget.child),
    );
  }
}
