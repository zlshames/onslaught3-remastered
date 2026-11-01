import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/features/game/game_view_model.dart';
import 'package:onslaught3_remastered/features/game/hud/game_over_panel.dart';
import 'package:onslaught3_remastered/features/game/hud/tower_tray.dart';
import 'package:onslaught3_remastered/features/game/hud/turret_sheet.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../support/fake_game_view_model.dart';
import '../../support/test_data.dart';

class _RecordingInput implements PlacementInput {
  final drags = <(String, Offset)>[];
  var ends = 0;
  @override
  void dragTo(String turretId, Offset globalPosition, {bool touch = false, bool start = false}) =>
      drags.add((turretId, globalPosition));
  @override
  void dragEnd() => ends++;
}

void main() {
  late GameData data;
  setUpAll(() => data = loadTestGameData());

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view
      ..physicalSize = const Size(1280, 720)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  }

  group('tower tray', () {
    testWidgets('lists buildable turrets with their cost', (tester) async {
      final vm = FakeGameViewModel(data: data);
      await pump(tester, TowerTray(viewModel: vm, input: _RecordingInput()));
      expect(find.text(r'$10'), findsOneWidget);
      expect(find.bySemanticsLabel(r'Blue Cannon, $10'), findsOneWidget);
    });

    testWidgets('tap arms the turret (and deselects); tap again disarms', (tester) async {
      final vm = FakeGameViewModel(data: data);
      await pump(tester, TowerTray(viewModel: vm, input: _RecordingInput()));
      await tester.tap(find.text(r'$10'));
      expect(vm.placement.value?.turretId, 'blue');
      expect(vm.placement.value?.at, isNull);
      expect(vm.selections, [null]);
      await tester.pump();
      await tester.tap(find.text(r'$10'));
      expect(vm.placement.value, isNull);
    });

    testWidgets('dragging a cell reports finger positions, then the drop', (tester) async {
      final vm = FakeGameViewModel(data: data);
      final input = _RecordingInput();
      await pump(
        tester,
        Align(
          alignment: Alignment.topRight,
          child: TowerTray(viewModel: vm, input: input),
        ),
      );
      await tester.timedDrag(
        find.text(r'$10'),
        const Offset(-300, 80),
        const Duration(milliseconds: 300),
      );
      expect(input.drags, isNotEmpty);
      expect(input.drags.every((d) => d.$1 == 'blue'), isTrue);
      expect(input.drags.last.$2.dx, lessThan(input.drags.first.$2.dx - 200));
      expect(input.ends, 1);
    });

    testWidgets('unaffordable cells say so', (tester) async {
      final blue = data.turrets['blue']!;
      final vm = FakeGameViewModel(
        data: data,
        tray: [TrayItem(id: 'blue', name: blue.name, cost: 10, icon: null, affordable: false)],
      );
      await pump(tester, TowerTray(viewModel: vm, input: _RecordingInput()));
      expect(find.bySemanticsLabel(r'Blue Cannon, $10, cannot afford'), findsOneWidget);
    });
  });

  group('turret sheet', () {
    Future<FakeGameViewModel> sheet(
      WidgetTester tester,
      TurretPanel? panel, {
      double cash = 30,
    }) async {
      final vm = FakeGameViewModel(
        data: data,
        selection: panel,
        hud: HudState(cash: cash, lives: 10, kills: 0, wave: 1, paused: false, speed: 1),
      );
      await pump(
        tester,
        Align(
          alignment: Alignment.bottomCenter,
          child: TurretSheet(viewModel: vm),
        ),
      );
      return vm;
    }

    testWidgets('hidden with no selection', (tester) async {
      await sheet(tester, null);
      expect(find.text('Damage'), findsNothing);
    });

    testWidgets('shows name, stats, upgrade costs, refund', (tester) async {
      await sheet(tester, bluePanel(data));
      expect(find.text('Kapow'), findsOneWidget);
      expect(find.text('Blue Cannon'), findsOneWidget);
      expect(find.text('12 kills · 40 shots'), findsOneWidget);
      expect(find.text(r'$20'), findsOneWidget);
      expect(find.text('15 → 30'), findsOneWidget);
      expect(find.text(r'Sell $7'), findsOneWidget);
      expect(find.text('Nearest'), findsOneWidget);
    });

    testWidgets('upgrade, target cycle, lock, sell and close dispatch', (tester) async {
      final vm = await sheet(tester, bluePanel(data));
      await tester.tap(find.text('Damage'));
      await tester.tap(find.text('Nearest'));
      await tester.tap(find.text('Lock on'));
      await tester.tap(find.text(r'Sell $7'));
      expect(vm.dispatched.map((c) => c.toJson()), [
        const UpgradeTurret(1, 'damage').toJson(),
        const SetTargetMode(1, 'far').toJson(),
        const SetTargetLock(1, lockOff: true).toJson(),
        const SellTurret(1).toJson(),
      ]);
      await tester.tap(find.byTooltip('Close'));
      expect(vm.selections.last, isNull);
    });

    testWidgets('unaffordable and locked buttons do nothing', (tester) async {
      final vm = await sheet(tester, bluePanel(data, cash: 0, locked: true), cash: 0);
      await tester.tap(find.text('Rate'));
      await tester.tap(find.text(r'Sell $7'));
      await tester.tap(find.text(r'Move $500'));
      expect(vm.dispatched, isEmpty);
      expect(vm.placement.value, isNull);
    });

    testWidgets('long-press asks the game to buy every affordable step', (tester) async {
      final vm = await sheet(tester, bluePanel(data, cash: 200), cash: 200);
      await tester.longPress(find.text('Damage'));
      expect(vm.dispatched.map((c) => c.toJson()), [const UpgradeTurretMax(1, 'damage').toJson()]);
    });

    testWidgets('long-press on a live game buys every affordable step', (tester) async {
      final session = GameSession(
        data: data,
        config: const GameConfig(mapId: 'map9', seed: 3),
      )..debugCash = 1e6;
      final vm = SessionGameViewModel(session);
      addTearDown(vm.dispose);
      vm.dispatch(const BuildTurret('blue', 300, 150));
      vm.advance(1 / data.rules.tickHz);
      final blue = session.turrets.single;
      // $20 + $50 + $100 = $170 of damage steps with $200; the fourth ($250) is not.
      session.debugCash = 200;
      vm.select(blue.uid);
      await pump(
        tester,
        Align(
          alignment: Alignment.bottomCenter,
          child: TurretSheet(viewModel: vm),
        ),
      );
      final upgrades = <TurretUpgraded>[];
      final sub = vm.events.listen((e) => upgrades.addAll([if (e is TurretUpgraded) e]));
      addTearDown(sub.cancel);
      await tester.longPress(find.text('Damage'));
      vm.advance(1 / data.rules.tickHz);
      await tester.pump();
      expect(upgrades.map((e) => (e.level, e.cost)), [(1, 20), (2, 50), (3, 100)]);
      expect(blue.damageLevel, 3);
      expect(session.cash, 30);
    });

    testWidgets('move arms a placement for this turret', (tester) async {
      final vm = await sheet(tester, bluePanel(data, cash: 600), cash: 600);
      await tester.tap(find.text(r'Move $500'));
      expect(vm.placement.value?.moving, 1);
    });

    testWidgets('long-press on the target chip picks any mode', (tester) async {
      final vm = await sheet(tester, bluePanel(data));
      await tester.longPress(find.text('Nearest'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Strongest'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(vm.dispatched.single.toJson(), const SetTargetMode(1, 'strong').toJson());
    });
  });

  group('game over panel', () {
    testWidgets('shows the summary and offers restart and menu', (tester) async {
      var restarted = 0;
      var menu = 0;
      final vm = FakeGameViewModel(data: data);
      await pump(
        tester,
        GameOverPanel(viewModel: vm, onRestart: () => restarted++, onMenu: () => menu++),
      );
      expect(find.text('Game Over'), findsNothing);
      vm.gameOverValue = const GameOverSummary(
        wave: 7,
        kills: 60,
        shots: 99,
        spent: 120,
        score: 7200,
      );
      await tester.pump();
      expect(find.text('Game Over'), findsOneWidget);
      expect(find.text('7200'), findsOneWidget);
      expect(find.text(r'$120'), findsOneWidget);
      await tester.tap(find.text('Restart'));
      await tester.tap(find.text('Main Menu'));
      expect((restarted, menu), (1, 1));
    });
  });

  testWidgets('HUD controls meet the tap target guideline', (tester) async {
    final handle = tester.ensureSemantics();
    final vm = FakeGameViewModel(data: data, selection: bluePanel(data, cash: 1000));
    await pump(
      tester,
      Stack(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TowerTray(viewModel: vm, input: _RecordingInput()),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: SizedBox(width: 1180, child: TurretSheet(viewModel: vm)),
          ),
        ],
      ),
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
