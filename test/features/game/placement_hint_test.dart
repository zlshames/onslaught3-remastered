import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/features/game/game_view_model.dart';
import 'package:onslaught3_remastered/features/game/hud/placement_hint.dart';
import 'package:onslaught3_remastered/features/game/hud/tower_tray.dart';
import 'package:onslaught3_remastered/services/persistence/settings.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../support/fake_game_view_model.dart';
import '../../support/pump.dart';
import '../../support/test_data.dart';

class _NoInput implements PlacementInput {
  @override
  void dragTo(String turretId, Offset globalPosition, {bool touch = false, bool start = false}) {}
  @override
  void dragEnd() {}
}

/// The placement bar and the tray with drag and drop and with drop and lock.
void main() {
  late GameData data;
  setUpAll(() => data = loadTestGameData());

  Future<ValueNotifier<PlacementMode>> pumpHint(
    WidgetTester tester,
    FakeGameViewModel vm, {
    PlacementMode mode = PlacementMode.dropAndLock,
  }) async {
    final notifier = ValueNotifier(mode);
    addTearDown(notifier.dispose);
    await tester.pumpWidget(
      goldenHost(
        Center(
          child: PlacementHint(viewModel: vm, mode: notifier),
        ),
      ),
    );
    return notifier;
  }

  testWidgets('nothing shows without a ghost', (tester) async {
    await pumpHint(tester, FakeGameViewModel(data: data));
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('an armed turret asks for a tap: to build, or to drop with drop and lock', (
    tester,
  ) async {
    final vm = FakeGameViewModel(data: data)..previewPlacement('blue', null);
    final mode = await pumpHint(tester, vm, mode: PlacementMode.dragAndDrop);
    expect(find.text('Tap the map to build Blue Cannon'), findsOneWidget);
    mode.value = PlacementMode.dropAndLock;
    await tester.pump();
    expect(find.text('Tap the map to drop Blue Cannon'), findsOneWidget);
    expect(find.text('Place'), findsNothing);
    vm.previewPlacement('blue', null, moving: 4);
    await tester.pump();
    expect(find.text('Tap the map to drop Blue Cannon at its new spot'), findsOneWidget);
  });

  testWidgets('a locked ghost offers Place, which builds it', (tester) async {
    final vm = FakeGameViewModel(data: data)
      ..previewPlacement('blue', const Vec2(200, 100), locked: true);
    await pumpHint(tester, vm);
    expect(find.text('Drag anywhere to adjust Blue Cannon'), findsOneWidget);
    await tester.tap(find.text('Place'));
    await tester.pump();
    final build = vm.dispatched.single as BuildTurret;
    expect((build.turret, build.x, build.y), ('blue', 200, 100));
    expect(vm.placement.value, isNull);
  });

  testWidgets('a locked move offers Move here', (tester) async {
    final vm = FakeGameViewModel(data: data)
      ..previewPlacement('blue', const Vec2(200, 100), moving: 4, locked: true);
    await pumpHint(tester, vm);
    await tester.tap(find.text('Move here'));
    await tester.pump();
    final move = vm.dispatched.single as MoveTurret;
    expect((move.uid, move.x, move.y), (4, 200, 100));
  });

  testWidgets('Place is disabled where the ghost cannot go; Cancel drops it', (tester) async {
    final vm = FakeGameViewModel(data: data)..placementValid = false;
    vm.previewPlacement('blue', const Vec2(200, 100), locked: true);
    await pumpHint(tester, vm);
    final place = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Place'));
    expect(place.onPressed, isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(vm.placement.value, isNull);
    expect(vm.dispatched, isEmpty);
  });

  testWidgets('with a ghost locked, another tray cell swaps the turret in place', (tester) async {
    final blue = data.turrets['blue']!;
    final green = data.turrets['green']!;
    final vm = FakeGameViewModel(
      data: data,
      tray: [
        for (final t in [blue, green])
          TrayItem(id: t.id, name: t.name, cost: t.cost, icon: t.art.icon, affordable: true),
      ],
    )..previewPlacement('blue', const Vec2(200, 100), locked: true);
    await tester.pumpWidget(goldenHost(TowerTray(viewModel: vm, input: _NoInput())));
    final cells = find.descendant(of: find.byType(TowerTray), matching: find.byType(InkWell));
    await tester.tap(cells.at(1));
    await tester.pump();
    final p = vm.placement.value!;
    expect((p.turretId, p.at, p.locked), ('green', const Vec2(200, 100), true));
    // The armed cell again cancels.
    await tester.tap(cells.at(1));
    await tester.pump();
    expect(vm.placement.value, isNull);
  });
}
