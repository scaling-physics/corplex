import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'features/sync/supabase_setup.dart';
import 'features/sync/transfer_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final transfer = await TransferSettings.load();
  final overrides = await supabaseOverrides(transfer);
  runApp(
    ProviderScope(
      overrides: [
        transferSettingsProvider.overrideWith((ref) => transfer),
        ...overrides,
      ],
      child: const CorplexApp(),
    ),
  );
}
