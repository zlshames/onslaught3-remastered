import 'dart:math' as math;

import 'package:onslaught_core/onslaught_core.dart';
import 'package:onslaught_core/testing.dart';
import 'package:test/test.dart';

import '../support/repo_data.dart';
import '../support/sim_helpers.dart';

void main() {
  late GameData data;
  late SimTestHarness harness;
  late TurretDef red;
  setUpAll(() {
    data = loadClassicData();
    harness = SimTestHarness(data);
    red = data.turrets['red']!;
  });

  /// Lyne (map9): road (0, 0) → (590, 410); (300, 150) is 48 px from it.
  const spot = Vec2(300, 150);

  GameSession lyne({RulesProfile profile = RulesProfile.classic}) =>
      harness.session(GameConfig(mapId: 'map9', seed: 4, profile: profile))..debugCash = 1e6;

  /// A Red with its holding pattern unlocked (range 3, rate 3).
  Turret holdingRed(GameSession s, {Vec2 at = spot}) {
    final t = build(s, 'red', at);
    upgrade(s, t, StatKind.range, 3);
    upgrade(s, t, StatKind.rate, 3);
    return t;
  }

  test('Red data (TurretRed ctor)', () {
    expect(red.cost, 20);
    expect([red.stats.damage, red.stats.range, red.stats.rate], [50, 200, 50]);
    expect(red.stats.mustFace, isFalse);
    expect(red.firePoints, hasLength(4));
    final p = red.specialParams['holding']!;
    expect(
      [
        p.number('maxRockets'),
        p.number('levelDamage'),
        p.number('levelRange'),
        p.number('levelRate'),
        p.number('sellTargetRange'),
      ],
      [4, 0, 3, 3, 720],
    );
    final rocket = data.projectiles['rocket-1']!.params;
    expect(
      [
        rocket.number('speed'),
        rocket.number('turnRate'),
        rocket.number('impactRadius'),
        rocket.number('acquireRange'),
      ],
      [250, 270, 8, 1000],
    );
    expect(red.projectileAtLevel(0), 'rocket-1');
    expect(red.projectileAtLevel(2), 'rocket-2');
    expect(red.projectileAtLevel(9), 'rocket-9');
  });

  test('rockets home in and deal their damage on impact, credited to the Red', () {
    final s = lyne();
    final t = build(s, 'red', spot);
    s.enqueue(const SendNextWave());
    final fired = stepUntil<TurretFired>(s)!;
    final rocket = s.projectiles.single;
    expect(rocket.specId, 'rocket-1');
    expect(rocket.damage, 50);
    expect(RocketState.of(rocket).holdingCapable, isFalse);
    // Wave 1 creeps have 13 HP on easy: the impact kills.
    final killed = stepUntil<CreepKilled>(s, maxSteps: 600)!;
    expect(killed.uid, fired.target);
    expect(killed.turret, t.uid);
    expect(t.kills, 1);
    expect(s.projectiles.where((p) => p.uid == rocket.uid), isEmpty);
  });

  test('the holding pattern unlocks at range level 3 and rate level 3', () {
    final s = lyne();
    final t = build(s, 'red', spot);
    upgrade(s, t, StatKind.range, 3);
    upgrade(s, t, StatKind.rate, 2);
    expect(HoldingSpecial.stateOf(t).pattern, isFalse);
    upgrade(s, t, StatKind.rate);
    expect(HoldingSpecial.stateOf(t).pattern, isTrue);
  });

  test('with no target it fills up to 4 held rockets, one per reload', () {
    final s = lyne();
    final t = holdingRed(s);
    final reloadMs = fireIntervalMs(s.statOf(t, StatKind.rate));
    expect(reloadMs, closeTo(60000 / 85, 1e-9));
    final shots = <(int, TurretFired)>[];
    for (var i = 0; i < 600; i++) {
      for (final e in s.step().whereType<TurretFired>()) {
        shots.add((i, e));
      }
    }
    expect(shots, hasLength(4));
    expect(shots.every((e) => e.$2.target == null), isTrue);
    expect(HoldingSpecial.stateOf(t).held, hasLength(4));
    for (final p in s.projectiles) {
      expect(RocketState.of(p).holdingInitially, isTrue);
      expect(RocketState.of(p).holdingCapable, isTrue);
    }
    // Consecutive fills are one reload apart, plus the wait for the Red's
    // next 70 ms update tick (ticks land on steps: at most five apart).
    for (var i = 1; i < shots.length; i++) {
      final gapMs = (shots[i].$1 - shots[i - 1].$1) * 1000 / data.rules.tickHz;
      expect(gapMs, inInclusiveRange(reloadMs, reloadMs + 5 * 1000 / data.rules.tickHz));
    }
  });

  test('held rockets circle with radius speed / turn rate (≈ 53 px)', () {
    final s = lyne();
    holdingRed(s);
    s.run(60); // the first held rocket is out (one reload, 706 ms)
    final rocket = s.projectiles.first;
    var minX = double.infinity, maxX = -double.infinity;
    var minY = double.infinity, maxY = -double.infinity;
    // One full turn at 270 °/s takes 1.33 s.
    for (var i = 0; i < 90; i++) {
      s.step();
      minX = math.min(minX, rocket.position.x);
      maxX = math.max(maxX, rocket.position.x);
      minY = math.min(minY, rocket.position.y);
      maxY = math.max(maxY, rocket.position.y);
    }
    const radius = 250 / (270 * math.pi / 180);
    expect(radius, closeTo(53.05, 0.01));
    expect((maxX - minX) / 2, closeTo(radius, 0.5));
    expect((maxY - minY) / 2, closeTo(radius, 0.5));
  });

  test('when a target appears every held rocket is sent at it', () {
    final s = lyne();
    final t = holdingRed(s);
    s.run(600);
    final held = [...HoldingSpecial.stateOf(t).held];
    expect(held, hasLength(4));
    s.enqueue(const SendNextWave());
    final fired = stepUntil<TurretFired>(s, test: (e) => e.target != null)!;
    expect(HoldingSpecial.stateOf(t).held, isEmpty);
    for (final uid in held) {
      final p = s.projectileByUid(uid)!;
      expect(RocketState.of(p).holdingInitially, isFalse);
      expect(p.targetUid, fired.target);
    }
    // Rockets fired once the pattern is on may circle when they lose their target.
    expect(RocketState.of(s.projectileByUid(s.projectiles.last.uid)!).holdingCapable, isTrue);
  });

  test('selling sends held rockets at the weakest creep within 720 px', () {
    final s = lyne();
    // Near the road's far end, out of reach of the first creeps.
    final t = holdingRed(s, at: const Vec2(550, 330));
    s.run(600);
    final held = [...HoldingSpecial.stateOf(t).held];
    expect(held, hasLength(4));
    // Creeps on the road, out of the Red's range: one hurt.
    s.enqueue(const SendNextWave());
    s.run(200);
    expect(s.creeps.length, greaterThan(1));
    final weakest = s.creeps.first..hp = 1;
    s.enqueue(SellTurret(t.uid));
    s.step();
    for (final uid in held) {
      final p = s.projectileByUid(uid)!;
      expect(RocketState.of(p).holdingInitially, isFalse);
      expect(p.targetUid, weakest.uid);
    }
  });

  test('a rocket with no target and no holding flies straight and leaves the stage', () {
    final s = lyne();
    final t = build(s, 'red', spot);
    t.rotation = 0;
    final p = s.turretFire(t, damage: 50);
    final startX = p.position.x;
    s.step();
    expect(RocketState.of(p).offscreenRemove, isTrue);
    final heading = p.heading;
    var steps = 0;
    while (!p.done && steps < 600) {
      s.step();
      steps++;
      expect(p.heading, heading);
    }
    expect(p.done, isTrue);
    // Removed once past 720 + its width (20 px), flying at 250 px/s.
    expect(steps * 1000 / data.rules.tickHz, closeTo((740 - startX) / 250 * 1000, 40));
    expect(p.position.x, greaterThan(740));
  });

  group('holdingRocketLifetime (docs/DEVIATIONS.md)', () {
    /// No shipped profile turns the lifetime on (owner decision 2026-10-21:
    /// circling rockets wait forever, as in the original); this profile does,
    /// so the code behind the toggle stays tested.
    const c = RulesProfile.classicFixed;
    final withLifetime = RulesProfile(
      id: 'test-holding-lifetime',
      napalmUsesComboDamage: c.napalmUsesComboDamage,
      poisonRocketModified: c.poisonRocketModified,
      laserRocketLaserBlast: c.laserRocketLaserBlast,
      landmineBulletDamage: c.landmineBulletDamage,
      blackHoleDirtyKills: c.blackHoleDirtyKills,
      shockwaveCredit: c.shockwaveCredit,
      holdingRocketLifetime: true,
      blackHoleGameClock: c.blackHoleGameClock,
      tutorialWaveLimit: c.tutorialWaveLimit,
      challengePickerData: c.challengePickerData,
      inGameSpeedButton: c.inGameSpeedButton,
      tapEmptyDeselects: c.tapEmptyDeselects,
      freakoutAutoStart: c.freakoutAutoStart,
      shockwaveBothWalkers: c.shockwaveBothWalkers,
      continueAfterWin: c.continueAfterWin,
      customGamesSeparate: c.customGamesSeparate,
      enhancedSkin: c.enhancedSkin,
    );

    Projectile orbiting(GameSession s) {
      final t = holdingRed(s);
      // A pattern rocket that lost its target circles where it is.
      final p = s.turretFire(t, damage: 50);
      expect(RocketState.of(p).holdingCapable, isTrue);
      expect(RocketState.of(p).holdingInitially, isFalse);
      return p;
    }

    for (final profile in RulesProfile.all) {
      test('${profile.id}: it circles forever with no target', () {
        expect(profile.holdingRocketLifetime, isFalse);
        final s = lyne(profile: profile);
        final p = orbiting(s);
        s.run(60 * 19);
        expect(p.done, isFalse);
        final since = RocketState.of(p).orbitSinceMs!;
        // Past where the old 20 s lifetime would have removed it, with no
        // creep on the map to find (waves are stopped from spawning).
        while (s.clock.nowMs - since < 30000) {
          s.waves.spawners.clear();
          s.step();
          expect(p.targetUid, isNull);
          expect(p.done, isFalse);
        }
        expect(s.projectiles, contains(p));
      });
    }

    /// A Red holding its 4 rockets, consumed by a Combonly plate (as a nuke
    /// with two Blues); returns the held rocket uids once it is gone.
    List<int> consumedRedRockets(GameSession s) {
      const plateAt = Vec2(200, 300);
      Vec2 ring(int i) =>
          plateAt + Vec2(math.cos(i * 2 * math.pi / 5), math.sin(i * 2 * math.pi / 5)) * 55;
      final plate = build(s, 'combonly', plateAt);
      for (final i in [0, 1]) {
        upgrade(
          s,
          build(s, 'blue', ring(i)),
          StatKind.damage,
          data.turrets['blue']!.upgrades.damage.length,
        );
      }
      final t = holdingRed(s, at: ring(2));
      upgrade(s, t, StatKind.damage, red.upgrades.damage.length);
      s.run(600);
      final held = [...HoldingSpecial.stateOf(t).held];
      expect(held, hasLength(4));
      final st = CombonlySpecial.stateOf(plate);
      for (var i = 0; i < 60 * 10 && st.shown != 'red'; i++) {
        s.step();
      }
      expect(st.shown, 'red');
      s.enqueue(ChooseCombonly(plate.uid));
      final consumed = stepUntil<TurretConsumed>(s, test: (e) => e.uid == t.uid, maxSteps: 600);
      expect(consumed, isNotNull);
      expect(s.turretByUid(t.uid), isNull);
      for (final uid in held) {
        expect(s.projectileByUid(uid), isNotNull, reason: 'still circling when consumed');
      }
      return held;
    }

    GameSession plateGame(RulesProfile profile) {
      final s = harness.session(
        GameConfig(mapId: 'map9', mode: 'sandbox2', seed: 4, profile: profile),
      )..debugCash = 1e12;
      for (final id in s.data.turrets.keys) {
        s.debugMakeAvailable(id);
      }
      return s;
    }

    test('classic: a consumed Red\'s held rockets circle forever', () {
      final s = plateGame(RulesProfile.classic);
      final held = consumedRedRockets(s);
      s.run(60 * 25);
      for (final uid in held) {
        final p = s.projectileByUid(uid);
        expect(p, isNotNull);
        expect(RocketState.of(p!).holdingInitially, isTrue);
      }
    });

    test('with the lifetime: a consumed Red\'s held rockets are let go and expire', () {
      final s = plateGame(withLifetime);
      final held = consumedRedRockets(s);
      for (final uid in held) {
        final rs = RocketState.of(s.projectileByUid(uid)!);
        expect(rs.holdingInitially, isFalse);
        expect(rs.orbitSinceMs, s.clock.nowMs);
      }
      s.run(60 * 25);
      for (final uid in held) {
        expect(s.projectileByUid(uid), isNull);
      }
    });

    test('with the lifetime: it is removed after 20 s of circling', () {
      final s = lyne(profile: withLifetime);
      final p = orbiting(s);
      s.run(60 * 19);
      expect(p.done, isFalse);
      s.run(60 * 1 + 2);
      expect(s.projectiles, isNot(contains(p)));
    });
  });
}
