import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:onslaught3_remastered/features/game/game_view_model.dart';
import 'package:onslaught3_remastered/features/game/hud/stats_bar.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../support/fake_game_view_model.dart';
import '../../support/pump.dart';
import '../../support/test_data.dart';
import '../devices.dart';

void main() {
  final GameData data = loadTestGameData();

  Widget bar(HudState hud, {Brightness brightness = Brightness.light, double? textScale}) =>
      goldenHost(
        Align(
          alignment: Alignment.topCenter,
          child: StatsBar(
            viewModel: FakeGameViewModel(data: data, hud: hud),
            onExit: () {},
          ),
        ),
        brightness: brightness,
        textScale: textScale,
      );

  const start = HudState(
    cash: 30,
    lives: 10,
    kills: 0,
    wave: 0,
    paused: false,
    speed: 1,
    nextWaveSeconds: 20,
  );
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
    'stats bar',
    fileName: 'stats_bar',
    builder: () => GoldenTestGroup(
      columns: 1,
      children: [
        for (final d in GoldenDevices.all.entries) ...[
          GoldenTestScenario(
            name: '${d.key} start',
            constraints: BoxConstraints.tight(Size(d.value.width, 64)),
            child: bar(start),
          ),
          GoldenTestScenario(
            name: '${d.key} late paused dark',
            constraints: BoxConstraints.tight(Size(d.value.width, 64)),
            child: bar(late, brightness: Brightness.dark),
          ),
        ],
        GoldenTestScenario(
          name: 'phone large text',
          constraints: BoxConstraints.tight(Size(GoldenDevices.phone.width, 72)),
          child: bar(late, textScale: 1.3),
        ),
      ],
    ),
  );
}
