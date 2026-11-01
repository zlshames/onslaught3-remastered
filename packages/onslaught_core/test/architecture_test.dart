import 'dart:io';

import 'package:test/test.dart';

/// Rule R1 / tenet 3: the core library is pure Dart. Rule R7: no balance
/// literals in rules/ and sim/ (and data/, testing/). Both are enforced by
/// scanning the source; so is the rules → sim/systems.dart layering.
void main() {
  final lib = Directory('lib');
  final files = lib
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('core library imports no Flutter, Flame, dart:ui or dart:io (R1)', () {
    final banned = RegExp(
      r'''^\s*(import|export)\s+['"](package:flutter|package:flame|dart:ui|dart:io)''',
      multiLine: true,
    );
    final offenders = [
      for (final f in files)
        if (banned.hasMatch(f.readAsStringSync())) f.path,
    ];
    expect(offenders, isEmpty);
  });

  test('core library depends only on allowed packages', () {
    final pkg = RegExp(r'''^\s*(?:import|export)\s+['"]package:(\w+)/''', multiLine: true);
    const allowed = {'onslaught_core', 'meta', 'collection'};
    final used = {
      for (final f in files)
        for (final m in pkg.allMatches(f.readAsStringSync())) m.group(1)!,
    };
    expect(used.difference(allowed), isEmpty);
  });

  test('rules never import sim/systems.dart (rules sit below the systems)', () {
    // Rules are what systems call; a rule reaching into a system inverts the
    // layering (.agents/architecture.md). Shared aiming lives in
    // rules/aiming.dart, shared tolerances in sim/sim_constants.dart.
    final systems = RegExp(
      r'''^\s*(?:import|export)\s+['"][^'"]*sim/systems\.dart['"]''',
      multiLine: true,
    );
    final offenders = [
      for (final f in Directory('lib/src/rules').listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart') && systems.hasMatch(f.readAsStringSync()))
          f.path.replaceAll(r'\', '/'),
    ];
    expect(offenders, isEmpty, reason: 'rules/ files importing sim/systems.dart');
  });

  test('math/, rules/ and sim/ use only sqrt, min, max and pi from dart:math', () {
    // dart:math's sin, cos, atan2, pow, … come from the host (the C library on
    // the VM, the JavaScript engine on the web) and can differ in the last
    // bit, which would make a replay differ between platforms. Use
    // math/det_math.dart (fdlibm in pure Dart) instead. sqrt is correctly
    // rounded everywhere; min, max and pi are exact. Random is not allowed
    // either: the session's SimRandom is the only randomness.
    const allowed = {'sqrt', 'min', 'max', 'pi'};
    final import = RegExp(
      r'''^\s*import\s+['"]dart:math['"]\s*(?:as\s+(\w+))?\s*(?:show\s+([\w\s,]+))?;''',
      multiLine: true,
    );
    final offenders = <String>[];
    for (final dir in ['lib/src/math', 'lib/src/rules', 'lib/src/sim']) {
      for (final f in Directory(dir).listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final source = f.readAsStringSync();
        for (final m in import.allMatches(source)) {
          final prefix = m.group(1);
          final shown = m.group(2)?.split(',').map((n) => n.trim()).toSet();
          if (shown != null) {
            offenders.addAll([for (final n in shown.difference(allowed)) '${f.path}: shows $n']);
          } else if (prefix == null) {
            offenders.add('${f.path}: import dart:math with a prefix or a show list');
          } else {
            for (final use in RegExp('\\b$prefix\\.(\\w+)').allMatches(source)) {
              if (!allowed.contains(use.group(1))) {
                offenders.add('${f.path}: $prefix.${use.group(1)}');
              }
            }
          }
        }
      }
    }
    expect(offenders, isEmpty);
  });

  group('no magic numbers in the core library (R7)', () {
    // R7 lists 0, 1, -1, 2, 100, 360 and 1000 in int or double spelling (-1 is
    // scanned as 1). Today's double uses are 0.0 and 1.0: zero accumulators
    // (map_rules.dart, targeting_rules.dart, combo.dart, road.dart) and the
    // clamp(0.0, 1.0) of a projection onto a segment (road.dart, rail.dart).
    const allowedLiterals = {
      ...{'0', '1', '2', '100', '360', '1000'},
      ...{'0.0', '1.0', '2.0', '100.0', '360.0', '1000.0'},
    };
    // Per-file exceptions, keyed by file name. Each needs a reason; none of
    // these is balance.
    const allowedPerFile = <String, Set<String>>{
      // R7's "0.5 in round-half-up", `(v + 0.5).floor()`, matching the
      // original's rounding: creep_rules.dart roundHalfUp, road.dart
      // _roundHalfUp and game_session.dart _roundHalfUp.
      'creep_rules.dart': {'0.5'},
      'road.dart': {'0.5'},
      'game_session.dart': {'0.5'},
      // xorshift128 shifts, SplitMix constants, 32-bit masks and 2^32.
      'sim_random.dart': {
        '0xFFFFFFFF',
        '0x9E3779B9',
        '0x85EBCA6B',
        '0xC2B2AE35',
        '0xFFFF',
        '4294967296.0',
        '8',
        '11',
        '13',
        '16',
        '19',
      },
      // Tolerance for comparing summed 1/60 s steps with interval lengths.
      'sim_constants.dart': {'1e-6'},
      // FNV-1a offset basis and prime halves; canonical-number precision and
      // the bounds where the VM's double printing changes form (1e15: whole
      // doubles below it are written as integers; 1e21: toString turns
      // exponential).
      'stable_hash.dart': {
        '0x811C9DC5',
        '0x0193',
        '0x0100',
        '0xFFFF',
        '0xFFFFFFFF',
        '16',
        '9',
        '1e15',
        '1e21',
      },
      // data/: the attract map sorts after every real map (1 << 16).
      'attract_defs.dart': {'16'},
      // data/: hex colour parsing (radix 16); a validation error shows at
      // most 20 issues.
      'json_reader.dart': {'16', '20'},
      // testing/: the soak driver's run settings (game speed 3, target wave
      // 300, 6 turrets per colour, churn every 25 decisions, send the next
      // wave below 150 creeps) and its never-run-out top-ups (1 << 30 lives,
      // 1e15 cash). Stress-test knobs, not balance.
      'soak.dart': {'3', '300', '6', '25', '150', '30', '1e15'},
      // testing/: the balance bot's default strategy knobs (10 turrets,
      // decide every 30 steps, 6 px grid), fixture hash interval (600 steps),
      // tick cap (1 << 22) and 4 px road sampling. Scripted-player settings.
      'bot.dart': {'10', '30', '6', '600', '22', '4'},
      // testing/: the map contract runs at most 60 steps/s × 600 s.
      'map_contract.dart': {'60', '600'},
      // testing/: the harness hashes the state every 60 steps by default.
      'sim_test_harness.dart': {'60'},
    };
    final number = RegExp(
      r'(?<![\w.$])(0x[0-9A-Fa-f]+|\d+\.\d+(?:e-?\d+)?|\d+e-?\d+|\d+)(?![\w.])',
    );

    // R7 names rules/ and sim/; data/ and testing/ are scanned too so a
    // balance number cannot hide in a parser default or a test driver.
    for (final dir in ['lib/src/rules', 'lib/src/sim', 'lib/src/data', 'lib/src/testing']) {
      test(dir, () {
        final offenders = <String>[];
        for (final f in Directory(dir).listSync(recursive: true).whereType<File>()) {
          final lines = f.readAsLinesSync();
          for (var i = 0; i < lines.length; i++) {
            final code = lines[i].split('//').first;
            if (code.trimLeft().startsWith('///') || code.trimLeft().startsWith('*')) continue;
            final stripped = code.replaceAll(RegExp(r"'[^']*'"), "''");
            for (final m in number.allMatches(stripped)) {
              final perFile = allowedPerFile[f.uri.pathSegments.last] ?? const {};
              if (!allowedLiterals.contains(m.group(1)) && !perFile.contains(m.group(1))) {
                offenders.add('${f.path}:${i + 1}: ${m.group(1)}');
              }
            }
          }
        }
        expect(offenders, isEmpty);
      });
    }
  });
}
