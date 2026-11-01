import 'package:meta/meta.dart';

import '../data/attract_defs.dart';
import '../data/challenge_defs.dart';
import '../data/map_definition.dart';
import '../rules/rules_profile.dart';

/// Everything that defines a game before the first step: mode, difficulty,
/// map, rule set, optional challenge and the RNG seed. Same config + same
/// commands ⇒ same game.
@immutable
class GameConfig {
  const GameConfig({
    required this.mapId,
    this.mode = 'normal',
    this.difficulty = 'easy',
    this.profile = RulesProfile.classicFixed,
    this.seed = 1,
    this.challenge,
    this.waveSpacingMs,
    this.waveFollow = false,
    this.attract = false,
    this.customMap,
  });

  /// A game on a map that is not in the data (a player's map from the
  /// editor or an import); [mapId] is its id.
  GameConfig.custom({
    required MapDefinition map,
    this.mode = 'normal',
    this.difficulty = 'easy',
    this.profile = RulesProfile.classicFixed,
    this.seed = 1,
    this.challenge,
    this.waveSpacingMs,
    this.waveFollow = false,
  }) : mapId = map.id,
       customMap = map,
       attract = false;

  /// The attract demo behind the main menu (`attract.json`): its own road,
  /// preset turrets and waves; lives are never lost and kills never count.
  const GameConfig.attractDemo({this.profile = RulesProfile.classicFixed, this.seed = 1})
    : mapId = AttractDef.mapId,
      mode = attractMode,
      difficulty = '',
      challenge = null,
      waveSpacingMs = null,
      waveFollow = false,
      attract = true,
      customMap = null;

  /// The mode id the attract demo reports.
  static const String attractMode = 'attract';

  /// The tutorial's `progression.json` mode id: it has the tutorial's wave
  /// limit and "Show me" cash.
  static const String tutorialMode = 'tutorial';

  /// The challenge mode id.
  static const String challengeMode = 'challenge';

  final String mapId;

  /// A `progression.json` mode id (normal, tutorial, challenge, sandbox …).
  final String mode;

  /// A `difficulty.json` level id. A challenge plays at its own difficulty
  /// and the attract demo at the one in `attract.json`.
  final String difficulty;
  final RulesProfile profile;
  final int seed;
  final ChallengeDef? challenge;

  /// The player's wave spacing (`PrefWaveSpace`); null = `waves.json`.
  final double? waveSpacingMs;

  /// Send the next wave as soon as the field is clear (`PrefWaveFollow`).
  final bool waveFollow;
  final bool attract;

  /// The map to play instead of the data's map [mapId] (see [GameConfig.custom]).
  final MapDefinition? customMap;

  Map<String, Object?> toJson() => {
    'map': mapId,
    'mode': mode,
    'difficulty': difficulty,
    'profile': profile.id,
    'seed': seed,
    'challenge': ?challenge?.id,
    'waveSpacingMs': ?waveSpacingMs,
    if (waveFollow) 'waveFollow': true,
    if (attract) 'attract': true,
    if (customMap != null) 'customMap': customMap!.toJson(),
  };
}
