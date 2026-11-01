// One-off extraction of the original game's values into a committed reference
// table. Run once (or to audit), never from the build or the tests:
//
//   fvm dart run tool/legacy_extract.dart
//
// Reads  .legacy/deobfuscated/  (read-only; rule R11)
//        tool/legacy_extract/engine_constants.dart (the hand-transcribed part)
// Writes docs/legacy/legacy_values.json  — the machine-readable reference
//        docs/legacy/LEGACY_VALUES.md    — the same values as readable tables
//
//   fvm dart run tool/legacy_extract.dart --transcribed
//
// Refreshes only the sections transcribed in engine_constants.dart (`engine`,
// the combo recipe structure, the sandbox racks: see
// legacy_extract/transcribed_sections.dart) in the committed table, and the
// readable tables, without .legacy/. Run it after editing engine_constants.dart;
// test/tool/legacy_transcription_test.dart fails until you do.
//
// Everything downstream (tool/gen_data_from_legacy.dart → assets/data, the data
// snapshot test) reads legacy_values.json, so nothing re-parses the legacy
// source. See docs/legacy/README.md.
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'legacy_extract/as2_literal.dart';
import 'legacy_extract/legacy_readers.dart';
import 'legacy_extract/transcribed_sections.dart';

const _root = '.legacy/deobfuscated/__Packages';
const _outDir = 'docs/legacy';

String _src(String f) => File('$_root/$f').readAsStringSync();

/// Short class name → turret file.
const _turretClasses = [
  'TurretBlue',
  'TurretGreen',
  'TurretRed',
  'TurretYellow',
  'TurretRangeUp',
  'TurretDamageUp',
  'TurretRateUpExchange',
  'TurretRangeUpExchange',
  'TurretRateUp',
  'TurretDamageUpBig',
  'TurretDamageUpBigExchange',
  'TurretTargeter',
  'TurretSniper',
  'TurretFusion',
  'TurretRailgun',
  'TurretCombonly',
];

