import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/features/game/game_view_model.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../support/test_data.dart';

void main() {
  late GameData data;
  setUpAll(() => data = loadTestGameData());

  SessionGameViewModel vmFor({String mapId = 'map9', double? cash}) {
    final s = GameSession(
      data: data,
      config: GameConfig(mapId: mapId, seed: 3),
    );
    if (cash != null) s.debugCash = cash;
    return SessionGameViewModel(s);
  }

  void step(SessionGameViewModel vm, [int n = 1]) {
    for (var i = 0; i < n; i++) {
      vm.advance(1 / data.rules.tickHz);
    }
  }

  test('advance runs fixed steps from frame time and caps a long stall', () {
    final vm = vmFor(mapId: 'map1');
    // 30 frames of exactly one step each.
    step(vm, 30);
    expect(vm.session.tick, 30);
    // A 10 s stall runs at most maxStepsPerFrame steps, then drops the backlog.
    vm.advance(10);
    expect(vm.session.tick, 30 + SessionGameViewModel.maxStepsPerFrame);
    vm.advance(0);
    expect(vm.session.tick, 30 + SessionGameViewModel.maxStepsPerFrame);
    vm.dispose();
  });

  test('dispatch reaches the session and the HUD updates after a step', () async {
    final vm = vmFor(mapId: 'map1');
    final events = <GameEvent>[];
    final sub = vm.events.listen(events.add);
    vm.dispatch(const SetPaused(true));
    step(vm);
    await Future<void>.delayed(Duration.zero);
    expect(vm.hud.value.paused, isTrue);
    expect(events.whereType<PausedChanged>(), hasLength(1));
    expect(vm.map.name, 'Classic');
    await sub.cancel();
    vm.dispose();
  });

  test('HUD shows the wave clock rounded up to a tenth', () {
    final vm = vmFor();
    expect(vm.hud.value.nextWaveSeconds, 20);
    step(vm, 7);
    expect(vm.hud.value.nextWaveSeconds, closeTo(19.9, 1e-9));
    expect(vm.hud.value.waveSpacingSeconds, 20);
    vm.dispose();
  });

  test('the tray lists every turret (Phase 4: all 16); locked ones say when they unlock', () {
    final vm = vmFor();
    expect(vm.tray.value.map((t) => t.id), [
      'blue',
      'green',
      'red',
      'yellow',
      'range-up',
      'damage-up',
      'rate-up-exchange',
      'range-up-exchange',
      'rate-up',
      'damage-up-big',
      'damage-up-big-exchange',
      'targeter',
      'sniper',
      'fusion',
      'railgun',
      'combonly',
    ]);
    final byId = {for (final t in vm.tray.value) t.id: t};
    for (final id in ['blue', 'green', 'red', 'yellow']) {
      expect(byId[id]!.locked, isFalse, reason: id);
    }
    expect(byId['blue']!.affordable, isTrue);
    expect(byId['yellow']!.affordable, isFalse, reason: r'$50 with $30');
    final rangeUp = byId['range-up']!;
    expect(rangeUp.locked, isTrue);
    expect(rangeUp.unlockKills, 300);
    expect(rangeUp.killsToUnlock, 300);
    vm.session
      ..debugCash = 5
      ..debugKills = 120;
    step(vm);
    expect(vm.tray.value.first.affordable, isFalse);
    expect(vm.tray.value.firstWhere((t) => t.id == 'range-up').killsToUnlock, 180);
    vm.dispose();
  });

  test('the tray notifies when an item changes, not on every step', () {
    // Each refresh builds a fresh list; a list compares by identity, so
    // without the value comparison the tray rebuilt on every frame.
    final vm = vmFor(mapId: 'map1');
    var notes = 0;
    vm.tray.addListener(() => notes++);
    step(vm, 60);
    expect(notes, 0);
    final before = vm.tray.value;
    vm.session.debugCash = 1e6;
    step(vm);
    expect(notes, 1);
    expect(vm.tray.value, isNot(before));
    expect(vm.tray.value.where((t) => !t.locked).every((t) => t.affordable), isTrue);
    step(vm, 10);
    expect(notes, 1);
    vm.dispose();
  });

  test('placement: preview validity, commit builds, invalid commit does nothing', () {
    final vm = vmFor();
    vm.previewPlacement('blue', const Vec2(200, 140)); // on the road
    expect(vm.placement.value!.valid, isFalse);
    expect(vm.commitPlacement(), isFalse);
    expect(vm.placement.value, isNull);
    vm.previewPlacement('blue', const Vec2(300, 150));
    expect(vm.placement.value!.valid, isTrue);
    expect(vm.placement.value!.range, 130);
    expect(vm.commitPlacement(), isTrue);
    step(vm);
    expect(vm.session.turrets, hasLength(1));
    expect(vm.hud.value.cash, 20);
    vm.dispose();
  });

  test('selection panel mirrors the turret and follows upgrades and sale', () {
    final vm = vmFor(cash: 100);
    vm.dispatch(const BuildTurret('blue', 300, 150));
    step(vm);
    final uid = vm.session.turrets.single.uid;
    expect(vm.turretAt(const Vec2(310, 160)), uid);
    expect(vm.turretAt(const Vec2(340, 150)), isNull);
    vm.select(uid);
    final panel = vm.selection.value!;
    expect(panel.turretId, 'blue');
    expect(panel.stats.map((s) => s.stat), StatKind.values);
    expect(panel.stats.first.nextCost, 20);
    expect(panel.refund, 7);
    expect(panel.targetMode, 'near');
    expect(panel.nextTargetMode, 'far');
    vm.dispatch(UpgradeTurret(uid, 'damage'));
    step(vm);
    expect(vm.selection.value!.stats.first.level, 1);
    expect(vm.selection.value!.refund, 21);
    vm.dispatch(SellTurret(uid));
    step(vm);
    expect(vm.selection.value, isNull);
    vm.dispose();
  });

  test('move: a pending move commits as MoveTurret', () {
    final vm = vmFor(cash: 1000);
    vm.dispatch(const BuildTurret('blue', 300, 150));
    step(vm);
    final uid = vm.session.turrets.single.uid;
    vm.previewPlacement('blue', const Vec2(320, 170), moving: uid);
    expect(vm.placement.value!.moving, uid);
    expect(vm.commitPlacement(), isTrue);
    step(vm);
    expect(vm.session.turrets.single.position, const Vec2(320, 170));
    vm.dispose();
  });

  test('game over publishes the summary', () {
    final vm = vmFor();
    var steps = 0;
    while (vm.gameOver.value == null && steps < 6000) {
      step(vm);
      steps++;
    }
    final summary = vm.gameOver.value!;
    expect(summary.kills, 0);
    expect(vm.hud.value.lives, 0);
    expect(vm.hud.value.gameOver, isTrue);
    vm.dispose();
  });
}
