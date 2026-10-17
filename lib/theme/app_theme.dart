import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

/// Desktop (pointer-first) platforms: compact density, hover, right-click
/// menus, a menu bar — and no swipe gestures for a mouse.
bool isDesktopPlatform(TargetPlatform platform) => switch (platform) {
  TargetPlatform.macOS ||
  TargetPlatform.windows ||
  TargetPlatform.linux => true,
  _ => false,
};

/// Corplex's visual language: calm, paper-like surfaces with sage green as
/// the one accent, so the reading and writing content stays the loudest
/// thing on screen. Every color used by the app comes from these two
/// schemes — widgets read `Theme.of(context).colorScheme`, never raw hex.
class AppTheme {
  const AppTheme._();

  static const _light = ColorScheme(
    brightness: Brightness.light,
    // Sage, deep enough to read as text on the paper background.
    primary: Color(0xFF55715A),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFD9E5D4),
    onPrimaryContainer: Color(0xFF1D3222),
    // Muted grey-green for secondary accents (selected chips, icons).
    secondary: Color(0xFF687568),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFE2E8DE),
    onSecondaryContainer: Color(0xFF232B24),
    // A soft clay, used sparingly for warmth (e.g. tag labels).
    tertiary: Color(0xFF94705C),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFF2E2D7),
    onTertiaryContainer: Color(0xFF3A2519),
    error: Color(0xFFA8514A),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFF6DAD6),
    onErrorContainer: Color(0xFF41110D),
    // Warm off-white "paper" and gently stepped containers.
    surface: Color(0xFFF7F6F1),
    onSurface: Color(0xFF282C28),
    onSurfaceVariant: Color(0xFF5E655E),
    surfaceDim: Color(0xFFE2E1DA),
    surfaceBright: Color(0xFFFCFBF7),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF1F1EA),
    surfaceContainer: Color(0xFFECECE4),
    surfaceContainerHigh: Color(0xFFE6E6DE),
    surfaceContainerHighest: Color(0xFFE0E0D8),
    outline: Color(0xFF9DA59C),
    outlineVariant: Color(0xFFD8DCD3),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF2E332F),
    onInverseSurface: Color(0xFFEFF1EB),
    inversePrimary: Color(0xFFA9C4A5),
    surfaceTint: Colors.transparent,
  );

  static const _dark = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFA9C4A5),
    onPrimary: Color(0xFF1B3120),
    primaryContainer: Color(0xFF384C3B),
    onPrimaryContainer: Color(0xFFD4E5CF),
    secondary: Color(0xFFB4C0B2),
    onSecondary: Color(0xFF212922),
    secondaryContainer: Color(0xFF353E37),
    onSecondaryContainer: Color(0xFFD6DFD3),
    tertiary: Color(0xFFD8B6A2),
    onTertiary: Color(0xFF3A2519),
    tertiaryContainer: Color(0xFF55402F),
    onTertiaryContainer: Color(0xFFF2E2D7),
    error: Color(0xFFE8A79F),
    onError: Color(0xFF41110D),
    errorContainer: Color(0xFF6B2B25),
    onErrorContainer: Color(0xFFF6DAD6),
    surface: Color(0xFF161917),
    onSurface: Color(0xFFE2E5DF),
    onSurfaceVariant: Color(0xFFB3BAB1),
    surfaceDim: Color(0xFF121412),
    surfaceBright: Color(0xFF363B37),
    surfaceContainerLowest: Color(0xFF111311),
    surfaceContainerLow: Color(0xFF1C201D),
    surfaceContainer: Color(0xFF212522),
    surfaceContainerHigh: Color(0xFF282C29),
    surfaceContainerHighest: Color(0xFF303531),
    outline: Color(0xFF7B8479),
    outlineVariant: Color(0xFF3A403B),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFE2E5DF),
    onInverseSurface: Color(0xFF2E332F),
    inversePrimary: Color(0xFF55715A),
    surfaceTint: Colors.transparent,
  );

  static ThemeData get light => _build(_light, desktop: _desktop);

  static ThemeData get dark => _build(_dark, desktop: _desktop);

  /// Pointer-first platforms (macOS above all) get a denser variant of the
  /// same theme: Mac-sized controls, radii and headings, and no touch
  /// affordances like sheet drag handles. Read at build time, so a test can
  /// switch it with `debugDefaultTargetPlatformOverride`.
  static bool get _desktop => isDesktopPlatform(defaultTargetPlatform);

  static ThemeData _build(ColorScheme c, {required bool desktop}) {
    final base = ThemeData(colorScheme: c, useMaterial3: true);
    final text = _textTheme(base.textTheme, c, desktop: desktop);
    final radius = Radius.circular(desktop ? 12 : 16);

    return base.copyWith(
      scaffoldBackgroundColor: c.surface,
      textTheme: text,
      splashFactory: InkRipple.splashFactory,
      visualDensity: desktop ? VisualDensity.compact : VisualDensity.standard,
      materialTapTargetSize: desktop
          ? MaterialTapTargetSize.shrinkWrap
          : MaterialTapTargetSize.padded,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          // Android: Material 3's soft fade + slide, with predictive back.
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          // iOS: native slide with edge-swipe to go back.
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          // A Mac has no edge swipe-back, and a sliding page across a
          // big window is a lot of motion: a short fade instead.
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.surface,
        foregroundColor: c.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: desktop ? 52 : null,
        titleTextStyle: desktop ? text.titleMedium : text.titleLarge,
        iconTheme: IconThemeData(color: c.onSurfaceVariant),
        actionsIconTheme: IconThemeData(color: c.onSurfaceVariant),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        indicatorColor: c.primaryContainer,
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? c.onPrimaryContainer
                : c.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected)
                ? c.onSurface
                : c.onSurfaceVariant,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: c.surfaceContainerLow,
        indicatorColor: c.primaryContainer,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
        elevation: 1,
        focusElevation: 2,
        hoverElevation: 2,
        highlightElevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(radius)),
        extendedTextStyle: text.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
      cardTheme: CardThemeData(
        // Cards sit slightly *above* the page: white on paper in light
        // mode, a lifted grey-green in dark mode.
        color: c.brightness == Brightness.light
            ? c.surfaceContainerLowest
            : c.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(radius),
          side: BorderSide(color: c.outlineVariant.withValues(alpha: 0.7)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.onSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(desktop ? 8 : 12)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surface,
        selectedColor: c.primaryContainer,
        secondarySelectedColor: c.primaryContainer,
        disabledColor: c.surfaceContainer,
        side: WidgetStateBorderSide.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.selected)
                ? Colors.transparent
                : c.outlineVariant,
          ),
        ),
        shape: const StadiumBorder(),
        showCheckmark: false,
        labelStyle: text.labelLarge?.copyWith(color: c.onSurface),
        secondaryLabelStyle: text.labelLarge?.copyWith(
          color: c.onPrimaryContainer,
        ),
        iconTheme: IconThemeData(color: c.onSurfaceVariant, size: 18),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      ),
      searchBarTheme: SearchBarThemeData(
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(c.surfaceContainerHigh),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16),
        ),
        hintStyle: WidgetStatePropertyAll(
          text.bodyLarge?.copyWith(color: c.onSurfaceVariant),
        ),
        constraints: BoxConstraints(minHeight: desktop ? 36 : 48),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: c.surfaceContainerHigh,
        hintStyle: TextStyle(color: c.onSurfaceVariant),
        contentPadding: EdgeInsets.symmetric(
          horizontal: desktop ? 12 : 16,
          vertical: desktop ? 10 : 14,
        ),
        // Underline-style (Material's filled field), not outline: an
        // outline border floats a field's label onto its top edge, half
        // outside the box.
        border: const UnderlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide.none,
        ),
        enabledBorder: const UnderlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide.none,
        ),
        focusedBorder: UnderlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: c.primary, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: Size(64, desktop ? 34 : 48),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: c.primaryContainer,
          selectedForegroundColor: c.onPrimaryContainer,
          side: BorderSide(color: c.outlineVariant),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surfaceContainerLow,
        modalBackgroundColor: c.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        // A drag handle is a touch affordance; on a Mac the sheet closes
        // with a click outside or Escape.
        showDragHandle: !desktop,
        dragHandleColor: c.outline.withValues(alpha: 0.5),
        constraints: desktop ? const BoxConstraints(maxWidth: 560) : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(desktop ? 16 : 28),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(desktop ? 14 : 24)),
        ),
        titleTextStyle: text.titleLarge,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(color: c.onInverseSurface),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: c.outlineVariant.withValues(alpha: 0.6),
        thickness: 1,
        space: 1,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: c.inverseSurface.withValues(alpha: 0.92),
          borderRadius: const BorderRadius.all(Radius.circular(8)),
        ),
        textStyle: text.bodySmall?.copyWith(color: c.onInverseSurface),
        waitDuration: const Duration(milliseconds: 400),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStatePropertyAll(desktop ? 7 : 4),
        radius: const Radius.circular(8),
        thumbColor: WidgetStatePropertyAll(
          c.onSurfaceVariant.withValues(alpha: 0.35),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.primary),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.primary,
        selectionColor: c.primary.withValues(alpha: 0.25),
        selectionHandleColor: c.primary,
      ),
    );
  }

  /// System fonts (nothing to download, so it works offline), tuned for
  /// long reading: slightly tighter headings, airier body text. On desktop
  /// the display, headline and title sizes step down (a Mac window is read
  /// from further away than a phone, but its UI type is smaller), while
  /// body text stays a comfortable reading size.
  static TextTheme _textTheme(
    TextTheme base,
    ColorScheme c, {
    required bool desktop,
  }) {
    if (desktop) base = _desktopSizes(base);
    TextStyle? heading(TextStyle? s) =>
        s?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.3);
    return base
        .copyWith(
          displaySmall: heading(base.displaySmall),
          headlineLarge: heading(base.headlineLarge),
          headlineMedium: heading(base.headlineMedium),
          headlineSmall: heading(base.headlineSmall),
          titleLarge: base.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
          titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          titleSmall: base.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: c.onSurfaceVariant,
          ),
          bodyLarge: base.bodyLarge?.copyWith(height: 1.5),
          bodyMedium: base.bodyMedium?.copyWith(height: 1.45),
        )
        .apply(bodyColor: c.onSurface, displayColor: c.onSurface);
  }

  static TextTheme _desktopSizes(TextTheme t) {
    TextStyle? size(TextStyle? s, double px) => s?.copyWith(fontSize: px);
    return t.copyWith(
      displayLarge: size(t.displayLarge, 48),
      displayMedium: size(t.displayMedium, 38),
      displaySmall: size(t.displaySmall, 30),
      headlineLarge: size(t.headlineLarge, 26),
      headlineMedium: size(t.headlineMedium, 22),
      headlineSmall: size(t.headlineSmall, 19),
      titleLarge: size(t.titleLarge, 17),
      titleMedium: size(t.titleMedium, 14),
      titleSmall: size(t.titleSmall, 13),
      bodyLarge: size(t.bodyLarge, 15),
      bodyMedium: size(t.bodyMedium, 13.5),
      bodySmall: size(t.bodySmall, 12),
      labelLarge: size(t.labelLarge, 13),
      labelMedium: size(t.labelMedium, 12),
      labelSmall: size(t.labelSmall, 11),
    );
  }
}

/// Shared motion values, so every animation in the app moves alike:
/// short, decelerating, never bouncy.
class AppMotion {
  const AppMotion._();

  static const short = Duration(milliseconds: 180);
  static const medium = Duration(milliseconds: 280);
  static const long = Duration(milliseconds: 420);

  static const enter = Easing.emphasizedDecelerate;
  static const exit = Easing.emphasizedAccelerate;
  static const standard = Easing.standard;

  /// Whether the system asks for reduced motion. Animations then jump to
  /// their end state; see [of].
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [duration], or zero when the system asks for reduced motion.
  static Duration of(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;
}
