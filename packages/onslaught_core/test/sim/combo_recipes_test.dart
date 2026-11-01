import 'package:onslaught_core/onslaught_core.dart';
import 'package:test/test.dart';

import '../support/combo_bench.dart';
import '../support/repo_data.dart';

/// One scenario per combo recipe (`docs/legacy/ENGINE_NOTES.md` §1): the
/// leader fires it at a single toughened creep with its helpers holding
/// fire, and the test checks what spawned and the damage totals against the
/// recipe's data (no modifiers, so every value is the data value).
/// Maxed damage: Blue 46 000, Green 35 000, Red 65 000, Yellow 30 000
/// (poison 10).
void main() {
  late GameData data;
  setUpAll(() => data = loadClassicData());

  ComboBench bench(
    String leader,
    List<String> helpers, {
    RulesProfile profile = RulesProfile.classic,
    bool inRange = true,
  }) {
    final b = ComboBench(data, profile: profile)
      ..place(leader, helpers)
      ..spawnCreep();
    if (inRange) b.waitInRange();
    return b;
  }

  double v(String combo, String field) => data.combos[combo]!.values.number(field)!;

  group('Blue leader', () {
    test('clusterbomb: bomb, small blast, 6 cluster rockets', () {
      final b = bench('blue', ['red']);
      final p = b.fire('clusterbomb');
      expect(p.specId, 'cluster-bomb');
      expect(p.damage, v('clusterbomb', 'bulletDamage'));
      final fired = b.eventsOf<ComboFired>().single;
      expect(fired.helpers, [b.helpers.single.uid]);
      b.resolve();
      expect(b.blastsOf('blast-small').single.damage, 7e6);
      expect(b.blastsOf('blast-small').single.sound, 'blast-small');
      expect(b.blastsOf('cluster-rockets'), hasLength(1));
      expect(b.count('rocket-9'), 6);
      expect(b.damage, 5e6 + 7e6 + 6 * 3.3e6);
    });

    test('sparky-clusterbomb: small blast and 8 sparks of 0.8M, −20 each', () {
      final b = bench('blue', ['red', 'yellow']);
      b
        ..fire('sparky-clusterbomb')
        ..resolve();
      expect(b.blastsOf('blast-small').single.damage, 4.7e6);
      expect(b.blastsOf('cluster-sparks').single.sound, 'tazer');
      expect(b.count('spark'), 8);
      expect(b.damage, 5.5e6 + 4.7e6 + 8 * 0.8e6);
      expect(b.creep.speed, lessThan(b.creep.baseSpeed));
    });

    test('big-clusterbomb: large blast, 10 cluster rockets; takes both reds', () {
      final b = bench('blue', ['red', 'red']);
      b.fire('big-clusterbomb');
      expect(b.eventsOf<ComboFired>().single.helpers, unorderedEquals(b.helpers.map((h) => h.uid)));
      b.resolve();
      expect(b.blastsOf('blast-large').single.damage, 8e6);
      expect(b.count('rocket-9'), 10);
      expect(b.damage, 8e6 + 8e6 + 10 * 4.5e6);
    });

    test('laser-clusterbomb: the green pools into the cluster lasers', () {
      final b = bench('blue', ['red', 'green']);
      final p = b.fire('laser-clusterbomb');
      final green = b.helpers[1];
      // The green has no link neighbour: it pools 0, plus its own damage.
      expect(p.load!.cluster!.laserDamage, 0.7e6 + 35000);
      expect(p.load!.cluster!.laser, isTrue);
      expect(green.shots, 1, reason: 'the green fires its link shot at the leader');
      expect(b.eventsOf<ComboFired>().single.helpers, unorderedEquals(b.helpers.map((h) => h.uid)));
      b.resolve();
      expect(b.blastsOf('blast-medium').single.damage, 4e6);
      expect(b.count('rocket-9'), 5);
      final lasers = b.count('laser-beam') - 1; // minus the green's link shot
      expect(b.damage, 2e6 + 4e6 + 5 * 2e6 + lasers * (0.7e6 + 35000));
    });

    test('big-laser-clusterbomb: large blast, 5 laser cluster rockets', () {
      final b = bench('blue', ['red', 'red', 'green']);
      final p = b.fire('big-laser-clusterbomb');
      expect(p.load!.cluster!.laserDamage, 0.9e6 + 35000);
      expect(b.eventsOf<ComboFired>().single.helpers, hasLength(3));
      b.resolve();
      expect(b.count('rocket-9'), 5);
      final lasers = b.count('laser-beam') - 1;
      expect(b.damage, 4e6 + 6e6 + 5 * 2e6 + lasers * (0.9e6 + 35000));
    });

    test('landmine: thrown from the centre to a mine point in max range; blast only', () {
      final b = bench('blue', ['blue'], inRange: false);
      final p = b.fire('landmine');
      expect(p.specId, 'landmine');
      expect(p.position, b.leader.position);
      final place = p.load!.place!;
      expect(b.s.road.minePoints, contains(place));
      expect(place.distanceTo(b.leader.position), lessThanOrEqualTo(220));
      b.step();
      final st = p.state! as LandmineState;
      expect((st.to.x - place.x).abs(), lessThanOrEqualTo(5));
      expect((st.to.y - place.y).abs(), lessThanOrEqualTo(5));
      b.resolve(maxSteps: 6000);
      expect(b.blastsOf('blast-small').single.damage, 9e6);
      expect(b.damage, 9e6, reason: 'landmines deal no direct damage');
    });

    test('big-landmine: large blast', () {
      final b = bench('blue', ['red', 'blue'], inRange: false);
      expect(b.fire('big-landmine').specId, 'landmine-big');
      b.resolve(maxSteps: 6000);
      expect(b.blastsOf('blast-large').single.damage, 15e6);
      expect(b.damage, 15e6);
    });

    test('sparky-landmine: 8 sparks of the 1M default; also takes a ready red', () {
      final b = bench('blue', ['blue', 'yellow', 'red'], inRange: false);
      final p = b.fire('sparky-landmine');
      expect(p.load!.cluster!.damage, 1e6, reason: 'cluster_damage is never set: the raw default');
      expect(b.eventsOf<ComboFired>().single.helpers, hasLength(3));
      b.resolve(maxSteps: 6000);
      expect(b.blastsOf('blast-small').single.damage, 15e6);
      expect(b.count('spark'), 8);
      expect(b.damage, 15e6 + 8 * 1e6);
    });

    test('sparky-landmine without a red takes only blue and yellow', () {
      final b = bench('blue', ['blue', 'yellow'], inRange: false)..fire('sparky-landmine');
      expect(b.eventsOf<ComboFired>().single.helpers, hasLength(2));
    });

    test('big-cluster-landmine: large blast, 10 cluster rockets', () {
      final b = bench('blue', ['red', 'red', 'blue'], inRange: false);
      expect(b.fire('big-cluster-landmine').specId, 'landmine-big-cluster');
      b.resolve(maxSteps: 6000);
      expect(b.blastsOf('blast-large').single.damage, 15e6);
      expect(b.count('rocket-9'), 10);
      expect(b.damage, 15e6 + 10 * 4.5e6);
    });

    test('big-laser-cluster-landmine: no link pool, plain take of the green', () {
      final b = bench('blue', ['red', 'red', 'blue', 'green'], inRange: false);
      final p = b.fire('big-laser-cluster-landmine');
      expect(p.load!.cluster!.laserDamage, 1e6);
      expect(b.helpers[3].shots, 0, reason: 'no link shot');
      expect(b.eventsOf<ComboFired>().single.helpers, hasLength(4));
      b.resolve(maxSteps: 6000);
      expect(b.count('rocket-9'), 10);
      final lasers = b.count('laser-beam');
      expect(b.damage, 9e6 + 10 * 2e6 + lasers * 1e6);
    });
  });

  group('Red leader', () {
    test('nuke: 150 px/s holding rocket, huge 60M blast', () {
      final b = bench('red', ['blue', 'blue']);
      final p = b.fire('nuke');
      expect(p.specId, 'rocket-nuke');
      expect(p.load!.speed, 150);
      expect(RocketState.of(p).holdingCapable, isTrue);
      b.resolve();
      final blast = b.blastsOf('blast-huge').single;
      expect(blast.damage, 60e6);
      expect(blast.sound, 'blast-large');
      expect(b.damage, 9e6 + 60e6);
    });

    test('napalm: hits with the leader damage; 16 silent 1M drops (classic)', () {
      final b = bench('red', ['red', 'yellow', 'blue']);
      final p = b.fire('napalm');
      expect(p.damage, 65000, reason: 'bullet_damage is not set: the leader damage');
      expect(p.load!.speed, isNull);
      b.resolve();
      expect(b.blastsOf('blast-napalm').single.sound, isNull);
      final drops = b.blastsOf('blast-tiny');
      expect(drops, hasLength(16));
      expect(drops.every((d) => d.damage == 1e6 && d.sound == null), isTrue);
      final fromDrops = b.damage - 65000;
      expect(fromDrops, greaterThan(0));
      expect(fromDrops % 1e6, 0);
    });

    test('napalm drops use the combo blast damage under napalmUsesComboDamage', () {
      final b = bench('red', ['red', 'yellow', 'blue'], profile: RulesProfile.classicFixed)
        ..fire('napalm')
        ..resolve();
      expect(b.blastsOf('blast-tiny').every((d) => d.damage == 2.5e6), isTrue);
    });

    test('poison-rocket: raw 100 blast that halves the speed', () {
      final b = bench('red', ['blue', 'green']);
      final p = b.fire('poison-rocket');
      expect(p.load!.blast!.poison, 2);
      b.resolve();
      expect(b.blastsOf('blast-poison').single.damage, 100);
      expect(b.damage, 1000 + 100);
      expect(b.minSpeed, b.creep.baseSpeed / 2);
    });

    test('tazer-rocket: sparks carry the yellow helper poison', () {
      final b = bench('red', ['yellow']);
      final p = b.fire('tazer-rocket');
      expect(p.poison, 10, reason: 'the yellow helper poison (maxed: 10)');
      expect(p.load!.laser!.projectile, 'spark');
      expect(p.load!.laser!.range, 200);
      expect(p.load!.laser!.intervalMs, 500);
      expect(b.eventsOf<ComboFired>().single.helpers, [b.helpers.single.uid]);
      b.resolve();
      final sparks = b.count('spark');
      expect(b.damage, 2e6 + sparks * 2e6);
    });

    test('laser-rocket: the green pool goes to the hit and the lasers; no laser blast', () {
      final b = bench('red', ['green']);
      final p = b.fire('laser-rocket');
      expect(p.damage, 2e6 + 35000);
      expect(p.load!.laser!.damage, 2e6 + 35000);
      expect(p.load!.laserBlast, isNull);
      b.resolve();
      final lasers = b.count('laser-beam') - 1;
      expect(b.damage, (2e6 + 35000) * (1 + lasers));
    });

    test('laser-rocket fires its laser blast under laserRocketLaserBlast', () {
      final b = bench('red', ['green'], profile: RulesProfile.classicFixed);
      final p = b.fire('laser-rocket');
      expect(p.load!.laserBlast!.qty, 6);
      expect(p.load!.laserBlast!.damage, 1e6, reason: 'copied raw');
      b.resolve();
      // Minus the green's link shot and the laser blast's one beam (one creep).
      final inFlight = b.count('laser-beam') - 2;
      expect(b.damage, (2e6 + 35000) * (1 + inFlight) + 1e6);
    });
  });

  group('Green leader', () {
    test('bfg: straight 60 px/s orb with lasers; its own empty link pool adds 0', () {
      final b = bench('green', ['red', 'blue']);
      final p = b.fire('bfg');
      expect(p.specId, 'bfg');
      expect(p.damage, 5.8e6);
      expect(p.load!.laser!.damage, 4.2e6);
      expect(p.load!.laser!.range, 250);
      expect(p.load!.laser!.intervalMs, closeTo(333.33, 0.01));
      expect(RocketState.of(p).holdingCapable, isTrue);
      expect(b.leader.shots, 1, reason: 'linkFire(self, 0) shoots a 0-damage laser');
      b.resolve();
      final lasers = b.count('laser-beam') - 1;
      final hit = b.blastsOf('blast-bfg').length;
      expect(b.damage, hit * (5.8e6 + 7.5e6) + lasers * 4.2e6);
      expect(lasers, greaterThan(0));
    });

    test('rocket-bfg: needs two reds, takes one; fires sub-rockets', () {
      final b = bench('green', ['red', 'red', 'blue']);
      final p = b.fire('rocket-bfg');
      expect(p.load!.subRocket!.projectile, 'rocket-9');
      expect(p.load!.subRocket!.intervalMs, 500);
      expect(b.eventsOf<ComboFired>().single.helpers, hasLength(2));
      b.resolve();
      final lasers = b.count('laser-beam') - 1;
      final rockets = b.count('rocket-9');
      final hit = b.blastsOf('blast-bfg').length;
      expect(rockets, greaterThan(0));
      expect(b.damage, hit * (6.5e6 + 7.5e6) + lasers * 4.5e6 + rockets * 2e6);
    });

    test('bfg adds the leader link pool when it has link neighbours', () {
      final b = ComboBench(data)..place('green', ['red', 'blue', 'green']);
      // The helper green (60° spot, 45 px) is within the leader's 100 px link range.
      b
        ..spawnCreep()
        ..waitInRange();
      for (final t in b.s.turrets) {
        t.firedAtMs = -1e9; // offered
      }
      b.s.step();
      for (final t in b.s.turrets) {
        t.firedAtMs = -1e9;
      }
      final p = ComboSpecial.fireRecipe(b.s, b.leader, data.combos['bfg']!, b.creep, {
        'red': [b.helpers[0]],
        'blue': [b.helpers[1]],
      });
      // Pool = own 35 000 + 1.25 × the helper's 35 000.
      expect(p.damage, 5.8e6 + 35000 + 1.25 * 35000);
    });
  });

  group('Yellow leader', () {
    test('blackhole: opens on a hole point and swallows the creep, no cash or kill', () {
      final b = bench('yellow', ['yellow', 'yellow', 'green']);
      final cash = b.s.cash;
      final p = b.fire('blackhole');
      expect(p.specId, 'black-hole');
      expect(b.eventsOf<ComboFired>().single.sound, 'black-hole');
      expect(b.eventsOf<BlackHoleOpened>(), hasLength(1));
      expect(p.position.distanceTo(b.leader.position), lessThanOrEqualTo(90));
      expect(p.load!.hole!.radius, 120);
      b.resolve();
      expect(b.eventsOf<CreepSwallowed>().single.uid, b.creep.uid);
      expect(b.s.kills, 0);
      expect(b.s.cash, cash);
      expect(b.damage, 0);
    });

    test('shockwave: spark slows to the floor, blast at the target, one walker (classic)', () {
      final b = bench('yellow', ['yellow', 'blue', 'green']);
      final p = b.fire('shockwave');
      final link = 35000.0;
      expect(p.specId, 'spark');
      expect(p.poison, 100);
      expect(b.creep.speed, data.rules.slowFloor);
      final blast = b.blastsOf('blast-shockwave').single;
      expect(blast.damage, 1e6 + link);
      expect(b.s.walkers, hasLength(1));
      expect(b.s.walkers.single.direction, 1);
      b.resolve();
      expect(b.damage, greaterThan(2 * (1e6 + link)));
    });

    test('shockwave sends both walkers under shockwaveBothWalkers', () {
      final b = bench('yellow', ['yellow', 'blue', 'green'], profile: RulesProfile.classicFixed)
        ..fire('shockwave');
      expect(b.s.walkers.map((w) => w.direction), [1, -1]);
    });

    test('tazer-bfg: sparks carry the leader poison as a whole number', () {
      final b = bench('yellow', ['red', 'blue']);
      final p = b.fire('tazer-bfg');
      expect(p.specId, 'bfg-tazer');
      expect(p.poison, 10);
      expect(p.load!.laser!.projectile, 'spark');
      b.resolve();
      final sparks = b.count('spark');
      final hit = b.blastsOf('blast-bfg').length;
      expect(b.damage, hit * (5.8e6 + 7.5e6) + sparks * 4.2e6);
    });
  });

  test('every recipe has a scenario here', () {
    expect(data.combos, hasLength(20));
  });
}
