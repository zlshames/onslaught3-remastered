import 'package:meta/meta.dart';

import '../data/challenge_defs.dart';
import '../data/progression_defs.dart';
import '../sim/game_config.dart';
import 'rules_profile.dart';

/// What a player has unlocked and completed (`ModesAvailable` and
/// `ModesComplete` in the original's shared object, without the MD5
/// tamper-proofing): mode ids in [available]; difficulty ids, `tutorial`
/// and challenge keys ([challengeKey]) in [complete].
@immutable
class ProgressState {
  const ProgressState({this.available = const {}, this.complete = const {}});

  final Set<String> available;
  final Set<String> complete;

  /// This state with [changes] applied.
  ProgressState apply(Iterable<ProgressChange> changes) {
    final a = {...available};
    final c = {...complete};
    for (final ch in changes) {
      (ch.kind == ProgressChange.unlock ? a : c).add(ch.id);
    }
    return ProgressState(available: a, complete: c);
  }
}

/// One change to a [ProgressState]: mode [id] unlocked, or [id] (a
/// difficulty, `tutorial` or a challenge key) completed. [messageKey] is the
/// string announcing it (`strings/<locale>.json`), with `{difficulty}`
/// filled from [difficulty]; null when the original says nothing.
@immutable
class ProgressChange {
  const ProgressChange(this.kind, this.id, {this.messageKey, this.difficulty});

  static const String unlock = 'unlock';
  static const String completion = 'complete';

  final String kind;
  final String id;
  final String? messageKey;
  final String? difficulty;

  @override
  bool operator ==(Object other) =>
      other is ProgressChange &&
      other.kind == kind &&
      other.id == id &&
      other.messageKey == messageKey &&
      other.difficulty == difficulty;

  @override
  int get hashCode => Object.hash(kind, id, messageKey, difficulty);

  @override
  String toString() => '$kind $id${messageKey == null ? '' : ' ($messageKey)'}';
}

/// Why a game is custom rather than a standard game.
enum CustomGameReason {
  /// A mod is switched on: the game's data (lives, costs, damage…) differs.
  mod,

  /// The map is a player's (`MapLibrary`), not one of the built-in maps.
  playerMap,
}

/// What makes the game set up by [config] custom; empty for a standard game.
/// [modded] says whether a mod is applied to the game's data (the session
/// cannot tell changed data from the original).
Set<CustomGameReason> customGameReasons(GameConfig config, {required bool modded}) => {
  if (modded) CustomGameReason.mod,
  if (config.customMap != null) CustomGameReason.playerMap,
};

/// Whether the game set up by [config] may change the player's progress:
/// always under [RulesProfile.customGamesSeparate] off (the original), else
/// only a standard game ([customGameReasons] empty).
bool recordsProgress(GameConfig config, {required bool modded}) =>
    !config.profile.customGamesSeparate || customGameReasons(config, modded: modded).isEmpty;

/// The mode whose games count towards the kill milestones
/// (`GameManager.modeUpdate` returns early unless `game_type == "normal"`;
/// the extreme difficulty is a normal game).
const String milestoneMode = 'normal';

/// Whether [mode] can be chosen: its rule is `always`, it has been
/// unlocked, or [unlockAll] (the debug toggle) is on.
bool isModeAvailable(
  ProgressionDefs defs,
  ProgressState state,
  String mode, {
  bool unlockAll = false,
}) {
  if (unlockAll || state.available.contains(mode)) return true;
  return defs.unlocks.any((u) => u.mode == mode && u.rule == 'always');
}

/// The changes a kill brings (`GameManager.modeUpdate`, run after every
/// kill): in a normal game whose kills now equal a milestone, the
/// difficulty is completed (`completeKills`), modes whose
/// `killsOnAnyDifficulty` rule names this difficulty unlock, and modes whose
/// `completeAll` rule is now met unlock. Only real changes are returned, in
/// the order the original announces them.
List<ProgressChange> progressOnKill(
  ProgressionDefs defs,
  ProgressState state, {
  required String mode,
  required String difficulty,
  required int kills,
}) {
  if (mode != milestoneMode) return const [];
  final out = <ProgressChange>[];
  final completes = kills == defs.completeKills && !state.complete.contains(difficulty);
  if (completes) {
    out.add(
      ProgressChange(
        ProgressChange.completion,
        difficulty,
        messageKey: 'flow.completeDifficulty',
        difficulty: difficulty,
      ),
    );
  }
  for (final u in defs.unlocks) {
    if (u.rule != 'killsOnAnyDifficulty' || u.kills != kills) continue;
    if (!u.difficulties.contains(difficulty) || state.available.contains(u.mode)) continue;
    out.add(
      ProgressChange(
        ProgressChange.unlock,
        u.mode,
        messageKey: unlockMessageKey(u.mode),
        difficulty: difficulty,
      ),
    );
  }
  if (completes) {
    final complete = {...state.complete, difficulty};
    for (final u in defs.unlocks) {
      if (u.rule != 'completeAll' || state.available.contains(u.mode)) continue;
      if (u.difficulties.every(complete.contains)) {
        out.add(
          ProgressChange(ProgressChange.unlock, u.mode, messageKey: unlockMessageKey(u.mode)),
        );
      }
    }
  }
  return out;
}

/// The changes starting a game brings (`GameManagerTutorial.setupFinal`):
/// the tutorial unlocks the modes whose rule is `tutorialStart`, each with its
/// [tutorialUnlockMessageKey] message.
List<ProgressChange> progressOnStart(ProgressionDefs defs, ProgressState state, GameConfig config) {
  if (config.mode != GameConfig.tutorialMode) return const [];
  return [
    for (final u in defs.unlocks)
      if (u.rule == 'tutorialStart' && !state.available.contains(u.mode))
        ProgressChange(ProgressChange.unlock, u.mode, messageKey: tutorialUnlockMessageKey(u.mode)),
  ];
}

