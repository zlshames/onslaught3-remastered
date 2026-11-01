import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/features/game/game_view_model.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../support/test_data.dart';

/// Phase 3: the selected-turret sheet's combo card and the world the Flame
/// layer draws ordnance from, read off a live session.
void main() {
  late GameData data;
  setUpAll(() => data = loadTestGameData());

  /// Lyne (map9): road (0, 0) → (590, 410); these spots are clear of it.
  const leaderAt = Vec2(300, 150);
  const helperAt = Vec2(325.7, 113.1);

  SessionGameViewModel vmFor() {
    final s = GameSession(
      data: data,
      config: const GameConfig(mapId: 'map9', mode: 'sandbox', seed: 3),
    )..debugCash = 1e9;
    for (final id in data.turrets.keys) {
      s.debugMakeAvailable(id);
    }
    return SessionGameViewModel(s);
  }

  void step(SessionGameViewModel vm, [int n = 1]) {
    for (var i = 0; i < n; i++) {
      vm.advance(1 / data.rules.tickHz);
    }
  }

  Turret build(SessionGameViewModel vm, String id, Vec2 at, {bool maxDamage = true}) {
    vm.dispatch(BuildTurret(id, at.x, at.y));
    step(vm);
    final t = vm.session.turrets.last;
    if (maxDamage) {
      for (var i = 0; i < t.def.upgrades.damage.length; i++) {
        vm.dispatch(UpgradeTurret(t.uid, 'damage'));
      }
      step(vm);
    }
    return t;
  }

  ComboCard card(SessionGameViewModel vm, Turret t) {
    vm.select(t.uid);
    step(vm);
    return vm.selection.value!.cards.whereType<ComboCard>().single;
  }

  test('every colour turret shows a combo card first', () {
    final vm = vmFor();
    for (final (i, id) in ['blue', 'green', 'red', 'yellow'].indexed) {
      final t = build(vm, id, Vec2(100 + 60.0 * i, 400), maxDamage: false);
      vm.select(t.uid);
      step(vm);
      expect(vm.selection.value!.cards.first, isA<ComboCard>(), reason: id);
    }
  });

  test('locked until the damage track is bought, with the levels to go', () {
    final vm = vmFor();
    final t = build(vm, 'blue', leaderAt, maxDamage: false);
    vm.dispatch(UpgradeTurret(t.uid, 'damage'));
    step(vm);
    final c = card(vm, t);
    expect(c.capable, isFalse);
    expect(c.damageLevelsToGo, t.def.upgrades.damage.length - 1);
    expect(c.recipe, isNull);
  });

  test('partners and the recipe they make; countdown after a combo', () {
    final vm = vmFor();
    final leader = build(vm, 'blue', leaderAt);
    final helper = build(vm, 'red', helperAt);
    var c = card(vm, leader);
    expect(c.capable, isTrue);
    expect(c.nextSeconds, isNull, reason: 'ready');
    expect(c.partners, {'red': 1});
    expect(c.recipe, data.combos['clusterbomb']!.name);

    final s = vm.session;
    s.enqueue(const SendNextWave());
    final creep = () {
      for (var i = 0; i < 600; i++) {
        step(vm);
        if (s.creeps.isNotEmpty) return s.creeps.first;
      }
      throw StateError('no creep');
    }();
    ComboSpecial.fireRecipe(s, leader, data.combos['clusterbomb']!, creep, {
      'red': [helper],
    });
    c = card(vm, leader);
    expect(c.led, 1);
    expect(c.nextSeconds, (data.combos['clusterbomb']!.rechargeMs / 1000).floor() - 1);
    expect(card(vm, helper).assisted, 1);
  });

  test('the world view exposes blasts and walkers', () {
    final vm = vmFor();
    final b = vm.session.debugSpawnBlast(
      specId: 'blast-small',
      at: const Vec2(100, 100),
      damage: 1,
      poison: 1,
      turretUid: null,
    );
    expect(vm.world.blasts, [b]);
    expect(vm.world.walkers, isEmpty);
  });
}
