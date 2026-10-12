import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/database_provider.dart';
import '../../data/tables/attachments_table.dart';
import '../../theme/app_theme.dart';
import '../../theme/haptics.dart';
import '../audio/audio_link.dart';
import '../library/add_attachment_sheet.dart';
import 'voice_services.dart';

/// What a finished voice note or dictation produced.
class VoiceResult {
  const VoiceResult({
    this.attachmentId,
    this.transcript = '',
    this.status = TranscriptStatus.done,
    this.duration = Duration.zero,
  });

  /// The saved recording; null for a dictation (text only).
  final String? attachmentId;
  final String transcript;
  final TranscriptStatus status;
  final Duration duration;
}

enum VoiceMode { voiceNote, dictate }

/// The small recording sheet. Returns null if cancelled (nothing is kept).
/// Text is only transcribed for a note ([noteId]); a paper has nowhere to
/// put it, so a paper's recording is audio only.
Future<VoiceResult?> showVoiceSheet(
  BuildContext context, {
  VoiceMode mode = VoiceMode.voiceNote,
  String? noteId,
  String? paperId,
}) {
  return showModalBottomSheet<VoiceResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    // A drag would pop the route even mid-recording; Cancel is explicit.
    enableDrag: false,
    builder: (_) => VoiceSheet(mode: mode, noteId: noteId, paperId: paperId),
  );
}

enum _Phase { idle, recording, working, blocked }

class VoiceSheet extends ConsumerStatefulWidget {
  const VoiceSheet({super.key, required this.mode, this.noteId, this.paperId});

  final VoiceMode mode;
  final String? noteId;
  final String? paperId;

