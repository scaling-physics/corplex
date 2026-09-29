import 'dart:io';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/supabase_config.dart';
import '../../data/database_provider.dart';
import '../auth/auth_service.dart';
import '../auth/supabase_auth_service.dart';
import 'file_sync.dart';
import 'sync_engine.dart';
import 'sync_remote.dart';
import 'sync_service.dart';

/// Initializes Supabase and returns the provider overrides that swap the
/// offline stand-ins for the real auth and sync services. Returns no
/// overrides when Supabase isn't configured (or can't initialize), leaving
/// the app fully usable offline — sync is additive, never required.
Future<List<Override>> supabaseOverrides() async {
  if (!SupabaseConfig.isConfigured) return const [];
  try {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
    );
  } catch (_) {
    return const [];
  }

  final client = Supabase.instance.client;
  return [
    authServiceProvider.overrideWith((ref) => SupabaseAuthService(client.auth)),
    syncServiceProvider.overrideWith((ref) {
      final db = ref.watch(databaseProvider);
      final service = EngineSyncService(
        db,
        SyncEngine(
          db,
          SupabaseSyncRemote(client),
          files: FileSync(db, SupabaseFileRemote(client), (
            subfolder,
            fileName,
          ) async {
            final docs = await getApplicationDocumentsDirectory();
            final dir = Directory(p.join(docs.path, subfolder));
            await dir.create(recursive: true);
            return p.join(dir.path, fileName);
          }),
        ),
      );
      ref.onDispose(service.stop);
      return service;
    }),
  ];
}
