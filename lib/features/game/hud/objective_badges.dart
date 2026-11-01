import 'package:flutter/material.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../../app/strings.dart';
import '../game_view_model.dart';

/// The challenge target badges under the top bar (`TheTimeLimit`,
/// `TheWaveLimit`, `TheKillTarget`): time left, waves and kills against
/// the target. A reached target glows green with a tick, a missed one red;
/// a badge flashes every 50 waves or 100 kills.
class ObjectiveBadges extends StatelessWidget {
  const ObjectiveBadges({super.key, required this.viewModel});

  final GameViewModel viewModel;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<ObjectiveBadge>>(
    valueListenable: viewModel.objectives,
    builder: (context, badges, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final b in badges)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _Badge(data: viewModel.data, badge: b),
          ),
      ],
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.data, required this.badge});

  final GameData data;
  final ObjectiveBadge badge;

  static const Map<String, IconData> _icons = {
    'time': Icons.timer_outlined,
    'waves': Icons.waves,
    'kills': Icons.gps_fixed,
  };

  /// The `strings` key of each badge's spoken name.
  static const Map<String, String> _names = {
    'time': 'ui.hud.timeLeft',
    'waves': 'ui.hud.waves',
    'kills': 'ui.gameOver.kills',
  };

  @override
  Widget build(BuildContext context) {
    final (border, glow) = switch (badge.state) {
      BadgeState.reached => (Colors.greenAccent, Colors.greenAccent.withValues(alpha: 0.5)),
      BadgeState.missed => (Colors.redAccent, Colors.redAccent.withValues(alpha: 0.5)),
      BadgeState.pending => (Colors.white24, Colors.transparent),
    };
    final name = _names[badge.kind];
    final args = {'name': name == null ? badge.kind : data.tr(context, name), 'value': badge.text};
    return Semantics(
      label: switch (badge.state) {
        BadgeState.reached => data.tr(context, 'ui.hud.objectiveReached', args),
        BadgeState.missed => data.tr(context, 'ui.hud.objectiveMissed', args),
        BadgeState.pending => data.tr(context, 'ui.hud.objective', args),
      },
      child: ExcludeSemantics(
        child: TweenAnimationBuilder<double>(
          // Restarts on every milestone: a short white flash.
          key: ValueKey(badge.milestone),
          tween: Tween(begin: badge.milestone == 0 ? 0 : 1, end: 0),
          duration: const Duration(milliseconds: 900),
          builder: (context, flash, child) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Color.lerp(Colors.black54, Colors.white54, flash),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: border),
              boxShadow: [BoxShadow(color: glow, blurRadius: 8)],
            ),
            child: child,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_icons[badge.kind] ?? Icons.flag, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                badge.text,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              if (badge.state == BadgeState.reached) ...[
                const SizedBox(width: 4),
                const Icon(Icons.check, size: 16, color: Colors.greenAccent),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
