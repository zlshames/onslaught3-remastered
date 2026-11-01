import 'package:flutter/material.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../../app/strings.dart';

/// Covers the game when the window is too small for any HUD layout
/// (`docs/history/SCREEN_FIT_PLAN.md` §8): "Make the window bigger". The game
/// pauses behind it and resumes when the window is playable again.
class UnsupportedShape extends StatelessWidget {
  const UnsupportedShape({super.key, required this.data});

  final GameData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: Colors.black87,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.open_in_full, color: Colors.white70, size: 28),
              const SizedBox(height: 8),
              Text(
                data.tr(context, 'ui.game.windowTooSmall'),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 4),
              Text(
                data.tr(context, 'ui.game.windowTooSmallInfo'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
