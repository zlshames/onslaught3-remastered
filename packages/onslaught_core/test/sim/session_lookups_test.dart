import 'package:onslaught_core/onslaught_core.dart';
import 'package:onslaught_core/testing.dart';
import 'package:test/test.dart';

import '../support/repo_data.dart';
import '../support/sim_helpers.dart';

/// The shared lookups specials use (audit D8, D9): [GameSession.turretsNear],
/// a null-tolerant [GameSession.creepByUid], [Turret.stateOrNull] and
/// [TurretSpecial.params].
void main() {
  late SimTestHarness harness;
  setUpAll(() => harness = SimTestHarness(loadClassicData()));

  GameSession sandbox() {
    final s = harness.session(const GameConfig(mapId: 'map9', mode: 'sandbox', seed: 4))
      ..debugCash = 1e12;
    unlockAll(s);
    return s;
  }

  const at = Vec2(500, 60);

  group('turretsNear', () {
    test('other active turrets within range, edge included, in build order', () {
      final s = sandbox();
      final t = [for (var i = 0; i < 4; i++) build(s, 'blue', at + Vec2(0, 40.0 * i))];
      expect(s.turretsNear(t[0], 80).toList(), [t[1], t[2]]);
      expect(s.turretsNear(t[0], 79.9).toList(), [t[1]]);
      expect(s.turretsNear(t[2], 40).toList(), [t[1], t[3]]);
      expect(s.turretsNear(t[0], 1000).contains(t[0]), isFalse, reason: 'never itself');
    });

    test('skips inactive turrets and applies the filter', () {
      final s = sandbox();
      final t = [for (var i = 0; i < 4; i++) build(s, 'blue', at + Vec2(0, 40.0 * i))];
      t[1].active = false;
      expect(s.turretsNear(t[0], 1000).toList(), [t[2], t[3]]);
      expect(s.turretsNear(t[0], 1000, where: (o) => o != t[2]).toList(), [t[3]]);
      expect(s.turretsNear(t[0], 1000, includeInactive: true).toList(), [t[1], t[2], t[3]]);
    });

    test('a modifier aura covers inactive turrets too', () {
      // `ModifierSpecial.covered` keeps its original scan: a turret being
      // consumed, or a Combonly plate still arming, stays under the aura.
      final s = sandbox();
      final m = build(s, 'range-up', at);
      final b = build(s, 'blue', at + const Vec2(0, 40));
      b.active = false;
      expect(ModifierSpecial.covered(s, m).toList(), [b]);
    });
  });

  test('creepByUid takes a null uid', () {
    final s = sandbox();
    final c = firstCreep(s);
    expect(s.creepByUid(null), isNull);
    expect(s.creepByUid(c.uid), same(c));
    expect(s.creepByUid(987654), isNull);
  });

  test('stateOrNull is null until a special creates its state', () {
    final s = sandbox();
    final blue = build(s, 'blue', at);
    expect(blue.stateOrNull<ComboState>(ComboSpecial.specialId), isNull);
    final st = ComboSpecial.stateOf(blue);
    expect(blue.stateOrNull<ComboState>(ComboSpecial.specialId), same(st));
  });

  test('TurretSpecial.params is the turret data for that special, else empty', () {
    final s = sandbox();
    final green = build(s, 'green', at);
    final blue = build(s, 'blue', at + const Vec2(0, 40));
    expect(const LinkSpecial().params(green), same(green.def.specialParams['link']));
    expect(const LinkSpecial().params(green).number('mult'), isNotNull);
    expect(const LinkSpecial().params(blue), same(Params.empty));
  });
}
