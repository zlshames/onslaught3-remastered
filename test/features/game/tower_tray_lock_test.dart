import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/features/game/game_view_model.dart';
import 'package:onslaught3_remastered/features/game/hud/tower_tray.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../support/fake_game_view_model.dart';
import '../../support/test_data.dart';

class _NoInput implements PlacementInput {
  final drags = <String>[];
  @override
  void dragTo(String turretId, Offset globalPosition, {bool touch = false, bool start = false}) =>
      drags.add(turretId);
  @override
  void dragEnd() {}
}

/// The tower tray: locked turrets show their kill threshold and cannot be
/// armed or dragged.
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
    const rangeUp = TrayItem(
      id: 'range-up',
      name: 'Range Enhancer',
      cost: 2000,
      icon: null,
      affordable: false,
      locked: true,
      unlockKills: 300,
      killsToUnlock: 180,
    );

    testWidgets('a locked turret shows its kill threshold and cannot be armed', (tester) async {
      final vm = FakeGameViewModel(data: data, tray: [rangeUp]);
      await pump(tester, TowerTray(viewModel: vm, input: _NoInput()));
      expect(find.text('300 kills'), findsOneWidget);
      expect(find.byIcon(Icons.lock), findsOneWidget);
      expect(
        find.bySemanticsLabel(r'Range Enhancer, $2000, locked: unlocks at 300 kills, 180 to go'),
        findsOneWidget,
      );
      await tester.tap(find.text('300 kills'));
      expect(vm.placement.value, isNull);
    });

    testWidgets('a locked turret cannot be dragged onto the map', (tester) async {
      final vm = FakeGameViewModel(data: data, tray: [rangeUp]);
      final input = _NoInput();
      await pump(
        tester,
        Align(
          alignment: Alignment.topRight,
          child: TowerTray(viewModel: vm, input: input),
        ),
      );
      await tester.drag(find.text('300 kills'), const Offset(-300, 0));
      expect(input.drags, isEmpty);
    });
  });
}
