import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:onslaught_core/onslaught_core.dart';

import '../../../app/strings.dart';
import '../../../app/theme.dart';
import '../game_view_model.dart';

/// The end dialog, with Restart and Main Menu. Once the lives run out: the
/// game-over panel (`TurretInfoGameOver`: wave, kills, shots, spend, score).
/// When a challenge ends: the challenge-over panel
/// (`TurretInfoChallengeOver`: passed or failed, kills, time, spend, score;
/// the original never fills in the time). A win (a challenge passed, the
/// tutorial beaten) also offers Continue Playing (freeplay,
/// `ContinuePlaying`) and Watch Replay (not built yet: shown disabled).
class GameOverPanel extends StatelessWidget {
  const GameOverPanel({
    super.key,
    required this.viewModel,
    required this.onRestart,
    required this.onMenu,
  });

  final GameViewModel viewModel;
  final VoidCallback onRestart;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<GameOverSummary?>(
    valueListenable: viewModel.gameOver,
    builder: (context, summary, _) {
      if (summary == null) return const SizedBox.shrink();
      final theme = Theme.of(context);
      String n(num v) => v.toStringAsFixed(0);
      String two(int v) => v.toString().padLeft(2, '0');
      final data = viewModel.data;
      final challenge = summary.end != GameEnd.gameOver;
      final won = summary.end.won;
      final title = switch (summary.end) {
        GameEnd.gameOver => data.tr(context, 'ui.gameOver.title'),
        GameEnd.challengePassed => data.tr(context, 'flow.challengeWonTitle'),
        GameEnd.challengeFailed => data.tr(context, 'flow.challengeLostTitle'),
        GameEnd.tutorialComplete => data.tr(context, 'ui.gameOver.tutorialTitle'),
      };
      final text = switch (summary.end) {
        GameEnd.gameOver => null,
        GameEnd.challengePassed => data.tr(context, 'flow.challengeWonText'),
        GameEnd.challengeFailed => data.tr(context, 'flow.challengeLostText'),
        GameEnd.tutorialComplete => data.tr(context, 'ui.gameOver.tutorialText', {
          'waves': summary.wave,
        }),
      };
      final rows = challenge
          ? {
              data.tr(context, 'ui.gameOver.kills'): n(summary.kills),
              data.tr(context, 'ui.gameOver.time'):
                  '${two(summary.seconds ~/ 60)}:${two(summary.seconds % 60)}',
              data.tr(context, 'ui.gameOver.spent'): '\$${n(summary.spent)}',
              data.tr(context, 'ui.gameOver.score'): n(summary.score),
            }
          : {
              data.tr(context, 'ui.gameOver.wave'): n(summary.wave),
              data.tr(context, 'ui.gameOver.kills'): n(summary.kills),
              data.tr(context, 'ui.gameOver.shots'): n(summary.shots),
              data.tr(context, 'ui.gameOver.spent'): '\$${n(summary.spent)}',
              data.tr(context, 'ui.gameOver.score'): n(summary.score),
            };
      return ColoredBox(
        color: Colors.black54,
        child: LayoutBuilder(
          builder: (context, box) => Center(
            child: Semantics(
              label: challenge ? title : data.tr(context, 'ui.gameOver.label'),
              child: Container(
                // A win has two more buttons: wider, tighter. Narrow
                // portrait phones keep a margin.
                width: math.min(
                  won ? 360.0 : 320.0,
                  box.maxWidth.isFinite ? box.maxWidth - 32 : double.infinity,
                ),
                constraints: BoxConstraints(
                  maxHeight: box.maxHeight.isFinite
                      ? (box.maxHeight - 16).clamp(0, double.infinity)
                      : double.infinity,
                ),
                padding: EdgeInsets.all(won ? 16 : 20),
                decoration: BoxDecoration(
                  color: HudColours.gameOverPanel,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: challenge
                              ? (won ? Colors.greenAccent : Colors.redAccent)
                              : Colors.white,
                        ),
                      ),
                      if (text != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          text,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                      const SizedBox(height: 12),
                      for (final e in rows.entries)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Text(e.key, style: const TextStyle(color: Colors.white70)),
                              const Spacer(),
                              Text(
                                e.value,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 16),
                      if (won) ...[
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                onPressed: summary.canContinue
                                    ? () => viewModel.dispatch(const ContinuePlaying())
                                    : null,
                                child: Text(data.tr(context, 'ui.gameOver.continue')),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Tooltip(
                                message: data.tr(context, 'ui.gameOver.replaySoon'),
                                child: OutlinedButton(
                                  onPressed: null,
                                  style: OutlinedButton.styleFrom(
                                    disabledForegroundColor: Colors.white54,
                                    side: const BorderSide(color: Colors.white24),
                                  ),
                                  child: FittedBox(
                                    child: Text(
                                      data.tr(context, 'ui.gameOver.replay'),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: onMenu,
                              child: Text(data.tr(context, 'ui.gameOver.menu')),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: won
                                ? OutlinedButton(
                                    onPressed: onRestart,
                                    child: Text(data.tr(context, 'ui.gameOver.restart')),
                                  )
                                : FilledButton(
                                    onPressed: onRestart,
                                    child: Text(data.tr(context, 'ui.gameOver.restart')),
                                  ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
