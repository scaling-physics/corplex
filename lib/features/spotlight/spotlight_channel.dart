import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One thing handed to Spotlight. [id] is the `NavTarget.key` of the place
/// (`note:ID`), so a result can be turned back into a place.
class SpotlightItem {
  const SpotlightItem({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.text = '',
    this.keywords = const [],
  });

  final String id;
  final String title;

  /// The quiet line under the title in Spotlight.
  final String subtitle;

  /// What else the item is found by (a snippet, an abstract).
  final String text;
  final List<String> keywords;

  Map<String, Object> toMessage() => {
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'text': text,
    'keywords': keywords,
  };
}

/// The system index (CoreSpotlight on macOS). Behind a seam so the indexer
/// can be tested, and so tests and other platforms never touch a channel.
abstract class SpotlightChannel {
  /// False for the inert default: nothing to index into.
  bool get available;

  /// Adds or replaces [items] by id.
  Future<void> index(List<SpotlightItem> items);
  Future<void> remove(List<String> ids);
  Future<void> clear();

  /// Unique ids of results the user opened in Spotlight, delivered once the
  /// app listens (a launch from a result is held until then).
  Stream<String> get opens;
}

/// The default. Never make this real: `main()` installs
/// [ChannelSpotlight] on macOS only.
class InertSpotlight implements SpotlightChannel {
  const InertSpotlight();

  @override
  bool get available => false;
  @override
  Future<void> index(List<SpotlightItem> items) async {}
  @override
  Future<void> remove(List<String> ids) async {}
  @override
  Future<void> clear() async {}
  @override
  Stream<String> get opens => const Stream.empty();
}

/// `corplex/spotlight`: `index` / `remove` / `clear` out; `open` in, after
/// Dart says `ready` (native queues a launch from a result until then, like
/// Services captures).
class ChannelSpotlight implements SpotlightChannel {
  ChannelSpotlight() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'open' && call.arguments is String) {
        final id = call.arguments as String;
        if (_opens.hasListener) {
          _opens.add(id);
        } else {
          _pending.add(id);
        }
      }
      return null;
    });
    _channel.invokeMethod<void>('ready').catchError((_) {});
  }

  static const _channel = MethodChannel('corplex/spotlight');
  final _pending = <String>[];
  late final StreamController<String> _opens =
      StreamController<String>.broadcast(
        onListen: () {
          final queued = List.of(_pending);
          _pending.clear();
          scheduleMicrotask(() => queued.forEach(_opens.add));
        },
      );

  @override
  bool get available => true;

  @override
  Future<void> index(List<SpotlightItem> items) => _channel.invokeMethod<void>(
    'index',
    [for (final item in items) item.toMessage()],
  );

  @override
  Future<void> remove(List<String> ids) =>
      _channel.invokeMethod<void>('remove', ids);

  @override
  Future<void> clear() => _channel.invokeMethod<void>('clear');

  @override
  Stream<String> get opens => _opens.stream;
}

final spotlightChannelProvider = Provider<SpotlightChannel>(
  (ref) => const InertSpotlight(),
);
