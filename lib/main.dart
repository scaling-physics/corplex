import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'features/sync/supabase_setup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final overrides = await supabaseOverrides();
  runApp(ProviderScope(overrides: overrides, child: const CorplexApp()));
}
