@Tags(['soak'])
library;

import 'package:onslaught_core/onslaught_core.dart';
import 'package:onslaught_core/testing.dart';
import 'package:test/test.dart';

import '../support/repo_data.dart';

/// The Phase 8 release gate (`docs/REMASTER_PLAN.md` §7): a Super Sandbox
/// game with every turret type, maxed upgrades, combos and sales, played
/// at 3× to wave 300 without an exception, a stuck clock or a runaway
/// entity count, inside the per-step budget. Skipped by default (minutes
/// long); the release workflow and the nightly job run it:
///
///     fvm dart test --run-skipped -t soak
void main() {
  for (final mapId in ['map1', 'map12']) {
    test('$mapId: 3× to wave 300', () {
      final data = loadClassicData();
      final s = SimTestHarness(data)
          .session(GameConfig(mapId: mapId, mode: 'sandbox2', difficulty: 'hard', seed: 8));
      final soak = SoakDriver(s)..setUp();
      final watch = Stopwatch();
      var steps = 0;
      var slowest = 0;
      var combos = 0;
      while (!soak.done && steps < 4000000) {
        if (steps % 30 == 0) soak.decide();
        watch
          ..reset()
          ..start();
        final events = s.step();
        watch.stop();
        combos += events.whereType<ComboFired>().length;
        steps++;
        if (watch.elapsedMicroseconds > slowest) slowest = watch.elapsedMicroseconds;
      }
      // ignore: avoid_print
      print(
        '$mapId: wave ${s.waves.wave} in $steps steps '
        '(${(s.clock.nowMs / 60000).toStringAsFixed(1)} game min), slowest step '
        '${(slowest / 1000).toStringAsFixed(2)} ms; $combos combos; ${soak.stats}',
      );
      expect(soak.done, isTrue, reason: 'reached wave ${s.waves.wave}');
      expect(s.gameOver, isFalse);
      expect(soak.stats.built, greaterThanOrEqualTo(data.turrets.length));
      expect(soak.stats.sold, greaterThan(0));
      expect(s.kills, greaterThan(0));
      expect(combos, greaterThan(0), reason: 'the colour clusters fire combos');
      // Nothing piles up: rockets, mines and blasts are cleaned away.
      expect(soak.stats.maxProjectiles, lessThan(3000));
      expect(soak.stats.maxBlasts, lessThan(500));
    }, timeout: const Timeout(Duration(minutes: 20)));
  }
}
