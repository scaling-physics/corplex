import 'package:flutter/services.dart';

/// The app's few haptic cues, in one place so they stay consistent and
/// sparse: a tick confirms something the hand just did, never decorates.
class AppHaptics {
  const AppHaptics._();

  /// Something was made or set: a highlight, a rating, a timestamp, a
  /// snapshot.
  static void confirm() => HapticFeedback.lightImpact();

  /// A drag passed the point where letting go will act (swipe to trash).
  static void threshold() => HapticFeedback.mediumImpact();

  /// A small change of choice: a tool switch, a status chip.
  static void selection() => HapticFeedback.selectionClick();
}
