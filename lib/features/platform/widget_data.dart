import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import '../../data/database.dart';
import '../../data/tables/papers_table.dart';
import '../../l10n/l10n.dart';
import '../library/highlights.dart' show paperPageLink;

/// Shared container the iOS widget extension reads (create it in Xcode as
/// an App Group capability on both the app and the widget targets).
const widgetAppGroupId = 'group.com.corplex.corplex';

/// Name of the Android provider class / iOS widget kind.
const widgetName = 'CorplexWidget';

/// Opened by the widget's "New note" button.
final newNoteUri = Uri.parse('corplex://new-note');

/// What the widget shows.
class WidgetPayload {
  const WidgetPayload({this.title, this.page, this.uri});

  /// Paper to continue; null when there's nothing to continue.
  final String? title;
  final int? page;

  /// Where tapping the paper line goes (`corplex://paper/<id>?page=N`).
  final String? uri;

  String get headline => title ?? '';
  String get detail => title == null || page == null
      ? ''
      : deviceL10n().platformWidgetPage(page!);

  @override
  bool operator ==(Object other) =>
      other is WidgetPayload &&
      other.title == title &&
      other.page == page &&
      other.uri == uri;

  @override
  int get hashCode => Object.hash(title, page, uri);
}

/// The paper to continue: the most recently updated one being read, else
/// the most recently updated one with a remembered page.
Paper? pickContinueReading(Iterable<Paper> papers) {
  Paper? newest(Iterable<Paper> ps) {
    Paper? best;
    for (final p in ps) {
      if (best == null || p.updatedAt.isAfter(best.updatedAt)) best = p;
    }
    return best;
  }

  return newest(
        papers.where((p) => p.readingStatus == ReadingStatus.reading),
      ) ??
      newest(papers.where((p) => p.lastPage != null));
}

/// The widget has no context, so [l10n] is the device language by default.
WidgetPayload widgetPayloadFor(Paper? paper, {AppLocalizations? l10n}) {
  if (paper == null) return const WidgetPayload();
  final page = paper.lastPage;
  return WidgetPayload(
    title: paper.title.trim().isEmpty
        ? (l10n ?? deviceL10n()).platformUntitledPaper
        : paper.title.trim(),
    page: page,
    uri: paperPageLink(paper.id, page ?? 1),
  );
}

/// Talks to the home-screen widget. A seam so tests don't need the plugin.
abstract class HomeWidgetBridge {
  Future<void> publish(WidgetPayload payload);

  /// The widget link the app was launched from, if any.
  Future<Uri?> initialLaunch();

  /// Widget taps while the app is running.
  Stream<Uri?> get clicks;
}

class PluginHomeWidgetBridge implements HomeWidgetBridge {
  bool _ready = false;

  Future<void> _init() async {
    if (_ready) return;
    _ready = true;
    // Only iOS has app groups; the Android widget reads its own prefs.
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await HomeWidget.setAppGroupId(widgetAppGroupId);
    }
  }

  @override
  Future<void> publish(WidgetPayload payload) async {
    try {
      await _init();
      await HomeWidget.saveWidgetData<String>('title', payload.title);
      await HomeWidget.saveWidgetData<String>('detail', payload.detail);
      await HomeWidget.saveWidgetData<String>('uri', payload.uri);
      await HomeWidget.updateWidget(
        qualifiedAndroidName: 'com.corplex.corplex.$widgetName',
        iOSName: widgetName,
      );
    } catch (_) {
      // No widget support here; the app doesn't depend on it.
    }
  }

  @override
  Future<Uri?> initialLaunch() async {
    try {
      return await HomeWidget.initiallyLaunchedFromHomeWidget();
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<Uri?> get clicks {
    try {
      return HomeWidget.widgetClicked;
    } catch (_) {
      return const Stream.empty();
    }
  }
}

/// Does nothing; the default so tests (where the plugin's channels have no
/// implementation) need no overrides. `main()` installs the real one.
class NoHomeWidgetBridge implements HomeWidgetBridge {
  @override
  Future<void> publish(WidgetPayload payload) async {}
  @override
  Future<Uri?> initialLaunch() async => null;
  @override
  Stream<Uri?> get clicks => const Stream.empty();
}

final homeWidgetBridgeProvider = Provider<HomeWidgetBridge>(
  (ref) => NoHomeWidgetBridge(),
);

/// How long to wait after the last paper change before rewriting the
/// widget (overridable in tests).
final widgetDebounceProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 2),
);
