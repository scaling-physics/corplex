import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../home/adaptive.dart' show readableWidth;

import '../../theme/app_theme.dart';
import 'audio_link.dart';
import 'audio_playback.dart';

/// Compact player for whatever is playing. Slides in when something is
/// loaded, out when closed, and renders nothing otherwise — so screens can
/// always include it without adding chrome when no audio is in use.
///
/// When [onMark] is given (the note editor), a "Mark" button inserts a
/// timestamp for the current position into the note.
class AudioPlayerBar extends ConsumerWidget {
  const AudioPlayerBar({super.key, this.onMark});

  final void Function(String attachmentId, Duration at)? onMark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(audioPlaybackProvider);
    final current = playback.current;

    return AnimatedSize(
      duration: AppMotion.medium,
      curve: AppMotion.standard,
      alignment: Alignment.bottomCenter,
      child: current == null
          ? const SizedBox(width: double.infinity)
          // A floating card; on a tablet it keeps to the reading width.
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: readableWidth),
                child: _Bar(playback: playback, onMark: onMark),
              ),
            ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.playback, required this.onMark});

  final AudioPlayback playback;
  final void Function(String attachmentId, Duration at)? onMark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    final current = playback.current!;
    final duration = playback.duration;
    final position = duration != null && playback.position > duration
        ? duration
        : playback.position;
    final title = current.title ?? current.url ?? 'Recording';
    final error = playback.error;
    final label = theme.textTheme.labelSmall?.copyWith(
      color: c.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 6),
      decoration: BoxDecoration(
        color: c.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.graphic_eq, size: 18, color: c.onPrimaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  error ?? title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: error == null ? c.onPrimaryContainer : c.error,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 20),
                tooltip: 'Close player',
                onPressed: playback.close,
              ),
            ],
          ),
          if (error == null) ...[
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: c.primary,
                inactiveTrackColor: c.primary.withValues(alpha: 0.2),
                thumbColor: c.primary,
              ),
              child: Slider(
                value: duration == null || duration == Duration.zero
                    ? 0
                    : position.inMilliseconds / duration.inMilliseconds,
                onChanged: duration == null
                    ? null
                    : (v) => playback.seek(duration * v),
              ),
            ),
            LayoutBuilder(
              builder: (context, box) {
                final narrow = box.maxWidth < 420;
                return Row(
                  children: [
                    const SizedBox(width: 8),
                    Text(formatTimestamp(position), style: label),
                    const Spacer(),
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(44, 36),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: playback.cycleSpeed,
                      child: Text('${_speedLabel(playback.speed)}×'),
                    ),
                    IconButton(
                      visualDensity: narrow ? VisualDensity.compact : null,
                      icon: const Icon(Icons.replay_10),
                      tooltip: 'Back 10 seconds',
                      onPressed: () =>
                          playback.skip(const Duration(seconds: -10)),
                    ),
                    IconButton.filled(
                      icon: AnimatedSwitcher(
                        duration: AppMotion.short,
                        child: Icon(
                          playback.playing ? Icons.pause : Icons.play_arrow,
                          key: ValueKey(playback.playing),
                        ),
                      ),
                      tooltip: playback.playing ? 'Pause' : 'Play',
                      onPressed: playback.togglePlay,
                    ),
                    IconButton(
                      visualDensity: narrow ? VisualDensity.compact : null,
                      icon: const Icon(Icons.forward_30),
                      tooltip: 'Forward 30 seconds',
                      onPressed: () =>
                          playback.skip(const Duration(seconds: 30)),
                    ),
                    if (onMark case final onMark? when narrow)
                      // No room for the label on a small phone.
                      IconButton(
                        icon: const Icon(Icons.bookmark_add_outlined),
                        tooltip: 'Mark',
                        onPressed: () => onMark(current.id, playback.position),
                      )
                    else if (onMark case final onMark?)
                      TextButton.icon(
                        icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                        label: const Text('Mark'),
                        // Live position at the moment of the tap, not the last redraw.
                        onPressed: () => onMark(current.id, playback.position),
                      )
                    else ...[
                      const Spacer(),
                      Text(
                        duration == null ? '' : formatTimestamp(duration),
                        style: label,
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  static String _speedLabel(double speed) =>
      speed == speed.roundToDouble() ? speed.toStringAsFixed(0) : '$speed';
}
