// Merges the per-area ARB parts in lib/l10n/parts/ into the app's ARB
// files, checking them first. Pure (no Flutter), so the test suite can run
// the same checks: test/l10n/arb_parts_test.dart.
//
// A part is a pair `<area>_en.arb` (the template: values plus `@key`
// metadata) and `<area>_<lang>.arb` for every other language. Every key in
// a part starts with the part's area name (`library` → `libraryImportPdf`),
// so parts written at the same time can never collide.
import 'dart:convert';
import 'dart:io';

/// The languages the app ships, template first.
const arbLanguages = ['en', 'de'];

class ArbProblem {
  ArbProblem(this.file, this.message);
  final String file;
  final String message;
  @override
  String toString() => '$file: $message';
}

class MergedArbs {
  MergedArbs(this.byLanguage, this.problems);

  /// language → merged ARB (keys sorted, `@@locale` first).
  final Map<String, Map<String, Object?>> byLanguage;
  final List<ArbProblem> problems;
}

final _part = RegExp(r'^([a-z][A-Za-z0-9]*)_([a-z]{2}(?:_[A-Z]{2})?)\.arb$');

/// Placeholder names used in an ICU message (`{name}`, `{count, plural, …}`),
/// ignoring the literal text inside plural/select branches.
Set<String> placeholdersOf(String message) {
  final names = <String>{};
  // What each open brace started: an argument (`{name…`) or a branch body
  // of a plural/select argument (`one{…}`).
  final open = <bool>[]; // true = argument
  for (var i = 0; i < message.length; i++) {
    final c = message[i];
    if (c == "'" && (open.isEmpty || !open.last)) {
      // ICU quoting in text: '…' is literal.
      final end = message.indexOf("'", i + 1);
      if (end > i) i = end;
      continue;
    }
    if (c == '{') {
      if (open.isNotEmpty && open.last) {
        open.add(false);
      } else {
        open.add(true);
        final m = RegExp(r'\{\s*([A-Za-z_][A-Za-z0-9_]*)')
            .matchAsPrefix(message, i);
        if (m != null) names.add(m.group(1)!);
      }
    } else if (c == '}' && open.isNotEmpty) {
      open.removeLast();
    }
  }
  return names;
}

/// Reads every part in [partsDir] and merges them. [problems] is empty
/// when the parts are consistent.
MergedArbs mergeArbParts(Directory partsDir) {
  final problems = <ArbProblem>[];
  // language → area → contents
  final parts = <String, Map<String, Map<String, Object?>>>{};
  final files = partsDir.listSync().whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in files) {
    final name = f.uri.pathSegments.last;
    if (!name.endsWith('.arb')) continue;
    final m = _part.firstMatch(name);
    if (m == null) {
      problems.add(ArbProblem(name, 'name must be <area>_<lang>.arb'));
      continue;
    }
    final area = m.group(1)!, lang = m.group(2)!;
    if (!arbLanguages.contains(lang)) {
      problems.add(ArbProblem(name, 'unknown language "$lang"'));
      continue;
    }
    Object? json;
    try {
      json = jsonDecode(f.readAsStringSync());
    } on FormatException catch (e) {
      problems.add(ArbProblem(name, 'invalid JSON: ${e.message}'));
      continue;
    }
    if (json is! Map<String, Object?>) {
      problems.add(ArbProblem(name, 'not a JSON object'));
      continue;
    }
    parts.putIfAbsent(lang, () => {})[area] = json;
  }

  final template = parts['en'] ?? {};
  final merged = <String, Map<String, Object?>>{};
  for (final lang in arbLanguages) {
    final out = <String, Object?>{};
    final langParts = parts[lang] ?? {};
    for (final area in {...template.keys, ...langParts.keys}.toList()..sort()) {
      final file = '${area}_$lang.arb';
      final base = template[area];
      final part = langParts[area];
      if (base == null) {
        problems.add(ArbProblem(file, 'has no ${area}_en.arb'));
        continue;
      }
      if (part == null) {
        problems.add(ArbProblem(file, 'missing'));
        continue;
      }
      for (final entry in part.entries) {
        final key = entry.key;
        if (key.startsWith('@@')) continue;
        final id = key.startsWith('@') ? key.substring(1) : key;
        if (!id.startsWith(area)) {
          problems.add(ArbProblem(file, '"$id" must start with "$area"'));
        }
        if (key.startsWith('@')) {
          if (lang == 'en') out[key] = entry.value;
          continue;
        }
        if (entry.value is! String) {
          problems.add(ArbProblem(file, '"$key" is not a string'));
          continue;
        }
        if (out.containsKey(key)) {
          problems.add(ArbProblem(file, '"$key" is defined twice'));
        }
        if (lang != 'en') {
          final en = base[key];
          if (en is! String) {
            problems.add(ArbProblem(file, '"$key" is not in ${area}_en.arb'));
          } else {
            final want = placeholdersOf(en),
                got = placeholdersOf(entry.value as String);
            if (want.length != got.length || !want.containsAll(got)) {
              problems.add(
                ArbProblem(file, '"$key" placeholders $got, expected $want'),
              );
            }
          }
        }
        out[key] = entry.value;
      }
      if (lang != 'en') {
        for (final key in base.keys) {
          if (key.startsWith('@')) continue;
          if (!part.containsKey(key)) {
            problems.add(ArbProblem(file, '"$key" has no translation'));
          }
        }
      }
    }
    final sorted = <String, Object?>{'@@locale': lang};
    final keys = out.keys.where((k) => !k.startsWith('@')).toList()..sort();
    for (final k in keys) {
      sorted[k] = out[k];
      if (out.containsKey('@$k')) sorted['@$k'] = out['@$k'];
    }
    merged[lang] = sorted;
  }
  return MergedArbs(merged, problems);
}

String encodeArb(Map<String, Object?> arb) =>
    '${const JsonEncoder.withIndent('  ').convert(arb)}\n';
