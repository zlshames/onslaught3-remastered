import 'package:onslaught_core/onslaught_core.dart';
import 'package:test/test.dart';

void main() {
  test('same seed, same sequence', () {
    final a = SimRandom(42);
    final b = SimRandom(42);
    expect(
      [for (var i = 0; i < 100; i++) a.nextUint32()],
      [for (var i = 0; i < 100; i++) b.nextUint32()],
    );
  });

  test('different seeds differ', () {
    expect(SimRandom(1).nextUint32(), isNot(SimRandom(2).nextUint32()));
  });

  test('sequence is pinned (cross-platform contract)', () {
    // If this changes, every regression fixture changes: re-record them in a
    // dedicated commit (see the regression-fixtures skill).
    final r = SimRandom(1);
    expect([for (var i = 0; i < 4; i++) r.nextUint32()], _pinnedSeed1);
  });

  test('ranges', () {
    final r = SimRandom(7);
    for (var i = 0; i < 10000; i++) {
      final d = r.nextDouble();
      expect(d, inInclusiveRange(0, 1));
      expect(d, lessThan(1));
      expect(r.nextInt(9), inInclusiveRange(0, 8));
      expect(r.jitter(9.5).abs(), lessThanOrEqualTo(9.5));
    }
  });

  test('values are 32-bit and draws are counted', () {
    final r = SimRandom(123);
    for (var i = 0; i < 1000; i++) {
      expect(r.nextUint32(), inInclusiveRange(0, 0xFFFFFFFF));
    }
    expect(r.draws, 1000);
  });
}

const _pinnedSeed1 = <int>[3898016280, 503430273, 2109199260, 1781707058];
