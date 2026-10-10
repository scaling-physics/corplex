import 'dart:math' as math;

import '../../data/attachment_label.dart';
import '../../data/database.dart' show Attachment;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../home/adaptive.dart' show readableWidth;

import '../../theme/app_theme.dart';
import '../../theme/haptics.dart';
import 'audio_link.dart';
import 'audio_playback.dart';

/// Compact player for whatever is playing. Slides in when something is
/// loaded, out when closed, and renders nothing otherwise — so screens can
/// always include it without adding chrome when no audio is in use.
///
/// When [onMark] is given (the note editor), a "Mark" button inserts a
/// timestamp for the current position into the note.
class AudioPlayerBar extends ConsumerStatefulWidget {
  const AudioPlayerBar({super.key, this.onMark});

  final void Function(String attachmentId, Duration at)? onMark;

  @override
  ConsumerState<AudioPlayerBar> createState() => _AudioPlayerBarState();
}

class _AudioPlayerBarState extends ConsumerState<AudioPlayerBar>
    with SingleTickerProviderStateMixin {
  /// 0 = tucked away, 1 = in place. Rises when something is loaded and
  /// falls when it is closed; a bar mounted while audio is already playing
  /// (opening another screen) starts in place.
  late final AnimationController _presence = AnimationController(
    vsync: this,
    duration: AppMotion.medium,
  )..addStatusListener(_onStatus);

  /// What the bar shows. Kept after the audio is closed so the bar can
  /// slide away with its contents instead of vanishing.
  Attachment? _shown;
  bool? _target;

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed &&
        mounted &&
        ref.read(audioPlaybackProvider).current == null &&
        _shown != null) {
      setState(() => _shown = null);
    }
  }

  void _moveTo(bool visible) {
    if (!mounted || _target != visible) return;
    if (AppMotion.reduced(context)) {
      _presence.value = visible ? 1 : 0;
    } else if (visible) {
      _presence.forward();
    } else {
      _presence.reverse();
    }
  }

  @override
  void dispose() {
    _presence.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playback = ref.watch(audioPlaybackProvider);
    final current = playback.current;
    if (current != null) _shown = current;

    final visible = current != null;
    if (_target == null) {
      _target = visible;
      _presence.value = visible ? 1 : 0;
    } else if (_target != visible) {
      _target = visible;
      WidgetsBinding.instance.addPostFrameCallback((_) => _moveTo(visible));
    }

    final shown = _shown;
    return AnimatedSize(
      // Not zero: AnimatedSize asserts when restarted with no duration.
      duration: AppMotion.reduced(context)
          ? const Duration(milliseconds: 1)
          : AppMotion.medium,
      curve: AppMotion.standard,
      alignment: Alignment.bottomCenter,
      child: shown == null
          ? const SizedBox(width: double.infinity)
          // A floating card; on a tablet it keeps to the reading width.
          // heightFactor 1: as a Scaffold's bottom bar it is offered the
          // whole screen's height, and a plain Center would take it all.
          : Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: readableWidth),
                child: FadeTransition(
                  opacity: CurvedAnimation(
                    parent: _presence,
                    curve: AppMotion.standard,
                  ),
                  child: SlideTransition(
                    position:
                        Tween(
                          begin: const Offset(0, 0.6),
                          end: Offset.zero,
                        ).animate(
                          CurvedAnimation(
                            parent: _presence,
                            curve: AppMotion.enter,
                            reverseCurve: AppMotion.exit,
                          ),
                        ),
                    child: _Bar(
                      playback: playback,
                      current: shown,
                      onMark: widget.onMark,
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

/// A few quiet bars that sway while audio plays. There is no amplitude
/// data, so the heights are a gentle function of the playback position.
/// Each position update glides the bars to their next heights and then
/// stops: nothing runs on its own, so a paused or stalled player is still
/// (and the tree can settle). Only built while playing and with motion
/// allowed; otherwise the bar shows a still icon.
class AudioLevelBars extends StatefulWidget {
  const AudioLevelBars({
    super.key,
    required this.color,
    required this.position,
  });

  final Color color;
  final Duration position;

  @override
  State<AudioLevelBars> createState() => _AudioLevelBarsState();
}

class _AudioLevelBarsState extends State<AudioLevelBars>
    with SingleTickerProviderStateMixin {
  static const _periods = [310.0, 470.0, 390.0, 570.0];
  static const _phases = [0.0, 1.7, 3.1, 4.4];

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 1,
  );
  late List<double> _from = _targets(widget.position);
  late List<double> _to = _from;

  static List<double> _targets(Duration p) => [
    for (var i = 0; i < _periods.length; i++)
      0.5 + 0.5 * math.sin(p.inMilliseconds / _periods[i] + _phases[i]),
  ];

  List<double> _now() => [
    for (var i = 0; i < _to.length; i++)
      _from[i] + (_to[i] - _from[i]) * Curves.easeOut.transform(_c.value),
  ];

  @override
  void didUpdateWidget(AudioLevelBars old) {
    super.didUpdateWidget(old);
    if (old.position != widget.position) {
      _from = _now();
      _to = _targets(widget.position);
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 18,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final levels = _now();
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final level in levels)
                Container(
                  width: 2.5,
                  height: 4 + 11 * level,
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Bar extends StatefulWidget {
  const _Bar({
    required this.playback,
    required this.current,
    required this.onMark,
  });

  final AudioPlayback playback;
  final Attachment current;
  final void Function(String attachmentId, Duration at)? onMark;

  @override
  State<_Bar> createState() => _BarState();
}

class _BarState extends State<_Bar> {
  /// While the thumb is held the slider follows the finger, not the
  /// smoothed playback position.
  bool _dragging = false;

  void _mark(void Function(String attachmentId, Duration at) onMark) {
    AppHaptics.confirm();
    // Live position at the moment of the tap, not the last redraw.
    onMark(widget.current.id, widget.playback.position);
  }

  @override
  Widget build(BuildContext context) {
    final playback = widget.playback;
    final onMark = widget.onMark;
    final current = widget.current;

    final theme = Theme.of(context);
    final c = theme.colorScheme;
    final duration = playback.duration;
    final position = duration != null && playback.position > duration
        ? duration
        : playback.position;
    final fraction = duration == null || duration == Duration.zero
        ? 0.0
        : position.inMilliseconds / duration.inMilliseconds;
    final title = current.label;
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
              if (playback.playing && !AppMotion.reduced(context))
                AudioLevelBars(
                  key: const ValueKey('level-bars'),
                  color: c.onPrimaryContainer,
                  position: position,
                )
              else
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
              // Position updates arrive a few times a second; gliding between
              // them keeps the line from stepping.
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: fraction),
                duration: _dragging
                    ? Duration.zero
                    : AppMotion.of(context, const Duration(milliseconds: 250)),
                curve: Curves.linear,
                builder: (context, value, _) => Slider(
                  value: value.clamp(0.0, 1.0),
                  onChangeStart: duration == null
                      ? null
                      : (_) => setState(() => _dragging = true),
                  onChangeEnd: duration == null
                      ? null
                      : (_) => setState(() => _dragging = false),
                  onChanged: duration == null
                      ? null
                      : (v) => playback.seek(duration * v),
                ),
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
                        onPressed: () => _mark(onMark),
                      )
                    else if (onMark case final onMark?)
                      TextButton.icon(
                        icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                        label: const Text('Mark'),
                        onPressed: () => _mark(onMark),
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
