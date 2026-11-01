import 'package:flutter/material.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../app/dialogs.dart';
import '../../app/format.dart';
import '../../app/strings.dart';
import '../../services/persistence/game_in_progress.dart';

/// What the player chose for the stored game in progress.
enum ResumeChoice { resume, discard }

/// Asks whether to resume the stored [game] (its map, difficulty, wave,
/// lives and cash) or discard it; null when dismissed.
Future<ResumeChoice?> askResumeGame(
  BuildContext context, {
  required GameData data,
  required GameInProgress game,
}) => showDialog<ResumeChoice>(
  context: context,
  builder: (context) => ResumeGameDialog(data: data, game: game),
);

/// The dialog of [askResumeGame].
class ResumeGameDialog extends StatelessWidget {
  const ResumeGameDialog({super.key, required this.data, required this.game});

  final GameData data;
  final GameInProgress game;

  /// The stored game's map name: the player map's own, or the data's in the
  /// interface language.
  String _mapName(BuildContext context) {
    final custom = game.customMap;
    if (custom != null) return custom.name;
    final map = data.maps[game.mapId];
    return map == null ? game.mapId : data.mapName(map, locale: uiLocale(context));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget line(String key, Object value) =>
        Text(data.tr(context, key, {'value': value}), style: text.bodyLarge);
    return CompactDialog(
      title: data.tr(context, 'ui.resume.title'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(data.tr(context, 'ui.resume.body')),
            const SizedBox(height: 12),
            line('ui.resume.map', _mapName(context)),
            line('ui.resume.difficulty', data.tr(context, 'difficulty.${game.difficulty}')),
            line('ui.resume.wave', game.wave),
            line('ui.resume.lives', game.lives),
            line('ui.resume.cash', formatCash(context, data, game.cash)),
            const SizedBox(height: 8),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('discardGame'),
          onPressed: () => Navigator.of(context).pop(ResumeChoice.discard),
          child: Text(data.tr(context, 'ui.resume.discard')),
        ),
        FilledButton(
          key: const Key('resumeGame'),
          onPressed: () => Navigator.of(context).pop(ResumeChoice.resume),
          child: Text(data.tr(context, 'ui.resume.resume')),
        ),
      ],
    );
  }
}
