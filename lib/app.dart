import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show FlutterQuillLocalizations;

import 'features/home/home_shell.dart';
import 'features/share/share_import.dart';
import 'features/sync/sync_coordinator.dart';
import 'theme/app_theme.dart';

class CorplexApp extends StatelessWidget {
  const CorplexApp({super.key});

  @override
  Widget build(BuildContext context) {
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
      themeAnimationDuration: AppMotion.long,
      themeAnimationCurve: AppMotion.standard,
      home: const SyncCoordinator(child: ShareCoordinator(child: HomeShell())),
    );
  }
}
