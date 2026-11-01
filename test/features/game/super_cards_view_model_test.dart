import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/features/game/game_view_model.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../support/test_data.dart';

/// Phase 4: the selected-turret sheet's Targeter, Fusion and Combonly cards,
/// the joiner, and consumed turrets, read off a live sandbox2 session.
void main() {
  late GameData data;
  setUpAll(() => data = loadTestGameData());

  /// Lyne (map9): road (0, 0) → (590, 410); these spots are clear of it.
  const nearRoad = Vec2(300, 150);
  const far = Vec2(500, 60);
  const plateAt = Vec2(200, 300);

  SessionGameViewModel vmFor() => SessionGameViewModel(
    GameSession(
      data: data,
      config: const GameConfig(mapId: 'map9', mode: 'sandbox2', seed: 3),
    )..debugCash = 1e9,
  );

  void step(SessionGameViewModel vm, [int n = 1]) {
    for (var i = 0; i < n; i++) {
      vm.advance(1 / data.rules.tickHz);
    }
  }

  Turret build(SessionGameViewModel vm, String id, Vec2 at, {bool maxDamage = false}) {
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

  T card<T extends SpecialCard>(SessionGameViewModel vm) =>
      vm.selection.value!.cards.whereType<T>().single;

  test('sandbox2 opens the whole rack', () {
    final vm = vmFor();
    expect(vm.tray.value, hasLength(16));
    expect(vm.tray.value.where((t) => t.locked), isEmpty);
  });

  test('the joiner: Join, tap turrets to join or let go, Done', () {
    final vm = vmFor();
    final targeter = build(vm, 'targeter', nearRoad);
    final blue = build(vm, 'blue', far);
    vm.select(targeter.uid);
    expect(card<TargeterCard>(vm), const TargeterCard(joins: 0, max: 3, joining: false));
    vm.joinFrom(targeter.uid);
    expect(vm.joining.value, targeter.uid);
    expect(card<TargeterCard>(vm).joining, isTrue);
    vm.dispatch(JoinTurret(targeter.uid, blue.uid));
    step(vm);
    expect(card<TargeterCard>(vm).joins, 1);
    vm.joinFrom(null);
    expect(card<TargeterCard>(vm).joining, isFalse);
  });

  test('only a Targeter can start the joiner; selecting another turret ends it', () {
    final vm = vmFor();
    final targeter = build(vm, 'targeter', nearRoad);
    final blue = build(vm, 'blue', far);
    vm.joinFrom(blue.uid);
    expect(vm.joining.value, isNull);
    vm
      ..select(targeter.uid)
      ..joinFrom(targeter.uid)
      ..select(blue.uid);
    expect(vm.joining.value, isNull);
  });

  test('the Fusion card shows its store and feeders', () {
    final vm = vmFor();
    final fusion = build(vm, 'fusion', nearRoad);
    build(vm, 'green', const Vec2(420, 40));
    vm.select(fusion.uid);
    step(vm, 120);
    final c = card<FusionCard>(vm);
    expect(c.feeders, 1);
    expect(c.storeDamage, greaterThan(0));
    expect(c.storeDamage, fusion.stateOrNull<FusionState>(FusionSpecial.specialId)!.storeDamage);
  });

  test('the Combonly card: options, the one showing, locked in, armed; consumed turrets go', () {
    final vm = vmFor();
    final plate = build(vm, 'combonly', plateAt);
    final blue = build(vm, 'blue', plateAt + const Vec2(55, 0), maxDamage: true);
    build(vm, 'blue', plateAt + const Vec2(-55, 0), maxDamage: true);
    vm.select(plate.uid);
    expect(card<CombonlyCard>(vm).options, isEmpty);
    step(vm, 130);
    final shown = card<CombonlyCard>(vm);
    expect(shown.options.map((o) => o.recipe), ['landmine']);
    expect(shown.shown?.name, data.combos['landmine']!.name);
    vm.select(blue.uid);
    expect(vm.selection.value?.uid, blue.uid);
    vm
      ..select(plate.uid)
      ..dispatch(ChooseCombonly(plate.uid));
    step(vm);
    expect(vm.selection.value!.locked, isTrue, reason: 'the plate is inactive while it arms');
    vm.select(blue.uid);
    expect(vm.selection.value, isNull, reason: 'a consumed turret cannot be clicked');
    expect(vm.turretAt(blue.position), isNull);
    step(vm, 125);
    expect(vm.session.turrets, [plate]);
    vm.select(plate.uid);
    final armed = card<CombonlyCard>(vm);
    expect(armed.chosen?.recipe, 'landmine');
    expect(armed.armed, isTrue);
    expect(armed.shown, isNull);
  });
}
