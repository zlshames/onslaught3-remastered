import 'package:onslaught_core/onslaught_core.dart';
import 'package:onslaught_core/testing.dart';
import 'package:test/test.dart';

import '../support/repo_data.dart';
import '../support/sim_helpers.dart';

void main() {
  late GameData data;
  late SimTestHarness harness;
  late TurretDef green;
  setUpAll(() {
    data = loadClassicData();
    harness = SimTestHarness(data);
    green = data.turrets['green']!;
  });

  /// Lyne (map9): road (0, 0) → (590, 410). Three spots 50 px off the road,
  /// 60 px apart along it: A–B and B–C are within Green's 100 px range,
  /// A–C (120 px) is not. Creeps reach A first.
  const a = Vec2(205, 82);
  const b = Vec2(254.3, 116.2);
  const c = Vec2(303.6, 150.4);

  GameSession lyne() =>
      harness.session(const GameConfig(mapId: 'map9', seed: 9, profile: RulesProfile.classic))
        ..debugCash = 1e6;

  /// Sends a wave and steps until the first non-assist shot; returns the
  /// shot, the events of that step and the creep's HP before it.
  (TurretFired, List<GameEvent>, double) firstShot(GameSession s) {
    s.enqueue(const SendNextWave());
    for (var i = 0; i < 6000; i++) {
      toughen(s);
      final hpBefore = {for (final c in s.creeps) c.uid: c.hp};
      final events = s.step();
      final lead = events.whereType<TurretFired>().where((e) => !e.assist).firstOrNull;
      if (lead != null) return (lead, events, hpBefore[lead.target]!);
    }
    fail('no shot');
  }

  test('Green data (TurretGreen ctor)', () {
    expect(green.cost, 15);
    expect([green.stats.damage, green.stats.range, green.stats.rate], [25, 100, 60]);
    expect(green.stats.mustFace, isTrue);
    expect(green.projectiles, ['laser-beam']);
    expect(green.specials, containsAll(['link', 'combo']));
    expect(green.specialParams['link']!.number('mult'), 1.25);
    expect(data.projectiles['laser-beam']!.params.number('fadeMs'), 350);
  });

  test('a lone Green hits instantly and its beam fades after 350 ms', () {
    final s = lyne();
    final t = build(s, 'green', a);
    final (shot, events, hpBefore) = firstShot(s);
    expect(shot.uid, t.uid);
    expect(shot.silent, isFalse);
    final creep = s.creepByUid(shot.target!)!;
    // Hit on the step it was fired: 25 damage, poison ignored.
    expect(hpBefore - creep.hp, 25);
    expect(creep.speed, creep.baseSpeed);
    final beam = s.projectiles.single;
    expect(beam.specId, 'laser-beam');
    expect(beam.lineTo, isNotNull);
    final firedAt = s.clock.nowMs;
    while (s.clock.nowMs - firedAt < 350 - 1e-6) {
      expect(s.projectiles.where((p) => p.uid == beam.uid), isNotEmpty);
      s.step();
    }
    s.step();
    expect(s.projectiles.where((p) => p.uid == beam.uid), isEmpty);
  });

  test('two reloaded Greens pool: leader + 1.25 × helper, helper fires into the leader', () {
    final s = lyne();
    final ta = build(s, 'green', a);
    final tb = build(s, 'green', b);
    final (shot, events, hpBefore) = firstShot(s);
    final leader = shot.uid == ta.uid ? ta : tb;
    final helper = leader == ta ? tb : ta;
    final assist = events.whereType<TurretFired>().where((e) => e.assist).single;
    expect(assist.uid, helper.uid);
    expect(assist.silent, isTrue, reason: 'pooling helpers fire without sound');
    expect(assist.target, isNull);
    expect(shot.silent, isFalse);
    // The helper's beam is drawn to the leader and hurts nothing (it
    // carries the helper's own damage, as `linkFire` passes it).
    final helperBeam = s.projectiles.firstWhere((p) => p.turretUid == helper.uid);
    expect(helperBeam.lineTo, leader.position);
    expect(helperBeam.targetUid, isNull);
    expect(helperBeam.damage, 25);
    // Pool: 25 + 1.25 × 25.
    final creep = s.creepByUid(shot.target!)!;
    expect(hpBefore - creep.hp, 25 + 1.25 * 25);
    // The helper spent its reload and turned to face the leader.
    expect(helper.firedAtMs, s.clock.nowMs);
    expect(helper.rotation, closeTo(bearingDeg(helper.position, leader.position), 1e-9));
    expect(LinkSpecial.stateOf(leader).led, 1);
    expect(LinkSpecial.stateOf(helper).assisted, 1);
    expect(LinkSpecial.stateOf(leader).lastDamage, 56.25);
    // Both shots count.
    expect(s.shots, 2);
  });

  test('chains compound 1.25 per depth through each helper\'s own neighbours', () {
    final s = lyne();
    final ta = build(s, 'green', a);
    final tb = build(s, 'green', b);
    final tc = build(s, 'green', c);
    final (shot, events, hpBefore) = firstShot(s);
    final assists = events.whereType<TurretFired>().where((e) => e.assist).toList();
    expect(assists, hasLength(2));
    final creep = s.creepByUid(shot.target!)!;
    final pooled = hpBefore - creep.hp;
    if (shot.uid == ta.uid) {
      // A ← B ← C: C helps B (A is 120 px from C), B helps A.
      expect(pooled, 25 + 1.25 * (25 + 1.25 * 25));
    } else if (shot.uid == tb.uid) {
      expect(pooled, 25 + 1.25 * 25 + 1.25 * 25);
    } else {
      expect(shot.uid, tc.uid);
      expect(pooled, 25 + 1.25 * (25 + 1.25 * 25));
    }
  });

  test('link range is each Green\'s own effective range (asymmetric)', () {
    final s = lyne();
    // A with range 125 reaches a Green 105 px away; that Green (range 100)
    // does not reach A and has no other neighbour, so as a helper it pools
    // nothing: it fires 0 at A, with sound, and spends its reload.
    final ta = build(s, 'green', a);
    upgrade(s, ta, StatKind.range, 2);
    expect(s.statOf(ta, StatKind.range), 125);
    final far = a + const Vec2(105, 0);
    final tf = build(s, 'green', far);
    expect(LinkSpecial.neighbours(s, ta), [tf]);
    expect(LinkSpecial.neighbours(s, tf), isEmpty);
    final (shot, events, hpBefore) = firstShot(s);
    final creep = s.creepByUid(shot.target!);
    if (shot.uid == ta.uid) {
      final assist = events.whereType<TurretFired>().where((e) => e.assist).single;
      expect(assist.uid, tf.uid);
      expect(assist.silent, isFalse);
      expect(hpBefore - creep!.hp, 25);
      expect(tf.firedAtMs, s.clock.nowMs);
    } else {
      expect(events.whereType<TurretFired>().where((e) => e.assist), isEmpty);
      expect(hpBefore - creep!.hp, 25);
    }
  });

  test('pooled damage uses each turret\'s effective (modified) damage', () {
    final s = lyne();
    unlockAll(s);
    final ta = build(s, 'green', a);
    final tb = build(s, 'green', b);
    // Damage Enhancer 50 px from A and from B: both ×1.4.
    build(s, 'damage-up', const Vec2(252.4, 66.2));
    expect(s.statOf(ta, StatKind.damage), 35);
    expect(s.statOf(tb, StatKind.damage), 35);
    final (shot, _, hpBefore) = firstShot(s);
    final creep = s.creepByUid(shot.target!)!;
    expect(hpBefore - creep.hp, closeTo(35 + 1.25 * 35, 1e-9));
  });

  test('a helper that has not reloaded is not used', () {
    final s = lyne();
    final ta = build(s, 'green', a);
    final tb = build(s, 'green', b);
    // B fired just now (as far as its reload goes), so it cannot help.
    tb.firedAtMs = 1e9;
    // Its offer is refreshed on its updates (the first tick, 70 ms after the
    // build, does nothing).
    s.run(12);
    expect(LinkSpecial.stateOf(tb).offered, isFalse);
    final (shot, events, hpBefore) = firstShot(s);
    expect(shot.uid, ta.uid);
    expect(events.whereType<TurretFired>().where((e) => e.assist), isEmpty);
    expect(hpBefore - s.creepByUid(shot.target!)!.hp, 25);
  });
}
