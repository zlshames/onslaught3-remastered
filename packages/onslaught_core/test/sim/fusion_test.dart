import 'package:onslaught_core/onslaught_core.dart';
import 'package:onslaught_core/testing.dart';
import 'package:test/test.dart';

import '../support/combo_bench.dart';
import '../support/repo_data.dart';
import '../support/sim_helpers.dart';

/// The Fusion cannon (`turrets/TurretFusion.as`; `docs/legacy/ENGINE_NOTES.md`
/// §4.7).
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

  const fusionAt = ComboBench.leaderAt;

  /// Spots far from the road (no creep comes in range of a Green or Yellow)
  /// but within the Fusion's 300 px.
  const quiet = [Vec2(420, 40), Vec2(470, 80), Vec2(520, 120), Vec2(380, 80)];

  Creep onlyCreep(GameSession s) {
    final c = firstCreep(s)..hp = 1e12;
    s.waves.spawners.clear();
    return c;
  }

  Iterable<TurretFired> feeds(Iterable<GameEvent> events, Turret fusion) =>
      events.whereType<TurretFired>().where((e) => e.into == fusion.uid);

  test('Greens and Yellows in range feed it one shot per update; it stores 1.15×', () {
    final s = lyne();
    final fusion = build(s, 'fusion', fusionAt);
    final green = build(s, 'green', quiet[0]);
    final yellow = build(s, 'yellow', quiet[1]);
    final blue = build(s, 'blue', quiet[2]);
    final far = build(s, 'green', const Vec2(690, 300));
    expect(far.position.distanceTo(fusion.position), greaterThan(300));
    final events = <List<GameEvent>>[];
    for (var i = 0; i < 300; i++) {
      events.add(s.step());
    }
    final fed = [for (final e in events) ...feeds(e, fusion)];
    expect(fed.map((e) => e.uid).toSet(), {green.uid, yellow.uid});
    for (final step in events) {
      expect(feeds(step, fusion).length, lessThanOrEqualTo(1), reason: 'one feeder per update');
    }
    expect(fed.every((e) => !e.silent), isTrue, reason: 'feeders fire with sound');
    expect(blue.shots, 0);
    final greens = fed.where((e) => e.uid == green.uid).length;
    final yellows = fed.where((e) => e.uid == yellow.uid).length;
    final st = FusionSpecial.stateOf(fusion);
    expect(st.storeDamage, closeTo(1.15 * (25 * greens + 50 * yellows), 1e-6));
    expect(st.storePoison, closeTo(1.15 * 1 * yellows, 1e-9), reason: 'lasers carry no poison');
    expect(st.fed, greens + yellows);
    expect(fed.map((e) => e.projectile).toSet(), {'laser-beam', 'spark'});
  });

  test('it keeps its feeder list until a pass finds none ready', () {
    final s = lyne();
    final fusion = build(s, 'fusion', fusionAt);
    final green = build(s, 'green', quiet[0]);
    stepUntil<TurretFired>(s, test: (e) => e.into == fusion.uid);
    final st = FusionSpecial.stateOf(fusion);
    expect(st.feeders, [green.uid]);
    final yellow = build(s, 'yellow', quiet[1]);
    // Its next pass goes through [green] only: green is reloading, so none
    // fires and the list is dropped, though the new yellow is ready.
    while (fusion.updatedAtMs != s.clock.nowMs) {
      expect(feeds(s.step(), fusion), isEmpty);
    }
    expect(st.feeders, isNull);
    final next = stepUntil<TurretFired>(s, test: (e) => e.into == fusion.uid, maxSteps: 10);
    expect(next?.uid, yellow.uid);
    expect(st.feeders, [yellow.uid, green.uid], reason: 'newest first');
  });

  test('it discharges min(damage, store) + damage with up to 100 stored poison', () {
    final s = lyne();
    final fusion = build(s, 'fusion', fusionAt);
    final built = fusion.firedAtMs;
    final st = FusionSpecial.stateOf(fusion)
      ..storeDamage = 500000
      ..storePoison = 150;
    final creep = onlyCreep(s);
    final before = creep.hp;
    final shot = stepUntil<TurretFired>(s, test: (e) => e.uid == fusion.uid);
    expect(shot!.projectile, 'spark');
    expect(s.clock.nowMs - built, greaterThan(6000), reason: 'store time from its build');
    expect(before - creep.hp, 1500000);
    expect(creep.speed, s.data.rules.slowFloor, reason: '100 poison, subtracted');
    expect(st.storeDamage, 0);
    expect(st.storePoison, 50);
    final second = stepUntil<TurretFired>(s, test: (e) => e.uid == fusion.uid);
    expect(second, isNotNull, reason: 'it fires even with an empty store');
    expect(before - creep.hp, 2500000);
    expect(st.storePoison, 0);
  });

  test('glow tiers by stored damage', () {
    final p = data.turrets['fusion']!.specialParams['fusion']!;
    FusionTier? tier(double units) => FusionSpecial.tierOf(p, units * 500000);
    expect(tier(0), FusionTier.none);
    expect(tier(0.5), isNull, reason: 'under one unit: no change');
    expect(tier(1), FusionTier.low);
    expect(tier(79.9), FusionTier.low);
    expect(tier(80), FusionTier.med);
    expect(tier(160), FusionTier.high);
    expect(tier(239), FusionTier.high);
    expect(tier(240), FusionTier.max);
    expect(tier(10000), FusionTier.max);
  });

  test('its discharge sounds by its glow tier', () {
    final s = lyne();
    final fusion = build(s, 'fusion', fusionAt);
    FusionSpecial.stateOf(fusion).storeDamage = 80 * 500000.0;
    onlyCreep(s);
    final shot = stepUntil<TurretFired>(s, test: (e) => e.uid == fusion.uid);
    expect(shot!.sound, 'fusion-med');
    expect(FusionSpecial.stateOf(fusion).pulse, isA<bool>());
  });

  test('turning without facing ends its update early, so it turns faster and faster', () {
    final s = lyne();
    final fusion = build(s, 'fusion', fusionAt);
    final creep = onlyCreep(s);
    while (creep.position.distanceTo(fusion.position) > 290) {
      s.step();
    }
    fusion.rotation = normalizeRotation(bearingDeg(fusion.position, creep.position) + 180);
    final start = s.clock.nowMs;
    final pinned = fusion.updatedAtMs;
    var faced = false;
    for (var i = 0; i < 120 && !faced; i++) {
      s.step();
      final off = normalizeRotation(bearingDeg(fusion.position, creep.position) - fusion.rotation);
      faced = off.abs() < 1;
      if (!faced) expect(fusion.updatedAtMs, pinned, reason: '`time_last` is not moved on');
    }
    expect(faced, isTrue);
    // 180° at 90 °/s takes 2 s; with the growing steps it takes under 0.7 s.
    expect(s.clock.nowMs - start, lessThan(700));
  });

  test('a Targeter joined to it makes it discharge without the 6 s wait', () {
    final s = lyne();
    final fusion = build(s, 'fusion', fusionAt);
    final targeter = build(s, 'targeter', ComboBench.ring[0]);
    s.enqueue(JoinTurret(targeter.uid, fusion.uid));
    s.step();
    final creep = onlyCreep(s);
    while (creep.position.distanceTo(targeter.position) > 110) {
      s.step();
    }
    fusion.firedAtMs = s.clock.nowMs;
    final reset = s.clock.nowMs;
    final shot = stepUntil<TurretFired>(s, test: (e) => e.uid == fusion.uid, maxSteps: 340);
    expect(shot, isNotNull);
    expect(s.clock.nowMs - reset, inInclusiveRange(2000, 6000));
  });
}
