import 'package:onslaught_core/onslaught_core.dart';
import 'package:onslaught_core/testing.dart';
import 'package:test/test.dart';

import '../support/repo_data.dart';
import '../support/sim_helpers.dart';

void main() {
  late GameData data;
  late SimTestHarness harness;
  setUpAll(() {
    data = loadClassicData();
    harness = SimTestHarness(data);
  });

  /// Lyne (map9): far from the road's start, so no creep is in range during
  /// these runs.
  const spot = Vec2(550, 330);

  GameSession lyne(RulesProfile profile) =>
      harness.session(GameConfig(mapId: 'map9', seed: 8, profile: profile))..debugCash = 1e7;

  /// A Blue at damage 4 and rate 4 (freak-available).
  Turret freakBlue(GameSession s) {
    final t = build(s, 'blue', spot);
    upgrade(s, t, StatKind.damage, 4);
    upgrade(s, t, StatKind.rate, 4);
    return t;
  }

  test('freakout data (Turret class vars, TurretBlue / TurretYellow)', () {
    for (final id in ['blue', 'yellow']) {
      final f = data.turrets[id]!.freakout!;
      expect(f.capable, isTrue, reason: id);
      expect(
        [f.lengthMs, f.spacingMs, f.damageMult, f.rangeMult, f.rateMult],
        [5000, 80000, 3, 0, 4],
      );
      expect([f.levelDamage, f.levelRange, f.levelRate], [4, 0, 4]);
      final p = data.turrets[id]!.specialParams['freakout']!;
      expect(
        [p.number('firstDelayMs'), p.number('warnMs'), p.number('buyCostPerSecond')],
        [60000, 3000, 250],
      );
    }
    for (final id in ['green', 'red']) {
      expect(data.turrets[id]!.freakout!.capable, isFalse, reason: id);
    }
  });

  test('it becomes available at damage 4 and rate 4, not before', () {
    final s = lyne(RulesProfile.classicFixed);
    final t = build(s, 'blue', spot);
    upgrade(s, t, StatKind.damage, 4);
    upgrade(s, t, StatKind.rate, 3);
    expect(FreakoutSpecial.stateOf(t).available, isFalse);
    expect(FreakoutSpecial.msUntilNext(s, t), isNull);
    upgrade(s, t, StatKind.rate);
    expect(FreakoutSpecial.stateOf(t).available, isTrue);
  });

  group('classic: no freakout is ever scheduled (uninitialised freak_next)', () {
    test('none happens and none can be bought', () {
      final s = lyne(RulesProfile.classic);
      final t = freakBlue(s);
      expect(FreakoutSpecial.stateOf(t).available, isTrue);
      final events = s.run(60 * 90);
      expect(events.whereType<FreakoutChanged>(), isEmpty);
      s.enqueue(BuyFreakout(t.uid));
      final rejected = s.step().whereType<CommandRejected>().single;
      expect(rejected.reason, 'unavailable');
      expect(t.terms, StatTerms.identity);
    });
  });

  group('classicFixed (freakoutAutoStart)', () {
    test('first freakout 60 s after it became available, warning 3 s, active 5 s', () {
      final s = lyne(RulesProfile.classicFixed);
      const step = 1000 / 60;
      final t = freakBlue(s);
      // Scheduled when the command applied, before that step's tick.
      final availableAt = s.clock.nowMs - step;
      expect(FreakoutSpecial.msUntilNext(s, t), closeTo(60000 - step, 1e-6));
      final stages = <(String, double)>[];
      final damage = <String, double>{};
      for (var i = 0; i < 60 * 70 && stages.length < 3; i++) {
        for (final e in s.step().whereType<FreakoutChanged>()) {
          stages.add((e.stage, s.clock.nowMs - availableAt));
          damage[e.stage] = s.statOf(t, StatKind.damage);
        }
      }
      expect(stages.map((e) => e.$1), ['warning', 'active', 'ended']);
      // Blue's update starts it on its first 70 ms tick at or after 60 s
      // (ticks land on steps: at most five steps apart).
      expect(stages[0].$2, inInclusiveRange(60000, 60000 + 5 * step + 1e-6));
      expect(stages[1].$2 - stages[0].$2, inInclusiveRange(3000, 3000 + step + 1e-6));
      expect(stages[2].$2 - stages[1].$2, inInclusiveRange(5000, 5000 + step + 1e-6));
      // Damage level 4 = 400; × (1 + 3) while active, back after.
      expect(damage['warning'], 400);
      expect(damage['active'], 1600);
      expect(damage['ended'], 400);
    });

    test('while active: damage × 4, rate × 5, range unchanged; stacks with auras', () {
      final s = lyne(RulesProfile.classicFixed);
      unlockAll(s);
      final t = freakBlue(s);
      build(s, 'damage-up', spot + const Vec2(0, -50));
      expect(s.statOf(t, StatKind.damage), closeTo(400 * 1.4, 1e-9));
      stepUntil<FreakoutChanged>(s, test: (e) => e.stage == 'active', maxSteps: 60 * 70);
      expect(s.statOf(t, StatKind.damage), closeTo(400 * (1 + 0.4 + 3), 1e-9));
      expect(s.statOf(t, StatKind.rate), closeTo(160 * 5, 1e-9));
      expect(s.statOf(t, StatKind.range), 130);
    });

    test('the next one is due 40 s + U(0, 40 s) − rate level × 4 s after the last', () {
      final s = lyne(RulesProfile.classicFixed);
      final t = freakBlue(s);
      stepUntil<FreakoutChanged>(s, maxSteps: 60 * 70);
      final next = FreakoutSpecial.msUntilNext(s, t)!;
      expect(next, inInclusiveRange(40000 - 16000, 80000 - 16000));
    });

    test('buying one costs floor(seconds to the next) × 250 and starts it now', () {
      final s = lyne(RulesProfile.classicFixed);
      final t = freakBlue(s);
      s.run(60 * 10);
      final seconds = (FreakoutSpecial.msUntilNext(s, t)! / 1000).floor();
      final cash = s.cash;
      final spent = s.totalSpent;
      s.enqueue(BuyFreakout(t.uid));
      final events = s.step();
      final warn = events.whereType<FreakoutChanged>().single;
      // The cost is computed before the step's clock tick.
      expect(warn.cost, inInclusiveRange((seconds - 1) * 250, seconds * 250));
      expect(warn.stage, 'warning');
      expect(s.cash, cash - warn.cost!);
      expect(s.totalSpent, spent + warn.cost!);
      expect(FreakoutSpecial.stateOf(t).runs, hasLength(1));
      // The schedule moves on from now.
      expect(FreakoutSpecial.msUntilNext(s, t), inInclusiveRange(24000, 64000));
    });

    test('an overdue freakout (due, before the turret ticked) costs 0, never less', () {
      final s = lyne(RulesProfile.classicFixed);
      final t = freakBlue(s);
      final sp = s.registry.turretSpecial(FreakoutSpecial.specialId) as FreakoutSpecial;
      // The automatic freakout only fires on Blue's own 70 ms tick, so there
      // are steps where the scheduled time has passed but it has not yet
      // started; step to one of them, checking the cost on every step.
      var overdue = false;
      for (var i = 0; i < 60 * 80 && !overdue; i++) {
        s.step();
        final cost = sp.buyCost(s, t);
        expect(cost, isNotNull);
        expect(cost, greaterThanOrEqualTo(0), reason: 'step $i');
        overdue = FreakoutSpecial.msUntilNext(s, t)! < 0;
      }
      expect(overdue, isTrue, reason: 'no step found with the freakout overdue');
      expect(sp.buyCost(s, t), 0);
      final cash = s.cash;
      final spent = s.totalSpent;
      s.enqueue(BuyFreakout(t.uid));
      final events = s.step();
      expect(events.whereType<CommandRejected>(), isEmpty);
      final warn = events.whereType<FreakoutChanged>().single;
      expect(warn.stage, 'warning');
      expect(warn.cost, 0);
      expect(s.cash, cash);
      expect(s.totalSpent, spent);
      expect(FreakoutSpecial.stateOf(t).runs, hasLength(1));
    });

    test('buying needs the cash', () {
      final s = lyne(RulesProfile.classicFixed);
      final t = freakBlue(s);
      s.debugCash = 0;
      s.enqueue(BuyFreakout(t.uid));
      expect(s.step().whereType<CommandRejected>().single.reason, 'cannotAfford');
    });

    test('turrets that cannot freak out refuse the command', () {
      final s = lyne(RulesProfile.classicFixed);
      final t = build(s, 'red', spot);
      s.enqueue(BuyFreakout(t.uid));
      expect(s.step().whereType<CommandRejected>().single.reason, 'unavailable');
    });

    test('Yellow freaks out too', () {
      final s = lyne(RulesProfile.classicFixed);
      final t = build(s, 'yellow', spot);
      upgrade(s, t, StatKind.damage, 4);
      upgrade(s, t, StatKind.rate, 4);
      final e = stepUntil<FreakoutChanged>(s, maxSteps: 60 * 70);
      expect(e?.uid, t.uid);
    });
  });
}
