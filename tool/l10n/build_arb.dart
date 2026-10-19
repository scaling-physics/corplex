// Merges lib/l10n/parts/*.arb into lib/l10n/app_<lang>.arb and runs
// `flutter gen-l10n`:
//
//   dart run tool/l10n/build_arb.dart          # merge + generate
//   dart run tool/l10n/build_arb.dart --check  # fail if anything is stale
//
// Several people (or agents) may run it at once, so it takes a lock file;
// the last run always sees every part on disk.
import 'dart:io';

import 'arb_parts.dart';

Future<void> main(List<String> args) async {
  final check = args.contains('--check');
  final lock = File('.dart_tool/l10n_build.lock');
  await _acquire(lock);
  try {
    final merged = mergeArbParts(Directory('lib/l10n/parts'));
    if (merged.problems.isNotEmpty) {
      stderr.writeln('ARB parts have problems:');
      for (final p in merged.problems) {
        stderr.writeln('  $p');
      }
      exitCode = 1;
      return;
    }
    var stale = false;
    for (final MapEntry(key: lang, value: arb) in merged.byLanguage.entries) {
      final file = File('lib/l10n/app_$lang.arb');
      final text = encodeArb(arb);
      if (file.existsSync() && file.readAsStringSync() == text) continue;
      stale = true;
      if (!check) file.writeAsStringSync(text);
    }
    if (check) {
      if (stale) {
        stderr.writeln(
          'lib/l10n/app_*.arb is stale: run '
          'dart run tool/l10n/build_arb.dart',
        );
        exitCode = 1;
      }
      return;
    }
    final gen = await Process.run('flutter', ['gen-l10n'], runInShell: true);
    stdout.write(gen.stdout);
    stderr.write(gen.stderr);
    if (gen.exitCode != 0) exitCode = gen.exitCode;
  } finally {
    if (lock.existsSync()) lock.deleteSync();
  }
}

Future<void> _acquire(File lock) async {
  lock.parent.createSync(recursive: true);
  for (var i = 0; ; i++) {
    try {
      lock.createSync(exclusive: true);
      return;
    } on FileSystemException {
      // A crashed run leaves its lock behind; a minute is far longer than
      // a merge takes.
      final age = DateTime.now().difference(lock.lastModifiedSync());
      if (age > const Duration(minutes: 1)) {
        lock.deleteSync();
        continue;
      }
      if (i % 20 == 0) stderr.writeln('waiting for another l10n build…');
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }
}
