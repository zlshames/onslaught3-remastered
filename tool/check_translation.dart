// Checks a translation, l10n/<locale>.json, against the generated English table.
//
//   fvm dart run tool/check_translation.dart <locale>
//   fvm dart run tool/check_translation.dart <locale> --todo
//
// Run from the repo root (or pass --root <dir>). Without --todo it reports, per
// key: errors (unknown key, placeholders differ from English, empty or
// non-string value, bad document shape), missing keys, and warnings (text
// identical to English, which is sometimes right). Exits 1 on any error or
// missing key (--allow-missing tolerates missing keys while a translation is in
// progress). The last line ends with `<n> errors, <n> missing, <n> warnings`.
//
// With --todo it prints the keys the translation does not have yet, with their
// English text, as a JSON object in English-table order: the work list to
// translate and merge into the file. A locale with no file yet gets every key.
//
// English comes from assets/data/strings/en.json, so regenerate the data
// (fvm dart run tool/gen_data_from_legacy.dart) after changing l10n/en.json.
// `en` itself is the hand-written English source: it is checked for shape and
// for being regenerated (every key in the table with the same text), never for
// missing keys, since the legacy table and the data documents supply the rest.
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

final _slot = RegExp(r'\{(\w+)\}');
const _shape = {'schemaVersion', 'locale', 'strings'};

const _usage = '''
Checks a translation, l10n/<locale>.json, against the generated English table.

usage: fvm dart run tool/check_translation.dart <locale> [--root <dir>] [--todo] [--allow-missing]

  <locale>         language code, e.g. fr (the file l10n/<locale>.json)
  --root <dir>     repo root (default: current directory)
  --todo           print the untranslated keys as JSON and exit
  --allow-missing  do not fail on missing keys''';

Set<String> _slots(String text) => {for (final m in _slot.allMatches(text)) m[1]!};

String _sorted(Iterable<String> s) => '[${(s.toList()..sort()).map((e) => "'$e'").join(', ')}]';

String _typeName(Object? v) => switch (v) {
  null => 'null',
  bool() => 'bool',
  int() => 'int',
  double() => 'float',
  List() => 'list',
  Map() => 'dict',
  _ => v.runtimeType.toString(),
};

void main(List<String> args) => exitCode = run(args);

/// Runs the checker with [args]; returns the exit code.
int run(List<String> args) {
  String? locale;
  var root = '.';
  var todo = false;
  var allowMissing = false;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--todo':
        todo = true;
      case '--allow-missing':
        allowMissing = true;
      case '--root' when i + 1 < args.length:
        root = args[++i];
      case '-h' || '--help':
        print(_usage);
        return 0;
      case final a when !a.startsWith('-') && locale == null:
        locale = a;
      default:
        stderr.writeln(_usage);
        return 2;
    }
  }
  if (locale == null) {
    stderr.writeln(_usage);
    return 2;
  }

  final english =
      ((jsonDecode(File('$root/assets/data/strings/en.json').readAsStringSync()) as Map)['strings']
              as Map)
          .cast<String, String>();
  final file = File('$root/l10n/$locale.json');
  final name = '$locale.json';
  final doc = file.existsSync() ? jsonDecode(file.readAsStringSync()) : null;
  final docMap = doc is Map ? doc.cast<String, Object?>() : null;
  final rawStrings = docMap?['strings'];
  final strings = rawStrings is Map ? rawStrings.cast<String, Object?>() : <String, Object?>{};
  final isEnglish = locale == 'en';

  final missing = isEnglish
      ? <String>[]
      : [
          for (final k in english.keys)
            if (!strings.containsKey(k)) k,
        ];
  if (todo) {
    print(const JsonEncoder.withIndent('  ').convert({for (final k in missing) k: english[k]}));
    return 0;
  }

  if (docMap == null) {
    print('${file.path}: no such file (start one with --todo)');
    return 1;
  }

  final errors = <String>[];
  final warnings = <String>[];
  if (!_sameSet(docMap.keys.toSet(), _shape)) {
    errors.add('document keys ${_sorted(docMap.keys)} must be exactly ${_sorted(_shape)}');
  }
  if (docMap['schemaVersion'] != 1) {
    errors.add('schemaVersion is ${_repr(docMap['schemaVersion'])}, expected 1');
  }
  if (docMap['locale'] != locale) {
    errors.add('locale is ${_repr(docMap['locale'])} but the file is $name');
  }

  strings.forEach((key, value) {
    if (!english.containsKey(key)) {
      errors.add(
        isEnglish
            ? '$key: not in strings/en.json (run fvm dart run tool/gen_data_from_legacy.dart)'
            : '$key: no English string has this key',
      );
      return;
    }
    if (value is! String) {
      errors.add('$key: value is ${_typeName(value)}, expected a string');
      return;
    }
    if (value.trim().isEmpty) {
      errors.add(
        isEnglish ? '$key: empty' : '$key: empty (leave the key out to fall back to English)',
      );
      return;
    }
    if (isEnglish) {
      if (value != english[key]) {
        errors.add(
          '$key: differs from strings/en.json (run fvm dart run tool/gen_data_from_legacy.dart)',
        );
      }
      return;
    }
    if (!_sameSet(_slots(value), _slots(english[key]!))) {
      errors.add(
        '$key: placeholders ${_sorted(_slots(value))} differ from English ${_sorted(_slots(english[key]!))}',
      );
    }
    if (value == english[key] && RegExp('[A-Za-z]{2}').hasMatch(value.replaceAll(_slot, ''))) {
      warnings.add('$key: same as English (${_repr(value)})');
    }
  });

  if (!isEnglish &&
      strings['language.name'] != null &&
      strings['language.name'] == english['language.name']) {
    errors.add("language.name: must be the language's own name, not 'English'");
  }

  for (final e in errors) {
    print('ERROR   $e');
  }
  for (final k in missing) {
    print('MISSING $k');
  }
  for (final w in warnings) {
    print('WARN    $w');
  }
  final counts = '${errors.length} errors, ${missing.length} missing, ${warnings.length} warnings';
  if (isEnglish) {
    print(
      'en: ${strings.length} hand-written keys of ${english.length} in strings/en.json, $counts',
    );
  } else {
    final done = english.length - missing.length;
    print('$locale: $done/${english.length} keys translated, $counts');
  }
  return errors.isNotEmpty || (missing.isNotEmpty && !allowMissing) ? 1 : 0;
}

String _repr(Object? v) => v is String ? "'$v'" : (v == null ? 'None' : '$v');

bool _sameSet(Set<String> a, Set<String> b) => a.length == b.length && a.containsAll(b);
