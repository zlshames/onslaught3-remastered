import 'dart:math' as math;

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

  const colours = ['blue', 'green', 'red', 'yellow'];
  const modifiers = [
    'range-up',
    'damage-up',
    'rate-up-exchange',
    'range-up-exchange',
    'rate-up',
    'damage-up-big',
    'damage-up-big-exchange',
  ];

  /// Lyne (map9): road (0, 0) → (590, 410). Both spots are clear of it and
  /// 60 px apart, inside a modifier's 80 px aura.
  const turretSpot = Vec2(300, 150);
  const modifierSpot = Vec2(360, 150);

  GameSession lyne() => harness.session(const GameConfig(mapId: 'map9', seed: 5))..debugCash = 1e7;

  /// `max(0, (base + added) × max(mult, 0.2))` with the data's terms.
  double expected(double base, double added, double mult) =>
      math.max(0, (base + added) * math.max(mult, data.rules.modifierMultFloor));

  group('modifier data (TurretModify subclasses, reference §6)', () {
    test('auras, costs and unlocks', () {
      ModifierAura aura(String id) => data.turrets[id]!.modifierAura!;
      List<double> terms(ModifierAura a) => [
        a.addDamage,
        a.addRange,
        a.addRate,
        a.multDamage,
        a.multRange,
        a.multRate,
      ];
      expect(terms(aura('range-up')), [0, 100, 0, 0, 0, 0]);
      expect(terms(aura('damage-up')), [0, 0, 0, 0.4, 0, 0]);
      expect(terms(aura('rate-up-exchange')), [0, 0, 0, -0.4, -0.1, 0.6]);
      expect(terms(aura('range-up-exchange')), [0, 100, 0, 0, 0, -0.25]);
      expect(terms(aura('rate-up')), [0, 0, 0, 0, 0, 1.2]);
      expect(terms(aura('damage-up-big')), [0, 0, 0, 1, 0, 0]);
      expect(terms(aura('damage-up-big-exchange')), [0, 0, 0, 1, -0.3, -0.3]);
      expect(
        [for (final m in modifiers) data.turrets[m]!.unlockKills],
        [300, 450, 550, 700, 850, 1000, 1100],
      );
      expect(
        [for (final m in modifiers) data.turrets[m]!.cost],
        [2000, 5000, 1200, 1000, 3000, 8500, 3500],
      );
      for (final m in modifiers) {
        final def = data.turrets[m]!;
        expect(def.stats.range, 80, reason: m);
        expect(def.modifiable, isFalse, reason: m);
        expect(def.projectiles, isEmpty, reason: m);
        expect(def.upgrades.range.single.cost, 1500, reason: m);
        expect(def.upgrades.range.single.value, 130, reason: m);
      }
    });
  });

  group('stacking matrix: every modifier × every colour', () {
    for (final m in modifiers) {
      for (final c in colours) {
        test('$m on $c', () {
          final s = lyne();
          unlockAll(s);
          final t = build(s, c, turretSpot);
          final def = t.def;
          final before = [for (final k in StatKind.values) s.statOf(t, k)];
          build(s, m, modifierSpot);
          final a = data.turrets[m]!.modifierAura!;
          expect(
            s.statOf(t, StatKind.damage),
            expected(def.stats.damage, a.addDamage, 1 + a.multDamage),
          );
          expect(
            s.statOf(t, StatKind.range),
            expected(def.stats.range, a.addRange, 1 + a.multRange),
          );
          expect(s.statOf(t, StatKind.rate), expected(def.stats.rate, a.addRate, 1 + a.multRate));
          // Selling the modifier takes its terms away again.
          s.enqueue(SellTurret(s.turrets.last.uid));
          s.step();
          expect([for (final k in StatKind.values) s.statOf(t, k)], before);
        });
      }
    }
  });

  group('aura rules (TurretModify.modifyGetInRange, Turret.modifyStat)', () {
    test('auras stack additively and the multiplier floor applies once', () {
      final s = lyne();
      unlockAll(s);
      final blue = build(s, 'blue', turretSpot);
      // Three Rate Exchangers: damage mult 1 − 3 × 0.4 = −0.2 → floored to 0.2.
      for (final at in const [Vec2(360, 150), Vec2(300, 90), Vec2(250, 110)]) {
        build(s, 'rate-up-exchange', at);
      }
      expect(blue.terms.mult(StatKind.damage), closeTo(-0.2, 1e-12));
      expect(s.statOf(blue, StatKind.damage), expected(15, 0, -0.2));
      expect(s.statOf(blue, StatKind.damage), closeTo(3, 1e-9));
      // Rate: 1 + 3 × 0.6 = 2.8; range: 1 − 0.3 = 0.7.
      expect(s.statOf(blue, StatKind.rate), closeTo(100 * 2.8, 1e-9));
      expect(s.statOf(blue, StatKind.range), closeTo(130 * 0.7, 1e-9));
    });

    test('added range and a multiplier combine as (base + added) × mult', () {
      final s = lyne();
      unlockAll(s);
      final red = build(s, 'red', turretSpot);
      build(s, 'range-up-exchange', modifierSpot); // +100 range, rate −0.25
      build(s, 'rate-up-exchange', const Vec2(300, 90)); // range −0.1, rate +0.6
      expect(s.statOf(red, StatKind.range), closeTo((200 + 100) * 0.9, 1e-9));
      expect(s.statOf(red, StatKind.rate), closeTo(50 * (1 - 0.25 + 0.6), 1e-9));
    });

    test('the aura reaches turret centres within its range, inclusive', () {
      final s = lyne();
      unlockAll(s);
      build(s, 'damage-up', const Vec2(380, 70));
      final edge = build(s, 'blue', const Vec2(300, 70)); // exactly 80 px
      final outside = build(s, 'blue', const Vec2(380, 150.5)); // 80.5 px
      expect(edge.terms.multDamage, 0.4);
      expect(outside.terms.multDamage, 0);
    });

    test('modifiers do not modify each other and have no weapon', () {
      final s = lyne();
      unlockAll(s);
      final a = build(s, 'damage-up', turretSpot);
      final b = build(s, 'rate-up', modifierSpot);
      expect(a.terms, StatTerms.identity);
      expect(b.terms, StatTerms.identity);
      s.run(120);
      expect(s.projectiles, isEmpty);
      expect(a.shots + b.shots, 0);
    });

    test('moving the turret or the modifier re-evaluates the aura', () {
      final s = lyne();
      unlockAll(s);
      final blue = build(s, 'blue', turretSpot);
      final mod = build(s, 'damage-up', modifierSpot);
      expect(blue.terms.multDamage, 0.4);
      s.enqueue(MoveTurret(blue.uid, 200, 60));
      s.step();
      expect(blue.terms.multDamage, 0);
      s.enqueue(MoveTurret(mod.uid, 240, 60));
      s.step();
      expect(blue.terms.multDamage, 0.4);
    });

    test("the modifier's range upgrade widens its aura to 130 px", () {
      final s = lyne();
      unlockAll(s);
      final blue = build(s, 'blue', turretSpot);
      final mod = build(s, 'range-up', const Vec2(300 + 100, 150));
      expect(blue.terms.addRange, 0);
      s.enqueue(UpgradeTurret(mod.uid, 'range'));
      s.step();
      expect(blue.terms.addRange, 100);
      expect(s.statOf(blue, StatKind.range), 230);
    });

    test('the effective range is what targeting uses', () {
      final s = lyne();
      unlockAll(s);
      final blue = build(s, 'blue', const Vec2(400, 150));
      build(s, 'range-up', const Vec2(460, 150));
      // (400, 150) is 98 px from the road and 218 px from its far end; with
      // range 230 it reaches creeps a 130 px Blue could not.
      s.enqueue(const SendNextWave());
      final fired = <TurretFired>[];
      for (var i = 0; i < 1200 && fired.isEmpty; i++) {
        fired.addAll(s.step().whereType<TurretFired>());
      }
      final target = s.creepByUid(fired.first.target!)!;
      expect(target.position.distanceTo(blue.position), greaterThan(130));
    });
  });

  group('ModifierSpecial.termsAt (the aura seen from a point)', () {
    test('sums the auras covering a point, in turret order, like applyRelations', () {
      final s = lyne();
      unlockAll(s);
      build(s, 'range-up-exchange', modifierSpot);
      build(s, 'rate-up-exchange', const Vec2(300, 90));
      build(s, 'damage-up', const Vec2(500, 300)); // far away
      final terms = ModifierSpecial.termsAt(s, turretSpot, modifiable: true);
      // A turret built there gets exactly these terms from the sim.
      final red = build(s, 'red', turretSpot);
      expect(terms, red.aura);
      expect(terms.addRange, 100);
      expect(terms.multDamage, -0.4); // the Rate Exchanger's damage cost
    });

    test('the edge is inclusive and nothing applies to an unmodifiable turret', () {
      final s = lyne();
      unlockAll(s);
      build(s, 'damage-up', const Vec2(380, 70));
      expect(ModifierSpecial.termsAt(s, const Vec2(300, 70), modifiable: true).multDamage, 0.4);
      expect(
        ModifierSpecial.termsAt(s, const Vec2(380, 150.5), modifiable: true),
        StatTerms.identity,
      );
      expect(
        ModifierSpecial.termsAt(s, const Vec2(300, 70), modifiable: false),
        StatTerms.identity,
      );
    });

    test('exclude leaves a modifier out (a modifier being moved)', () {
      final s = lyne();
      unlockAll(s);
      final a = build(s, 'damage-up', modifierSpot);
      build(s, 'range-up', const Vec2(300, 90));
      final all = ModifierSpecial.termsAt(s, turretSpot, modifiable: true);
      final without = ModifierSpecial.termsAt(s, turretSpot, exclude: a, modifiable: true);
      expect((all.multDamage, all.addRange), (0.4, 100));
      expect((without.multDamage, without.addRange), (0, 100));
    });
  });
}