/// The changes a won game brings (`GameManager.gameWin`): the tutorial
/// unlocks the modes whose rule is `tutorialComplete` or `tutorialStart`
/// (should the start not have) and is ticked off; a challenge is ticked off
/// under its [challengeKey].
List<ProgressChange> progressOnWin(ProgressionDefs defs, ProgressState state, GameConfig config) {
  if (config.mode == GameConfig.tutorialMode) {
    return [
      for (final u in defs.unlocks)
        if ((u.rule == 'tutorialComplete' || u.rule == 'tutorialStart') &&
            !state.available.contains(u.mode))
          ProgressChange(ProgressChange.unlock, u.mode, messageKey: unlockMessageKey(u.mode)),
      if (!state.complete.contains(GameConfig.tutorialMode))
        const ProgressChange(ProgressChange.completion, GameConfig.tutorialMode),
    ];
  }
  final challenge = config.challenge;
  if (config.mode == GameConfig.challengeMode && challenge != null) {
    final key = challengeKey(challenge);
    if (!state.complete.contains(key)) {
      return [ProgressChange(ProgressChange.completion, key)];
    }
  }
  return const [];
}

/// `flow.unlockSandbox2` for `sandbox2` and so on.
String unlockMessageKey(String mode) => 'flow.unlock${_capitalised(mode)}';

/// `flow.tutorialUnlockChallenge` for `challenge`: the message of a mode the
/// tutorial unlocks as it starts.
String tutorialUnlockMessageKey(String mode) => 'flow.tutorialUnlock${_capitalised(mode)}';

String _capitalised(String s) => s.isEmpty ? '' : s[0].toUpperCase() + s.substring(1);

/// A challenge's identity (`GameManager.challengeEncode`): its difficulty,
/// objective, cash, time limit, turret limit, wave sizes and wave speeds as
/// the original strings them, `undefined` for none. Best games and
/// completion are kept under it, so a custom challenge that matches a preset
/// shares the preset's record.
String challengeKey(ChallengeDef c) {
  String n(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  final objective = c.objective;
  return [
    'challenge',
    c.difficulty,
    if (objective == null)
      'undefined'
    else
      '${objective.type == ChallengeObjective.waves ? 'w' : 'k'},${objective.target}',
    n(c.cash),
    if (c.timeLimitS == null) 'undefined' else n(c.timeLimitS!),
    if (c.turretLimit == null) 'undefined' else '${c.turretLimit}',
    c.waveSizes.join(','),
    [for (final v in c.waveSpeeds) n(v)].join(','),
  ].join(';');
}

/// The challenge a [key] describes: the preset with that key (its name and
/// id), else a custom challenge. Null when [key] is not a challenge key.
ChallengeDef? challengeFromKey(String key, ChallengeDefs defs) {
  for (final p in defs.presets) {
    if (challengeKey(p) == key) return p;
  }
  if (key.split(';') case [
    'challenge',
    final difficulty,
    final objectiveText,
    final cashText,
    final timeText,
    final turretText,
    final sizesText,
    final speedsText,
  ]) {
    double? optNum(String s) => s == 'undefined' ? null : double.tryParse(s);
    ChallengeObjective? objective;
    if (objectiveText != 'undefined') {
      final (kind, target) = switch (objectiveText.split(',')) {
        [final k, final t] => (k, int.tryParse(t)),
        _ => (null, null),
      };
      if (target == null || (kind != 'w' && kind != 'k')) return null;
      objective = ChallengeObjective(
        kind == 'w' ? ChallengeObjective.waves : ChallengeObjective.kills,
        target,
      );
    }
    final cash = double.tryParse(cashText);
    final sizes = sizesText.split(',').map(int.tryParse).toList();
    final speeds = speedsText.split(',').map(double.tryParse).toList();
    if (cash == null || sizes.contains(null) || speeds.contains(null)) return null;
    if (sizes.any((s) => s! < 1) || speeds.any((s) => s! <= 0)) return null;
    return ChallengeDef(
      id: customChallengeId,
      name: 'Custom challenge',
      difficulty: difficulty,
      objective: objective,
      cash: cash,
      timeLimitS: optNum(timeText),
      turretLimit: optNum(turretText)?.toInt(),
      waveSizes: List.unmodifiable(sizes.cast<int>()),
      waveSpeeds: List.unmodifiable(speeds.cast<double>()),
      debugOnly: false,
    );
  }
  return null;
}

/// The id of a challenge that is not a preset.
const String customChallengeId = 'custom';

/// The numbers kept for a challenge's best game (`challengeSaveBest`).
@immutable
class ChallengeResult {
  const ChallengeResult({required this.kills, required this.spent, required this.score});

  final int kills;
  final double spent;

  /// Kills × spent.
  final double score;
}

/// Whether [next] replaces [best] as a challenge's best game
/// (`challengeSaveBest`): always when there is none yet; otherwise when it
/// has strictly more kills (challenges with a kill target) or a strictly
/// higher score (every other challenge). Saved whether the game was passed
/// or failed.
bool improvesBest(ChallengeResult? best, ChallengeResult next, ChallengeDef challenge) {
  if (best == null) return true;
  if (challenge.objective?.type == ChallengeObjective.kills) return next.kills > best.kills;
  return next.score > best.score;
}
