import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:onslaught_core/onslaught_core.dart';

import '../../../app/strings.dart';
import '../../../services/persistence/settings.dart' show PlacementMode;
import '../game_view_model.dart';

/// While a turret is armed from the tray (or a move is pending), tells the
/// player to tap the map (to build, or with drop and lock to drop it), with
/// Cancel; once a ghost is dropped and locked, to drag to adjust it, with
/// Cancel and Place (or Move here), which builds only where it is valid.
class PlacementHint extends StatelessWidget {
  const PlacementHint({super.key, required this.viewModel, required this.mode});

  final GameViewModel viewModel;

  /// The player's placement mode.
  final ValueListenable<PlacementMode> mode;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<PlacementPreview?>(
    valueListenable: viewModel.placement,
    builder: (context, p, _) => ValueListenableBuilder<PlacementMode>(
      valueListenable: mode,
      builder: (context, mode, _) => p == null ? const SizedBox.shrink() : _hint(context, p, mode),
    ),
  );

  Widget _hint(BuildContext context, PlacementPreview p, PlacementMode mode) {
    final name = viewModel.data.turretName(p.turretId, locale: uiLocale(context));
    final building = p.moving == null;
    final drop = mode == PlacementMode.dropAndLock;
    final text = switch ((p.locked, drop, building)) {
      (true, _, _) => 'ui.game.placeAdjust',
      (false, true, true) => 'ui.game.placeDropBuild',
      (false, true, false) => 'ui.game.placeDropMove',
      (false, false, true) => 'ui.game.placeBuild',
      (false, false, false) => 'ui.game.placeMove',
    };
    return Material(
      color: Colors.black87,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.only(left: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Wraps on a narrow portrait phone rather than overflowing.
            Flexible(
              child: Text(
                viewModel.data.tr(context, text, {'name': name}),
                style: const TextStyle(color: Colors.white),
              ),
            ),
            TextButton(
              onPressed: viewModel.cancelPlacement,
              child: Text(viewModel.data.tr(context, 'ui.common.cancel')),
            ),
            if (p.locked)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: FilledButton(
                  // Greyed out on the dark bar where the ghost cannot go.
                  style: FilledButton.styleFrom(
                    disabledBackgroundColor: Colors.white12,
                    disabledForegroundColor: Colors.white38,
                  ),
                  onPressed: p.valid ? viewModel.commitPlacement : null,
                  child: Text(
                    viewModel.data.tr(
                      context,
                      building ? 'ui.game.placeConfirm' : 'ui.game.moveConfirm',
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
