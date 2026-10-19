import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show FlutterQuillLocalizations;

import 'features/home/home_shell.dart';
import 'features/platform/mac_window.dart';
import 'features/platform/platform_coordinator.dart';
import 'features/settings/appearance_settings.dart';
import 'features/share/share_import.dart';
import 'features/sync/sync_coordinator.dart';
import 'l10n/l10n.dart';
import 'theme/app_theme.dart';

class CorplexApp extends ConsumerStatefulWidget {
  const CorplexApp({super.key});

  @override
  ConsumerState<CorplexApp> createState() => _CorplexAppState();
}

class _CorplexAppState extends ConsumerState<CorplexApp> {
  // macOS: the toolbar row only while home is the top page. Told after the
  // navigator's update (providers can't change mid-build).
  late final _toolbarObserver = MacToolbarRouteObserver(
    (homeOnTop) => scheduleMicrotask(() {
      if (!mounted) return;
      ref.read(macHomeOnTopProvider.notifier).state = homeOnTop;
      ref.read(macWindowProvider).setToolbar(homeOnTop);
    }),
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorObservers: [_toolbarObserver],
      title: 'Corplex',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(appearanceSettingsProvider).themeMode,
      themeAnimationDuration: AppMotion.long,
      themeAnimationCurve: AppMotion.standard,
      // macOS: the title bar becomes top padding (see MacWindowFrame).
      builder: (context, child) => MacWindowFrame(child: child!),
      home: const SyncCoordinator(
        child: ShareCoordinator(child: PlatformCoordinator(child: HomeShell())),
      ),
    );
  }
}
