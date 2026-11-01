import 'package:onslaught_core/onslaught_core.dart';
import 'package:onslaught_core/testing.dart';
import 'package:test/test.dart';

import '../support/repo_data.dart';
import '../support/sim_helpers.dart';

/// Phase 3 performance budget (`docs/REMASTER_PLAN.md` §7): the simulation
/// steps 300 projectiles in flight, plus creeps, blasts and turrets, well
/// inside a 60 Hz frame.
void main() {
  test('300 projectiles step inside the budget', () {
    final data = loadClassicData();
    final s = SimTestHarness(
      data,
    ).session(const GameConfig(mapId: 'map12', mode: 'sandbox', seed: 9))..debugCash = 1e12;
    unlockAll(s);
    // Sixty creeps on the road at once (six waves sent together), too tough
    // to die.
    for (var w = 0; w < 6; w++) {
      s.enqueue(const SendNextWave());
    }
    for (var i = 0; i < 8 * 60 + 30; i++) {
      s.step();
      for (final c in s.creeps) {
        c.hp = 1e15;
      }
    }
    expect(s.creeps.length, greaterThanOrEqualTo(50));
    expect(s.lives, data.rules.lives);
    // The leaks must not end the game while it is measured.
    s.debugLives = 1 << 30;
    // Nine Reds wherever the placement rules allow (Miss Direction: the
    // longest road, 4501 px, so the creeps stay on it).
    var reds = 0;
    for (var y = 30.0; y < 470 && reds < 9; y += 40) {
      for (var x = 30.0; x < 700 && reds < 9; x += 40) {
        if (s.placementIssueAt(Vec2(x, y)) != null) continue;
        build(s, 'red', Vec2(x, y));
        reds++;
      }
    }
    expect(reds, 9);
    var made = 0;
    Projectile add(String spec, Vec2 at, {int? target}) => s.addProjectile(
      specId: spec,
      kind: data.projectiles[spec]!.kind,
      position: at,
      heading: 90,
      damage: 1,
      targetUid: target,
      turretUid: null,
    );
    // 150 held rockets circling (each scans every creep every step), 50
    // armed landmines, and homing rockets topping the total up to 300.
    for (var i = 0; i < 150; i++) {
      s.launchProjectile(
        add('rocket-1', Vec2(100.0 + i, 300))
          ..state = (RocketState()
            ..holdingCapable = true
            ..holdingInitially = true),
      );
    }
    for (var i = 0; i < 50; i++) {
      final at = s.road.minePoints[i * 7];
      s.launchProjectile(add('landmine', at)..load = Ordnance(combo: 'landmine', place: at));
    }
    void topUp() {
      while (s.projectiles.length < 300) {
        final creep = s.creeps[made++ % s.creeps.length];
        s.launchProjectile(add('rocket-1', Vec2(360, 10.0 + made % 50), target: creep.uid));
      }
    }

    topUp();
    s.run(60); // warm up the VM
    const steps = 600;
    final watch = Stopwatch()..start();
    for (var i = 0; i < steps; i++) {
      topUp();
      s.step();
    }
    watch.stop();
    final perStepMs = watch.elapsedMicroseconds / 1000 / steps;
    // ignore: avoid_print
    print('300 projectiles: ${perStepMs.toStringAsFixed(3)} ms per step');
    expect(s.projectiles.length, greaterThanOrEqualTo(290));
    expect(s.clock.stopped, isFalse);
    expect(s.creeps.length, greaterThanOrEqualTo(50));
    // An eighth of a 60 Hz frame: ample headroom for slow CI machines (a
    // laptop runs this in well under 0.1 ms).
    expect(perStepMs, lessThan(2.0));
  });
}
