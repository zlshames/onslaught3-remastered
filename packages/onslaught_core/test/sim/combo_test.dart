import 'package:onslaught_core/onslaught_core.dart';
import 'package:onslaught_core/testing.dart';
import 'package:test/test.dart';

import '../support/combo_bench.dart';
import '../support/repo_data.dart';
import '../support/sim_helpers.dart';

/// Combo mechanics shared by every recipe (`Turret.comboActivate`,
/// `comboCanFire`, `comboCountColours`, `comboTake`, `comboFired`, each
/// colour's `comboFire`; `docs/legacy/ENGINE_NOTES.md` §1.0).
void main() {
  late GameData data;
  late SimTestHarness harness;
  setUpAll(() {
    data = loadClassicData();
    harness = SimTestHarness(data);
  });

  GameSession lyne({RulesProfile profile = RulesProfile.classic}) {
    final s = harness.session(GameConfig(mapId: 'map9', mode: 'sandbox', seed: 4, profile: profile))
      ..debugCash = 1e12;
    unlockAll(s);
    return s;
  }

  test('combos come first among each colour\'s specials', () {
    for (final id in ['blue', 'green', 'red', 'yellow']) {
      expect(data.turrets[id]!.specials.first, 'combo', reason: id);
    }
    expect(data.turrets['yellow']!.specialParams['combo']!.boolean('bearToLeader'), isFalse);
    expect(data.turrets['red']!.specialParams['combo']!.boolean('bearToLeader'), isTrue);
  });

  test('a turret can combo once its damage track is fully bought', () {
    final s = lyne();
    final t = build(s, 'blue', ComboBench.leaderAt);
    final track = t.def.upgrades.damage.length;
    upgrade(s, t, StatKind.damage, track - 1);
    s.run(60);
    expect(ComboSpecial.canCombo(s, t), isFalse);
    upgrade(s, t, StatKind.damage);
    s.run(60);
    expect(ComboSpecial.canCombo(s, t), isTrue);
  });

  test('the neighbourhood is every combo turret within 70 px; modifiers never combo', () {
    final s = lyne();
    final t = build(s, 'blue', ComboBench.leaderAt);
    final near = build(s, 'red', ComboBench.ring[0]);
    final mod = build(s, 'damage-up', ComboBench.ring[2]);
    final far = build(s, 'green', ComboBench.leaderAt + const Vec2(0.5708, -0.8211) * 71);
    final n = ComboSpecial.neighbours(s, t);
    expect(n, contains(near));
    expect(n, isNot(contains(mod)));
    expect(n, isNot(contains(far)));
    expect(mod.def.comboNever, isTrue);
  });

  test('a helper counts only when it may combo itself: capable, reloaded, recharged', () {
    final s = lyne();
    final t = maxed(s, 'blue', ComboBench.leaderAt);
    final weak = build(s, 'red', ComboBench.ring[0]);
    final red = maxed(s, 'red', ComboBench.ring[1]);
    s.run(120);
    expect(ComboSpecial.readyHelpers(s, t), {
      'red': [red],
    });
    expect(weak, isNot(isIn(ComboSpecial.readyHelpers(s, t)['red']!)));
    red.firedAtMs = s.clock.nowMs;
    expect(ComboSpecial.readyHelpers(s, t), isEmpty, reason: 'just fired');
    red.firedAtMs = -1e9;
    ComboSpecial.stateOf(red).nextAtMs = s.clock.nowMs + 1;
    expect(ComboSpecial.readyHelpers(s, t), isEmpty, reason: 'recharging');
  });

  group('recipe choice', () {
    late GameSession s;
    late Map<String, List<Turret>> pool;
    var built = 0;
    setUp(() {
      s = lyne();
      pool = {};
      built = 0;
    });

    // Recipe choice reads only the pool, so the turrets can stand anywhere.
    void add(String colour, int n) {
      for (var i = 0; i < n; i++) {
        final at = Vec2(40 + 40.0 * (built % 16), built < 16 ? 400 : 440);
        built++;
        pool.putIfAbsent(colour, () => []).add(build(s, colour, at));
      }
    }

    String? pick(String leader) => ComboSpecial.match(data, leader, pool)?.id;

    test('Blue takes its first matching recipe in priority order', () {
      add('red', 2);
      add('green', 1);
      add('blue', 1);
      expect(pick('blue'), 'big-laser-cluster-landmine');
      pool.remove('green');
      expect(pick('blue'), 'big-cluster-landmine');
      pool.remove('blue');
      expect(pick('blue'), 'big-clusterbomb');
      pool['red']!.removeLast();
      expect(pick('blue'), 'clusterbomb');
      add('yellow', 1);
      expect(pick('blue'), 'sparky-clusterbomb');
      pool.clear();
      add('blue', 1);
      expect(pick('blue'), 'landmine');
      pool.clear();
      expect(pick('blue'), isNull);
    });

    test('Red: nuke beats napalm; poison gas, tazer, laser rockets', () {
      add('blue', 2);
      add('red', 1);
      add('yellow', 1);
      expect(pick('red'), 'nuke');
      pool['blue']!.removeLast();
      expect(pick('red'), 'napalm');
      pool.clear();
      add('blue', 1);
      add('green', 1);
      expect(pick('red'), 'poison-rocket');
      pool.clear();
      add('yellow', 1);
      add('green', 1);
      expect(pick('red'), 'tazer-rocket');
      pool.remove('yellow');
      expect(pick('red'), 'laser-rocket');
    });

    test('Green: rocket BFG needs two reds; BFG one', () {
      add('red', 2);
      add('blue', 1);
      expect(pick('green'), 'rocket-bfg');
      pool['red']!.removeLast();
      expect(pick('green'), 'bfg');
      pool.remove('blue');
      expect(pick('green'), isNull, reason: 'green link-fires instead');
    });

    test('Yellow recipes test exact counts', () {
      add('yellow', 2);
      add('green', 1);
      expect(pick('yellow'), 'blackhole');
      add('green', 1);
      expect(pick('yellow'), isNull, reason: 'G == 1 fails, and so does the shockwave');
      pool.clear();
      add('yellow', 1);
      add('blue', 1);
      add('green', 1);
      expect(pick('yellow'), 'shockwave');
      add('blue', 1);
      expect(pick('yellow'), isNull, reason: 'B == 1 fails');
      pool.clear();
      add('red', 1);
      add('blue', 1);
      expect(pick('yellow'), 'tazer-bfg');
      add('blue', 1);
      expect(pick('yellow'), isNull);
    });
  });

  test('firing puts the leader and its helpers on recharge, without counting a shot', () {
    final b = ComboBench(data)
      ..place('blue', ['red', 'red'])
      ..spawnCreep()
      ..waitInRange();
    final now = b.s.clock.nowMs;
    final shots = b.s.shots;
    final helperReload = [for (final h in b.helpers) h.firedAtMs];
    b.fire('big-clusterbomb');
    final recharge = data.combos['big-clusterbomb']!.rechargeMs;
    final lead = ComboSpecial.stateOf(b.leader);
    expect(lead.nextAtMs, now + recharge);
    expect(lead.led, 1);
    expect(b.leader.firedAtMs, now, reason: 'the weapon reloads');
    expect(b.leader.shots, 0);
    expect(b.s.shots, shots);
    expect(b.s.combos, 1);
    for (var i = 0; i < 2; i++) {
      final h = ComboSpecial.stateOf(b.helpers[i]);
      expect(h.nextAtMs, now + recharge - 1);
      expect(h.assisted, 1);
      expect(h.bearTo, b.leader.uid);
      expect(b.helpers[i].firedAtMs, helperReload[i], reason: 'a helper\'s reload is untouched');
    }
  });

  test('taken helpers turn toward their leader while they have no target; Yellow does not', () {
    final s = lyne();
    final leader = maxed(s, 'red', ComboBench.leaderAt);
    final blue = maxed(s, 'blue', ComboBench.ring[0]);
    final yellow = maxed(s, 'yellow', ComboBench.ring[2]);
    s.run(10);
    final creep = firstCreep(s);
    s.waves.spawners.clear();
    creep.gone = true; // no targets from here on
    s.step();
    final blueBefore = blue.rotation;
    final yellowBefore = yellow.rotation;
    ComboSpecial.fireRecipe(s, leader, data.combos['napalm']!, creep, {
      'blue': [blue],
      'yellow': [yellow],
    });
    s.run(120);
    expect(blue.rotation, isNot(blueBefore));
    expect(blue.rotation, closeTo(bearingDeg(blue.position, leader.position), 1e-9));
    expect(yellow.rotation, yellowBefore);
  });

  test('combos happen in play: a Blue with an idle Blue helper throws landmines', () {
    final s = lyne();
    // Leader 100 px from the road (range 130 reaches it); helper 165 px out, idle.
    final leader = maxed(s, 'blue', const Vec2(357.08, 126.36));
    final helper = maxed(s, 'blue', const Vec2(394.18, 72.99));
    s.enqueue(const SendNextWave());
    final fired = stepUntil<ComboFired>(s, maxSteps: 3000)!;
    expect(fired.uid, leader.uid);
    expect(fired.combo, 'landmine');
    expect(fired.helpers, [helper.uid]);
    expect(s.projectiles.where((p) => p.specId == 'landmine'), hasLength(1));
    final next = stepUntil<ComboFired>(s, maxSteps: 1200)!;
    expect(next.combo, 'landmine');
    final recharge = data.combos['landmine']!.rechargeMs;
    expect((next.tick - fired.tick) * 1000 / data.rules.tickHz, greaterThanOrEqualTo(recharge));
  });

  test('without a matching recipe each colour shoots its own way', () {
    final s = lyne();
    final green = maxed(s, 'green', ComboBench.leaderAt);
    maxed(s, 'blue', ComboBench.ring[0]); // BFG needs a red too
    s.enqueue(const SendNextWave());
    final fired = stepUntil<TurretFired>(s, test: (e) => e.uid == green.uid)!;
    expect(fired.projectile, 'laser-beam');
    expect(s.combos, 0);
  });

  test('pickRandom follows arrayPick', () {
    final r = SimRandom(1);
    expect(pickRandom(r, [1], 1), [1]);
    expect(r.draws, 0, reason: 'a list of exactly n is returned as is');
    expect(pickRandom(r, <int>[], 1), isEmpty);
    expect(r.draws, 1, reason: 'one draw even for an empty list');
    final two = pickRandom(r, [1, 2, 3], 2);
    expect(two.toSet(), hasLength(2));
    expect(pickRandom(r, [1, 2], 2), [1, 2]);
  });
}
