import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../app/map_tile_grid.dart';
import '../../app/menu_scaffold.dart';
import '../../app/strings.dart';

/// "Choose a Map" (`GameSelectMap`): the built-in maps as thumbnails of
/// their roads. The title says what is being played (`GameSelectMap.update`):
/// the difficulty, the sandbox or the challenge. A map starts the game.
class MapScreen extends StatelessWidget {
  const MapScreen({super.key, this.mode = 'normal', this.difficulty = 'easy', this.challengeKey});

  final String mode;
  final String difficulty;

  /// The challenge being played ([challengeKey]), in the challenge mode.
  final String? challengeKey;

  bool get _challenge => mode == GameConfig.challengeMode;

  String _query() =>
      Uri(queryParameters: {'mode': mode, 'difficulty': difficulty, 'challenge': ?challengeKey})
          .query;

  @override
  Widget build(BuildContext context) => MenuData(
    builder: (context, data, profile) {
      final challenge = challengeKey == null
          ? null
          : challengeFromKey(challengeKey!, data.challenges);
      final title = switch (mode) {
        GameConfig.challengeMode => data.tr(context, 'ui.map.challengeTitle', {
          'name': challenge == null || challenge.id == customChallengeId
              ? data.tr(context, 'flow.customChallenge')
              : data.challengeName(challenge.id, challenge.name, locale: uiLocale(context)),
        }),
        'sandbox' => data.tr(context, 'ui.map.sandboxTitle'),
        'sandbox2' => data.tr(context, 'ui.map.superSandboxTitle'),
        _ => data.tr(context, 'ui.map.difficultyTitle', {
          'difficulty': data.tr(context, 'difficulty.$difficulty'),
        }),
      };
      final maps = [
        for (final m in data.maps.values)
          if (m.builtIn && m.id != data.tutorial.map) m,
      ];
      return MenuScaffold(
        title: title,
        onBack: () => context.go(
          _challenge
              ? Uri(path: '/challenge', queryParameters: {'challenge': ?challengeKey}).toString()
              : '/mode',
        ),
        child: MapTileGrid(
          children: [
            for (final m in maps)
              MapTile(
                map: m,
                data: data,
                name: data.mapName(m, locale: uiLocale(context)),
                label: data.tr(context, 'ui.map.tile', {
                  'name': data.mapName(m, locale: uiLocale(context)),
                }),
                onTap: () => context.go('/game/${m.id}?${_query()}'),
              ),
          ],
        ),
      );
    },
  );
}
