import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quick_actions/quick_actions.dart';

import '../../l10n/l10n.dart';

/// The two app shortcuts (long-press the icon).
const quickNewNote = 'new_note';
const quickImportPdf = 'import_pdf';

/// Where app-icon shortcuts come from. A seam so widget tests don't need
/// the platform plugin (which has no implementation under `flutter test`).
abstract class QuickActionSource {
  /// Registers the shortcuts and starts delivering taps to [onAction] —
  /// both the one the app was launched with and later ones.
  Future<void> start(void Function(String type) onAction);
}

class PluginQuickActionSource implements QuickActionSource {
  @override
  Future<void> start(void Function(String type) onAction) async {
    try {
      const quick = QuickActions();
      await quick.initialize(onAction);
      // No context here: the device language stands in for the app's.
      final l10n = deviceL10n();
      await quick.setShortcutItems([
        ShortcutItem(type: quickNewNote, localizedTitle: l10n.commonNewNote),
        ShortcutItem(
          type: quickImportPdf,
          localizedTitle: l10n.commonImportPdf,
        ),
      ]);
    } catch (_) {
      // No shortcuts on this platform; nothing else depends on them.
    }
  }
}

/// Does nothing; the default so tests need no overrides. `main()` installs
/// [PluginQuickActionSource].
class NoQuickActionSource implements QuickActionSource {
  @override
  Future<void> start(void Function(String type) onAction) async {}
}

final quickActionSourceProvider = Provider<QuickActionSource>(
  (ref) => NoQuickActionSource(),
);
