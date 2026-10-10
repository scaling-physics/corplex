import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show FlutterQuillLocalizations;

import 'features/home/home_shell.dart';
import 'features/platform/platform_coordinator.dart';
import 'features/settings/appearance_settings.dart';
import 'features/share/share_import.dart';
import 'features/sync/sync_coordinator.dart';
import 'theme/app_theme.dart';

class CorplexApp extends ConsumerWidget {
  const CorplexApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Corplex',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        FlutterQuillLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(appearanceSettingsProvider).themeMode,
      themeAnimationDuration: AppMotion.long,
      themeAnimationCurve: AppMotion.standard,
      home: const SyncCoordinator(
        child: ShareCoordinator(child: PlatformCoordinator(child: HomeShell())),
      ),
    );
  }
}
