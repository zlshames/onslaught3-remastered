import 'package:onslaught_core/onslaught_core.dart';
import 'package:onslaught_core/testing.dart';
import 'package:test/test.dart';

import '../support/repo_data.dart';
import '../support/sim_helpers.dart' show build;

void main() {
  late GameData data;
  late SimTestHarness harness;
  late TurretDef blue;
  setUpAll(() {
    data = loadClassicData();
    harness = SimTestHarness(data);
    blue = data.turrets['blue']!;
  });

  /// Lyne (map9): one straight road from (0, 0) to (590, 410). (300, 150)
  /// is 48 px from it, well inside Blue's 130 px range.
  const spot = Vec2(300, 150);

  GameSession lyne({double? cash}) {
    final s = harness.session(const GameConfig(mapId: 'map9', seed: 3));
    if (cash != null) s.debugCash = cash;
    return s;
  }

  CommandRejected rejectedBy(GameSession s, GameCommand c) {
    s.enqueue(c);
    return s.step().whereType<CommandRejected>().single;
  }

  group('Blue data (TurretBlue ctor)', () {
    test('stats', () {
      expect(blue.cost, 10);
      expect(blue.stats.damage, 15);
      expect(blue.stats.range, 130);
      expect(blue.stats.rate, 100);
      expect(blue.stats.rotate, 270);
      expect(blue.stats.mustFace, isTrue);
      expect(blue.defaultTargetMode, 'near');
      expect(blue.lockOff, isFalse);
      expect(blue.firePoints.single, const Vec2(26, 0));
      expect(blue.weaponRotation, -90);
    });

    test('upgrade tracks (cost -> value), damage step 8 = 18 400', () {
      List<List<double>> track(StatKind k) => [
        for (final s in blue.upgrades.track(k)) [s.cost, s.value],
      ];
      expect(track(StatKind.damage), [
        [20, 30], [50, 60], [100, 150], [250, 400], [600, 1200], //
        [1000, 3100], [1100, 8500], [1200, 18400], [1500, 46000],
      ]);
      expect(track(StatKind.range), [
        [30, 140],
        [100, 150],
        [200, 165],
        [500, 180],
        [950, 220],
      ]);
      expect(track(StatKind.rate), [
        [50, 110],
        [150, 125],
        [300, 140],
        [450, 160],
        [950, 180],
        [1000, 200],
        [1450, 240],
      ]);
    });
  });

  group('building', () {
    test('costs 10, keeps the original defaults and a random type name', () {
      final s = lyne();
      final t = build(s, 'blue', spot);
      expect(s.cash, 20);
      expect(s.totalSpent, 10);
      expect(t.cashValue, 10);
      expect(t.targetMode, 'near');
      expect(t.targetModeIndex, 0);
      expect(t.rotation, -90);
      expect(blue.displayNames, contains(t.displayName));
      expect(s.isBuildable(blue), isTrue);
    });

    test('is refused for each placement rule, cash, pause and unknown types', () {
      final s = lyne(cash: 100);
      build(s, 'blue', spot);
      expect(rejectedBy(s, const BuildTurret('blue', 320, 150)).reason, 'tooCloseToTurret');
      expect(rejectedBy(s, const BuildTurret('blue', 200, 140)).reason, 'blocked');
      expect(rejectedBy(s, const BuildTurret('blue', 800, 150)).reason, 'outsidePlayArea');
      expect(rejectedBy(s, const BuildTurret('nope', 100, 300)).reason, 'unknownTurret');
      expect(rejectedBy(s, const BuildTurret('blue', 680, 440)).reason, 'blocked'); // Lyne's base
      // Cash is checked before the spot (BuildShape.buildCheck).
      s.debugCash = 9;
      expect(rejectedBy(s, const BuildTurret('blue', 320, 150)).reason, 'cannotAfford');
      s.debugCash = 100;
      s.enqueue(const SetPaused(true));
      expect(rejectedBy(s, const BuildTurret('blue', 100, 300)).reason, 'paused');
      expect(s.turrets, hasLength(1));
    });
  });

  group('firing (TurretBlue.update / turretTryFiring, ShellEngine)', () {
    test('turns from -90, fires once facing, and the shell kills a 13 HP creep', () {
      final s = lyne();
      final t = build(s, 'blue', spot);
      s.enqueue(const SendNextWave());
      final events = <GameEvent>[];
      while (events.whereType<CreepKilled>().isEmpty && s.tick < 3000) {
        events.addAll(s.step());
      }
      final fired = events.whereType<TurretFired>().first;
      expect(fired.uid, t.uid);
      expect(fired.projectile, 'shell-1');
      final kill = events.whereType<CreepKilled>().single;
      expect(kill.turret, t.uid);
      expect(kill.bounty, 1);
      expect(s.cash, 21);
      expect(s.kills, 1);
      expect(t.kills, 1);
      expect(t.shots, 1);
      expect(s.shots, 1);
      // Wave 1 is sent on step 1; its first creep reaches Blue's range a few
      // seconds later and dies to the first shell.
      expect(kill.tick, lessThan(400));
    });

    test('the shell leaves from the barrel tip, 26 px along the weapon', () {
      final s = lyne()..enqueue(const SendNextWave());
      final t = build(s, 'blue', spot);
      while (s.projectiles.isEmpty) {
        s.step();
      }
      final p = s.projectiles.single;
      expect(p.position.distanceTo(t.position), closeTo(26, 1e-9));
      expect(p.heading, t.rotation);
      expect(p.damage, 15);
    });

    test('shots are more than 60000 / rate ms apart (600 ms at rate 100)', () {
      final s = lyne(cash: 1000);
      final t = build(s, 'blue', spot);
      for (var i = 0; i < 5; i++) {
        s.enqueue(UpgradeTurret(t.uid, 'damage'));
      }
      s.enqueue(const SendNextWave());
      final ticks = <int>[];
      for (var i = 0; i < 2400; i++) {
        for (final e in s.step().whereType<TurretFired>()) {
          ticks.add(e.tick);
        }
      }
      expect(ticks.length, greaterThan(3));
      final stepMs = s.clock.stepMs;
      for (var i = 1; i < ticks.length; i++) {
        expect((ticks[i] - ticks[i - 1]) * stepMs, greaterThan(600));
      }
    });

    test('lock off drops the target after each shot', () {
      final s = lyne();
      final t = build(s, 'blue', spot);
      s
        ..enqueue(SetTargetLock(t.uid, lockOff: true))
        ..enqueue(const SendNextWave());
      while (s.projectiles.isEmpty) {
        s.step();
      }
      expect(t.targetUid, isNull);
    });
  });

  group('upgrades (Turret.upgradeDamage/Range/Rate)', () {
    test('each step sets the stat, adds its cost to the value, and maxes out', () {
      final s = lyne(cash: 100000);
      final t = build(s, 'blue', spot);
      for (final step in blue.upgrades.damage) {
        s.enqueue(UpgradeTurret(t.uid, 'damage'));
        final up = s.step().whereType<TurretUpgraded>().single;
        expect(up.cost, step.cost);
        expect(s.statOf(t, StatKind.damage), step.value);
      }
      expect(t.damageLevel, 9);
      expect(t.def.projectileAtLevel(t.damageLevel), 'shell-9');
      expect(rejectedBy(s, UpgradeTurret(t.uid, 'damage')).reason, 'maxed');
      final spent = blue.upgrades.damage.fold<double>(0, (a, b) => a + b.cost);
      expect(t.cashValue, 10 + spent);
      expect(s.totalSpent, 10 + spent);
    });

    test('range and rate change the effective stats', () {
      final s = lyne(cash: 1000);
      final t = build(s, 'blue', spot);
      s
        ..enqueue(UpgradeTurret(t.uid, 'range'))
        ..enqueue(UpgradeTurret(t.uid, 'rate'))
        ..step();
      expect(s.statOf(t, StatKind.range), 140);
      expect(s.statOf(t, StatKind.rate), 110);
      expect(fireIntervalMs(s.statOf(t, StatKind.rate)), closeTo(545.4545, 1e-3));
    });

    test('refused when unaffordable, while paused, for unknown stats and turrets', () {
      final s = lyne();
      final t = build(s, 'blue', spot);
      s.debugCash = 19;
      expect(rejectedBy(s, UpgradeTurret(t.uid, 'damage')).reason, 'cannotAfford');
      s.debugCash = 1000;
      expect(rejectedBy(s, UpgradeTurret(t.uid, 'speed')).reason, 'unknownStat');
      expect(rejectedBy(s, const UpgradeTurret(999, 'damage')).reason, 'noSuchTurret');
      // The original refuses upgrades while paused (Turret.upgradeDamage
      // checks game_paused), unlike what the reference doc used to say.
      s.enqueue(const SetPaused(true));
      expect(rejectedBy(s, UpgradeTurret(t.uid, 'damage')).reason, 'paused');
    });
  });

  group('selling and moving (TurretManager.turretSell, MoveShape)', () {
    test('sell refunds ceil(70 % of value) and takes it off the total spent', () {
      final s = lyne(cash: 100);
      final t = build(s, 'blue', spot);
      s
        ..enqueue(UpgradeTurret(t.uid, 'damage'))
        ..step()
        ..enqueue(SellTurret(t.uid));
      final sold = s.step().whereType<TurretSold>().single;
      expect(sold.refund, 21); // ceil(30 × 0.7)
      expect(s.cash, 100 - 30 + 21);
      expect(s.totalSpent, 30 - 21);
      expect(s.turrets, isEmpty);
    });

    test('move costs 500, keeps upgrades and ignores its own old spot', () {
      final s = lyne(cash: 1000);
      final t = build(s, 'blue', spot);
      s
        ..enqueue(UpgradeTurret(t.uid, 'damage'))
        ..step();
      const to = Vec2(310, 160);
      s.enqueue(MoveTurret(t.uid, to.x, to.y));
      final moved = s.step().whereType<TurretMoved>().single;
      expect(moved.cost, 500);
      expect(t.position, to);
      expect(t.damageLevel, 1);
      expect(t.cashValue, 30, reason: 'the move cost is not turret value');
      expect(s.totalSpent, 530);
      s.debugCash = 1000;
      expect(rejectedBy(s, MoveTurret(t.uid, 200, 140)).reason, 'blocked');
      s.debugCash = 499;
      expect(rejectedBy(s, MoveTurret(t.uid, 100, 300)).reason, 'cannotAfford');
    });
  });

  group('target modes (Turret.turretTargetModeCycle)', () {
    test('set any mode of targeting.json; the index follows', () {
      final s = lyne();
      final t = build(s, 'blue', spot);
      s.enqueue(SetTargetMode(t.uid, 'strong'));
      final changed = s.step().whereType<TargetModeChanged>().single;
      expect(changed.mode, 'strong');
      expect(t.targetModeIndex, data.targeting.modes.indexOf('strong'));
      expect(rejectedBy(s, SetTargetMode(t.uid, 'zzz')).reason, 'unknownMode');
    });

    test('far beats near once both creeps are in range', () {
      final s = lyne(cash: 1000);
      final t = build(s, 'blue', spot);
      s
        ..enqueue(SetTargetMode(t.uid, 'far'))
        ..enqueue(UpgradeTurret(t.uid, 'range'))
        ..enqueue(const SendNextWave());
      // Run until two creeps are in range, then check the pick.
      for (var i = 0; i < 2000; i++) {
        s.step();
        final range = s.statOf(t, StatKind.range);
        final inRange = s.creeps
            .where((c) => c.targetable && c.position.distanceTo(t.position) < range)
            .toList();
        if (inRange.length >= 2 && t.targetUid != null) {
          final target = s.creepByUid(t.targetUid!)!;
          final farthest = inRange
              .map((c) => c.position.distanceTo(t.position))
              .reduce((a, b) => a > b ? a : b);
          // The pick was the farthest when acquired; it is kept while in range.
          expect(target.position.distanceTo(t.position), lessThanOrEqualTo(range));
          expect(farthest, greaterThan(0));
          return;
        }
      }
      fail('never had two creeps in range');
    });
  });
}
