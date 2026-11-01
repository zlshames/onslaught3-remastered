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

/// Goldens for the selected-turret sheet's special cards per turret. No
/// asset pack is given, so sprites draw as placeholder discs.
void main() {
  final GameData data = loadTestGameData();

  Widget sheet(TurretPanel panel, {double cash = 30, Brightness b = Brightness.light}) =>
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
      );

  final phone = BoxConstraints.tight(
    Size(GoldenDevices.phone.width - TowerTray.width, TurretSheet.height + 16),
  );
  final aura = auraTerms(data.turrets['rate-up-exchange']!.modifierAura!);

  goldenTest(
    'turret sheet special cards',
    fileName: 'turret_sheet_special_cards',
    builder: () => GoldenTestGroup(
      columns: 1,
      children: [
        GoldenTestScenario(
          name: 'yellow: freakout ready to buy, charge',
          constraints: phone,
          child: sheet(
            turretPanel(
              data,
              'yellow',
              damage: 4,
              rate: 4,
              cash: 20000,
              cards: const [
                FreakoutCard(
                  available: true,
                  stage: 'idle',
                  nextSeconds: 34,
                  buyCost: 8500,
                  affordable: true,
                ),
                ChargeCard(charge: 92.4, max: 140, ratePerSecond: 18, shotPoison: 8.5),
              ],
            ),
            cash: 20000,
          ),
        ),
        GoldenTestScenario(
          name: 'blue freaking out, range raised by an aura',
          constraints: phone,
          child: sheet(
            turretPanel(
              data,
              'blue',
              damage: 4,
              rate: 4,
              terms: const StatTerms(addRange: 100, multDamage: 3, multRate: 4),
              cards: const [
                FreakoutCard(
                  available: true,
                  stage: 'active',
                  nextSeconds: 51,
                  buyCost: 12750,
                  affordable: false,
                ),
              ],
            ),
          ),
        ),
        GoldenTestScenario(
          name: 'red: holding pattern, 3 of 4 held',
          constraints: phone,
          child: sheet(
            turretPanel(
              data,
              'red',
              range: 3,
              rate: 3,
              cards: const [
                HoldingCard(unlocked: true, held: 3, max: 4, levelRange: 3, levelRate: 3),
              ],
            ),
          ),
        ),
        GoldenTestScenario(
          name: 'green: linked to 2 (dark)',
          constraints: phone,
          child: sheet(
            turretPanel(
              data,
              'green',
              damage: 2,
              cards: const [LinkCard(links: 2, lastDamage: 270, mult: 1.25)],
            ),
            b: Brightness.dark,
          ),
        ),
        GoldenTestScenario(
          name: 'rate exchanger aura',
          constraints: phone,
          child: sheet(
            turretPanel(
              data,
              'rate-up-exchange',
              cards: [AuraCard(terms: aura, radius: 80, covered: 3)],
            ),
          ),
        ),
      ],
    ),
  );
}
