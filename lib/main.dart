import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'features/settings/appearance_settings.dart';
import 'features/sync/supabase_setup.dart';
import 'features/sync/transfer_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final transfer = await TransferSettings.load();
  final appearance = await AppearanceSettings.load();
  final overrides = await supabaseOverrides(transfer);
  runApp(
    ProviderScope(
      overrides: [
        transferSettingsProvider.overrideWith((ref) => transfer),
        appearanceSettingsProvider.overrideWith((ref) => appearance),
        ...overrides,
      ],
      child: const CorplexApp(),
    ),
  );
}
