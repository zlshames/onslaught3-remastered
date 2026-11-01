import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_translation.dart' as checker;

/// `tool/check_translation.dart` (the `add-language` coverage checker) on a
/// small repo of its own: errors, missing keys, warnings, the English
/// source, the `--todo` work list and the exit codes.
void main() {
  late Directory root;

  void write(String path, Object json) {
    File('${root.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(json));
  }

  ({int code, List<String> lines}) check(List<String> args) {
    final lines = <String>[];
    final code = runZoned(
      () => checker.run([...args, '--root', root.path]),
      zoneSpecification: ZoneSpecification(print: (_, _, _, line) => lines.add(line)),
    );
    return (code: code, lines: lines);
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('check_translation');
    write('assets/data/strings/en.json', {
      'schemaVersion': 1,
      'locale': 'en',
      'strings': {
        'language.name': 'English',
        'ui.menu.play': 'Play',
        'ui.records.best': 'Best wave {wave}',
        'turret.blue.name': 'Blue Cannon',
      },
    });
    write('l10n/en.json', {
      'schemaVersion': 1,
      'locale': 'en',
      'strings': {'language.name': 'English', 'ui.menu.play': 'Play'},
    });
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('a complete translation passes, warning where it matches English', () {
    write('l10n/fr.json', {
      'schemaVersion': 1,
      'locale': 'fr',
      'strings': {
        'language.name': 'Français',
        'ui.menu.play': 'Jouer',
        'ui.records.best': 'Meilleure vague {wave}',
        'turret.blue.name': 'Blue Cannon',
      },
    });
    final r = check(['fr']);
    expect(r.code, 0);
    expect(r.lines, [
      "WARN    turret.blue.name: same as English ('Blue Cannon')",
      'fr: 4/4 keys translated, 0 errors, 0 missing, 1 warnings',
    ]);
  });

  test('errors and missing keys fail; --allow-missing tolerates only missing', () {
    write('l10n/fr.json', {
      'schemaVersion': 1,
      'locale': 'fr',
      'strings': {'language.name': 'Français', 'ui.records.best': 'Vague {vague}'},
    });
    final r = check(['fr']);
    expect(r.code, 1);
    expect(r.lines, [
      "ERROR   ui.records.best: placeholders ['vague'] differ from English ['wave']",
      'MISSING ui.menu.play',
      'MISSING turret.blue.name',
      'fr: 2/4 keys translated, 1 errors, 2 missing, 0 warnings',
    ]);
    expect(check(['fr', '--allow-missing']).code, 1, reason: 'the placeholder error remains');
    write('l10n/fr.json', {
      'schemaVersion': 1,
      'locale': 'fr',
      'strings': {'language.name': 'Français'},
    });
    expect(check(['fr', '--allow-missing']).code, 0);
  });

  test('a bad document shape, an unknown key and an English language name are errors', () {
    write('l10n/fr.json', {
      'schemaVersion': 2,
      'locale': 'de',
      'extra': true,
      'strings': {'language.name': 'English', 'ui.nope': 'x', 'ui.menu.play': ' '},
    });
    final errors = check(['fr']).lines.where((l) => l.startsWith('ERROR')).toList();
    expect(errors, [
      "ERROR   document keys ['extra', 'locale', 'schemaVersion', 'strings'] must be exactly "
          "['locale', 'schemaVersion', 'strings']",
      'ERROR   schemaVersion is 2, expected 1',
      "ERROR   locale is 'de' but the file is fr.json",
      'ERROR   ui.nope: no English string has this key',
      'ERROR   ui.menu.play: empty (leave the key out to fall back to English)',
      "ERROR   language.name: must be the language's own name, not 'English'",
    ]);
  });

  test('the English source is checked against the generated table, never for missing keys', () {
    expect(
      check(['en']).lines.last,
      'en: 2 hand-written keys of 4 in strings/en.json, '
      '0 errors, 0 missing, 0 warnings',
    );
    write('l10n/en.json', {
      'schemaVersion': 1,
      'locale': 'en',
      'strings': {'language.name': 'English', 'ui.menu.play': 'Play now', 'ui.new': 'New'},
    });
    final r = check(['en']);
    expect(r.code, 1);
    expect(r.lines.where((l) => l.startsWith('ERROR')), [
      'ERROR   ui.menu.play: differs from strings/en.json (run fvm dart run '
          'tool/gen_data_from_legacy.dart)',
      'ERROR   ui.new: not in strings/en.json (run fvm dart run tool/gen_data_from_legacy.dart)',
    ]);
  });

  test('--todo lists the untranslated keys with their English, in table order', () {
    write('l10n/fr.json', {
      'schemaVersion': 1,
      'locale': 'fr',
      'strings': {'ui.menu.play': 'Jouer'},
    });
    final r = check(['fr', '--todo']);
    expect(r.code, 0);
    expect(jsonDecode(r.lines.single), {
      'language.name': 'English',
      'ui.records.best': 'Best wave {wave}',
      'turret.blue.name': 'Blue Cannon',
    });
    expect((jsonDecode(check(['es', '--todo']).lines.single) as Map).length, 4);
    expect(check(['es']).code, 1, reason: 'no file yet');
  });
}
