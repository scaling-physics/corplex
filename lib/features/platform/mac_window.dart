import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import '../settings/appearance_settings.dart';

export '../../theme/app_theme.dart' show isDesktopPlatform;

/// Whether this context is on a desktop platform ([isDesktopPlatform]).
/// Decided by the theme's platform, so a widget test can switch it with
/// `debugDefaultTargetPlatformOverride`.
bool isDesktop(BuildContext context) =>
    isDesktopPlatform(Theme.of(context).platform);

bool isMac(BuildContext context) =>
    Theme.of(context).platform == TargetPlatform.macOS;

/// Height of the transparent macOS title bar that the window's content runs
/// under. Every column's top keeps this much free of controls: AppKit takes
/// the clicks there (window drag, double-click to zoom), and the traffic
/// lights sit in it at the top left.
const macTitleBarHeight = 28.0;

/// How far the traffic lights reach in from the left edge of the window.
const macTrafficLightsWidth = 78.0;

/// The widest a Mac pane's text measure gets. Panes fill their width like
/// Notes with small margins, but on an ultrawide display (a 38" 3840×1600
/// monitor gives a note pane over 3,000 pt) a full-width line would be
/// unreadable, so beyond this the content centres at this width.
const macMaxMeasure = 1600.0;

/// Side padding for a Mac pane [available] points wide: 24 pt, 40 pt from
/// 1400 pt, and on ultrawide panes whatever centres [macMaxMeasure].
double macPanePadding(double available) {
  final base = available >= 1400 ? 40.0 : 24.0;
  final centred = (available - macMaxMeasure) / 2;
  return centred > base ? centred : base;
}

/// The commands the macOS menu bar sends (`MainFlutterWindow.swift`).
/// Each goes first to the focused widget's nearest [MenuCommandHandler]
/// that handles it (like AppKit's responder chain), and only then, if none
/// does, to `MacWindow.menuCommands` (the home shell's app-level handling).
/// A menu shortcut Flutter already handles (a focused editor's ⌘B) never
/// reaches the menu at all: the Mac embedder offers key equivalents to
/// Flutter first and passes only unhandled ones on to the menu bar.
enum MenuCommand {
  // File
  newNote,
  importPdf,
  importReferences,
  backup,
  exportMarkdown,
  trash,
  moveToTrash,
  lockNote,
  lockAllNotes,
  // Edit → Find
  find,
  findNext,
  findPrevious,
  // Format
  bold,
  italic,
  underline,
  strikethrough,
  title,
  heading,
  subheading,
  body,
  bulletList,
  numberedList,
  blockQuote,
  linkNote,
  citePaper,
  // View
  showNotes,
  showLibrary,
  search,
  toggleSidebar,
  zoomIn,
  zoomOut,
  actualSize,
  interfaceLarger,
  interfaceSmaller,
  interfaceDefault,
  // Go
  back,
  // App / Help
  settings,
  keyboardShortcuts,
}

/// Handles menu-bar [commands] while keyboard focus is inside [child].
/// Map a command to null to pass it on up (e.g. Find while no document is
/// open). Nested handlers: the one nearest the focus wins.
class MenuCommandHandler extends StatelessWidget {
  const MenuCommandHandler({
    super.key,
    required this.commands,
    required this.child,
  });

  final Map<MenuCommand, VoidCallback?> commands;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// Offers [command] to the [MenuCommandHandler]s above [from] (default: the
/// primary focus), nearest first. True if one handled it.
bool dispatchMenuCommand(MenuCommand command, {BuildContext? from}) {
  final context = from ?? FocusManager.instance.primaryFocus?.context;
  if (context == null || !context.mounted) return false;
  VoidCallback? handler;
  bool visit(Element element) {
    final widget = element.widget;
    if (widget is MenuCommandHandler) handler = widget.commands[command];
    return handler == null;
  }

  if (visit(context as Element)) context.visitAncestorElements(visit);
  handler?.call();
  return handler != null;
}

/// The native window: menu commands in, window drag/zoom out, and whether
/// it's full screen (where the title bar strip goes away).
abstract class MacWindow {
  Stream<MenuCommand> get menuCommands;
  ValueListenable<bool> get fullScreen;
  Future<void> startDrag();
  Future<void> zoom();
}

/// The default: no native window (tests, iOS, Android). Never make this
/// real — `main()` installs [ChannelMacWindow] on macOS.
class InertMacWindow implements MacWindow {
  InertMacWindow();

  final _fullScreen = ValueNotifier(false);

