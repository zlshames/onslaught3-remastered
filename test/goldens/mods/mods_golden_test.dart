import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onslaught3_remastered/app/providers.dart';
import 'package:onslaught3_remastered/features/mods/mods_screen.dart';
import 'package:onslaught3_remastered/services/persistence/mod_library.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../support/pump.dart';
import '../../support/test_data.dart';
import '../devices.dart';

/// Goldens for the Phase 7 mod editor: a new (empty) mod, a mod with
/// changes (marked items and values, Reset, the default, the signature)
/// at phone sizes and on a tablet, and the indexed-value editor.
void main() {
  final GameData data = loadTestGameData();
  final rules = ModRules(data, behaviours: RulesRegistry.classic());
  var mod = rules.withValue(
    const ModDelta({}, name: 'Big Blue'),
    rules.field('TurretBlue.weapon_damage')!,
    99,
  );
  mod = rules.withValue(mod, rules.field('TurretBlue.weapon_must_face')!, false);
  mod = rules.withValue(mod, rules.field('GameSettings.wave_size')!, 12);
  final modded = ModLibrary(mod: mod, active: true);

  Widget screen(ModLibrary mods, {String? field}) => ProviderScope(
    overrides: appOverrides(
      data: data,
      fakes: false,
      extra: [modsProvider.overrideWith(() => _FixedMods(mods))],
    ),
    child: MaterialApp(debugShowCheckedModeBanner: false, home: ModsScreen(initialField: field)),
  );

  goldenTest(
    'mod editor',
    fileName: 'mods_screen',
    pumpBeforeTest: (tester) async => tester.pump(const Duration(milliseconds: 50)),
    builder: () => GoldenTestGroup(
      columns: 1,
      children: [
        GoldenTestScenario(
          name: 'phone new mod',
          constraints: BoxConstraints.tight(GoldenDevices.phone),
          child: screen(const ModLibrary()),
        ),
        GoldenTestScenario(
          name: 'phoneSmall Blue damage changed',
          constraints: BoxConstraints.tight(GoldenDevices.phoneSmall),
          child: screen(modded, field: 'TurretBlue.weapon_damage'),
        ),
        GoldenTestScenario(
          name: 'phone upgrade path',
          constraints: BoxConstraints.tight(GoldenDevices.phone),
          child: screen(modded, field: 'TurretBlue.upgrade_damage'),
        ),
        GoldenTestScenario(
          name: 'tablet settings',
          constraints: BoxConstraints.tight(GoldenDevices.tablet),
          child: screen(modded, field: 'GameSettings.wave_size'),
        ),
      ],
    ),
  );

  goldenTest(
    'mod editor in portrait',
    fileName: 'mods_screen_portrait',
    pumpBeforeTest: (tester) async => tester.pump(const Duration(milliseconds: 50)),
    builder: () => GoldenTestGroup(
      columns: 2,
      children: [
        GoldenTestScenario(
          name: 'phonePortrait items',
          constraints: BoxConstraints.tight(GoldenDevices.phonePortrait),
          child: screen(modded),
        ),
        GoldenTestScenario(
          name: 'tabletPortrait three panes',
          constraints: BoxConstraints.tight(GoldenDevices.tabletPortrait),
          child: screen(modded, field: 'TurretBlue.weapon_damage'),
        ),
      ],
    ),
  );
}

class _FixedMods extends ModsNotifier {
  _FixedMods(this.mods);

  final ModLibrary mods;

  @override
  Future<ModLibrary> build() async => mods;
}
