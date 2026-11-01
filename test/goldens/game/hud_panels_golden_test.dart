import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:onslaught3_remastered/features/game/game_view_model.dart';
import 'package:onslaught3_remastered/features/game/hud/game_over_panel.dart';
import 'package:onslaught3_remastered/features/game/hud/tower_tray.dart';
import 'package:onslaught3_remastered/features/game/hud/turret_sheet.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../support/fake_game_view_model.dart';
import '../../support/pump.dart';
import '../../support/test_data.dart';
import '../devices.dart';

class _NoInput implements PlacementInput {
  @override
  void dragTo(String turretId, Offset globalPosition, {bool touch = false, bool start = false}) {}
  @override
  void dragEnd() {}
}

/// Goldens for the Phase 1 HUD panels: tower tray, selected-turret sheet and
/// game-over dialog, rendered from [FakeGameViewModel] (golden-tests skill).
/// No asset pack is given, so sprites draw as placeholder discs.
void main() {
  final GameData data = loadTestGameData();

  final blue = data.turrets['blue']!;
  List<TrayItem> tray({required bool affordable}) => [
    TrayItem(
      id: blue.id,
      name: blue.name,
      cost: blue.cost,
      icon: blue.art.icon,
      affordable: affordable,
    ),
  ];

  goldenTest(
    'tower tray',
    fileName: 'tower_tray',
    builder: () => GoldenTestGroup(
      columns: 4,
      children: [
        for (final (name, affordable, armed) in [
          ('affordable', true, false),
          ('cannot afford', false, false),
          ('armed', true, true),
        ])
          GoldenTestScenario(
            name: name,
            constraints: const BoxConstraints.tightFor(width: TowerTray.width, height: 220),
            child: goldenHost(
              TowerTray(
                viewModel:
                    FakeGameViewModel(
                        data: data,
                        tray: tray(affordable: affordable),
                      )
                      ..previewPlacement(armed ? 'blue' : 'blue', null)
                      ..cancelPlacementIf(!armed),
                input: _NoInput(),
              ),
            ),
          ),
        GoldenTestScenario(
          name: 'dark',
          constraints: const BoxConstraints.tightFor(width: TowerTray.width, height: 220),
          child: goldenHost(
            TowerTray(
              viewModel: FakeGameViewModel(data: data),
              input: _NoInput(),
            ),
            brightness: Brightness.dark,
          ),
        ),
      ],
    ),
  );

  Widget sheet(TurretPanel panel, {double cash = 30, Brightness b = Brightness.light, double? t}) =>
      goldenHost(
        Align(
          alignment: Alignment.bottomCenter,
          child: TurretSheet(
            viewModel: FakeGameViewModel(
              data: data,
              selection: panel,
              hud: HudState(cash: cash, lives: 10, kills: 0, wave: 1, paused: false, speed: 1),
            ),
          ),
        ),
        brightness: b,
        textScale: t,
      );

  goldenTest(
    'turret sheet',
    fileName: 'turret_sheet',
    builder: () => GoldenTestGroup(
      columns: 1,
      children: [
        for (final d in {'phone': GoldenDevices.phone, 'tablet': GoldenDevices.tablet}.entries) ...[
          GoldenTestScenario(
            name: '${d.key} fresh blue, \$30',
            constraints: BoxConstraints.tight(
              Size(d.value.width - TowerTray.width, TurretSheet.height + 16),
            ),
            child: sheet(bluePanel(data)),
          ),
          GoldenTestScenario(
            name: '${d.key} blue mid-game, rich, lock off, strongest',
            constraints: BoxConstraints.tight(
              Size(d.value.width - TowerTray.width, TurretSheet.height + 16),
            ),
            child: sheet(
              bluePanel(
                data,
                damage: 4,
                range: 2,
                rate: 3,
                cash: 5000,
                lockOff: true,
                mode: 'strong',
              ),
              cash: 5000,
            ),
          ),
        ],
        GoldenTestScenario(
          name: 'phone maxed, paused (dark)',
          constraints: BoxConstraints.tight(
            Size(GoldenDevices.phone.width - TowerTray.width, TurretSheet.height + 16),
          ),
          child: sheet(
            bluePanel(data, damage: 9, range: 5, rate: 7, cash: 100, locked: true),
            cash: 100,
            b: Brightness.dark,
          ),
        ),
        GoldenTestScenario(
          name: 'phone large text',
          constraints: BoxConstraints.tight(
            Size(GoldenDevices.phone.width - TowerTray.width, TurretSheet.height + 16),
          ),
          child: sheet(bluePanel(data, damage: 2, cash: 200), cash: 200, t: 1.3),
        ),
      ],
    ),
  );

  goldenTest(
    'game over panel',
    fileName: 'game_over_panel',
    builder: () => GoldenTestGroup(
      columns: 2,
      children: [
        for (final b in Brightness.values)
          GoldenTestScenario(
            name: b.name,
            constraints: BoxConstraints.tight(const Size(400, 340)),
            child: goldenHost(
              GameOverPanel(
                viewModel: FakeGameViewModel(
                  data: data,
                  gameOver: const GameOverSummary(
                    wave: 51,
                    kills: 508,
                    shots: 2210,
                    spent: 12300,
                    score: 6248400,
                  ),
                ),
                onRestart: () {},
                onMenu: () {},
              ),
              brightness: b,
            ),
          ),
      ],
    ),
  );
}

extension on FakeGameViewModel {
  /// Clears the ghost when [clear] (lets a cascade build both states).
  // ignore: avoid_positional_boolean_parameters
  void cancelPlacementIf(bool clear) {
    if (clear) cancelPlacement();
  }
}
