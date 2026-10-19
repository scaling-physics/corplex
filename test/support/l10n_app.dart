import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show FlutterQuillLocalizations;
import 'package:corplex/l10n/l10n.dart';

/// Every delegate the real app registers, for tests that build their own
/// `MaterialApp`.
const appLocalizationsDelegates = <LocalizationsDelegate<Object>>[
  AppLocalizations.delegate,
  FlutterQuillLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

/// A `MaterialApp` showing [home] in [locale] (German by default), for
/// checking a screen's translated strings and that they fit.
Widget localizedApp(Widget home, {Locale locale = const Locale('de')}) =>
    MaterialApp(
      locale: locale,
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );
