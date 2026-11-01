import 'package:onslaught_core/onslaught_core.dart';
import 'package:test/test.dart';

// Reference §2–§3. Sources: TurretManager.turretSell (ceil(value × 0.7)),
// AttackerManager._waveNext / waveSend (HP growth, bounty, size bump).
void main() {
  group('sellRefund', () {
    test('rounds up', () {
      expect(sellRefund(10, 0.7), 7);
      expect(sellRefund(15, 0.7), 11); // 10.5 → 11
      expect(sellRefund(1, 0.7), 1);
    });
  });

  test('score is kills × spent', () {
    expect(score(kills: 120, spent: 450), 54000);
  });

  group('creepHpForWave', () {
    const defs = DifficultyDefs(levels: [], baseHp: 10, defaultHpRate: 1.125, modeCash: {});
    const easy = DifficultyDef(
      id: 'easy',
      name: 'Easy',
      creepSpeed: 60,
      startingCash: 30,
      hpSchedule: [HpRateStep(1, 1.3), HpRateStep(10, 1.2), HpRateStep(30, 1.15)],
    );

    test('wave 1 already applies the first multiplier', () {
      expect(creepHpForWave(defs, easy, 1), closeTo(13, 1e-9));
    });

    test('the rate switches on the schedule wave itself', () {
      final w9 = 10 * _pow(1.3, 9);
      expect(creepHpForWave(defs, easy, 9), closeTo(w9, 1e-6));
      expect(creepHpForWave(defs, easy, 10), closeTo(w9 * 1.2, 1e-6));
    });

    test('wave 0 is the base HP', () {
      expect(creepHpForWave(defs, easy, 0), 10);
    });
  });

  group('wave size scaling', () {
    test('fewer creeps per wave scale HP, bounty and size up', () {
      expect(waveSizeScale(10, 10), 1);
      expect(waveSizeScale(1, 10), 10);
      expect(waveSizeScale(3, 10), closeTo(3.333, 0.001));
    });

    test('bounty is the wave number scaled and rounded', () {
      expect(creepBounty(7, 10, 10), 7);
      expect(creepBounty(7, 3, 10), 23); // 23.33
      expect(creepBounty(1, 2, 10), 5);
    });
  });

  test('creep type rotates every wave', () {
    expect([for (var w = 1; w <= 11; w++) creepTypeIndex(w, 9)], [0, 1, 2, 3, 4, 5, 6, 7, 8, 0, 1]);
  });
}

double _pow(double b, int e) {
  var r = 1.0;
  for (var i = 0; i < e; i++) {
    r *= b;
  }
  return r;
}
