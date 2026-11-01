import 'package:onslaught_core/onslaught_core.dart';
import 'package:test/test.dart';

// Reference §4: effective = max(0, (base + added) × max(mult, 0.2));
// rate_msec = 1000 / (rate / 60). Source: turrets/Turret.as modifyStat,
// modifyUpdate. The 0.2 floor is data (rules.json modifiers.multFloor); it is
// passed in here so the formula is tested, not the number.
void main() {
  group('effectiveStat', () {
    test('unmodified stat equals base', () {
      expect(effectiveStat(base: 130, added: 0, mult: 1, multFloor: 0.2), 130);
    });

    test('added applies before the multiplier', () {
      // RangeUp (+100) on a Blue (130) with a DamageUp-style ×1.4.
      expect(effectiveStat(base: 130, added: 100, mult: 1.4, multFloor: 0.2), closeTo(322, 1e-9));
    });

    test('multiplier is floored', () {
      // Stacked exchangers can push mult below the floor; it never goes lower.
      expect(effectiveStat(base: 100, added: 0, mult: -0.5, multFloor: 0.2), closeTo(20, 1e-9));
      expect(effectiveStat(base: 100, added: 0, mult: 0.1, multFloor: 0.2), closeTo(20, 1e-9));
    });

    test('result is never negative', () {
      expect(effectiveStat(base: 50, added: -420, mult: 1, multFloor: 0.2), 0);
    });
  });

  group('fireIntervalMs', () {
    test('rate is shots per minute', () {
      expect(fireIntervalMs(100), closeTo(600, 1e-9)); // Blue base rate
      expect(fireIntervalMs(60), closeTo(1000, 1e-9)); // Green base rate
      expect(fireIntervalMs(7), closeTo(8571.43, 0.01)); // combo_rate
    });

    test('zero rate never fires', () {
      expect(fireIntervalMs(0), double.infinity);
    });
  });

  group('upgrade tracks', () {
    const track = [UpgradeStep(20, 30), UpgradeStep(50, 60), UpgradeStep(100, 150)];

    test('upgrading sets the stat to the step value (absolute)', () {
      expect(statAtLevel(15, track, 0), 15);
      expect(statAtLevel(15, track, 1), 30);
      expect(statAtLevel(15, track, 3), 150);
      expect(statAtLevel(15, track, 9), 150, reason: 'clamped at max level');
    });

    test('next cost is the next step, null when maxed', () {
      expect(nextUpgradeCost(track, 0), 20);
      expect(nextUpgradeCost(track, 2), 100);
      expect(nextUpgradeCost(track, 3), isNull);
    });

    test('percent', () {
      expect(upgradePercent(track, 0), 0);
      expect(upgradePercent(track, 3), 100);
      expect(upgradePercent(const [], 0), 0);
    });
  });

  group('StatTerms (modify_*_added / _mult)', () {
    test('identity adds nothing and multiplies by 1', () {
      for (final k in StatKind.values) {
        expect(StatTerms.identity.added(k), 0);
        expect(StatTerms.identity.mult(k), 1);
      }
    });

    test('terms add and negate component-wise', () {
      const a = StatTerms(addRange: 100, multRate: -0.25);
      const b = StatTerms(multDamage: 0.4, multRate: 0.6, addPoison: 3);
      final sum = a + b;
      expect(sum.added(StatKind.range), 100);
      expect(sum.mult(StatKind.rate), closeTo(1.35, 1e-12));
      expect(sum.mult(StatKind.damage), closeTo(1.4, 1e-12));
      expect(sum.addPoison, 3);
      expect(sum + -b, a);
    });

    test('a modifier aura becomes terms field by field', () {
      const aura = ModifierAura(
        addDamage: 1,
        addRange: 2,
        addRate: 3,
        multDamage: 4,
        multRange: 5,
        multRate: 6,
      );
      expect(auraTerms(aura).toJson(), [1, 2, 3, 0, 4, 5, 6, 0]);
    });
  });
}
