import 'dart:async';

import 'package:flutter/services.dart';

/// What the user chose for a double-tap of the Apple Pencil (2nd gen / Pro)
/// in iPadOS Settings → Apple Pencil. Corplex follows that preference
/// instead of inventing its own.
enum PencilAction { switchEraser, switchPrevious, showColorPalette, ignore }

/// Double-taps of the Pencil, delivered by a few lines of Swift
/// (`SceneDelegate.swift`) over the `corplex/pencil` channel. On other
/// platforms nothing ever arrives, so callers need no platform checks.
class PencilTaps {
  PencilTaps._() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'doubleTap') {
        _controller.add(parse(call.arguments as String?));
      }
    });
  }

  static final instance = PencilTaps._();

  static const _channel = MethodChannel('corplex/pencil');
  final _controller = StreamController<PencilAction>.broadcast();

  Stream<PencilAction> get doubleTaps => _controller.stream;

  /// For tests: behaves as if the Pencil was double-tapped.
  void debugTap(PencilAction action) => _controller.add(action);

  static PencilAction parse(String? name) => PencilAction.values.firstWhere(
    (a) => a.name == name,
    orElse: () => PencilAction.switchEraser,
  );
}
