import 'package:onslaught_core/onslaught_core.dart';
import 'package:onslaught_core/testing.dart';
import 'package:test/test.dart';

import '../support/repo_data.dart';
import '../support/sim_helpers.dart';

/// `UpgradeTurretMax`: `Turret.upgradeDamageMax` (and Range, Rate), the
/// original's Shift-click on an upgrade button.
void main() {
  late GameData data;
  late SimTestHarness harness;
  setUpAll(() {
    data = loadClassicData();
    harness = SimTestHarness(data);
  });

  const spot = Vec2(300, 150);

  /// Lyne (map9) with a fresh Blue at [spot] and [cash] left after building.
  (GameSession, Turret) blueWith(double cash) {
    final s = harness.session(const GameConfig(mapId: 'map9', seed: 5))..debugCash = 1e7;
    final t = build(s, 'blue', spot);
    s.debugCash = cash;
    return (s, t);
  }

  List<UpgradeStep> track(Turret t, StatKind stat) => t.def.upgrades.track(stat);

  /// The sum of the first [n] step costs of [stat].
  double costOf(Turret t, StatKind stat, int n) =>
      track(t, stat).take(n).fold(0.0, (sum, step) => sum + step.cost);

  test('buys every step the cash allows, one TurretUpgraded per step', () {
    final probe = blueWith(0).$2;
    final steps = track(probe, StatKind.damage);
    expect(steps.length, greaterThan(2), reason: 'needs a track with room to stop early');
    // Enough for two steps and a bit, not three.
    final cash = costOf(probe, StatKind.damage, 2) + steps[2].cost / 2;
    final (s, t) = blueWith(cash);

    s.enqueue(UpgradeTurretMax(t.uid, 'damage'));
    final events = s.step();

    final ups = events.whereType<TurretUpgraded>().toList();
    expect(ups.map((e) => (e.uid, e.stat, e.level)), [(t.uid, 'damage', 1), (t.uid, 'damage', 2)]);
    expect(ups.map((e) => e.cost), [steps[0].cost, steps[1].cost]);
    expect(ups.last.cash, closeTo(steps[2].cost / 2, 1e-9));
    expect(events.whereType<CommandRejected>(), isEmpty);
    expect(t.damageLevel, 2);
    expect(s.cash, closeTo(steps[2].cost / 2, 1e-9));
  });

  test('stops at the end of the track with cash to spare', () {
    final (s, t) = blueWith(1e7);
    s.enqueue(UpgradeTurretMax(t.uid, 'range'));
    final ups = s.step().whereType<TurretUpgraded>().toList();
    expect(ups, hasLength(track(t, StatKind.range).length));
    expect(t.level(StatKind.range), track(t, StatKind.range).length);
    expect(s.cash, closeTo(1e7 - costOf(t, StatKind.range, ups.length), 1e-6));
  });

  test('matches the same steps sent as single upgrades, event for event', () {
    final probe = blueWith(0).$2;
    final cash = costOf(probe, StatKind.rate, 3) + 1;
    final (a, ta) = blueWith(cash);
    final (b, tb) = blueWith(cash);

    a.enqueue(UpgradeTurretMax(ta.uid, 'rate'));
    for (var i = 0; i < 3; i++) {
      b.enqueue(UpgradeTurret(tb.uid, 'rate'));
    }
    final ea = a.step();
    final eb = b.step();

    expect([for (final e in ea) e.toJson()], [for (final e in eb) e.toJson()]);
    expect(a.stateHash(), b.stateHash());
    // Both go on identically.
    a.run(200);
    b.run(200);
    expect(a.stateHash(), b.stateHash());
  });

  test('rejected like a single upgrade when no step can be bought', () {
    CommandRejected rejectedFor(GameSession s, GameCommand c) {
      s.enqueue(c);
      return s.step().whereType<CommandRejected>().single;
    }

    final (poor, tp) = blueWith(0);
    var r = rejectedFor(poor, UpgradeTurretMax(tp.uid, 'damage'));
    expect((r.command, r.reason), ('upgradeMax', 'cannotAfford'));
    expect(tp.damageLevel, 0);

    final (rich, tr) = blueWith(1e7);
    upgrade(rich, tr, StatKind.damage, track(tr, StatKind.damage).length);
    r = rejectedFor(rich, UpgradeTurretMax(tr.uid, 'damage'));
    expect((r.command, r.reason), ('upgradeMax', 'maxed'));

    r = rejectedFor(rich, UpgradeTurretMax(tr.uid, 'poison'));
    expect(r.reason, 'unknownStat');
    r = rejectedFor(rich, const UpgradeTurretMax(999, 'damage'));
    expect(r.reason, 'noSuchTurret');

    rich.enqueue(const SetPaused(true));
    rich.step();
    r = rejectedFor(rich, UpgradeTurretMax(tr.uid, 'range'));
    expect(r.reason, 'paused');
    expect(tr.level(StatKind.range), 0);
  });
}
