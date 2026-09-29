import 'package:flutter/material.dart';

/// Swipe a card away (either direction) to move it to the trash. The
/// caller offers Undo, so there's no confirmation step to slow it down.
class SwipeToTrash extends StatelessWidget {
  const SwipeToTrash({
    super.key,
    required this.dismissKey,
    required this.onTrash,
    required this.child,
  });

  final Key dismissKey;
  final VoidCallback onTrash;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    Widget background(Alignment alignment) => Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: c.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(Icons.delete_outline, color: c.onErrorContainer),
    );
    return Dismissible(
      key: dismissKey,
      background: background(Alignment.centerLeft),
      secondaryBackground: background(Alignment.centerRight),
      onDismissed: (_) => onTrash(),
      child: child,
    );
  }
}