void main(List<String> args) {
  if (args.contains('--transcribed')) return _refreshTranscribed();
  if (!Directory(_root).existsSync()) {
    stderr.writeln('Run from the repo root; $_root not found.');
    exit(1);
  }

  // Turret classes, resolved through the inheritance chain.
  final classes = <String, ClassDefaults>{
    'Turret': readClassDefaults(_src('turrets/Turret.as')),
    'TurretModify': readClassDefaults(_src('turrets/TurretModify.as')),
    for (final c in _turretClasses) c: readClassDefaults(_src('turrets/$c.as')),
  };
  List<ClassDefaults> chain(String name) {
    final out = <ClassDefaults>[];
    String? n = name;
    while (n != null && classes.containsKey(n)) {
      out.insert(0, classes[n]!);
      n = classes[n]!.superName;
    }
    return out;
  }

  final gm = readClassDefaults(_src('GameManager.as'));
  final am = readClassDefaults(_src('AttackerManager.as'));
  final tm = readClassDefaults(_src('TurretManager.as'));
  final typeNames = readTypeNames(_src('TurretManager.as'));
  final modDefaults = readModDefaults(_src('mods/ModDefaults.as'));
  final modAssets = readModAssets(
    _src('mods/ModDefaults.as'),
    readModTypeNames(_src('mods/ModManager.as')),
  );

  final costs = gm.values['turrets_cost']! as Map<String, Object?>;
  final available = gm.values['turrets_available']! as Map<String, Object?>;
  final unlockByKills = gm.values['turrets_unlock']! as Map<String, Object?>;
  final unlocks = <String, int>{
    for (final e in unlockByKills.entries)
      for (final t in e.value! as List<Object?>) t! as String: int.parse(e.key),
  };

  final turrets = <String, Object?>{};
  for (final c in _turretClasses) {
    final short = c.substring('Turret'.length);
    final values = mergeClassChain(chain(c));
    turrets[c] = {
      'source': [for (final k in chain(c)) 'turrets/${k.className}.as'].join(' ← '),
      'cost': costs[short],
      'unlockKills': unlocks[short] ?? 0,
      'availableInitially': available[short],
      'displayNames': typeNames[c] ?? const [],
      'values': values,
    };
  }

  final combosData = readCombos(_src('Combos.as'));
  final maps = readMaps(_src('RoadManager.as'));
  final challenges = readChallenges(_src('GameSelectChallenge.as'));
  final tutorial = readTutorialPages(_src('GameTutorial.as'));
  final milestones = _readMilestones(_src('GameManager.as'));

  final table = <String, Object?>{
    'schemaVersion': 1,
    'about':
        'Values of the original Onslaught 2 (SWF "2350-gaby"), extracted once '
        'from the FFDec deobfuscated ActionScript by tool/legacy_extract.dart. '
        'Runtime defaults come from the class constructors and GameManager / '
        'AttackerManager tables; mods/ModDefaults.as values are what the '
        'original mod editor showed and only apply as deltas when a mod is '
        'active (mods/ModManager.as:modObject).',
    'turrets': turrets,
    'gameManager': {
      'source': 'GameManager.as (class vars, ctor)',
      'playerLives': gm.values['player_lives'],
      'startingCash': gm.values['starting_cash_levels'],
      'modeRacks': modeRacksSection(),
      'milestones': milestones,
      'values': gm.values,
    },
    'attackerManager': {'source': 'AttackerManager.as (class vars, ctor)', 'values': am.values},
    'turretManager': {
      'source': 'TurretManager.as (class vars)',
      'turretResale': tm.values['turret_resale'],
    },
    'combos': {
      'source': 'Combos.as:init (data); turrets/Turret*.as:comboFire (recipes)',
      'data': combosData,
      ...comboStructure(),
    },
    'maps': {
      'source': 'RoadManager.as',
      'maps': [
        for (final m in maps) {'key': m.key, 'name': m.name, 'base': m.base, 'road': m.road},
      ],
    },
    'challenges': {
      'source': 'GameSelectChallenge.as (ctor presets, onLoad pickers)',
      'presets': challenges.presets,
      'pickers': challenges.pickers,
    },
    'tutorial': {'source': 'GameTutorial.as:tutorialBuild', 'pages': tutorial},
    'engine': engineSection(),
    'modEditor': {
      'source': 'mods/ModDefaults.as',
      'itemTitles': modDefaults.itemTitles,
      'defaults': modDefaults.items,
      'descriptors': modDefaults.descriptors,
      // `initModAssets`: item → asset → type. Combo items are derived from
      // the combo data at run time (`typeof` of each field: number, boolean
      // or string), so they are not listed.
      'assets': modAssets,
    },
    'discrepancies': _discrepancies(turrets, modDefaults, costs, unlocks),
  };

  _write(table);
}

/// `--transcribed`: the committed table with its transcribed sections
/// refreshed from `engine_constants.dart`.
void _refreshTranscribed() {
  final file = File('$_outDir/legacy_values.json');
  if (!file.existsSync()) {
    stderr.writeln('Run from the repo root; ${file.path} not found.');
    exit(1);
  }
  final table = (jsonDecode(file.readAsStringSync()) as Map).cast<String, Object?>();
  _write(withTranscribedSections(table));
}

void _write(Map<String, Object?> table) {
  Directory(_outDir).createSync(recursive: true);
  File('$_outDir/legacy_values.json')
      .writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(table)}\n');
  File('$_outDir/LEGACY_VALUES.md').writeAsStringSync(_markdown(table));
  print('Wrote $_outDir/legacy_values.json and $_outDir/LEGACY_VALUES.md');
}

/// Kill milestones from `GameManager.modeUpdate` (`total_kills == N`).
Map<String, Object?> _readMilestones(String source) {
  final body = functionBody(source, 'modeUpdate');
  final kills = RegExp(r'total_kills == (\d+)')
      .allMatches(body)
      .map((m) => int.parse(m.group(1)!))
      .toList();
  return {
    'source': 'GameManager.as:modeUpdate',
    'extremeKills': kills.first,
    'completeKills': kills.last,
    'rules': {
      'extreme': 'reach ${kills.first} kills in one normal game on any difficulty',
      'sandbox': 'reach ${kills.last} kills on medium',
      'sandbox2': 'reach ${kills.last} kills on hard',
      'modding': 'complete easy, medium and hard (${kills.last} kills each)',
      'challenge':
          'start the tutorial (GameManagerTutorial.as:setupFinal; GameManager.as:gameWin too)',
    },
  };
}

