import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:onslaught3_remastered/features/game/game_view_model.dart';
import 'package:onslaught3_remastered/features/game/hud/tower_tray.dart';
import 'package:onslaught3_remastered/features/game/hud/turret_sheet.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../support/fake_game_view_model.dart';
import '../../support/pump.dart';
import '../../support/test_data.dart';
import '../devices.dart';

/// Goldens for the Phase 3 HUD: the combo card on the selected-turret sheet,
/// first among each colour's cards. No asset pack is given, so sprites draw
/// as placeholder discs.
void main() {
  final GameData data = loadTestGameData();

  Widget sheet(TurretPanel panel, {Brightness b = Brightness.light}) => goldenHost(
    Align(
      alignment: Alignment.bottomCenter,
      child: TurretSheet(
        viewModel: FakeGameViewModel(
          data: data,
          selection: panel,
          hud: const HudState(cash: 30, lives: 10, kills: 0, wave: 1, paused: false, speed: 1),
        ),
      ),
    ),
    brightness: b,
  );

  final phone = BoxConstraints.tight(
    Size(GoldenDevices.phone.width - TowerTray.width, TurretSheet.height + 16),
  );

  goldenTest(
    'turret sheet combo cards',
    fileName: 'turret_sheet_combo_cards',
    builder: () => GoldenTestGroup(
      columns: 1,
      children: [
        GoldenTestScenario(
          name: 'blue: combos locked, freakout idle',
          constraints: phone,
          child: sheet(
            turretPanel(
              data,
              'blue',
              damage: 6,
              cards: const [
                ComboCard(
                  capable: false,
                  damageLevelsToGo: 3,
                  nextSeconds: null,
                  partners: {},
                  recipe: null,
                  led: 0,
                  assisted: 0,
                ),
                FreakoutCard(
                  available: false,
                  stage: 'idle',
                  nextSeconds: null,
                  buyCost: null,
                  affordable: false,
                ),
              ],
            ),
          ),
        ),
        GoldenTestScenario(
          name: 'red: nuke ready with two blues',
          constraints: phone,
          child: sheet(
            turretPanel(
              data,
              'red',
              damage: 9,
              cards: const [
                ComboCard(
                  capable: true,
                  damageLevelsToGo: 0,
                  nextSeconds: null,
                  partners: {'blue': 2},
                  recipe: 'Nuke',
                  led: 2,
                  assisted: 0,
                ),
                HoldingCard(unlocked: false, held: 0, max: 4, levelRange: 3, levelRate: 3),
              ],
            ),
          ),
        ),
        GoldenTestScenario(
          name: 'yellow: recharging, three cards (dark)',
          constraints: phone,
          child: sheet(
            turretPanel(
              data,
              'yellow',
              damage: 7,
              cards: const [
                ComboCard(
                  capable: true,
                  damageLevelsToGo: 0,
                  nextSeconds: 14,
                  partners: {'yellow': 2, 'green': 1},
                  recipe: 'Black Hole',
                  led: 1,
                  assisted: 2,
                ),
                FreakoutCard(
                  available: true,
                  stage: 'idle',
                  nextSeconds: 34,
                  buyCost: 8500,
                  affordable: false,
                ),
                ChargeCard(charge: 92.4, max: 140, ratePerSecond: 18, shotPoison: 8.5),
              ],
            ),
            b: Brightness.dark,
          ),
        ),
      ],
    ),
  );
}
