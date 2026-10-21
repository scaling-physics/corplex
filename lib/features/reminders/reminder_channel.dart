import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One local notification to schedule. [id] is stable for a mention, so the
/// same request replaces itself.
class ReminderRequest {
  const ReminderRequest({
    required this.id,
    required this.noteId,
    required this.title,
    required this.body,
    required this.when,
  });

  final int id;
  final String noteId;
  final String title;
  final String body;
  final DateTime when;

  Map<String, Object> toMessage() => {
    'id': id,
    'noteId': noteId,
    'title': title,
    'body': body,
    'at': when.millisecondsSinceEpoch,
  };
}

/// Local notifications on this device (never a server). Behind a seam so
/// the scheduler can be tested, and so tests and other platforms never
/// touch a channel.
abstract class ReminderChannel {
  /// False for the inert default: nowhere to schedule.
  bool get available;

  /// Schedules [requests] (replacing any with the same id). The first call
  /// is what asks the system for permission, never startup.
  Future<void> schedule(List<ReminderRequest> requests, {String? channelName});
  Future<void> cancel(List<int> ids);
  Future<void> cancelAll();

  /// Note ids the user opened by tapping a notification, delivered once the
  /// app listens (a launch from one is held until then).
  Stream<String> get opens;
}

/// The default. Never make this real: `main()` installs [ChannelReminders]
/// on iOS, Android and macOS only.
class InertReminders implements ReminderChannel {
  const InertReminders();

  @override
  bool get available => false;
  @override
  Future<void> schedule(
    List<ReminderRequest> requests, {
    String? channelName,
  }) async {}
  @override
  Future<void> cancel(List<int> ids) async {}
  @override
  Future<void> cancelAll() async {}
  @override
  Stream<String> get opens => const Stream.empty();
}

/// `corplex/reminders`: `schedule` / `cancel` / `cancelAll` out; `open` (a
/// note id) in, after Dart says `ready`. Native objects are created on the
/// first call, never at registration.
class ChannelReminders implements ReminderChannel {
  ChannelReminders() {
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

  static const _channel = MethodChannel('corplex/reminders');
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
  Future<void> schedule(
    List<ReminderRequest> requests, {
    String? channelName,
  }) => _channel.invokeMethod<void>('schedule', {
    'items': [for (final r in requests) r.toMessage()],
    'channelName': ?channelName,
  });

  @override
  Future<void> cancel(List<int> ids) =>
      _channel.invokeMethod<void>('cancel', ids);

  @override
  Future<void> cancelAll() => _channel.invokeMethod<void>('cancelAll');

  @override
  Stream<String> get opens => _opens.stream;
}

final reminderChannelProvider = Provider<ReminderChannel>(
  (ref) => const InertReminders(),
);
