import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../theme/app_theme.dart';
import '../capture/quick_capture.dart';
import '../settings/appearance_settings.dart';

export '../../theme/app_theme.dart' show isDesktopPlatform;

/// Whether this context is on a desktop platform ([isDesktopPlatform]).
/// Decided by the theme's platform, so a widget test can switch it with
/// `debugDefaultTargetPlatformOverride`.
bool isDesktop(BuildContext context) =>
    isDesktopPlatform(Theme.of(context).platform);

bool isMac(BuildContext context) =>
    Theme.of(context).platform == TargetPlatform.macOS;

/// Height of the slim transparent macOS title bar that pages pushed over
/// home run under (the native window reports the real height, see
/// [MacWindow.titleBand]; 28 pt before macOS 26, 32 pt after).
const macTitleBarHeight = 28.0;

/// Height of the home window's toolbar row, as in Notes: the native window
/// has an empty unified toolbar there, so the traffic lights sit in its
/// middle, and Flutter draws the row's controls (search, new note, the
/// formatting buttons) in that band — clicks there still reach Flutter.
const macToolbarHeight = 52.0;

/// How far the traffic lights reach in from the left edge of the window
/// in the toolbar row, plus a little air: a toolbar that starts at the
/// window's left edge starts its controls after this.
const macTrafficLightsWidth = 86.0;

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
  todaysNote,
  newNoteFromTemplate,
  importPdf,
  importReferences,
  backup,
  exportMarkdown,
  importMarkdown,
  trash,
  moveToTrash,
  lockNote,
  lockAllNotes,
  duplicateNote,
  printNote,
  closePane,
  // Edit → Find
  find,
  findNext,
  findPrevious,
  // Format
  bold,
  italic,
  underline,
  strikethrough,
  highlight,
  monospaced,
  title,
  heading,
  subheading,
  body,
  bulletList,
  numberedList,
  checklist,
  blockQuote,
  insertTable,
  addComment,
  linkNote,
  citePaper,
  footnote,
  openLink,
  // Quick switcher's command list only (no menu item).
  addBibliography,
  // View
  showNotes,
  showLibrary,
  showAttachments,
  search,
  toggleSidebar,
  outline,
  collapseSections,
  expandSections,
  zoomIn,
  zoomOut,
  actualSize,
  interfaceLarger,
  interfaceSmaller,
  interfaceDefault,
  // Go
  back,
  forward,
  goTo,
  previousHeading,
  nextHeading,
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

  /// Quick Note hotkey, Dock menu and Services captures.
  Stream<QuickCapture> get captures;

  /// Registers (or releases) the global Quick Note hotkey ⌃⌥N. True only
  /// when it is now registered; false when off or taken by another app.
  Future<bool> setQuickNoteHotKey(bool enabled);
  ValueListenable<bool> get fullScreen;

  /// The title bar band's height outside full screen: [macToolbarHeight]
  /// while the toolbar row shows, the slim title bar's otherwise.
  ValueListenable<double> get titleBand;

  /// Shows the toolbar row (home on top) or the slim title bar (a page
  /// pushed over home, whose own app bar sits under it).
  Future<void> setToolbar(bool visible);
  Future<void> startDrag();
  Future<void> zoom();

  /// File → Print…: shows the print panel for [pdf]. False if it couldn't.
  Future<bool> printPdf(Uint8List pdf, String title);
}

/// The default: no native window (tests, iOS, Android). Never make this
/// real — `main()` installs [ChannelMacWindow] on macOS.
class InertMacWindow implements MacWindow {
  InertMacWindow();

  final _fullScreen = ValueNotifier(false);
  final _titleBand = ValueNotifier(macToolbarHeight);

