import 'package:onslaught_core/onslaught_core.dart';
import 'package:onslaught_core/testing.dart';
import 'package:test/test.dart';

import '../support/combo_bench.dart';
import '../support/repo_data.dart';
import '../support/sim_helpers.dart';

/// Sniper (`turrets/TurretSniper.as`, `BulletSniper.as`) and Railgun
/// (`turrets/TurretRailgun.as`, `RailLaser.as`); `docs/legacy/ENGINE_NOTES.md`
/// §2.2, §4.9, §4.10.
void main() {
  late GameData data;
  late SimTestHarness harness;
  setUpAll(() {
    data = loadClassicData();
    harness = SimTestHarness(data);
  });

  GameSession lyne() {
    final s = harness.session(const GameConfig(mapId: 'map9', mode: 'sandbox2', seed: 4))
      ..debugCash = 1e12;
    unlockAll(s);
    return s;
  }

  /// Sends a wave, keeps [n] creeps, toughens them and pauses the game.
  List<Creep> pausedCreeps(GameSession s, int n) {
    s.enqueue(const SendNextWave());
    while (s.creeps.length < n) {
      s.step();
    }
    s.waves.spawners.clear();
    toughen(s, 1e12);
    s
      ..enqueue(const SetPaused(true))
      ..step();
    return s.creeps.take(n).toList();
  }

  group('Sniper', () {
    test('hits its target the moment it fires, then the tracer goes', () {
      final s = lyne();
      final sniper = build(s, 'sniper', ComboBench.leaderAt);
      final creep = firstCreep(s);
      creep.hp = 1e12;
      TurretFired? shot;
      for (var i = 0; i < 6000 && shot == null; i++) {
        final before = creep.hp;
        shot = s.step().whereType<TurretFired>().where((e) => e.uid == sniper.uid).firstOrNull;
        if (shot != null) expect(before - creep.hp, 3000000);
      }
      expect(shot, isNotNull);
      expect(shot!.projectile, 'sniper-shot');
      expect(shot.target, creep.uid);
      final p = s.projectiles.singleWhere((p) => p.turretUid == sniper.uid);
      expect(p.lineTo, isNotNull);
      s.run(2);
      expect(s.projectiles.where((p) => p.turretUid == sniper.uid), isEmpty, reason: '32 ms');
    });

    test('never combos and is not modifiable', () {
      final s = lyne();
      final sniper = build(s, 'sniper', ComboBench.leaderAt);
      build(s, 'damage-up-big', ComboBench.ring[0]);
      expect(sniper.def.comboNever, isTrue);
      expect(s.statOf(sniper, StatKind.damage), 3000000);
      upgrade(s, sniper, StatKind.damage, 3);
      expect(s.statOf(sniper, StatKind.damage), 55000000);
      expect(s.statOf(sniper, StatKind.rate), 30);
    });
  });

  group('Railgun', () {
    test('distanceToSegment measures to the segment, ends included', () {
      const a = Vec2(0, 0);
      const b = Vec2(10, 0);
      expect(distanceToSegment(const Vec2(5, 3), a, b), 3);
      expect(distanceToSegment(const Vec2(-4, 3), a, b), 5);
      expect(distanceToSegment(const Vec2(13, 4), a, b), 5);
      expect(distanceToSegment(const Vec2(2, 2), a, a), closeTo(2.8284, 1e-4));
    });

    test('the beam runs 900 px from the fire point through the target', () {
      final s = lyne();
      final rail = build(s, 'railgun', ComboBench.leaderAt);
      final target = pausedCreeps(s, 1).single..position = const Vec2(427.5, 150);
      rail.rotation = 0;
      final p = s.turretFire(rail, target: target, damage: 4e6);
      expect(p.position, const Vec2(327.5, 150), reason: 'fire point 27.5 px along');
      expect(p.lineTo!.x, closeTo(327.5 + 900, 1e-9));
      expect(p.lineTo!.y, closeTo(150, 1e-9));
    });

    test('one pass 32 real ms later hits every creep within 20 px of the beam, paused too', () {
      final s = lyne();
      final rail = build(s, 'railgun', ComboBench.leaderAt);
      final creeps = pausedCreeps(s, 5);
      rail.rotation = 0;
      final spots = [
        const Vec2(427.5, 150), // the target
        const Vec2(700, 169), // 19 px off the line: hit
        const Vec2(700, 171), // 21 px off: missed
        const Vec2(308.5, 150), // 19 px behind the start (round cap): hit
        const Vec2(302.5, 150), // 25 px behind: missed
      ];
      for (var i = 0; i < creeps.length; i++) {
        creeps[i].position = spots[i];
      }
      s.debugClearProjectiles();
      final hp = [for (final c in creeps) c.hp];
      s.turretFire(rail, target: creeps[0], damage: 4e6);
      s.step();
      expect(creeps[0].hp, hp[0], reason: 'not before 32 ms');
      s.step();
      final dealt = [for (var i = 0; i < creeps.length; i++) hp[i] - creeps[i].hp];
      expect(dealt, [4e6, 4e6, 0, 4e6, 0]);
      s.run(10);
      expect(creeps[0].hp, hp[0] - 4e6, reason: 'one pass only');
      expect(s.projectiles, isNotEmpty, reason: 'the 125 ms visual is pausable');
      s
        ..enqueue(const SetPaused(false))
        ..run(9);
      expect(s.projectiles, isEmpty);
    });

    test('kills on the beam are credited to the railgun', () {
      final s = lyne();
      final rail = build(s, 'railgun', ComboBench.leaderAt);
      final creeps = pausedCreeps(s, 2);
      rail.rotation = 0;
      s.debugClearProjectiles();
      creeps[0]
        ..position = const Vec2(427.5, 150)
        ..hp = 10;
      creeps[1]
        ..position = const Vec2(600, 150)
        ..hp = 10;
      s.turretFire(rail, target: creeps[0], damage: 4e6);
      final killed = [...s.step(), ...s.step()].whereType<CreepKilled>().toList();
      expect(killed.map((k) => k.turret).toSet(), {rail.uid});
      expect(killed, hasLength(2));
      expect(rail.kills, 2);
    });

    test('fires its beam with the "tazer" sound at creeps in range', () {
      final s = lyne();
      final rail = build(s, 'railgun', ComboBench.leaderAt);
      expect(rail.def.fireSound, 'tazer');
      firstCreep(s);
      toughen(s, 1e12);
      final shot = stepUntil<TurretFired>(s, test: (e) => e.uid == rail.uid);
      expect(shot!.projectile, 'rail-laser');
    });
  });
}
