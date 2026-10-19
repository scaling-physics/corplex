import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/widgets.dart';

import 'generated/app_localizations.dart';

export 'generated/app_localizations.dart';

/// The app's strings: `context.l10n.commonCancel`.
///
/// Falls back to English where no `AppLocalizations` is above [context]
/// (a test's bare `MaterialApp`, an overlay built outside the app), so a
/// string lookup can never throw. Always use this, never
/// `AppLocalizations.of`.
extension L10nContext on BuildContext {
  AppLocalizations get l10n =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ??
      lookupAppLocalizations(const Locale('en'));
}

/// The strings for the device's language, for the few places that have no
/// [BuildContext] (a notification title, a native menu). Prefer
/// [L10nContext.l10n] everywhere else: it follows the app's locale.
AppLocalizations deviceL10n() {
  for (final locale in PlatformDispatcher.instance.locales) {
    if (AppLocalizations.delegate.isSupported(Locale(locale.languageCode))) {
      return lookupAppLocalizations(Locale(locale.languageCode));
    }
  }
  return lookupAppLocalizations(const Locale('en'));
}
