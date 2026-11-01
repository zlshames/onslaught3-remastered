import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/features/game/flame/onslaught_flame_game.dart';
import 'package:onslaught3_remastered/features/game/game_view_model.dart';
import 'package:onslaught3_remastered/features/game/hud/turret_sheet.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../support/fake_game_view_model.dart';
import '../../support/fakes.dart';
import '../../support/test_data.dart';

/// Phase 4 HUD: the Targeter, Fusion and Combonly cards and their buttons,
/// and joining by tapping turrets.
void main() {
  late GameData data;
  setUpAll(() => data = loadTestGameData());

  Future<FakeGameViewModel> pumpCard(
    WidgetTester tester,
    String turretId,
    SpecialCard card, {
    bool locked = false,
  }) async {
    tester.view
      ..physicalSize = const Size(1280, 720)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final vm = FakeGameViewModel(
      data: data,
      selection: turretPanel(data, turretId, uid: 7, cards: [card], locked: locked),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: TurretSheet(viewModel: vm),
          ),
        ),
      ),
    );
    return vm;
  }

  testWidgets('Targeter: Join starts the joiner, Done ends it', (tester) async {
    var vm = await pumpCard(
      tester,
      'targeter',
      const TargeterCard(joins: 2, max: 3, joining: false),
    );
    expect(find.text('Joined 2/3'), findsOneWidget);
    expect(find.text('Paints fastest'), findsOneWidget);
    await tester.tap(find.text('Join'));
    expect(vm.joinCalls, [7]);
    vm = await pumpCard(tester, 'targeter', const TargeterCard(joins: 2, max: 3, joining: true));
    expect(find.text('Tap turrets'), findsOneWidget);
    await tester.tap(find.text('Done'));
    expect(vm.joinCalls, [null]);
  });

  testWidgets('Targeter: no joining while paused', (tester) async {
    final vm = await pumpCard(
      tester,
      'targeter',
      const TargeterCard(joins: 0, max: 3, joining: false),
      locked: true,
    );
    await tester.tap(find.text('Join'));
    expect(vm.joinCalls, isEmpty);
  });

  testWidgets('Fusion: stored energy, slow, tier and feeders', (tester) async {
    await pumpCard(
      tester,
      'fusion',
      const FusionCard(storeDamage: 3.45e7, storePoison: 120, tier: 'low', feeders: 3),
    );
    expect(find.text('Stored 34.5M'), findsOneWidget);
    expect(find.text('Slow 120 · low'), findsOneWidget);
    expect(find.text('3 feeding'), findsOneWidget);
  });

  testWidgets('Combonly: Lock in while an option shows', (tester) async {
    const nuke = (colour: 'red', recipe: 'nuke', name: 'Nuke');
    const landmine = (colour: 'blue', recipe: 'big-landmine', name: 'Big Landmine');
    final vm = await pumpCard(
      tester,
      'combonly',
      const CombonlyCard(options: [nuke, landmine], shown: nuke, chosen: null, armed: false),
    );
    expect(find.text('Nuke'), findsOneWidget);
    expect(find.text('2 options'), findsOneWidget);
    await tester.tap(find.text('Lock\nin'));
    expect(vm.dispatched.single.toJson(), const ChooseCombonly(7).toJson());
  });

  testWidgets('Combonly: nothing to offer, then locked in', (tester) async {
    await pumpCard(
      tester,
      'combonly',
      const CombonlyCard(options: [], shown: null, chosen: null, armed: false),
    );
    expect(find.text('No combo'), findsOneWidget);
    expect(find.text('Lock\nin'), findsNothing);
    await pumpCard(
      tester,
      'combonly',
      const CombonlyCard(
        options: [],
        shown: null,
        chosen: (colour: 'red', recipe: 'nuke', name: 'Nuke'),
        armed: true,
      ),
    );
    expect(find.text('Ready'), findsOneWidget);
  });

  testWidgets('while joining, a tap on a turret joins it and empty ground ends it', (tester) async {
    tester.view
      ..physicalSize = const Size(923, 411)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final vm = FakeGameViewModel(data: data, mapId: 'map9')..joinFrom(3);
    final game = OnslaughtFlameGame(viewModel: vm, pack: EmptyAssetPack(), driveSimulation: false);
    await tester.pumpWidget(GameWidget(game: game));
    await tester.pump();
    vm.turretAtResult = 5;
    game.tapAt(const Offset(400, 200));
    expect(vm.dispatched.single.toJson(), const JoinTurret(3, 5).toJson());
    expect(vm.selections, isEmpty, reason: 'joining does not select');
    vm.turretAtResult = null;
    game.tapAt(const Offset(10, 10));
    expect(vm.joining.value, isNull);
  });
}
