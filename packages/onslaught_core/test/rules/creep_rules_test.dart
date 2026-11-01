import 'package:onslaught_core/onslaught_core.dart';
import 'package:test/test.dart';

void main() {
  test('roundHalfUp is AS2 Math.round', () {
    expect(roundHalfUp(-9.5), -9);
    expect(roundHalfUp(-0.5), 0);
    expect(roundHalfUp(0.5), 1);
    expect(roundHalfUp(9.49), 9);
  });

  test('waypoint jitter is a whole number in -9..9 for the original 19 px', () {
    final r = SimRandom(5);
    final seen = <double>{};
    for (var i = 0; i < 5000; i++) {
      final j = jitterOffset(r, 19);
      expect(j, j.roundToDouble());
      expect(j, inInclusiveRange(-9, 9));
      seen.add(j);
    }
    expect(seen, hasLength(19));
  });

  test('creep sprite scale (AttackerEngine.onLoad)', () {
    expect(creepScalePercent(1, 6), 100);
    expect(creepScalePercent(10, 6), 154); // a wave of 1: 10 / 1
  });

  test('wave clock rounds up to a tenth of a second (AttackerManager.update)', () {
    expect(waveClockSeconds(20000), 20);
    expect(waveClockSeconds(19801), 19.9);
    expect(waveClockSeconds(1), 0.1);
    expect(waveClockSeconds(0), 0);
  });
}