/// Where the runtime defaults differ from what the original mod editor showed.
List<Map<String, Object?>> _discrepancies(
  Map<String, Object?> turrets,
  ModDefaultsData mod,
  Map<String, Object?> costs,
  Map<String, int> unlocks,
) {
  final out = <Map<String, Object?>>[];
  for (final e in turrets.entries) {
    final runtime = (e.value! as Map)['values'] as Map<String, Object?>;
    final editor = mod.items[e.key] ?? const {};
    editor.forEach((asset, edValue) {
      Object? rt;
      if (asset.startsWith('upgrade_')) {
        rt = {
          'cost': runtime['${asset}_cost'] ?? const [],
          'amount': runtime['${asset}_amount'] ?? const [],
        };
      } else if (asset == 'turret_cost') {
        rt = costs[e.key.substring(6)];
      } else if (asset == 'turret_unlock') {
        rt = unlocks[e.key.substring(6)];
      } else if (asset == 'turret_available') {
        return;
      } else {
        rt = runtime[asset];
      }
      if (jsonEncode(rt) != jsonEncode(edValue)) {
        out.add({'item': e.key, 'asset': asset, 'runtime': rt, 'modEditor': edValue});
      }
    });
  }
  return out;
}

String _markdown(Map<String, Object?> t) {
  final b = StringBuffer()
    ..writeln('# Legacy values (original Onslaught 2)')
    ..writeln()
    ..writeln('Generated by `tool/legacy_extract.dart` from `.legacy/deobfuscated/`; do not edit.')
    ..writeln('Machine-readable source: [`legacy_values.json`](legacy_values.json). Behaviour,')
    ..writeln('formulas and quirks: [`ENGINE_NOTES.md`](ENGINE_NOTES.md).')
    ..writeln()
    ..writeln('> ${t['about']}')
    ..writeln();

  String fmt(Object? v) => v == null ? '–' : (v is List ? v.join(', ') : '$v');

  final turrets = (t['turrets']! as Map).cast<String, Object?>();
  b
    ..writeln('## Turrets (runtime defaults)')
    ..writeln()
    ..writeln(
      '| Turret | Cost | Unlock kills | Damage | Range | Rate | Poison | Rotate | Must face | Source |',
    )
    ..writeln('|---|---|---|---|---|---|---|---|---|---|');
  turrets.forEach((k, v) {
    final m = (v! as Map).cast<String, Object?>();
    final vals = (m['values']! as Map).cast<String, Object?>();
    b.writeln(
      '| $k | ${fmt(m['cost'])} | ${fmt(m['unlockKills'])} | ${fmt(vals['weapon_damage'])} | '
      '${fmt(vals['weapon_range'])} | ${fmt(vals['weapon_rate'])} | ${fmt(vals['weapon_poison'])} | '
      '${fmt(vals['weapon_rotate'])} | ${fmt(vals['weapon_must_face'])} | `${m['source']}` |',
    );
  });
  b
    ..writeln()
    ..writeln('### Upgrade tracks (cost → value)')
    ..writeln();
  turrets.forEach((k, v) {
    final vals = ((v! as Map)['values']! as Map).cast<String, Object?>();
    final rows = <String>[];
    for (final s in ['damage', 'range', 'rate']) {
      final c = vals['upgrade_${s}_cost'];
      final a = vals['upgrade_${s}_amount'];
      final cost = c is List ? c : const <Object?>[];
      final amount = a is List ? a : const <Object?>[];
      if (cost.isEmpty) continue;
      rows.add(
        '$s: ${[for (var i = 0; i < cost.length; i++) '${cost[i]}→${i < amount.length ? amount[i] : '?'}'].join(', ')}',
      );
    }
    if (rows.isNotEmpty) b.writeln('- **$k** — ${rows.join('; ')}');
  });

  final gm = (t['gameManager']! as Map).cast<String, Object?>();
  final am = ((t['attackerManager']! as Map)['values']! as Map).cast<String, Object?>();
  b
    ..writeln()
    ..writeln('## Game and waves')
    ..writeln()
    ..writeln('| Item | Value | Source |')
    ..writeln('|---|---|---|')
    ..writeln('| Lives | ${gm['playerLives']} | `GameManager.as` |')
    ..writeln('| Starting cash | ${jsonEncode(gm['startingCash'])} | `GameManager.as:ctor` |')
    ..writeln(
      '| Sandbox racks | ${jsonEncode((gm['modeRacks']! as Map)['racks'])} | '
      '`GameManager.as:resetGame` |',
    )
    ..writeln(
      '| Sell refund | ${(t['turretManager']! as Map)['turretResale']} | `TurretManager.as` |',
    );
  for (final k in [
    'attacker_energy',
    'attacker_upgrade_rate',
    'attacker_spacing',
    'wave_size',
    'wave_spacing',
    'attacker_types',
  ]) {
    b.writeln('| `$k` | ${fmt(am[k])} | `AttackerManager.as` |');
  }
  for (final d in ['easy', 'medium', 'hard', 'extreme']) {
    b.writeln(
      '| HP rate $d (wave → rate) | ${jsonEncode(am['attacker_hp_rate_$d'])} | `AttackerManager.as:ctor` |',
    );
    b.writeln('| Creep speed $d | ${fmt(am['attacker_speed_$d'])} | `AttackerManager.as:ctor` |');
  }
  final ms = (gm['milestones']! as Map).cast<String, Object?>();
  b
    ..writeln()
    ..writeln('### Mode unlocks (`GameManager.as:modeUpdate`)')
    ..writeln();
  ((ms['rules']! as Map).cast<String, Object?>()).forEach((k, v) => b.writeln('- **$k**: $v'));

  final combos = (t['combos']! as Map).cast<String, Object?>();
  final data = (combos['data']! as Map).cast<String, Object?>();
  b
    ..writeln()
    ..writeln('## Combos')
    ..writeln()
    ..writeln('| Leader | # | Key | Needs | Takes | Projectile | Blast | Data (`Combos.as`) |')
    ..writeln('|---|---|---|---|---|---|---|---|');
  for (final r in (combos['recipes']! as List).cast<Map<String, Object?>>()) {
    final exact = (r['exact'] as List?)?.toSet() ?? const {};
    final needs = (r['requires']! as Map).entries
        .map((e) => '${e.key}${exact.contains(e.key) ? '==' : '≥'}${e.value}')
        .join(' ');
    final takes = [
      ...(r['takes']! as Map).entries.map((e) => '${e.key} ${e.value}'),
      ...((r['takesIfReady'] as Map?) ?? const {}).entries.map(
        (e) => '${e.key} ${e.value} if ready',
      ),
    ].join(', ');
    b.writeln(
      '| ${r['leader']} | ${r['priority']} | ${r['key']} | $needs | $takes | ${r['projectile']} | ${fmt(r['blast'])} | '
      '${jsonEncode(data[r['key']])} |',
    );
  }
  b.writeln();
  ((combos['unreachable']! as Map).cast<String, Object?>()).forEach(
    (k, v) => b.writeln('Unreachable: `$k` (${jsonEncode(data[k])}) — $v.'),
  );
  b
    ..writeln()
    ..writeln(
      '### Combonly scan (`TurretCombonly.as:comboScan`; per colour the last matching row wins)',
    )
    ..writeln()
    ..writeln('| # | Colour | Option | Recipe | Consumes |')
    ..writeln('|---|---|---|---|---|');
  final scan = ((combos['combonly']! as Map)['scan']! as List).cast<Map<String, Object?>>();
  for (var i = 0; i < scan.length; i++) {
    final r = scan[i];
    b.writeln(
      '| $i | ${r['colour']} | ${r['name']} | ${r['recipe']} | ${jsonEncode(r['needs'])} |',
    );
  }

  final eng = (t['engine']! as Map).cast<String, Object?>();
  b
    ..writeln()
    ..writeln('## Projectile engines')
    ..writeln()
    ..writeln('| Engine | Constants | Source |')
    ..writeln('|---|---|---|');
  ((eng['projectileEngines']! as Map).cast<String, Object?>()).forEach((k, v) {
    final m = Map<String, Object?>.of((v! as Map).cast<String, Object?>());
    final src = m.remove('source');
    b.writeln('| $k | ${m.entries.map((e) => '${e.key} ${e.value}').join(', ')} | `$src` |');
  });
  b
    ..writeln()
    ..writeln('Projectile defaults (`Projectile.as`): ${jsonEncode(eng['projectileDefaults'])}')
    ..writeln()
    ..writeln('## Blasts')
    ..writeln()
    ..writeln('| Blast | Constants | Source |')
    ..writeln('|---|---|---|');
  ((eng['blasts']! as Map).cast<String, Object?>()).forEach((k, v) {
    final m = Map<String, Object?>.of((v! as Map).cast<String, Object?>());
    final src = m.remove('source');
    b.writeln('| $k | ${m.entries.map((e) => '${e.key} ${e.value}').join(', ')} | `$src` |');
  });

  b
    ..writeln()
    ..writeln('## Maps (`RoadManager.as`)')
    ..writeln()
    ..writeln('| Key | Name | Base | Road points |')
    ..writeln('|---|---|---|---|');
  for (final m in ((t['maps']! as Map)['maps']! as List).cast<Map<String, Object?>>()) {
    final base = (m['base']! as Map);
    final road = (m['road']! as List).cast<Map<String, Object?>>();
    b.writeln(
      '| ${m['key']} | ${m['name']} | ${base['x']},${base['y']} | '
      '${road.map((p) => '(${p['x']},${p['y']})').join(' ')} |',
    );
  }

  final ch = (t['challenges']! as Map).cast<String, Object?>();
  b
    ..writeln()
    ..writeln('## Challenge presets (`GameSelectChallenge.as`)')
    ..writeln()
    ..writeln(
      '| Name | Difficulty | Objective | Cash | Time limit s | Turret limit | Wave sizes | Speeds | Debug only |',
    )
    ..writeln('|---|---|---|---|---|---|---|---|---|');
  for (final p in (ch['presets']! as List).cast<Map<String, Object?>>()) {
    b.writeln(
      '| ${p['name']} | ${p['difficulty']} | ${fmt(p['objective'])} | ${p['cash']} | ${fmt(p['timelimit'])} | '
      '${fmt(p['turretlimit'])} | ${p['wavesize']} | ${p['wavespeed']} | ${p['debugOnly'] ?? false} |',
    );
  }
  b
    ..writeln()
    ..writeln(
      'Pickers: see `challenges.pickers` in the JSON (labels and values exactly as the original).',
    )
    ..writeln()
    ..writeln('## Targeting, creeps, sounds')
    ..writeln()
    ..writeln('- World: ${jsonEncode(eng['world'])}')
    ..writeln('- Map editor: ${jsonEncode(eng['mapEditor'])}')
    ..writeln('- Rules: ${jsonEncode(eng['rules'])}')
    ..writeln('- Targeting: ${jsonEncode(eng['targeting'])}')
    ..writeln('- Creeps: ${jsonEncode(eng['creeps'])}')
    ..writeln('- Settings: ${jsonEncode(eng['settings'])}')
    ..writeln('- Sound mix: ${jsonEncode(eng['soundMix'])}')
    ..writeln()
    ..writeln('| Sound event | Files |')
    ..writeln('|---|---|');
  ((eng['soundEvents']! as Map).cast<String, Object?>()).forEach(
    (k, v) => b.writeln('| $k | ${(v! as List).isEmpty ? '(silent)' : (v as List).join(', ')} |'),
  );

  final tut = ((t['tutorial']! as Map)['pages']! as List).cast<Map<String, Object?>>();
  b
    ..writeln()
    ..writeln('## Tutorial (`GameTutorial.as`): ${tut.length} pages')
    ..writeln();
  for (var i = 0; i < tut.length; i++) {
    final p = tut[i];
    b.writeln(
      '${i + 1}. **${p['title']}**${p['show'] != null ? ' — points at `${p['show']}`' : ''}'
      '${p['setCash'] != null ? ' — sets cash to ${p['setCash']}' : ''}',
    );
  }

  final disc = (t['discrepancies']! as List).cast<Map<String, Object?>>();
  b
    ..writeln()
    ..writeln('## Runtime defaults vs. the original mod editor (`ModDefaults.as`)')
    ..writeln()
    ..writeln('The game runs on the left column; the mod editor displayed the right one.')
    ..writeln()
    ..writeln('| Item | Asset | Runtime | Mod editor |')
    ..writeln('|---|---|---|---|');
  for (final d in disc) {
    b.writeln(
      '| ${d['item']} | ${d['asset']} | `${jsonEncode(d['runtime'])}` | `${jsonEncode(d['modEditor'])}` |',
    );
  }
  return b.toString();
}
