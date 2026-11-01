import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:onslaught3_remastered/features/game/hud/placement_hint.dart';
import 'package:onslaught3_remastered/services/persistence/settings.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../support/fake_game_view_model.dart';
import '../../support/pump.dart';
import '../../support/test_data.dart';
import '../devices.dart';

/// Goldens for the placement bar: an armed turret with each placement
/// mode, and a dropped-and-locked ghost (valid, blocked, a move) with
/// Place, at the narrowest phone, the tablet, dark and large text.
void main() {
  final GameData data = loadTestGameData();
  const at = Vec2(200, 100);

  /// A view model whose ghost [arm] set up.
  FakeGameViewModel ghost(void Function(FakeGameViewModel vm) arm) {
    final vm = FakeGameViewModel(data: data);
    arm(vm);
    return vm;
  }

  final states = <String, (PlacementMode, FakeGameViewModel Function())>{
    'armed drag': (
      PlacementMode.dragAndDrop,
      () => ghost((vm) => vm.previewPlacement('blue', null)),
    ),
    'armed lock': (
      PlacementMode.dropAndLock,
      () => ghost((vm) => vm.previewPlacement('blue', null)),
    ),
    'locked': (
      PlacementMode.dropAndLock,
      () => ghost((vm) => vm.previewPlacement('blue', at, locked: true)),
    ),
    'locked blocked': (
      PlacementMode.dropAndLock,
      () => ghost(
        (vm) => vm
          ..placementValid = false
          ..previewPlacement('blue', at, locked: true),
      ),
    ),
    'locked move': (
      PlacementMode.dropAndLock,
      () => ghost((vm) => vm.previewPlacement('blue', at, moving: 3, locked: true)),
    ),
  };

  Widget hint(PlacementMode mode, FakeGameViewModel vm) => Center(
    child: PlacementHint(viewModel: vm, mode: ValueNotifier(mode)),
  );

  goldenTest(
    'placement hint',
    fileName: 'placement_hint',
    builder: () => GoldenTestGroup(
      columns: 1,
      children: [
        for (final MapEntry(key: name, value: (mode, vm)) in states.entries)
          GoldenTestScenario(
            name: 'phoneSmallPortrait $name',
            constraints: BoxConstraints.tight(Size(GoldenDevices.phoneSmallPortrait.width, 72)),
            child: goldenHost(hint(mode, vm())),
          ),
        GoldenTestScenario(
          name: 'tablet locked dark',
          constraints: BoxConstraints.tight(Size(GoldenDevices.tablet.width, 72)),
          child: goldenHost(
            hint(PlacementMode.dropAndLock, states['locked']!.$2()),
            brightness: Brightness.dark,
          ),
        ),
        GoldenTestScenario(
          name: 'phoneSmallPortrait locked large text',
          constraints: BoxConstraints.tight(Size(GoldenDevices.phoneSmallPortrait.width, 96)),
          child: goldenHost(
            hint(PlacementMode.dropAndLock, states['locked']!.$2()),
            textScale: 1.3,
          ),
        ),
      ],
    ),
  );
}
