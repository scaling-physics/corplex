import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Helpers for looking at the macOS layout without a Mac screen: switch the
/// test to macOS, size the window like a real one, load real fonts (the
/// test default draws every glyph as a box) and write PNGs to look at.
///
/// Screenshots are a review aid, not assertions. They're written only when
/// `MAC_SCREENSHOTS` names a folder:
///   MAC_SCREENSHOTS=/tmp/shots flutter test test/features/home/mac_layout_test.dart

/// Common Mac window sizes in points: a 13" laptop's default, a 16"
/// laptop's, a 27" display's, a 38" Dell ultrawide (3840×1600) maximised
/// at 1× and at its HiDPI "looks like 2560×1067" setting (short and wide),
/// and the window's minimum.
const macWindowSizes = {
  'laptop13': Size(1280, 800),
  'laptop16': Size(1728, 1080),
  'display27': Size(2560, 1400),
  'dell38': Size(3840, 1575),
  'dell38hidpi': Size(2560, 1042),
  'minimum': Size(720, 520),
};

/// Pass as `variant:` to run a testWidgets as macOS (Flutter resets the
/// platform override itself at the end of the body, as it must be).
final macOnly = TargetPlatformVariant.only(TargetPlatform.macOS);

/// Sizes the test window like a Mac's at [size] points (2×, like a Retina
/// screen). Use with `variant: macOnly`.
void useMacWindow(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = size * 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

bool _fontsLoaded = false;

/// Loads real fonts for the families the Mac theme asks for (SF from the
/// system when present, else the bundled Roboto) and Material icons. Call
/// once per file, e.g. in setUpAll.
Future<void> loadMacFonts() async {
  if (_fontsLoaded) return;
  _fontsLoaded = true;
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    var any = false;
    for (final p in paths) {
      final f = File(p);
      if (!f.existsSync()) continue;
      loader.addFont(f.readAsBytes().then(ByteData.sublistView));
      any = true;
    }
    if (any) await loader.load();
  }

  const sf = '/System/Library/Fonts/SFNS.ttf';
  final text = File(sf).existsSync()
      ? [sf]
      : [
          'assets/fonts/Roboto-Regular.ttf',
          'assets/fonts/Roboto-Bold.ttf',
          'assets/fonts/Roboto-Italic.ttf',
        ];
  for (final family in const [
    'CupertinoSystemText',
    'CupertinoSystemDisplay',
    '.AppleSystemUIFont',
    'Roboto',
  ]) {
    await load(family, text);
  }
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    await load('MaterialIcons', [
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ]);
  }
}

/// Writes the whole test view to `$MAC_SCREENSHOTS/<name>.png` when that
/// variable is set; otherwise does nothing. Call it from the test body,
/// not from inside `tester.runAsync` (it uses one itself).
Future<void> macScreenshot(WidgetTester tester, String name) async {
  final dir = Platform.environment['MAC_SCREENSHOTS'];
  if (dir == null || dir.isEmpty) return;
  // The view's own layer holds everything painted, dialogs included.
  final view = tester.binding.renderViews.first;
  final layer = view.debugLayer! as OffsetLayer;
  // It paints in physical pixels; the PNG comes out in points.
  final ratio = tester.view.devicePixelRatio;
  final bounds = Offset.zero & tester.view.physicalSize;
  await tester.runAsync(() async {
    final image = await layer.toImage(bounds, pixelRatio: 1 / ratio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    Directory(dir).createSync(recursive: true);
    File('$dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
