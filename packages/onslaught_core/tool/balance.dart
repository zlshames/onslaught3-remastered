// Runs the headless balance bots (see the balance-bot skill).
//
//   fvm dart run tool/balance.dart run blue-rush [--waves 300] [--seed 42]
//   fvm dart run tool/balance.dart run --all
//   fvm dart run tool/balance.dart baseline blue-rush   # re-record a baseline (state the reason)
//
// Run from packages/onslaught_core. Strategies: test/balance/strategies/*.json;
// baselines and bands: test/balance/bands.json.
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:onslaught_core/onslaught_core.dart';
import 'package:onslaught_core/testing.dart';

const _strategies = 'test/balance/strategies';
const _bands = 'test/balance/bands.json';

void main(List<String> args) {
  if (args.isEmpty) _usage();
  final cmd = args.first;
  final rest = args.skip(1).toList();
  int? opt(String name) {
    final i = rest.indexOf(name);
    return i < 0 ? null : int.parse(rest[i + 1]);
  }

  final waves = opt('--waves') ?? baselineWaves;
  final seed = opt('--seed');
  final ids = rest.contains('--all')
      ? _strategyIds()
      : [
          for (var i = 0; i < rest.length; i++)
            if (!rest[i].startsWith('--') && (i == 0 || !rest[i - 1].startsWith('--'))) rest[i],
        ];
  if (ids.isEmpty) _usage();
  final runner = BotRunner(_loadData());
  final bands = _readBands();
  for (final id in ids) {
    var strategy = _strategy(id);
    if (seed != null) strategy = _withSeed(strategy, seed);
    final sw = Stopwatch()..start();
    final result = runner.run(strategy, untilWave: waves);
    print('${jsonEncode(result.toJson())}  (${sw.elapsedMilliseconds} ms)');
    if (cmd == 'baseline') {
      (bands['bots']! as Map)[id] = {
        'wavesCleared': result.wavesCleared,
        'kills': result.kills,
        'livesLeft': result.livesLeft,
      };
      print('baseline for $id recorded');
    } else if (cmd != 'run') {
      _usage();
    }
  }
  if (cmd == 'baseline') {
    File(_bands).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(bands)}\n');
  }
}

/// Waves a baseline run plays to (or until the game is lost).
const int baselineWaves = 300;

BotStrategy _withSeed(BotStrategy s, int seed) => BotStrategy(
  id: s.id,
  description: s.description,
  mapId: s.mapId,
  turret: s.turret,
  difficulty: s.difficulty,
  mode: s.mode,
  profile: s.profile,
  seed: seed,
  maxTurrets: s.maxTurrets,
  upgradeOrder: s.upgradeOrder,
  sendEarly: s.sendEarly,
  decideEvery: s.decideEvery,
  gridStep: s.gridStep,
);

Never _usage() {
  stderr.writeln('usage: balance.dart run|baseline <bot…>|--all [--waves N] [--seed S]');
  exit(64);
}

List<String> _strategyIds() => [
  for (final f in Directory(_strategies).listSync().whereType<File>())
    if (f.path.endsWith('.json')) f.uri.pathSegments.last.replaceAll('.json', ''),
]..sort();

BotStrategy _strategy(String id) => BotStrategy.fromJson(
  (jsonDecode(File('$_strategies/$id.json').readAsStringSync()) as Map).cast<String, Object?>(),
);

Map<String, Object?> _readBands() =>
    (jsonDecode(File(_bands).readAsStringSync()) as Map).cast<String, Object?>();

GameData _loadData() {
  const root = '../../assets/data';
  final manifest = jsonDecode(File('$root/manifest.json').readAsStringSync()) as Map;
  final docs = <String, Object?>{
    'manifest.json': manifest,
    for (final f in (manifest['files'] as List).cast<String>())
      f: jsonDecode(File('$root/$f').readAsStringSync()),
  };
  return GameData.fromDocuments(docs, behaviours: RulesRegistry.classic());
}
