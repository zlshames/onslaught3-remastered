import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:onslaught3_remastered/app/camera_rig.dart';
import 'package:onslaught3_remastered/app/ui_skin.dart';
import 'package:onslaught3_remastered/features/game/game_view_model.dart';
import 'package:onslaught3_remastered/features/game/hud/stats_bar.dart';
import 'package:onslaught3_remastered/features/game/hud/tower_tray.dart';
import 'package:onslaught3_remastered/features/game/hud/turret_sheet.dart';
import 'package:onslaught3_remastered/features/game/layout/hud_layout.dart';
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

/// Goldens for the screen-fit HUD forms (`docs/history/PORTRAIT_PLAN.md`): the
/// compact stats bar and the Enhanced stats rail, the tray strip, the
/// compact turret sheet, and the whole HUD laid out per screen and skin.
void main() {
  final GameData data = loadTestGameData();

  const late = HudState(
    cash: 123456,
    lives: 3,
    kills: 2400,
    wave: 187,
    paused: true,
    speed: 2,
    nextWaveSeconds: 7.3,
  );

  goldenTest(
    'stats bar compact and rail',
    fileName: 'stats_bar_compact',
    builder: () => GoldenTestGroup(
      columns: 1,
      children: [
        for (final d in GoldenDevices.portrait.entries.where((d) => d.value.width < 560)) ...[
          GoldenTestScenario(
            name: '${d.key} start',
            constraints: BoxConstraints.tight(Size(d.value.width, 56)),
            child: goldenHost(
              Align(
                alignment: Alignment.topCenter,
                child: StatsBar(
                  viewModel: FakeGameViewModel(data: data),
                  onExit: () {},
                ),
              ),
            ),
          ),
          GoldenTestScenario(
            name: '${d.key} late paused dark',
            constraints: BoxConstraints.tight(Size(d.value.width, 56)),
            child: goldenHost(
              Align(
                alignment: Alignment.topCenter,
                child: StatsBar(
                  viewModel: FakeGameViewModel(data: data, hud: late),
                  onExit: () {},
                  onSettings: () {},
                ),
              ),
              brightness: Brightness.dark,
            ),
          ),
        ],
        GoldenTestScenario(
          name: 'phoneSmallPortrait large text',
          constraints: BoxConstraints.tight(Size(GoldenDevices.phoneSmallPortrait.width, 64)),
          child: goldenHost(
            Align(
              alignment: Alignment.topCenter,
              child: StatsBar(
                viewModel: FakeGameViewModel(data: data, hud: late),
                onExit: () {},
                onSettings: () {},
              ),
            ),
            textScale: 1.3,
          ),
        ),
        GoldenTestScenario(
          name: 'rail (Enhanced) on a landscape phone',
          constraints: BoxConstraints.tight(Size(StatsBar.railWidth, GoldenDevices.phone.height)),
          child: goldenHost(
            StatsBar(
              viewModel: FakeGameViewModel(data: data, hud: late),
              onExit: () {},
              onSettings: () {},
              axis: Axis.vertical,
            ),
          ),
        ),
      ],
    ),
  );

  final blue = data.turrets['blue']!;
  final green = data.turrets['green']!;
  List<TrayItem> items() => [
    for (final (t, affordable) in [(blue, true), (green, false)])
      TrayItem(id: t.id, name: t.name, cost: t.cost, icon: t.art.icon, affordable: affordable),
  ];

  goldenTest(
    'tower tray strip',
    fileName: 'tower_tray_strip',
    builder: () => GoldenTestGroup(
      columns: 1,
      children: [
        for (final b in Brightness.values)
          GoldenTestScenario(
            name: 'phonePortrait ${b.name}',
            constraints: BoxConstraints.tight(
              Size(GoldenDevices.phonePortrait.width, TowerTray.stripHeight),
            ),
            child: goldenHost(
              TowerTray(
                viewModel: FakeGameViewModel(data: data, tray: items()),
                input: _NoInput(),
                axis: Axis.horizontal,
              ),
              brightness: b,
            ),
          ),
        GoldenTestScenario(
          name: 'phonePortrait default tray',
          constraints: BoxConstraints.tight(
            Size(GoldenDevices.phonePortrait.width, TowerTray.stripHeight),
          ),
          child: goldenHost(
            TowerTray(
              viewModel: FakeGameViewModel(data: data),
              input: _NoInput(),
              axis: Axis.horizontal,
            ),
          ),
        ),
      ],
    ),
  );

  Widget sheet(
    TurretPanel panel, {
    double cash = 30,
    Brightness b = Brightness.light,
    double? t,
    SheetEdge edge = SheetEdge.bottom,
  }) => goldenHost(
    Align(
      alignment: edge == SheetEdge.top ? Alignment.topCenter : Alignment.bottomCenter,
      child: TurretSheet(
        viewModel: FakeGameViewModel(
          data: data,
          selection: panel,
          hud: HudState(cash: cash, lives: 10, kills: 0, wave: 1, paused: false, speed: 1),
        ),
        edge: edge,
      ),
    ),
    brightness: b,
    textScale: t,
  );

  final yellow = turretPanel(
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
  );

  goldenTest(
    'turret sheet compact',
    fileName: 'turret_sheet_compact',
    builder: () => GoldenTestGroup(
      columns: 3,
      children: [
        GoldenTestScenario(
          name: 'phonePortrait fresh blue',
          constraints: BoxConstraints.tight(Size(GoldenDevices.phonePortrait.width, 420)),
          child: sheet(bluePanel(data)),
        ),
        GoldenTestScenario(
          name: 'phoneSmallPortrait yellow with cards, top edge',
          constraints: BoxConstraints.tight(Size(GoldenDevices.phoneSmallPortrait.width, 420)),
          child: sheet(yellow, cash: 20000, edge: SheetEdge.top),
        ),
        GoldenTestScenario(
          name: 'side panel (Enhanced rails), dark',
          constraints: BoxConstraints.tight(const Size(HudMetrics.sidePanelWidth, 420)),
          child: sheet(yellow, cash: 20000, b: Brightness.dark, edge: SheetEdge.left),
        ),
        GoldenTestScenario(
          name: 'phonePortrait maxed, paused, large text',
          constraints: BoxConstraints.tight(Size(GoldenDevices.phonePortrait.width, 460)),
          child: sheet(
            bluePanel(data, damage: 9, range: 5, rate: 7, cash: 100, locked: true),
            cash: 100,
            t: 1.3,
          ),
        ),
      ],
    ),
  );

  /// The whole HUD on a screen: the stats and tray in their regions and the
  /// play area (the map) drawn as a plain rect where the camera's home view
  /// puts it (filling the space in portrait, where the ground also runs on
  /// past the map, drawn darker).
  Widget composed(Size screen, UiSkin skin) {
    final layout = HudLayout.resolve(screen, EdgeInsets.zero, skin: skin);
    final rig = CameraRig(world: const Rect.fromLTWH(0, 0, 720, 480))
      ..resize(screen)
      ..setFrame(layout.mapInsets, fill: layout.fillsMap, homeFloor: layout.homeFloor);
    final playArea = Rect.fromPoints(
      rig.worldToScreen(Offset.zero),
      rig.worldToScreen(const Offset(720, 480)),
    );
    final vm = FakeGameViewModel(data: data, tray: items());
    return goldenHost(
      ColoredBox(
        color: const Color(0xFFB89A7C),
        child: Stack(
          children: [
            Positioned.fromRect(
              rect: playArea,
              child: const ColoredBox(color: Color(0xFFE8C9A0)),
            ),
            Positioned.fromRect(
              rect: layout.stats,
              child: StatsBar(viewModel: vm, onExit: () {}, axis: layout.statsAxis),
            ),
            Positioned.fromRect(
              rect: layout.tray,
              child: TowerTray(viewModel: vm, input: _NoInput(), axis: layout.trayAxis),
            ),
          ],
        ),
      ),
    );
  }

  final sizes = {...GoldenDevices.all, ...GoldenDevices.landscapeExtra, ...GoldenDevices.portrait};
  for (final skin in UiSkin.values) {
    goldenTest(
      'hud layout ${skin.name}',
      fileName: 'hud_layout_${skin.name}',
      builder: () => GoldenTestGroup(
        columns: 4,
        children: [
          for (final d in sizes.entries)
            GoldenTestScenario(
              name: '${d.key} ${d.value.width.toInt()}×${d.value.height.toInt()}',
              constraints: BoxConstraints.tight(d.value),
              child: composed(d.value, skin),
            ),
        ],
      ),
    );
  }
}
