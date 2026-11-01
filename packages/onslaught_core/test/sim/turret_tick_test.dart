import 'package:onslaught_core/onslaught_core.dart';
import 'package:onslaught_core/testing.dart';
import 'package:test/test.dart';

import '../support/combo_bench.dart';
import '../support/repo_data.dart';
import '../support/sim_helpers.dart';

/// The turret update timer (`turrets/Turret.as`: `setInterval(update,
/// frame_space)`, 70 ms; `time_last` starts undefined).
void main() {
  late GameData data;
  late SimTestHarness harness;
  setUpAll(() {
    data = loadClassicData();
    harness = SimTestHarness(data);
  });

  const step = 1000 / 60;

  GameSession lyne() => harness.session(const GameConfig(mapId: 'map9', seed: 4))..debugCash = 1e9;

  /// Game times of [t]'s updates over [steps] steps.
  List<double> updates(GameSession s, Turret t, int steps) {
    final out = <double>[];
    double? last = t.updatedAtMs;
    for (var i = 0; i < steps; i++) {
      s.step();
      if (t.updatedAtMs != last) out.add(last = t.updatedAtMs!);
    }
    return out;
  }

  test('turret data carries frame_space: 70 ms, Fusion 64 ms', () {
    for (final def in data.turrets.values) {
      expect(def.tickMs, def.id == 'fusion' ? 64 : 70, reason: def.id);
    }
  });

  test('the first tick, 70 ms after the build, sets time_last and does nothing', () {
    final s = lyne();
    final t = build(s, 'yellow', ComboBench.leaderAt);
    expect(t.updatedAtMs, isNull);
    final state = ChargeSpecial.stateOf(t);
    final ticks = updates(s, t, 5);
    expect(ticks, hasLength(1));
    expect(state.charge, 0, reason: 'no update work on the first tick');
    updates(s, t, 5);
    expect(state.charge, greaterThan(0));
  });

  test('ticks come every 70 ms of real time on average, on step boundaries', () {
    final s = lyne();
    final t = build(s, 'blue', ComboBench.leaderAt);
    final ticks = updates(s, t, 6000);
    final gaps = [for (var i = 1; i < ticks.length; i++) ticks[i] - ticks[i - 1]];
    expect(gaps.toSet().map((g) => (g / step).round()).toSet(), {4, 5});
    final mean = gaps.reduce((a, b) => a + b) / gaps.length;
    expect(mean, closeTo(70, 0.1));
  });

  test('at 2× speed a tick covers twice the game time', () {
    final s = lyne()..enqueue(const SetSpeed(2));
    final t = build(s, 'blue', ComboBench.leaderAt);
    final ticks = updates(s, t, 3000);
    final mean = (ticks.last - ticks.first) / (ticks.length - 1);
    expect(mean, closeTo(140, 0.2));
  });

  test('the timer keeps its phase while paused, and paused ticks do nothing', () {
    final s = lyne();
    final t = build(s, 'blue', ComboBench.leaderAt);
    s.run(20);
    final at = t.updatedAtMs;
    s.enqueue(const SetPaused(true));
    final before = t.sinceTickMs;
    s.step();
    expect(t.sinceTickMs, isNot(before));
    s.run(30);
    expect(t.updatedAtMs, at);
  });

  test('a turret fires on its first tick after reloading', () {
    final s = lyne();
    final t = build(s, 'blue', ComboBench.leaderAt);
    // One creep it never kills, so it keeps facing the same target.
    firstCreep(s).hp = 1e12;
    s.waves.spawners.clear();
    final shots = <double>[];
    for (var i = 0; i < 1800; i++) {
      for (final e in s.step()) {
        if (e is TurretFired && e.uid == t.uid) shots.add(s.clock.nowMs);
      }
    }
    final reload = fireIntervalMs(s.statOf(t, StatKind.rate));
    final gaps = [for (var i = 1; i < shots.length; i++) shots[i] - shots[i - 1]];
    // Back-to-back shots while the creep is in range.
    final close = gaps.where((g) => g < 2 * reload).toList();
    expect(close.length, greaterThan(3));
    for (final g in close) {
      expect(g, greaterThan(reload));
      expect(g, lessThanOrEqualTo(reload + 5 * step + 1e-6));
    }
  });

  test('a busy helper is ready between its reload and its next tick, so combos fire', () {
    // Blue leader and a Red helper side by side, both shooting the creeps
    // (the case that needed a coincidence when every turret updated every
    // step).
    var combos = 0;
    for (final seed in [1, 2, 3]) {
      final s = harness.session(GameConfig(mapId: 'map9', mode: 'sandbox', seed: seed))
        ..debugCash = 1e12;
      maxed(s, 'blue', ComboBench.leaderAt);
      maxed(s, 'red', ComboBench.ring[0]);
      s.enqueue(const SendNextWave());
      combos += s.run(3600).whereType<ComboFired>().length;
    }
    expect(combos, greaterThan(0));
  });

  test('moving a turret restarts its timer', () {
    final s = lyne();
    final t = build(s, 'blue', ComboBench.leaderAt);
    s.run(3);
    s.enqueue(MoveTurret(t.uid, ComboBench.ring[2].x, ComboBench.ring[2].y));
    s.step();
    expect(t.sinceTickMs, closeTo(step, 1e-9));
  });
}
