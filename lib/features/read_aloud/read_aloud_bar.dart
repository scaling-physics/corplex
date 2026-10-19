import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import 'read_aloud_controller.dart';

/// The slim bar shown in the PDF viewer while a paper is read aloud:
/// previous / play-pause / next sentence, speed, the page being read, close.
/// When the reader has scrolled elsewhere, a "Back to reading" chip shows.
class ReadAloudBar extends StatelessWidget {
  const ReadAloudBar({
    super.key,
    required this.controller,
    required this.onClose,
    required this.away,
    required this.onBackToReading,
  });

  final ReadAloudController controller;
  final VoidCallback onClose;

  /// The reader is looking at another page than the one being read.
  final bool away;
  final VoidCallback onBackToReading;

  static const speeds = [0.8, 1.0, 1.25, 1.5, 1.75, 2.0];

  static String speedLabel(double r) =>
      r == r.roundToDouble() ? '${r.toInt()}×' : '$r×';

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final l = context.l10n;
        final status = controller.loading
            ? l.readAloudPreparing
            : controller.isEmpty
            ? l.readAloudNoText
            : controller.finished
            ? l.readAloudFinished
            : l.viewerPageShort(controller.page);
        final ready = !controller.loading && !controller.isEmpty;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (away && ready)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: ActionChip(
                  key: const ValueKey('read-back'),
                  avatar: const Icon(Icons.my_location, size: 16),
                  label: Text(l.readAloudBack),
                  onPressed: onBackToReading,
                ),
              ),
            Material(
              color: c.surfaceContainerHigh,
              elevation: 2,
              borderRadius: BorderRadius.circular(28),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: const ValueKey('read-prev'),
                      icon: const Icon(Icons.skip_previous),
                      tooltip: l.readAloudPrevious,
                      onPressed: ready ? () => controller.skip(-1) : null,
                    ),
                    IconButton.filled(
                      key: const ValueKey('read-toggle'),
                      icon: Icon(
                        controller.playing ? Icons.pause : Icons.play_arrow,
                      ),
                      tooltip: controller.playing
                          ? l.readAloudPause
                          : l.readAloudPlay,
                      onPressed: ready ? controller.toggle : null,
                    ),
                    IconButton(
                      key: const ValueKey('read-next'),
                      icon: const Icon(Icons.skip_next),
                      tooltip: l.readAloudNext,
                      onPressed: ready ? () => controller.skip(1) : null,
                    ),
                    PopupMenuButton<double>(
                      key: const ValueKey('read-speed'),
                      tooltip: l.readAloudSpeed,
                      onSelected: controller.setRate,
                      itemBuilder: (_) => [
                        for (final s in speeds)
                          CheckedPopupMenuItem(
                            value: s,
                            checked: s == controller.rate,
                            child: Text(speedLabel(s)),
                          ),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 12,
                        ),
                        child: Text(
                          speedLabel(controller.rate),
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: AnimatedSize(
                        duration: AppMotion.of(context, AppMotion.short),
                        child: Text(
                          status,
                          key: const ValueKey('read-status'),
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: c.onSurfaceVariant),
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('read-close'),
                      icon: const Icon(Icons.close),
                      tooltip: l.readAloudStop,
                      onPressed: onClose,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
