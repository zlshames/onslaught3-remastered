import 'package:flutter/foundation.dart';
import 'package:onslaught_core/onslaught_core.dart';

import 'document_store.dart';

/// The game the player left without finishing (`gameInProgress` document):
/// what was played, the commands sent with the step each applied at, and
/// the step it was saved at. The simulation is deterministic, so replaying
/// the commands on a fresh session of the same config rebuilds the game
/// exactly ([SessionReplay]); [stateHash] confirms it (docs/REPLAY_PLAN.md
/// §2, §7). [wave], [lives] and [cash] are what the resume dialog shows.
///
/// There is one game in progress at a time; leaving a game replaces it.
@immutable
class GameInProgress {
  const GameInProgress({
    required this.mapId,
    required this.mode,
    required this.difficulty,
    required this.profileId,
    required this.seed,
    required this.commands,
    required this.tick,
    required this.stateHash,
    required this.wave,
    required this.lives,
    required this.cash,
    this.challengeKey,
    this.waveSpacingMs,
    this.waveFollow = false,
    this.customMap,
  });

  /// Reads a stored document; throws a [DataValidationException] naming every
  /// field of the wrong type (and a [TypeError] or [FormatException] for a
  /// command that cannot be read).
  factory GameInProgress.fromJson(Map<String, Object?> j) {
    final sink = IssueSink();
    final r = JsonReader.root(j, key, sink);
    final g = GameInProgress(
      mapId: r.string('map'),
      mode: r.string('mode'),
      difficulty: r.string('difficulty'),
      challengeKey: r.optString('challengeKey'),
      profileId: r.string('profile'),
      seed: r.integer('seed'),
      waveSpacingMs: r.optNumber('waveSpacingMs'),
      waveFollow: r.optBoolean('waveFollow', fallback: false),
      customMap: r.optChild('customMap', MapDefinition.fromJson),
      commands: r.list('commands', (c) {
        final raw = c.raw;
        if (raw is! Map) throw const FormatException('a command is not a JSON object');
        return ScheduledCommand.fromJson(raw.cast<String, Object?>());
      }),
      tick: r.integer('tick', min: 0),
      stateHash: r.integer('stateHash'),
      wave: r.integer('wave', min: 0),
      lives: r.integer('lives'),
      cash: r.number('cash'),
    );
    sink.throwIfAny();
    return g;
  }

  /// The game in progress of [session], started with [challengeKey] (the
  /// challenge it plays, if any), as it stands now.
  factory GameInProgress.of(GameSession session, {String? challengeKey}) {
    final c = session.config;
    return GameInProgress(
      mapId: c.mapId,
      mode: c.mode,
      difficulty: c.difficulty,
      challengeKey: challengeKey,
      profileId: c.profile.id,
      seed: c.seed,
      waveSpacingMs: c.waveSpacingMs,
      waveFollow: c.waveFollow,
      customMap: c.customMap,
      commands: List.unmodifiable(session.commandLog),
      tick: session.tick,
      stateHash: session.stateHash(),
      wave: session.waves.wave,
      lives: session.lives,
      cash: session.cash,
    );
  }

  static const int schemaVersion = 1;
  static const String key = 'gameInProgress';
  static final Migrator migrator = Migrator(currentVersion: schemaVersion, steps: []);

  /// The data's map id, or the player map's ([customMap]).
  final String mapId;
  final String mode;
  final String difficulty;

  /// The challenge played (`challengeKey`), for the challenge mode.
  final String? challengeKey;
  final String profileId;
  final int seed;
  final double? waveSpacingMs;
  final bool waveFollow;

  /// The player map played, as it was when the game started.
  final MapDefinition? customMap;

  final List<ScheduledCommand> commands;

  /// The step the game was saved at.
  final int tick;

  /// [GameSession.stateHash] at [tick].
  final int stateHash;

  final int wave;
  final int lives;
  final double cash;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'map': mapId,
    'mode': mode,
    'difficulty': difficulty,
    'challengeKey': ?challengeKey,
    'profile': profileId,
    'seed': seed,
    'waveSpacingMs': ?waveSpacingMs,
    if (waveFollow) 'waveFollow': true,
    'customMap': ?customMap?.toJson(),
    'commands': [for (final c in commands) c.toJson()],
    'tick': tick,
    'stateHash': stateHash,
    'wave': wave,
    'lives': lives,
    'cash': cash,
  };
}
