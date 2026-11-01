import 'package:meta/meta.dart';

import 'json_reader.dart';

/// A mode-unlock milestone from `progression.json`.
@immutable
class ModeUnlock {
  const ModeUnlock({
    required this.mode,
    required this.rule,
    required this.difficulties,
    required this.kills,
  });

  factory ModeUnlock.fromJson(JsonReader r) {
    r.expectOnlyKeys({'mode', 'rule', 'difficulties', 'kills'});
    return ModeUnlock(
      mode: r.string('mode'),
      rule: r.oneOf('rule', {
        'killsOnAnyDifficulty',
        'completeAll',
        'tutorialComplete',
        'tutorialStart',
        'always',
      }, fallback: 'always'),
      difficulties: r.optList('difficulties', (c) => c.asString()),
      kills: r.optInteger('kills', min: 0),
    );
  }

  final String mode;

  /// `killsOnAnyDifficulty` (reach [kills] in one game on any of
  /// [difficulties]), `completeAll` (complete every one of [difficulties]),
  /// `tutorialComplete`, `tutorialStart` (on starting the tutorial, and on
  /// winning it should the start not have unlocked it), or `always`.
  final String rule;
  final List<String> difficulties;
  final int? kills;

  Map<String, Object?> toJson() => {
    'mode': mode,
    'rule': rule,
    if (difficulties.isNotEmpty) 'difficulties': difficulties,
    'kills': ?kills,
  };
}

/// `progression.json`.
@immutable
class ProgressionDefs {
  const ProgressionDefs({required this.modes, required this.completeKills, required this.unlocks});

  factory ProgressionDefs.fromJson(JsonReader r) {
    r.expectOnlyKeys({'schemaVersion', 'modes', 'completeKills', 'unlocks'});
    return ProgressionDefs(
      modes: r.list('modes', (c) => c.asString()),
      completeKills: r.integer('completeKills', min: 1),
      unlocks: r.list('unlocks', ModeUnlock.fromJson),
    );
  }

  static const int schemaVersion = 1;

  /// Every mode id, in menu order.
  final List<String> modes;

  /// Kills in one game that mark a difficulty "complete".
  final int completeKills;
  final List<ModeUnlock> unlocks;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'modes': modes,
    'completeKills': completeKills,
    'unlocks': [for (final u in unlocks) u.toJson()],
  };
}
