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

/// Goldens for the Phase 4 HUD: the Targeter, Fusion and Combonly cards on
/// the selected-turret sheet, with their buttons. No asset pack is given, so
/// sprites draw as placeholder discs.
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

  const nuke = (colour: 'red', recipe: 'nuke', name: 'Nuke');
  const landmine = (colour: 'blue', recipe: 'big-landmine', name: 'Big Landmine');

  goldenTest(
    'turret sheet super turret cards',
    fileName: 'turret_sheet_super_cards',
    builder: () => GoldenTestGroup(
      columns: 1,
      children: [
        GoldenTestScenario(
          name: 'targeter: joining, two joined',
          constraints: phone,
          child: sheet(
            turretPanel(
              data,
              'targeter',
              range: 2,
              cards: const [TargeterCard(joins: 2, max: 3, joining: true)],
            ),
          ),
        ),
        GoldenTestScenario(
          name: 'fusion: medium store, three feeders',
          constraints: phone,
          child: sheet(
            turretPanel(
              data,
              'fusion',
              damage: 1,
              cards: const [
                FusionCard(storeDamage: 4.25e7, storePoison: 64.4, tier: 'med', feeders: 3),
              ],
            ),
          ),
        ),
        GoldenTestScenario(
          name: 'combonly: showing the nuke (dark)',
          constraints: phone,
          child: sheet(
            turretPanel(
              data,
              'combonly',
              cards: const [
                CombonlyCard(options: [nuke, landmine], shown: nuke, chosen: null, armed: false),
              ],
            ),
            b: Brightness.dark,
          ),
        ),
        GoldenTestScenario(
          name: 'sniper: no cards',
          constraints: phone,
          child: sheet(turretPanel(data, 'sniper', damage: 3, range: 1)),
        ),
      ],
    ),
  );
}
