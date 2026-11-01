import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:onslaught3_remastered/features/game/game_view_model.dart';
import 'package:onslaught3_remastered/features/game/hud/tower_tray.dart';
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

/// Goldens for the full tower tray: the four colours, and the modifiers
/// locked at the start and unlocked later. No asset pack is given, so
/// sprites draw as placeholder discs.
void main() {
  final GameData data = loadTestGameData();

  List<TrayItem> tray({required int kills, required double cash}) => [
    for (final def in data.turrets.values)
      if (def.category.name == 'basic' || def.category.name == 'modifier')
        TrayItem(
          id: def.id,
          name: def.name,
          cost: def.cost,
          icon: def.art.icon,
          affordable: cash >= def.cost,
          locked: !def.availableInitially && kills < def.unlockKills,
          unlockKills: def.unlockKills,
          killsToUnlock: def.availableInitially ? 0 : (def.unlockKills - kills).clamp(0, 1 << 30),
        ),
  ];

  goldenTest(
    'tower tray locks',
    fileName: 'tower_tray_locks',
    builder: () => GoldenTestGroup(
      columns: 2,
      children: [
        for (final (name, kills, cash) in [
          ('start: four colours, modifiers locked', 0, 30.0),
          ('500 kills, rich', 500, 6000.0),
        ])
          GoldenTestScenario(
            name: name,
            constraints: const BoxConstraints.tightFor(width: TowerTray.width, height: 820),
            child: goldenHost(
              TowerTray(
                viewModel: FakeGameViewModel(
                  data: data,
                  tray: tray(kills: kills, cash: cash),
                ),
                input: _NoInput(),
              ),
            ),
          ),
      ],
    ),
  );
}
