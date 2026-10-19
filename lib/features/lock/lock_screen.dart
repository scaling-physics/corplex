import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import 'note_lock_service.dart';
import 'notes_password_dialogs.dart';

/// Shown in place of the editor while a locked note's key isn't unlocked.
/// Calm and bare: the title, a password field, nothing else until needed.
/// Unlocking (here, or by anything else) makes the caller swap in the
/// editor, so this widget only has to unlock.
class NoteLockScreen extends ConsumerStatefulWidget {
  const NoteLockScreen({super.key, required this.title, this.embedded = false});

  final String title;

  /// One pane of the tablet/desktop layout: no back arrow.
  final bool embedded;

  @override
  ConsumerState<NoteLockScreen> createState() => _NoteLockScreenState();
}

class _NoteLockScreenState extends ConsumerState<NoteLockScreen>
    with SingleTickerProviderStateMixin {
  final _password = TextEditingController();
  final _focus = FocusNode();
  late final NoteLockService _service = ref.read(noteLockServiceProvider);
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  String Function(AppLocalizations)? _error;
  String? _hint;
  bool _showHint = false;
  bool _busy = false;
  bool _biometrics = false;

  @override
  void initState() {
    super.initState();
    _service.hint().then((h) {
      if (mounted) setState(() => _hint = h);
    });
    _tryBiometrics(automatic: true);
  }

  @override
  void dispose() {
    _password.dispose();
    _focus.dispose();
    _shake.dispose();
    super.dispose();
  }

  Future<void> _tryBiometrics({bool automatic = false}) async {
    final enabled = await _service.biometricsEnabled();
    if (!mounted) return;
    setState(() => _biometrics = enabled);
    if (!enabled) return;
    final ok = await _service.unlockWithBiometrics(
      reason: context.l10n.lockBiometricReason,
    );
    if (!mounted || ok) return;
    if (!automatic) _focus.requestFocus();
  }

  Future<void> _submit() async {
    if (_busy || _password.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await _service.unlock(_password.text);
    if (!mounted) return;
    if (ok) {
      // The caller swaps in the editor when the key is available. If it
      // isn't, the note is under an earlier password.
      setState(() {
        _busy = false;
        _error = (l) => l.lockEarlierPassword;
        _password.clear();
      });
      return;
    }
    setState(() {
      _busy = false;
      _error = (l) => l.lockWrongPassword;
    });
    _focus.requestFocus();
    _password.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _password.text.length,
    );
    if (!AppMotion.reduced(context)) _shake.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    final name = biometricName(context.l10n, theme.platform);
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: !widget.embedded),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.lock_outline, size: 40, color: c.primary),
                const SizedBox(height: 16),
                Text(
                  widget.title.isEmpty
                      ? context.l10n.commonUntitled
                      : widget.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  context.l10n.lockLockedNote,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: c.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                AnimatedBuilder(
                  animation: _shake,
                  builder: (context, child) => Transform.translate(
                    offset: Offset(
                      math.sin(_shake.value * math.pi * 6) *
                          10 *
                          (1 - _shake.value),
                      0,
                    ),
                    child: child,
                  ),
                  child: TextField(
                    controller: _password,
                    focusNode: _focus,
                    autofocus: true,
                    obscureText: true,
                    textInputAction: TextInputAction.go,
                    decoration: InputDecoration(
                      labelText: context.l10n.lockPassword,
                      errorText: _error?.call(context.l10n),
                      errorMaxLines: 2,
                      suffixIcon: _busy
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : IconButton(
                              tooltip: context.l10n.lockUnlock,
                              icon: const Icon(Icons.arrow_forward),
                              onPressed: _submit,
                            ),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                if (_hint != null) ...[
                  const SizedBox(height: 8),
                  if (_showHint)
                    Text(
                      context.l10n.lockHint(_hint!),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: c.onSurfaceVariant,
                      ),
                    )
                  else
                    TextButton(
                      onPressed: () => setState(() => _showHint = true),
                      child: Text(context.l10n.lockShowHint),
                    ),
                ],
                if (_biometrics) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => _tryBiometrics(),
                    icon: Icon(
                      theme.platform == TargetPlatform.android
                          ? Icons.fingerprint
                          : Icons.lock_open_outlined,
                    ),
                    label: Text(context.l10n.lockUseBiometric(name)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