  @override
  ConsumerState<VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends ConsumerState<VoiceSheet> {
  static const _bars = 30;

  late final VoiceRecorder _recorder = ref.read(voiceRecorderProvider);
  late final Dictation _dictation = ref.read(dictationProvider);
  var _phase = _Phase.idle;
  var _blockedBy = MicAccess.denied;
  var _levels = List<double>.filled(_bars, 0);
  var _elapsed = Duration.zero;
  var _live = '';
  final _stopwatch = Stopwatch();
  Timer? _ticker;
  StreamSubscription<double>? _levelSub;
  var _finished = false;

  bool get _dictate => widget.mode == VoiceMode.dictate;

  @override
  void dispose() {
    _ticker?.cancel();
    _levelSub?.cancel();
    if (_phase == _Phase.recording && !_finished) {
      // Torn down mid-recording: keep nothing.
      _dictate ? _dictation.cancel() : _recorder.cancel();
    }
    super.dispose();
  }

  Future<void> _start() async {
    final access = await (_dictate
        ? _dictation.ensureAccess()
        : _recorder.ensureAccess());
    if (!mounted) return;
    if (access != MicAccess.granted) {
      setState(() {
        _phase = _Phase.blocked;
        _blockedBy = access;
      });
      return;
    }
    try {
      if (_dictate) {
        await _dictation.start((t) {
          if (mounted) setState(() => _live = t);
        });
      } else {
        await _recorder.start();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.blocked;
        _blockedBy = MicAccess.unavailable;
      });
      return;
    }
    if (!mounted) return;
    _stopwatch
      ..reset()
      ..start();
    _levelSub = (_dictate ? _dictation.levels : _recorder.levels).listen((l) {
      if (!mounted) return;
      setState(() => _levels = [..._levels.skip(1), l]);
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() => _elapsed = _stopwatch.elapsed);
    });
    HapticFeedback.selectionClick();
    setState(() => _phase = _Phase.recording);
  }

  void _stopClocks() {
    _stopwatch.stop();
    _ticker?.cancel();
    _levelSub?.cancel();
  }

  Future<void> _stop() async {
    _stopClocks();
    final duration = _stopwatch.elapsed;
    AppHaptics.confirm();
    setState(() {
      _phase = _Phase.working;
      _elapsed = duration;
    });
    if (_dictate) {
      final text = (await _dictation.stop()).trim();
      _finish(VoiceResult(transcript: text, duration: duration));
      return;
    }
    final path = await _recorder.stop();
    if (path == null) {
      _finish(null);
      return;
    }
    final db = ref.read(databaseProvider);
    final title =
        'Voice note, ${DateFormat.MMMd().add_Hm().format(DateTime.now())}';
    final id = await insertAttachment(
      db,
      noteId: widget.noteId,
      paperId: widget.paperId,
      type: AttachmentType.podcast,
      path: path,
      title: title,
    );
    var transcript = const Transcript(TranscriptStatus.done);
    if (widget.noteId != null) {
      transcript = await ref.read(transcriberProvider).transcribeFile(path);
    }
    _finish(
      VoiceResult(
        attachmentId: id,
        transcript: transcript.text,
        status: transcript.status,
        duration: duration,
      ),
    );
  }

  Future<void> _cancel() async {
    _stopClocks();
    if (_phase == _Phase.recording) {
      _finished = true;
      await (_dictate ? _dictation.cancel() : _recorder.cancel());
    }
    _finish(null);
  }

  void _finish(VoiceResult? result) {
    _finished = true;
    if (mounted) Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final recording = _phase == _Phase.recording;
    return PopScope(
      canPop: _phase == _Phase.idle || _phase == _Phase.blocked,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _dictate ? 'Dictate' : 'Voice note',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              if (_phase == _Phase.blocked)
                _Blocked(access: _blockedBy)
              else ...[
                Text(
                  formatTimestamp(_elapsed),
                  style: theme.textTheme.headlineLarge?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 40,
                  child: _LevelMeter(levels: _levels, active: recording),
                ),
                if (_dictate && _live.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 96),
                    child: SingleChildScrollView(
                      reverse: true,
                      child: Text(_live, style: theme.textTheme.bodyMedium),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (_phase == _Phase.working)
                  Column(
                    children: [
                      const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _dictate ? 'Finishing…' : 'Saving and transcribing…',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  )
                else
                  Semantics(
                    button: true,
                    label: recording ? 'Stop recording' : 'Start recording',
                    excludeSemantics: true,
                    child: SizedBox.square(
                      dimension: 72,
                      child: IconButton.filled(
                        key: const Key('voice-record-button'),
                        style: IconButton.styleFrom(
                          backgroundColor: recording
                              ? scheme.error
                              : scheme.primary,
                          foregroundColor: recording
                              ? scheme.onError
                              : scheme.onPrimary,
                        ),
                        iconSize: 34,
                        icon: Icon(recording ? Icons.stop_rounded : Icons.mic),
                        onPressed: recording ? _stop : _start,
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 8),
              if (_phase != _Phase.working)
                TextButton(
                  key: const Key('voice-cancel-button'),
                  onPressed: _cancel,
                  child: Text(_phase == _Phase.blocked ? 'Close' : 'Cancel'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Blocked extends ConsumerWidget {
  const _Blocked({required this.access});

  final MicAccess access;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final denied = access == MicAccess.denied;
    return Column(
      children: [
        Text(
          denied
              ? 'Corplex needs the microphone to record. You can allow it in '
                    'Settings.'
              : 'Recording isn’t available here, so nothing was recorded.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (denied) ...[
          const SizedBox(height: 12),
          FilledButton.tonal(
            key: const Key('voice-open-settings'),
            onPressed: () => ref.read(openAppSettingsProvider)(),
            child: const Text('Open Settings'),
          ),
        ],
      ],
    );
  }
}

/// A row of bars that follows the input level. With reduced motion (or
/// before recording) the bars are static.
class _LevelMeter extends StatelessWidget {
  const _LevelMeter({required this.levels, required this.active});

  final List<double> levels;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);
    final scheme = Theme.of(context).colorScheme;
    return Row(
      key: const Key('voice-level-meter'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final level in levels)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.5),
            child: AnimatedContainer(
              duration: AppMotion.of(context, const Duration(milliseconds: 90)),
              curve: AppMotion.standard,
              width: 4,
              height: reduced || !active
                  ? 6
                  : 6 + 34 * math.sqrt(level.clamp(0.0, 1.0)),
              decoration: BoxDecoration(
                color: active
                    ? scheme.primary.withValues(alpha: reduced ? 0.5 : 0.85)
                    : scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
      ],
    );
  }
}

/// Puts a dictation's text, or a voice note's title and transcript, in the
/// note at the cursor. For a voice note the `▸ 0:00 ` link must already be
/// placed with the cursor after it.
void insertVoiceText(QuillController controller, VoiceResult result) {
  final docEnd = controller.document.length - 1;
  final at = controller.selection.baseOffset;
  final index = at < 0 || at > docEnd ? docEnd : at;
  final text = result.attachmentId != null
      ? (result.transcript.isEmpty
            ? 'Voice note\n'
            : 'Voice note\n${result.transcript}\n')
      : (result.transcript.isEmpty ? '' : '${result.transcript} ');
  if (text.isEmpty) return;
  controller.replaceText(
    index,
    0,
    text,
    TextSelection.collapsed(offset: index + text.length),
  );
}

/// Tells the user, calmly, why a voice note has no text (the audio is kept).
void reportVoiceResult(BuildContext context, WidgetRef ref, VoiceResult r) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  if (r.attachmentId == null) {
    if (r.transcript.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Didn’t catch any speech.')),
      );
    }
    return;
  }
  switch (r.status) {
    case TranscriptStatus.done:
      if (r.transcript.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Saved. No speech was heard.')),
        );
      }
    case TranscriptStatus.unavailable:
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Saved the audio. This device can’t transcribe it offline.',
          ),
        ),
      );
    case TranscriptStatus.denied:
      final open = ref.read(openAppSettingsProvider);
      messenger.showSnackBar(
        SnackBar(
          content: const Text(
            'Saved the audio. Allow Speech Recognition to get text too.',
          ),
          action: SnackBarAction(label: 'Settings', onPressed: open),
        ),
      );
  }
}
