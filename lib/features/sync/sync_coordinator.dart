import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_service.dart';
import 'sync_service.dart';

/// Invisible widget that starts sync when a user is signed in and stops it
/// when they sign out. Renders [child] untouched — no UI of its own.
class SyncCoordinator extends ConsumerStatefulWidget {
  const SyncCoordinator({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SyncCoordinator> createState() => _SyncCoordinatorState();
}

class _SyncCoordinatorState extends ConsumerState<SyncCoordinator> {
  @override
  void initState() {
    super.initState();
    ref.listenManual(authStateProvider, (_, next) {
      final sync = ref.read(syncServiceProvider);
      final user = next.value;
      if (user == null) {
        sync.stop();
      } else {
        sync.start(userId: user.id);
      }
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