  @override
  Stream<MenuCommand> get menuCommands => const Stream.empty();
  @override
  ValueListenable<bool> get fullScreen => _fullScreen;
  @override
  Future<void> startDrag() async {}
  @override
  Future<void> zoom() async {}
}

class ChannelMacWindow implements MacWindow {
  ChannelMacWindow() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'menu':
          final command = MenuCommand.values.asNameMap()[call.arguments];
          if (command != null && !dispatchMenuCommand(command)) {
            _commands.add(command);
          }
        case 'fullScreen':
          _fullScreen.value = call.arguments == true;
      }
      return null;
    });
  }

  static const _channel = MethodChannel('corplex/window');
  final _commands = StreamController<MenuCommand>.broadcast();
  final _fullScreen = ValueNotifier(false);

  @override
  Stream<MenuCommand> get menuCommands => _commands.stream;
  @override
  ValueListenable<bool> get fullScreen => _fullScreen;
  @override
  Future<void> startDrag() => _channel.invokeMethod('startDrag');
  @override
  Future<void> zoom() => _channel.invokeMethod('zoom');
}

final macWindowProvider = Provider<MacWindow>((ref) => InertMacWindow());

/// Menu bar commands no focused [MenuCommandHandler] took, for app-level
/// handling (the home shell).
final menuCommandsProvider = StreamProvider<MenuCommand>(
  (ref) => ref.watch(macWindowProvider).menuCommands,
);

/// Whether the window is full screen (no title bar strip then).
final macFullScreenProvider = Provider<bool>((ref) {
  final fullScreen = ref.watch(macWindowProvider).fullScreen;
  void changed() => ref.invalidateSelf();
  fullScreen.addListener(changed);
  ref.onDispose(() => fullScreen.removeListener(changed));
  return fullScreen.value;
});

/// [macTitleBarHeight] on macOS outside full screen, else 0. Most code
/// never needs this: [MacWindowFrame] already adds it to the top of
/// `MediaQuery.padding`, so AppBars and SafeAreas leave room by themselves.
double macTitleBarInset(BuildContext context, WidgetRef ref) =>
    isMac(context) && !ref.watch(macFullScreenProvider) ? macTitleBarHeight : 0;

/// Wraps the whole app (`MaterialApp.builder`). On macOS the window's
/// content runs under a transparent title bar, so this treats the title
/// bar like a phone's status bar: its height joins the top of
/// `MediaQuery.padding`/`viewPadding`, which every AppBar, SafeArea and
/// sheet already respects — a page's header colour runs up behind the
/// traffic lights and nothing sits under them. A transparent strip over
/// that band drags the window and zooms on double-click, in case AppKit
/// leaves those clicks to Flutter.
///
/// On desktop it also applies the Interface Size
/// (`AppearanceSettings.interfaceScale`): the app lays out in a window
/// 1/scale the size and is drawn scaled up, so everything — text, icons,
/// hit targets — grows together and stays sharp (it's a transform, not a
/// bitmap stretch). MediaQuery reports the scaled size and a matching
/// devicePixelRatio, so images and PDF pages render at full resolution.
/// Elsewhere it returns [child] untouched.
class MacWindowFrame extends ConsumerWidget {
  const MacWindowFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inset = macTitleBarInset(context, ref);
    final scale = isDesktop(context)
        ? ref.watch(appearanceSettingsProvider.select((s) => s.interfaceScale))
        : 1.0;
    if (inset == 0 && scale == 1.0) return child;
    final media = MediaQuery.of(context);
    final size = media.size / scale;
    EdgeInsets scaled(EdgeInsets e) =>
        (e / scale).copyWith(top: (e.top + inset) / scale);
    Widget app = MediaQuery(
      data: media.copyWith(
        size: size,
        devicePixelRatio: media.devicePixelRatio * scale,
        padding: scaled(media.padding),
        viewPadding: scaled(media.viewPadding),
        viewInsets: media.viewInsets / scale,
      ),
      child: child,
    );
    if (scale != 1.0) {
      app = FittedBox(
        fit: BoxFit.fill,
        alignment: Alignment.topLeft,
        child: SizedBox.fromSize(size: size, child: app),
      );
    }
    if (inset == 0) return app;
    final window = ref.watch(macWindowProvider);
    return Stack(
      children: [
        Positioned.fill(child: app),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: inset,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => window.startDrag(),
            onDoubleTap: window.zoom,
          ),
        ),
      ],
    );
  }
}
