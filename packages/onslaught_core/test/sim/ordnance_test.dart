import 'package:onslaught_core/onslaught_core.dart';
import 'package:test/test.dart';

import '../support/combo_bench.dart';
import '../support/repo_data.dart';

/// Blasts, slows, black holes, shockwave walkers and the cluster bomb
/// (`docs/legacy/ENGINE_NOTES.md` §2.2, §3).
void main() {
  late GameData data;
  setUpAll(() => data = loadClassicData());

  ComboBench bench(
    String leader,
    List<String> helpers, {
    RulesProfile profile = RulesProfile.classic,
  }) => ComboBench(data, profile: profile)
    ..place(leader, helpers)
    ..spawnCreep()
    ..waitInRange();

  Blast blastAt(ComboBench b, String spec, {double damage = 1e6, double poison = 1}) =>
      b.s.spawnBlast(
        specId: spec,
        at: b.creep.position,
        damage: damage,
        poison: poison,
        turretUid: b.leader.uid,
      );

  test('the blast table (BlastEngine.blastSetup, blasts/*)', () {
    final table = {
      'blast-tiny': [60, 70, 1500],
      'blast-small': [70, 100, 1500],
      'blast-medium': [80, 160, 1750],
      'blast-large': [80, 190, 2000],
      'blast-huge': [90, 250, 2500],
      'blast-poison': [80, 190, 2500],
      'blast-bfg': [80, 190, 2500],
      'blast-shockwave': [105, 200, 2500],
    };
    table.forEach((id, row) {
      final p = data.blasts[id]!.params;
      expect([p.number('growMs'), p.number('diameter'), p.number('fadeMs')], row, reason: id);
      expect(p.number('startSize'), 10, reason: id);
    });
    for (final c in data.combos.values) {
      final blast = c.blast;
      if (blast != null) expect(data.blasts, contains(blast), reason: c.id);
      final cluster = c.cluster;
      if (cluster != null) expect(data.blasts[cluster]!.kind, startsWith('cluster-'), reason: c.id);
    }
  });

  test('a blast grows, deals its damage once at full size within d/2, then fades', () {
    final b = bench('blue', []);
    final blast = blastAt(b, 'blast-medium');
    expect(blast.size, 10);
    final growSteps = (80 / (1000 / 60)).ceil();
    for (var i = 0; i < growSteps - 1; i++) {
      b.step();
      expect(b.damage, 0);
    }
    expect(blast.size, greaterThan(10));
    b.step();
    expect(blast.size, 160);
    expect(b.damage, 1e6);
    b.resolve();
    expect(b.damage, 1e6, reason: 'once, no falloff');
    expect(b.s.blasts, isEmpty);
  });

  test('a blast misses creeps beyond half its diameter', () {
    final b = bench('blue', []);
    b.s.spawnBlast(
      specId: 'blast-small',
      at: b.creep.position - const Vec2(0.8211, 0.5708) * 60, // behind it, on the road
      damage: 1e6,
      poison: 1,
      turretUid: null,
    );
    b.resolve();
    expect(b.damage, 0);
  });

  group('slows', () {
    test('blasts divide the speed by their poison, down to the 5 px/s floor', () {
      final b = bench('blue', []);
      final base = b.creep.speed;
      blastAt(b, 'blast-poison', poison: 2);
      b.resolve();
      expect(b.minSpeed, base / 2);
      final c = ComboBench(data)
        ..place('blue', [])
        ..spawnCreep()
        ..waitInRange();
      blastAt(c, 'blast-shockwave', poison: 75);
      c.resolve();
      expect(c.minSpeed, data.rules.slowFloor);
    });

    test('a slowed creep recovers 2 px/s every second up to its speed', () {
      final b = bench('blue', []);
      final base = b.creep.speed;
      blastAt(b, 'blast-poison', poison: 2);
      b.resolve();
      final slowed = b.creep.speed;
      for (var i = 0; i < 60; i++) {
        b.step();
      }
      expect(b.creep.speed, closeTo(slowed + data.rules.slowRecoverAmount, 1e-9));
      for (var i = 0; i < 60; i++) {
        b.step();
      }
      expect(b.creep.speed, closeTo(slowed + 2 * data.rules.slowRecoverAmount, 1e-9));
      expect(b.creep.speed, lessThan(base));
    });
  });

  group('black hole', () {
    /// Opens a black hole [ahead] px down the road from the creep, so the
    /// creep is caught near the edge and pulled for a while.
    Projectile openHole(ComboBench b, {double ahead = 150}) {
      final p =
          b.s.addProjectile(
              specId: 'black-hole',
              kind: 'black-hole',
              position: Vec2.zero,
              heading: 0,
              damage: 0,
              targetUid: null,
              turretUid: b.leader.uid,
            )
            ..load = Ordnance(
              combo: 'blackhole',
              place: b.creep.position + const Vec2(0.8211, 0.5708) * ahead,
              hole: const HoleLoad(radius: 120, durationMs: 3000),
            );
      b.s.launchProjectile(p);
      return p;
    }

    void stepUntilCaught(ComboBench b) {
      for (var i = 0; i < 600 && !b.creep.blackHoled; i++) {
        b.step();
      }
      expect(b.creep.blackHoled, isTrue);
    }

    test('a caught creep loses its bounty and is pulled in at 500 px/s', () {
      final b = bench('blue', []);
      final bounty = b.creep.bounty;
      final hole = openHole(b);
      stepUntilCaught(b);
      final cap = b.creep.capture!;
      expect(b.creep.bounty, 0);
      expect(b.creep.bountyBeforeHole, bounty);
      expect(cap.durationMs, closeTo(cap.from.distanceTo(hole.position) / 500 * 1000, 1e-9));
      expect(cap.from.distanceTo(hole.position), lessThanOrEqualTo(120));
      expect(cap.from.distanceTo(hole.position), greaterThan(60));
    });

    test('a black-holed creep stays targetable but ignores hits and slows', () {
      final b = bench('blue', []);
      b.creep.blackHoled = true;
      final hp = b.creep.hp;
      final speed = b.creep.speed;
      b.s
        ..hitCreep(b.creep, 1e6, by: b.leader.uid)
        ..slowCreep(b.creep, 50, subtract: true);
      expect(b.creep.hp, hp);
      expect(b.creep.speed, speed);
      expect(b.creep.targetable, isTrue);
      expect(
        acquireTarget(
          creeps: b.s.creeps,
          from: b.leader.position,
          range: 1000,
          mode: 'near',
          nowMs: b.s.clock.nowMs,
        ),
        b.creep,
      );
    });

    test('it opens after 200 ms and closes after its duration plus 200 ms', () {
      final b = bench('blue', [], profile: RulesProfile.classicFixed);
      final p = openHole(b);
      final st = p.state! as BlackHoleState;
      final steps = <BlackHoleStage, int>{};
      var i = 0;
      while (!p.done && i < 1000) {
        b.step();
        i++;
        steps.putIfAbsent(st.stage, () => i);
      }
      expect(steps[BlackHoleStage.open]!, closeTo(12, 1));
      expect(steps[BlackHoleStage.closing]!, closeTo(180, 13), reason: '3000 ms, at a 200 ms scan');
      expect(i, closeTo(192, 13));
    });

    test('classic: the pull runs on real time and goes on while paused', () {
      final b = bench('blue', []);
      openHole(b);
      stepUntilCaught(b);
      b.s.enqueue(const SetPaused(true));
      b.step();
      final cap = b.creep.capture!;
      final before = cap.elapsedMs;
      b.step();
      expect(cap.elapsedMs, closeTo(before + 1000 / 60, 1e-9));
    });

    test('blackHoleGameClock: the pull stops while paused', () {
      final b = bench('blue', [], profile: RulesProfile.classicFixed);
      openHole(b);
      stepUntilCaught(b);
      b.s.enqueue(const SetPaused(true));
      b.step();
      final cap = b.creep.capture!;
      final before = cap.elapsedMs;
      b
        ..step()
        ..step();
      expect(cap.elapsedMs, before);
    });

    test('the swallowed creep is removed with no kill, cash or credit', () {
      final b = bench('blue', []);
      final cash = b.s.cash;
      openHole(b);
      b.resolve();
      expect(b.eventsOf<CreepSwallowed>().single.uid, b.creep.uid);
      expect(b.s.creeps, isEmpty);
      expect([b.s.kills, b.s.cash, b.leader.kills], [0, cash, 0]);
    });

    test('it catches rockets and blasts in its square box, not instant shots', () {
      final b = bench('blue', []);
      final hole = openHole(b, ahead: 400);
      Projectile shot(String spec, Vec2 at) => b.s.addProjectile(
        specId: spec,
        kind: data.projectiles[spec]!.kind,
        position: at,
        heading: 0,
        damage: 1,
        targetUid: null,
        turretUid: null,
      );
      // A landmine in the box corner, 141 px out: outside the radius.
      final corner = hole.position + const Vec2(100, 100);
      final mine = shot('landmine', corner)..load = Ordnance(combo: 'landmine', place: corner);
      b.s.launchProjectile(mine);
      final rocket = shot('rocket-1', hole.position + const Vec2(40, -50))
        ..state = (RocketState()
          ..holdingCapable = true
          ..holdingInitially = true);
      final beam = shot('laser-beam', hole.position + const Vec2(10, 10))..lineTo = hole.position;
      final blast = b.s.spawnBlast(
        specId: 'blast-small',
        at: hole.position + const Vec2(-110, 0),
        damage: 1,
        poison: 1,
        turretUid: null,
      );
      for (var i = 0; i < 13; i++) {
        b.step();
      }
      expect(mine.capture, isNotNull);
      expect(rocket.capture, isNotNull);
      expect(beam.capture, isNull);
      expect(blast.capture, isNotNull);
      b.resolve();
      expect(b.s.projectiles, isEmpty);
    });
  });

  group('shockwave walkers', () {
    test('walk the road at 150 px/s and fade over 3 s; no turret credit (classic)', () {
      final b = bench('yellow', ['yellow', 'blue', 'green'])..fire('shockwave');
      final w = b.s.walkers.single;
      final start = w.position;
      // Lyne is one leg: the walker leaves at its end or after 3 s.
      final endMs = start.distanceTo(b.s.road.points.last) / 150 * 1000;
      final lifeMs = endMs < 3000 ? endMs : 3000.0;
      b.step();
      expect(w.position.distanceTo(start), closeTo(150 / 60, 0.05));
      var steps = 1;
      while (b.s.walkers.isNotEmpty) {
        b.step();
        steps++;
      }
      expect(steps, closeTo(lifeMs / (1000 / 60), 1));
      expect(w.zaps, closeTo(lifeMs / 32, 1), reason: 'every 32 ms');
      expect(b.eventsOf<CreepKilled>().where((k) => k.turret != null), isEmpty);
    });

    test('a zap deals f × damage and slows by f × poison, f = 1 − age / 3000', () {
      final b = bench('blue', []);
      final speed = b.creep.speed;
      b.s.spawnBlast(
        specId: 'blast-shockwave',
        at: b.creep.position,
        damage: 3000,
        poison: 3,
        turretUid: b.leader.uid,
        targetUid: b.creep.uid,
      );
      final w = b.s.walkers.single;
      while (w.zaps == 0) {
        b.step();
      }
      // The first zap, 32 ms in; the blast itself lands at 105 ms.
      const f = 1 - 32 / 3000;
      expect(b.damage, closeTo(f * 3000, 1e-6));
      expect(b.creep.speed, closeTo(speed - f * 3, 1e-9));
      expect(b.s.kills, 0);
    });

    test('shockwaveCredit credits the leader with walker kills', () {
      for (final profile in [RulesProfile.classic, RulesProfile.classicFixed]) {
        final b = bench('blue', [], profile: profile);
        b.creep.hp = 1;
        b.s.spawnBlast(
          specId: 'blast-shockwave',
          at: b.creep.position,
          damage: 3000,
          poison: 3,
          turretUid: b.leader.uid,
          targetUid: b.creep.uid,
        );
        while (b.s.kills == 0) {
          b.step();
        }
        final killed = b.eventsOf<CreepKilled>().single;
        expect(killed.turret, profile.shockwaveCredit ? b.leader.uid : null, reason: profile.id);
      }
    });
  });

  test('a cluster bomb within 3 px hits every step without exploding', () {
    final b = bench('blue', ['red']);
    final p = b.fire('clusterbomb');
    p.position = b.creep.position + const Vec2(1, 0);
    b.creep.position = p.position + const Vec2(1, 0);
    final before = b.damage;
    b.s.step();
    expect(b.damage - before, p.damage);
    expect(p.done, isFalse);
  });

  test('a landmine with no mine point in range is a dud', () {
    final s = ComboBench(data).s;
    // Far corner of Lyne: no road within Blue's 220 px max range.
    final leader = maxed(s, 'blue', const Vec2(60, 440));
    final helper = maxed(s, 'blue', const Vec2(105, 440));
    expect(ComboSpecial.minePoints(s, leader), isEmpty);
    s.enqueue(const SendNextWave());
    while (s.creeps.isEmpty) {
      s.step();
    }
    final p = ComboSpecial.fireRecipe(s, leader, data.combos['landmine']!, s.creeps.first, {
      'blue': [helper],
    });
    expect(p.done, isTrue);
  });
}
