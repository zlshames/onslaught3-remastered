// Balance bots against their recorded baselines (balance-bot skill), and the
// Phase 1 headless acceptance test (docs/REMASTER_PLAN.md §7).
import 'dart:convert';
import 'dart:io';

import 'package:onslaught_core/onslaught_core.dart';
import 'package:onslaught_core/testing.dart';
import 'package:test/test.dart';

import '../support/repo_data.dart';

const _dir = 'test/balance';

/// Waves a baseline plays to (or until lost); keep in step with tool/balance.dart.
const int _baselineWaves = 300;

BotStrategy _strategy(String id) => BotStrategy.fromJson(
  (jsonDecode(File('$_dir/strategies/$id.json').readAsStringSync()) as Map).cast<String, Object?>(),
);

void main() {
  late GameData data;
  late BotRunner runner;
  setUpAll(() {
    data = loadClassicData();
    runner = BotRunner(data);
  });

  test('10 blue turrets on Classic survive to wave 20 on easy', () {
    final result = runner.run(_strategy('blue-rush'), untilWave: 20);
    expect(result.strategy.maxTurrets, 10);
    expect(result.strategy.mapId, 'map1');
    expect(result.strategy.difficulty, 'easy');
    expect(
      result.commands.whereType<ScheduledCommand>().where((c) => c.command is BuildTurret),
      hasLength(10),
    );
    expect(result.gameOver, isFalse);
    expect(result.wavesCleared, greaterThanOrEqualTo(20));
    expect(result.livesLeft, greaterThan(0));
  });

  group('bots stay within their bands', () {
    final bands = (jsonDecode(File('$_dir/bands.json').readAsStringSync()) as Map)
        .cast<String, Object?>();
    final bots = (bands['bots']! as Map).cast<String, Object?>();
    final pct = (bands['wavesTolerancePct']! as num).toDouble();
    final lives = (bands['livesTolerance']! as num).toInt();
    final strategies =
        Directory('$_dir/strategies')
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.json'))
            .map((f) => f.uri.pathSegments.last.replaceAll('.json', ''))
            .toList()
          ..sort();

    test('every strategy has a baseline', () => expect(bots.keys, containsAll(strategies)));

    for (final id in strategies) {
      test(id, () {
        final base = (bots[id]! as Map).cast<String, Object?>();
        final r = runner.run(_strategy(id), untilWave: _baselineWaves);
        final waves = (base['wavesCleared']! as num).toInt();
        final band = (waves * pct / 100).ceil();
        expect(r.wavesCleared, inInclusiveRange(waves - band, waves + band));
        final baseLives = (base['livesLeft']! as num).toInt();
        expect(r.livesLeft, inInclusiveRange(baseLives - lives, baseLives + lives));
      });
    }
  });

  test('bots are deterministic', () {
    final a = runner.run(_strategy('blue-rush'), untilWave: 10);
    final b = runner.run(_strategy('blue-rush'), untilWave: 10);
    expect(jsonEncode(a.toJson()), jsonEncode(b.toJson()));
    expect([for (final c in a.commands) c.toJson()], [for (final c in b.commands) c.toJson()]);
  });
}