  @override
  Stream<MenuCommand> get menuCommands => const Stream.empty();
  @override
  ValueListenable<double> get titleBand => _titleBand;
  @override
  Future<void> setToolbar(bool visible) async =>
      _titleBand.value = visible ? macToolbarHeight : macTitleBarHeight;
  @override
  Stream<QuickCapture> get captures => const Stream.empty();
  @override
  Future<bool> setQuickNoteHotKey(bool enabled) async => false;
  @override
  ValueListenable<bool> get fullScreen => _fullScreen;
  @override
  Future<void> startDrag() async {}
  @override
  Future<void> zoom() async {}
  @override
  Future<bool> printPdf(Uint8List pdf, String title) async => false;
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
        case 'capture':
          final capture = quickCaptureFromMessage(call.arguments);
          if (capture == null) break;
          // Before anyone listens (a cold start through Services) keep it.
          if (_captures.hasListener) {
            _captures.add(capture);
          } else {
            _pending.add(capture);
          }
      }
      return null;
    });
    // Native holds captures until told Dart is listening.
    _channel.invokeMethod<void>('captureReady').catchError((_) {});
    _channel
        .invokeMethod<double>('titleBandHeight')
        .then((h) => _titleBand.value = h ?? _titleBand.value)
        .catchError((_) => _titleBand.value);
  }

  static const _channel = MethodChannel('corplex/window');
  final _commands = StreamController<MenuCommand>.broadcast();
  final _fullScreen = ValueNotifier(false);
  final _titleBand = ValueNotifier(macToolbarHeight);
  final _pending = <QuickCapture>[];
  late final StreamController<QuickCapture> _captures =
      StreamController<QuickCapture>.broadcast(
        onListen: () {
          final queued = List.of(_pending);
          _pending.clear();
          // After onListen returns, so the new listener receives them.
          scheduleMicrotask(() => queued.forEach(_captures.add));
        },
      );

  @override
  Stream<MenuCommand> get menuCommands => _commands.stream;
  @override
  Stream<QuickCapture> get captures => _captures.stream;
  @override
  Future<bool> setQuickNoteHotKey(bool enabled) async {
    try {
      return await _channel.invokeMethod<bool>('setQuickNoteHotKey', enabled) ??
          false;
    } catch (_) {
      return false;
    }
  }

  @override
  ValueListenable<bool> get fullScreen => _fullScreen;
  @override
  ValueListenable<double> get titleBand => _titleBand;
  @override
  Future<void> setToolbar(bool visible) async {
    try {
      final h = await _channel.invokeMethod<double>('setToolbar', visible);
      if (h != null) _titleBand.value = h;
    } catch (_) {}
  }

  @override
  Future<void> startDrag() => _channel.invokeMethod('startDrag');
  @override
  Future<void> zoom() => _channel.invokeMethod('zoom');
  @override
  Future<bool> printPdf(Uint8List pdf, String title) async =>
      await _channel.invokeMethod<bool>('printPdf', {
        'pdf': pdf,
        'title': title,
      }) ??
      false;
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

/// The title bar band's height ([MacWindow.titleBand]).
final macTitleBandProvider = Provider<double>((ref) {
  final band = ref.watch(macWindowProvider).titleBand;
  void changed() => ref.invalidateSelf();
  band.addListener(changed);
  ref.onDispose(() => band.removeListener(changed));
  return band.value;
});

/// The title bar band on macOS outside full screen, else 0. Most code
/// never needs this: [MacWindowFrame] already adds it to the top of
/// `MediaQuery.padding`, so AppBars and SafeAreas leave room by themselves.
/// The home window removes it and draws its toolbar row in the band.
double macTitleBarInset(BuildContext context, WidgetRef ref) =>
    isMac(context) && !ref.watch(macFullScreenProvider)
    ? ref.watch(macTitleBandProvider)
    : 0;

/// Whether the toolbar row shows: home is the top page (dialogs, sheets and
/// menus over it don't count). Kept by [MacToolbarRouteObserver].
final macHomeOnTopProvider = StateProvider<bool>((ref) => true);

/// Keeps the native toolbar row for the home window only: a page pushed
/// over home (the PDF viewer, a project) gets the slim title bar and its
/// own app bar below it, so its back button never sits under the traffic
/// lights. Popup routes (dialogs, sheets, menus) are ignored.
class MacToolbarRouteObserver extends NavigatorObserver {
  MacToolbarRouteObserver(this._onChanged);

  final void Function(bool homeOnTop) _onChanged;
  final _pages = <Route<dynamic>>[];
  bool? _last;

  void _update() {
    final homeOnTop = _pages.length <= 1;
    if (homeOnTop == _last) return;
    _last = homeOnTop;
    _onChanged(homeOnTop);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) _pages.add(route);
    _update();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _pages.remove(route);
    _update();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _pages.remove(route);
    _update();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _pages.indexOf(oldRoute);
    if (i >= 0) _pages.removeAt(i);
    if (newRoute is PageRoute) {
      i >= 0 ? _pages.insert(i, newRoute) : _pages.add(newRoute);
    }
    _update();
  }
}

/// Empty toolbar space on a Mac: drags the window, double-click zooms (the
/// band's clicks reach Flutter, not AppKit). Put it behind a toolbar row's
/// controls, e.g. as an AppBar's `flexibleSpace`.
class MacWindowDragArea extends ConsumerWidget {
  const MacWindowDragArea({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isMac(context)) return child ?? const SizedBox.expand();
    final window = ref.watch(macWindowProvider);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => window.startDrag(),
      onDoubleTap: window.zoom,
      child: child ?? const SizedBox.expand(),
    );
  }
}

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
    // On home the toolbar row's own empty space drags the window.
    if (inset == 0 || ref.watch(macHomeOnTopProvider)) return app;
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
