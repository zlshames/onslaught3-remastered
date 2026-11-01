import 'package:onslaught_core/onslaught_core.dart';

import '../../services/logging/logging.dart';
import '../../services/persistence/custom_records.dart';
import '../../services/persistence/profile.dart';

const Logger _log = Logger('progress');

/// What a custom game is played on, for its record ([CustomRecordKey] without
/// the mode, difficulty and challenge, which come from the game).
class CustomGameIdentity {
  const CustomGameIdentity({
    required this.mapId,
    required this.mapName,
    this.mapVersion,
    this.mod,
    this.modName,
  });

  final String mapId;
  final String mapName;

  /// [mapVersionHash] of a player map.
  final String? mapVersion;

  /// The mod's signature and name, when one is on.
  final String? mod;
  final String? modName;
}

/// Turns a game's events into profile changes (`GameManager.modeUpdate`,
/// `gameWin`, `challengeSaveBest`, `GameManagerTutorial.setupFinal`): kill
/// milestones of normal games, the modes the tutorial unlocks as it starts,
/// the tutorial and challenge wins, and every challenge's best game (passed or
/// failed). Each change is announced as the original words it, then saved.
/// Freeplay after a win changes nothing: the win was recorded. A custom game
/// ([records] false: [recordsProgress]) changes none of that; when [custom]
/// names it, its own record ([CustomRecords]) is kept instead, at the win and
/// at the game's end (freeplay included, which can only raise the wave).
class ProgressRecorder {
  ProgressRecorder({
    required this.data,
    required this.config,
    this.records = true,
    this.custom,
    required this.difficulty,
    required this.read,
    required this.save,
    required this.announce,
    String Function()? locale,
    DateTime Function()? clock,
  }) : _locale = locale ?? (() => 'en'),
       _clock = clock ?? DateTime.now;

  final GameData data;
  final GameConfig config;

  /// Whether this game may change the profile (false for a custom game).
  final bool records;

  /// The custom game this is, or null for a standard game.
  final CustomGameIdentity? custom;

  /// The difficulty the game is played at (a challenge's own).
  final String difficulty;

  /// The profile as it is now (null while it loads: nothing is recorded).
  final Profile? Function() read;

  /// Stores an edit of the profile.
  final void Function(Profile Function(Profile)) save;

  /// Shows a message in the game.
  final void Function(String) announce;

  /// The interface language the messages are announced in, as it is now.
  final String Function() _locale;
  final DateTime Function() _clock;

  /// The game was won and goes on in freeplay: its record is already made.
  bool _freeplay = false;

  void onEvent(GameEvent e) {
    if (custom != null) {
      switch (e) {
        case GameWon(:final wave, :final kills, :final spent, :final score) ||
            GameOver(:final wave, :final kills, :final spent, :final score):
          _customRecord(wave, kills, spent, score);
        default:
      }
    }
    if (!records) return;
    switch (e) {
      case SessionStarted():
        _progress((p) => progressOnStart(data.progression, p, config));
      case FreeplayStarted():
        _freeplay = true;
      case CreepKilled(:final kills):
        _progress(
          (p) => progressOnKill(
            data.progression,
            p,
            mode: config.mode,
            difficulty: difficulty,
            kills: kills,
          ),
        );
      case GameWon(:final kills, :final spent, :final score):
        _progress((p) => progressOnWin(data.progression, p, config));
        _best(kills, spent, score);
      case GameOver(:final kills, :final spent, :final score) when !_freeplay:
        _best(kills, spent, score);
      default:
    }
  }

  void _progress(List<ProgressChange> Function(ProgressState) changesFor) {
    final profile = read();
    if (profile == null) {
      _log.warning('progress not recorded: the profile has not loaded');
      return;
    }
    final changes = changesFor(profile.progress);
    if (changes.isEmpty) return;
    for (final c in changes) {
      _log.info(
        'progress',
        fields: {'kind': c.kind, 'id': c.id, 'difficulty': c.difficulty, 'mode': config.mode},
      );
      final key = c.messageKey;
      if (key == null) continue;
      final locale = _locale();
      final level = c.difficulty == null
          ? ''
          : data.text('difficulty.${c.difficulty}', locale: locale);
      announce(data.text(key, locale: locale).replaceAll('{difficulty}', level));
    }
    save((p) => p.applying(changes));
  }

  void _best(int kills, double spent, double score) {
    final challenge = config.challenge;
    if (challenge == null) return;
    final best = ChallengeBest(
      kills: kills,
      spent: spent,
      score: score,
      dateMs: _clock().millisecondsSinceEpoch,
    );
    save((p) {
      final next = p.withResult(challenge, best);
      _log.info(
        'challenge result',
        fields: {
          'challenge': challengeKey(challenge),
          'kills': kills,
          'score': score,
          'newBest': !identical(next, p),
        },
      );
      return next;
    });
  }

  void _customRecord(int wave, int kills, double spent, double score) {
    final c = custom!;
    final challenge = config.challenge;
    final record = CustomRecord(
      key: CustomRecordKey(
        mapId: c.mapId,
        mapVersion: c.mapVersion,
        mod: c.mod,
        mode: config.mode,
        difficulty: difficulty,
        challenge: challenge == null ? null : challengeKey(challenge),
      ),
      mapName: c.mapName,
      modName: c.modName,
      wave: wave,
      kills: kills,
      score: score,
      spent: spent,
      dateMs: _clock().millisecondsSinceEpoch,
    );
    save((p) {
      final newBest = improvesCustomBest(p.custom.records[record.key.id]?.result, record.result);
      _log.info(
        'custom game result',
        fields: {
          'map': c.mapId,
          'mapName': Pii(c.mapName),
          'modded': c.mod != null,
          'mode': config.mode,
          'difficulty': difficulty,
          'wave': wave,
          'score': score,
          'newBest': newBest,
        },
      );
      return p.withCustomRecord(record);
    });
  }
}
