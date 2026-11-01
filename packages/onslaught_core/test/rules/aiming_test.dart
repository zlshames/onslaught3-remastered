import 'package:onslaught_core/onslaught_core.dart';
import 'package:onslaught_core/testing.dart';
import 'package:test/test.dart';

import '../support/repo_data.dart';
import '../support/sim_helpers.dart';

/// `rules/aiming.dart`: keep-or-acquire, turning, bearing toward a
/// Targeter's creep and `turretTryFiring`, shared by the turret system and
/// the Targeter, Fusion and Combonly updates (audit A3).
void main() {
  late SimTestHarness harness;
  setUpAll(() => harness = SimTestHarness(loadClassicData()));

  /// Far from Lyne's road, so no creep reaches it on its own.
  const at = Vec2(500, 60);

  ({GameSession s, Turret blue, Creep creep}) bench() {
    final s = harness.session(const GameConfig(mapId: 'map9', mode: 'sandbox', seed: 4))
      ..debugCash = 1e12;
    unlockAll(s);
    final blue = build(s, 'blue', at);
    final creep = firstCreep(s)..hp = 1e12;
    s.waves.spawners.clear();
    return (s: s, blue: blue, creep: creep);
  }

  group('acquireFor', () {
    test('acquires a creep in range and stores it as the target', () {
      final b = bench();
      b.creep.position = at + const Vec2(50, 0);
      expect(acquireFor(b.s, b.blue), same(b.creep));
      expect(b.blue.targetUid, b.creep.uid);
    });

    test('keeps the current target, and drops it once out of range', () {
      final b = bench();
      b.creep.position = at + const Vec2(50, 0);
      acquireFor(b.s, b.blue);
      b.creep.position = at + const Vec2(60, 0);
      expect(acquireFor(b.s, b.blue), same(b.creep));
      b.creep.position = at + const Vec2(0, 500);
      expect(acquireFor(b.s, b.blue), isNull);
      expect(b.blue.targetUid, isNull);
    });

    test('a stale target uid acquires afresh', () {
      final b = bench();
      b.creep.position = at + const Vec2(50, 0);
      b.blue.targetUid = 987654;
      expect(acquireFor(b.s, b.blue), same(b.creep));
    });
  });

  group('turnToward', () {
    test('turns by rotate × dt and reports facing once there', () {
      final b = bench();
      final t = b.blue..rotation = 0;
      final rotate = t.def.stats.rotate;
      final below = at + const Vec2(0, 100); // bearing 90°
      final stepMs = 10 / rotate * 1000; // 10° of turn
      expect(turnToward(b.s, t, below, stepMs), isFalse);
      expect(t.rotation, closeTo(10, 1e-9));
      expect(turnToward(b.s, t, below, 1e6), isTrue);
      expect(t.rotation, 90);
    });
  });

  group('bearToCreep', () {
    test('turns toward the creep a Targeter sent it at', () {
      final b = bench();
      b.creep.position = at + const Vec2(0, 300);
      b.blue
        ..rotation = 0
        ..bearCreepUid = b.creep.uid;
      bearToCreep(b.s, b.blue, 1e6);
      expect(b.blue.rotation, 90);
      expect(b.blue.bearCreepUid, b.creep.uid);
    });

    test('forgets a creep that is gone', () {
      final b = bench();
      b.blue
        ..rotation = 0
        ..bearCreepUid = 987654;
      bearToCreep(b.s, b.blue, 1e6);
      expect(b.blue.bearCreepUid, isNull);
      expect(b.blue.rotation, 0);
    });
  });

  group('turretTryFiring', () {
    test('a reloaded turret facing its target fires', () {
      final b = bench();
      b.creep.position = at + const Vec2(50, 0);
      b.blue
        ..rotation = 0
        ..firedAtMs = -1e9;
      final before = b.s.projectiles.length;
      turretTryFiring(b.s, b.blue, b.creep, 1);
      expect(b.s.projectiles.length, before + 1);
      expect(b.blue.firedAtMs, b.s.clock.nowMs);
    });

    test('one still reloading turns but does not fire', () {
      final b = bench();
      b.creep.position = at + const Vec2(0, 50);
      b.blue
        ..rotation = 0
        ..firedAtMs = b.s.clock.nowMs;
      final before = b.s.projectiles.length;
      turretTryFiring(b.s, b.blue, b.creep, 1e6);
      expect(b.s.projectiles.length, before);
      expect(b.blue.rotation, 90);
    });
  });
}
