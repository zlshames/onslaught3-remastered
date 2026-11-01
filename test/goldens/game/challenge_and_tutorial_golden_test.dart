import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onslaught3_remastered/features/game/game_view_model.dart';
import 'package:onslaught3_remastered/features/game/hud/game_over_panel.dart';
import 'package:onslaught3_remastered/features/game/hud/objective_badges.dart';
import 'package:onslaught3_remastered/features/game/hud/tutorial_panel.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../support/fake_game_view_model.dart';
import '../../support/pump.dart';
import '../../support/test_data.dart';
import '../devices.dart';

/// Goldens for the Phase 5 HUD: challenge target badges, the challenge-over
/// dialog and the tutorial window.
void main() {
  final GameData data = loadTestGameData();

  Widget frame(Widget child) => ProviderScope(
    overrides: appOverrides(data: data, fakes: false),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(backgroundColor: const Color(0xFF5B7F3A), body: child),
    ),
  );

  goldenTest(
    'challenge badges',
    fileName: 'objective_badges',
    builder: () => GoldenTestGroup(
      columns: 1,
      children: [
        GoldenTestScenario(
          name: 'time, waves, kills: pending, reached, missed',
          constraints: const BoxConstraints.tightFor(width: 200, height: 120),
          child: frame(
            Padding(
              padding: const EdgeInsets.all(8),
              child: ObjectiveBadges(
                viewModel: FakeGameViewModel(data: data)
                  ..objectivesValue = const [
                    ObjectiveBadge(kind: 'time', text: '19:42'),
                    ObjectiveBadge(kind: 'waves', text: '100/100', state: BadgeState.reached),
                    ObjectiveBadge(kind: 'kills', text: '312/1000', state: BadgeState.missed),
                  ],
              ),
            ),
          ),
        ),
      ],
    ),
  );

  GameOverSummary end(GameEnd e) => GameOverSummary(
    wave: e == GameEnd.tutorialComplete ? 50 : 31,
    kills: 302,
    shots: 1200,
    spent: 1450,
    score: 437900,
    end: e,
    seconds: 1199,
    canContinue: e.won,
  );

  goldenTest(
    'challenge over dialog',
    fileName: 'challenge_over_panel',
    builder: () => GoldenTestGroup(
      columns: 3,
      children: [
        for (final e in [
          GameEnd.challengePassed,
          GameEnd.challengeFailed,
          GameEnd.tutorialComplete,
        ])
          GoldenTestScenario(
            name: e.name,
            constraints: BoxConstraints.tight(GoldenDevices.phone),
            child: frame(
              GameOverPanel(
                viewModel: FakeGameViewModel(data: data, gameOver: end(e)),
                onRestart: () {},
                onMenu: () {},
              ),
            ),
          ),
      ],
    ),
  );

  goldenTest(
    'tutorial window',
    fileName: 'tutorial_panel',
    builder: () => GoldenTestGroup(
      columns: 1,
      children: [
        GoldenTestScenario(
          name: 'a page without a target',
          constraints: BoxConstraints.tight(GoldenDevices.phone),
          child: frame(
            TutorialPanel(
              pages: [data.tutorial.pages[7], data.tutorial.pages[8]],
              top: 48,
              resolve: (_) => null,
              onShow: (_) {},
              onClose: () {},
            ),
          ),
        ),
      ],
    ),
  );
}
