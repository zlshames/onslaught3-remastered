import 'package:onslaught_core/onslaught_core.dart';
import 'package:onslaught_core/testing.dart';
import 'package:test/test.dart';

import '../support/repo_data.dart';
import '../support/sim_helpers.dart';

void main() {
  late GameData data;
  late SimTestHarness harness;
  late TurretDef yellow;
  setUpAll(() {
    data = loadClassicData();
    harness = SimTestHarness(data);
    yellow = data.turrets['yellow']!;
  });

  /// Lyne (map9): road (0, 0) → (590, 410); (300, 150) is 48 px from it,
  /// inside Yellow's 70 px range.
  const spot = Vec2(300, 150);

  GameSession lyne() =>
      harness.session(const GameConfig(mapId: 'map9', seed: 6, profile: RulesProfile.classic))
        ..debugCash = 1e6;

  test('Yellow data (TurretYellow ctor)', () {
    expect(yellow.cost, 50);
    expect([yellow.stats.damage, yellow.stats.range, yellow.stats.rate], [50, 70, 60]);
    expect(yellow.stats.poison, 1);
    expect(yellow.stats.rotate, 720);
    expect(yellow.stats.mustFace, isFalse);
    expect(yellow.defaultTargetMode, 'fast');
    expect(yellow.lockOff, isTrue);
    expect(yellow.projectiles, ['spark']);
    final p = yellow.specialParams['charge']!;
    expect(
      [
        p.number('base'),
        p.number('rateBase'),
        p.number('cost'),
        p.number('poisonMax'),
        p.number('maxPerDamageLevel'),
        p.number('ratePerRateLevel'),
        p.number('poisonBoost'),
      ],
      [100, 10, 50, 10, 10, 2, 3],
    );
    expect(data.projectiles['spark']!.params.number('fadeMs'), 400);
  });

  test('base poison scales with the damage track: max(1, 10 × floor(level / 7 × 100) / 100)', () {
    final s = lyne();
    final t = build(s, 'yellow', spot);
    final poisons = [t.poison];
    for (var level = 1; level <= 7; level++) {
      upgrade(s, t, StatKind.damage);
      poisons.add(t.poison);
    }
    expect(poisons, [1, 1.4, 2.8, 4.2, 5.7, 7.1, 8.5, 10].map((v) => closeTo(v, 1e-9)).toList());
    // Range and rate upgrades also re-run it (onUpgrade) without changing it.
    upgrade(s, t, StatKind.rate);
    expect(t.poison, 10);
  });

  test('charge grows by 10 + 2 × rate level per second up to 100 + 10 × damage level', () {
    final s = lyne();
    final t = build(s, 'yellow', spot);
    final state = ChargeSpecial.stateOf(t);
    // It charges on its updates (70 ms ticks), from the second tick on.
    s.run(10);
    final (c0, at0) = (state.charge, t.updatedAtMs!);
    s.run(300);
    expect(state.charge - c0, closeTo(10 * (t.updatedAtMs! - at0) / 1000, 1e-6));
    s.run(600);
    expect(state.charge, 100);
    upgrade(s, t, StatKind.damage, 2);
    expect(ChargeSpecial.maxCharge(t), 120);
    upgrade(s, t, StatKind.rate, 3);
    expect(ChargeSpecial.chargeRate(t), 16);
    final (c1, at1) = (state.charge, t.updatedAtMs!);
    s.run(60);
    expect(state.charge, closeTo(c1 + 16 * (t.updatedAtMs! - at1) / 1000, 1e-6));
    s.run(120);
    expect(state.charge, 120);
  });

  test('a charged shot adds 3 × charge/100 to the poison, then uses 50 charge', () {
    final s = lyne();
    final t = build(s, 'yellow', spot);
    final state = ChargeSpecial.stateOf(t);
    s.enqueue(const SendNextWave());
    TurretFired? shot;
    var speedBefore = 0.0;
    for (var i = 0; i < 6000 && shot == null; i++) {
      toughen(s);
      final speeds = {for (final c in s.creeps) c.uid: c.speed};
      final hps = {for (final c in s.creeps) c.uid: c.hp};
      shot = s.step().whereType<TurretFired>().firstOrNull;
      if (shot != null) {
        speedBefore = speeds[shot.target]!;
        final creep = s.creepByUid(shot.target!)!;
        expect(hps[shot.target]! - creep.hp, 50, reason: 'damage is not boosted');
      }
    }
    final creep = s.creepByUid(shot!.target!)!;
    // Several seconds of charge were stored (more than the 50 a shot uses).
    final atFire = state.charge + 50;
    expect(atFire, greaterThan(50));
    expect(speedBefore, 60);
    expect(creep.speed, closeTo(60 - (1 + 3 * atFire / 100), 1e-9));
    expect(state.shownDamage, closeTo(50 * (1 + atFire / 100), 1e-9));
    // Lock off: the target is dropped after the shot.
    expect(t.targetUid, isNull);
  });

  test('with no charge stored the shot carries the plain poison', () {
    final s = lyne();
    final t = build(s, 'yellow', spot);
    final creep = firstCreep(s);
    toughen(s);
    ChargeSpecial.stateOf(t).charge = -1e9; // nothing stored, even after this step's gain
    s.turretFire(t, target: creep, damage: 50);
    expect(creep.speed, 60 - 1);
  });

  test('sparks slow by subtraction, never below 5 px/s', () {
    final s = lyne();
    final creep = firstCreep(s)..speed = 6;
    final t = build(s, 'yellow', spot);
    final p = s.addProjectile(
      specId: 'spark',
      kind: 'spark',
      position: t.position,
      heading: 0,
      damage: 1,
      targetUid: creep.uid,
      turretUid: t.uid,
      poison: 4,
    );
    s.launchProjectile(p);
    expect(creep.speed, 5);
    expect(creep.hp, creep.hpStart - 1);
    expect(p.lineTo, creep.position);
  });

  test('slowed creeps regain 2 px/s every 1000 ms, up to their spawn speed', () {
    final s = lyne();
    final creep = firstCreep(s);
    s.slowCreep(creep, 10, subtract: true);
    expect(creep.speed, 50);
    final slowedAt = s.clock.nowMs;
    expect(creep.recoverAtMs, slowedAt + 1000);
    final changes = <(double, double)>[];
    var last = creep.speed;
    for (var i = 0; i < 60 * 7; i++) {
      s.step();
      if (creep.speed != last) {
        changes.add((s.clock.nowMs - slowedAt, creep.speed));
        last = creep.speed;
      }
    }
    expect(changes.map((c) => c.$2), [52, 54, 56, 58, 60]);
    for (var i = 0; i < changes.length; i++) {
      expect(changes[i].$1, closeTo((i + 1) * 1000, 1000 / data.rules.tickHz + 1e-6));
    }
    expect(creep.recoverAtMs, isNull);
  });

  test('blast-style slows divide (attackerPoison without minus)', () {
    final s = lyne();
    final creep = firstCreep(s);
    s.slowCreep(creep, 2, subtract: false);
    expect(creep.speed, 30);
    s.slowCreep(creep, 75, subtract: false);
    expect(creep.speed, 5);
  });

  test('a slow re-plans the leg at the new speed toward a freshly jittered point', () {
    final s = lyne();
    final creep = firstCreep(s);
    s.run(20);
    final draws = s.random.draws;
    final waypoint = s.road.points[creep.waypoint];
    s.slowCreep(creep, 30, subtract: true);
    expect(s.random.draws, draws + 2);
    expect(creep.legFrom, creep.position);
    expect(creep.legDurationMs, closeTo(creep.position.distanceTo(waypoint) / 30 * 1000, 1e-6));
  });
}
