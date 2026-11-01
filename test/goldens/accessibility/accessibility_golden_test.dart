import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onslaught3_remastered/app/feature_flags.dart';
import 'package:onslaught3_remastered/app/providers.dart';
import 'package:onslaught3_remastered/features/game/effect_settings.dart';
import 'package:onslaught3_remastered/features/game/game_view_model.dart';
import 'package:onslaught3_remastered/features/game/hud/tower_tray.dart';
import 'package:onslaught3_remastered/features/game/hud/turret_sheet.dart';
import 'package:onslaught3_remastered/features/menu/map_screen.dart';
import 'package:onslaught3_remastered/features/menu/mode_screen.dart';
import 'package:onslaught3_remastered/features/menu/settings_screen.dart';
import 'package:onslaught3_remastered/services/persistence/profile.dart';
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

/// Phase 8 accessibility goldens: the menus with the system text at 130 %
/// (the large-text release gate), and the colour badges on the tray and the
/// sheet at normal and large text (golden-tests skill).
void main() {
  final GameData data = loadTestGameData();
  const large = 1.3;

  Widget scaled(Widget child, double textScale) => MediaQuery(
    data: MediaQueryData(size: GoldenDevices.phone, textScaler: TextScaler.linear(textScale)),
    child: child,
  );

  Widget screen(Widget child) => ProviderScope(
    overrides: appOverrides(
      data: data,
      flags: const FeatureFlags(),
      fakes: false,
      extra: [profileProvider.overrideWith(() => _FixedProfile(const Profile(unlockAll: true)))],
    ),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Builder(builder: (context) => scaled(child, large)),
    ),
  );

  goldenTest(
    'menus at large text',
    fileName: 'menus_large_text',
    pumpBeforeTest: (tester) async => tester.pump(const Duration(milliseconds: 50)),
    builder: () => GoldenTestGroup(
      columns: 1,
      children: [
        for (final (name, page) in [
          ('mode', const ModeScreen()),
          ('map', const MapScreen()),
          ('settings', const SettingsScreen()),
        ])
          GoldenTestScenario(
            name: '$name 130 %',
            constraints: BoxConstraints.tight(GoldenDevices.phone),
            child: screen(page),
          ),
      ],
    ),
  );

  const badges = FixedEffects(EffectSettings(rocketSmoke: true, smokeMax: 100, colourBadges: true));
  final tray = [
    for (final id in ['blue', 'green', 'red', 'yellow', 'range-up'])
      TrayItem(
        id: id,
        name: data.turrets[id]!.name,
        cost: data.turrets[id]!.cost,
        icon: data.turrets[id]!.art.icon,
        affordable: true,
      ),
  ];

  Widget hud(double textScale, Brightness brightness) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(brightness: brightness),
    home: scaled(
      Scaffold(
        backgroundColor: const Color(0xFFE8C9A0),
        body: Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: TurretSheet(
                  viewModel: FakeGameViewModel(data: data, selection: bluePanel(data)),
                  effects: badges,
                ),
              ),
            ),
            TowerTray(
              viewModel: FakeGameViewModel(data: data, tray: tray),
              input: _NoInput(),
              effects: badges,
            ),
          ],
        ),
      ),
      textScale,
    ),
  );

  goldenTest(
    'colour badges',
    fileName: 'colour_badges',
    builder: () => GoldenTestGroup(
      columns: 1,
      children: [
        for (final (name, scale, brightness) in [
          ('phone', 1.0, Brightness.light),
          ('phone 130 %', large, Brightness.light),
          ('phone dark', 1.0, Brightness.dark),
        ])
          GoldenTestScenario(
            name: name,
            constraints: BoxConstraints.tight(GoldenDevices.phone),
            child: hud(scale, brightness),
          ),
      ],
    ),
  );
}

class _FixedProfile extends ProfileNotifier {
  _FixedProfile(this.profile);

  final Profile profile;

  @override
  Future<Profile> build() async => profile;
}
