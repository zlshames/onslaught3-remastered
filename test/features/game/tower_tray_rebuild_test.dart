import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/features/game/game_view_model.dart';
import 'package:onslaught3_remastered/features/game/hud/tower_tray.dart';
import 'package:onslaught3_remastered/services/assets/pack_sprite.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../support/fake_game_view_model.dart';
import '../../support/test_data.dart';

class _NoInput implements PlacementInput {
  @override
  void dragTo(String turretId, Offset globalPosition, {bool touch = false, bool start = false}) {}
  @override
  void dragEnd() {}
}

/// The tower tray during a drag: the ghost moves every frame, but only the
/// armed turret reaches the cells, so moving it rebuilds no cell, while
/// arming, a move and cancelling still light and clear the right cell.
void main() {
  late GameData data;
  setUpAll(() => data = loadTestGameData());

  TrayItem item(String id) {
    final def = data.turrets[id]!;
    return TrayItem(id: id, name: def.name, cost: def.cost, icon: def.art.icon, affordable: true);
  }

  final cells = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_TrayCell');

  testWidgets('moving the ghost rebuilds no cell; arming, moving and cancelling show', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1280, 720)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final vm = FakeGameViewModel(data: data, tray: [item('blue'), item('green')]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TowerTray(viewModel: vm, input: _NoInput()),
        ),
      ),
    );

    List<String?> armed() => [
      for (final s in tester.widgetList<Semantics>(
        find.descendant(of: find.byType(TowerTray), matching: find.byType(Semantics)),
      ))
        if (s.properties.selected ?? false) s.properties.label,
    ];
    void expectSame(List<Widget> a, List<Widget> b) {
      expect(a, hasLength(b.length));
      for (var i = 0; i < a.length; i++) {
        expect(identical(a[i], b[i]), isTrue, reason: 'widget $i was rebuilt');
      }
    }

    expect(armed(), isEmpty);
    final sprites = tester.widgetList(find.byType(PackSprite)).toList();

    vm.previewPlacement('blue', null);
    await tester.pump();
    expect(armed(), [contains(data.turrets['blue']!.name)]);
    // Arming changes only the highlight: the icons are not rebuilt.
    expectSame(tester.widgetList(find.byType(PackSprite)).toList(), sprites);

    final before = tester.widgetList(cells).toList();
    for (var i = 0; i < 5; i++) {
      vm.previewPlacement('blue', Vec2(100.0 + 10 * i, 120));
      await tester.pump();
    }
    expectSame(tester.widgetList(cells).toList(), before);
    expect(armed(), [contains(data.turrets['blue']!.name)]);

    // Moving a turret is not arming a tray cell.
    vm.previewPlacement('green', const Vec2(200, 120), moving: 7);
    await tester.pump();
    expect(armed(), isEmpty);

    vm.previewPlacement('green', null);
    await tester.pump();
    expect(armed(), [contains(data.turrets['green']!.name)]);

    // Tapping the armed cell disarms it.
    await tester.tap(find.text('\$${data.turrets['green']!.cost.toStringAsFixed(0)}'));
    await tester.pump();
    expect(vm.placement.value, isNull);
    expect(armed(), isEmpty);
  });
}
