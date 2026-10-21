import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'features/ocr/ocr_engine.dart';
import 'features/ink/handwriting.dart';
import 'features/audio/audio_playback.dart';
import 'features/lock/biometric_store.dart';
import 'features/lock/note_lock_service.dart';
import 'features/platform/mac_window.dart';
import 'features/platform/quick_action_source.dart';
import 'features/platform/widget_data.dart';
import 'features/read_aloud/speaker.dart';
import 'features/settings/appearance_settings.dart';
import 'features/share/share_import.dart';
import 'features/spell/spell_checker.dart';
import 'features/reminders/reminder_channel.dart';
import 'features/spotlight/spotlight_channel.dart';
import 'features/sync/supabase_setup.dart';
import 'features/sync/transfer_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioEngine.initBackground();
  final transfer = await TransferSettings.load();
  final appearance = await AppearanceSettings.load();
  final overrides = await supabaseOverrides(transfer);
  final mac = defaultTargetPlatform == TargetPlatform.macOS;
  runApp(
    ProviderScope(
      overrides: [
        transferSettingsProvider.overrideWith((ref) => transfer),
        appearanceSettingsProvider.overrideWith((ref) => appearance),
        // macOS has no share sheet, app-icon shortcuts or home-screen
        // widget plugins; it has a window with a menu bar instead.
        if (mac) ...[
          macWindowProvider.overrideWithValue(ChannelMacWindow()),
          spotlightChannelProvider.overrideWithValue(ChannelSpotlight()),
          shareIntentSourceProvider.overrideWithValue(
            const NoShareIntentSource(),
          ),
        ] else ...[
          quickActionSourceProvider.overrideWithValue(
            PluginQuickActionSource(),
          ),
          homeWidgetBridgeProvider.overrideWithValue(PluginHomeWidgetBridge()),
        ],
        // Local notifications for dates written in notes.
        reminderChannelProvider.overrideWithValue(ChannelReminders()),
        biometricKeyStoreProvider.overrideWithValue(PluginBiometricKeyStore()),
        speakerProvider.overrideWithValue(ChannelSpeaker()),
        // Handwriting in drawings is read with the on-device OCR.
        inkOcrEngineProvider.overrideWith(
          (ref) => ref.watch(ocrEngineProvider),
        ),
        // macOS and iOS have a system checker; Android keeps the inert one.
        if (mac || defaultTargetPlatform == TargetPlatform.iOS)
          spellCheckerProvider.overrideWithValue(ChannelSpellChecker()),
        ...overrides,
      ],
      child: const CorplexApp(),
    ),
  );
}
