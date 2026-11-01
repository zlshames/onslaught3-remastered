import 'package:flutter/foundation.dart';
import 'package:onslaught_core/onslaught_core.dart';

import 'custom_records.dart';
import 'document_store.dart';

/// A challenge's best game (`ChallengeBestGame`: score, kills, spend, date).
/// Whether the challenge was passed is kept apart, in [Profile.complete].
@immutable
class ChallengeBest {
  const ChallengeBest({
    required this.kills,
    required this.spent,
    required this.score,
    required this.dateMs,
  });

  factory ChallengeBest.fromJson(Map<String, Object?> j) {
    final sink = IssueSink();
    final b = ChallengeBest.read(JsonReader.root(j, 'challengeBest', sink));
    sink.throwIfAny();
    return b;
  }

  /// Reads a best game through [r], recording mistyped fields in its sink.
  factory ChallengeBest.read(JsonReader r) => ChallengeBest(
    kills: r.optInteger('kills') ?? 0,
    spent: r.optNumber('spent') ?? 0,
    score: r.optNumber('score') ?? 0,
    dateMs: r.optInteger('dateMs') ?? 0,
  );

  final int kills;
  final double spent;
  final double score;

  /// When it was played, ms since the epoch (UTC).
  final int dateMs;

  ChallengeResult get result => ChallengeResult(kills: kills, spent: spent, score: score);

  Map<String, Object?> toJson() => {
    'kills': kills,
    'spent': spent,
    'score': score,
    'dateMs': dateMs,
  };

  @override
  bool operator ==(Object other) =>
      other is ChallengeBest &&
      other.kills == kills &&
      other.spent == spent &&
      other.score == score &&
      other.dateMs == dateMs;

  @override
  int get hashCode => Object.hash(kills, spent, score, dateMs);
}

/// The player's progress (`profile` document; the original's
/// `ModesAvailable`, `ModesComplete` and `ChallengeBestGame` without the MD5
/// tamper-proofing): unlocked modes, completed difficulties / tutorial /
/// challenges, the best game per challenge key, the debug unlock-all
/// toggle, and the custom games' own records ([custom]).
@immutable
class Profile {
  const Profile({
    this.available = const {},
    this.complete = const {},
    this.challengeBest = const {},
    this.unlockAll = false,
    this.custom = const CustomRecords(),
  });

  /// Reads a stored document; throws a [DataValidationException] naming
  /// every field of the wrong type (`profile:/available/0: expected a
  /// string`).
  factory Profile.fromJson(Map<String, Object?> j) {
    final sink = IssueSink();
    final r = JsonReader.root(j, key, sink);
    Set<String> ids(String field) => {...r.optList(field, (e) => e.asString())};
    final best = r.child('challengeBest');
    final custom = r.child('custom');
    final p = Profile(
      available: ids('available'),
      complete: ids('complete'),
      challengeBest: best.isNull ? const {} : best.asMapOf(ChallengeBest.read),
      unlockAll: r.optBoolean('unlockAll', fallback: false),
      custom: custom.isNull ? const CustomRecords() : CustomRecords.read(custom),
    );
    sink.throwIfAny();
    return p;
  }

  /// v2 added [custom].
  static const int schemaVersion = 2;
  static const String key = 'profile';
  static final Migrator migrator = Migrator(
    currentVersion: schemaVersion,
    steps: [
      // v1 → v2: no custom game had a record.
      (doc) => {
        ...doc,
        'custom': {'records': <Object?>[], 'mapVersions': <String, Object?>{}},
      },
    ],
  );

  /// Mode ids unlocked.
  final Set<String> available;

  /// Difficulty ids, `tutorial` and challenge keys completed.
  final Set<String> complete;

  /// Challenge key ([challengeKey]) → its best game.
  final Map<String, ChallengeBest> challengeBest;

  /// Debug: every mode is available (`GameStatus.debug_mode`'s
  /// `modeIsAvailable`); nothing is written to [available].
  final bool unlockAll;

  /// Custom games' records (a mod on, or a player's map), kept apart from
  /// the standard progress above (`RulesProfile.customGamesSeparate`).
  final CustomRecords custom;

  ProgressState get progress => ProgressState(available: available, complete: complete);

  /// With [changes] applied.
  Profile applying(Iterable<ProgressChange> changes) {
    final p = progress.apply(changes);
    return copyWith(available: p.available, complete: p.complete);
  }

  /// With [next] kept as the best game of challenge [c] if it beats the
  /// stored one (`challengeSaveBest`, on a pass or a fail).
  Profile withResult(ChallengeDef c, ChallengeBest next) {
    final k = challengeKey(c);
    if (!improvesBest(challengeBest[k]?.result, next.result, c)) return this;
    return copyWith(challengeBest: {...challengeBest, k: next});
  }

  /// With custom game [next] recorded ([CustomRecords.withResult]).
  Profile withCustomRecord(CustomRecord next) => copyWith(custom: custom.withResult(next));

  Profile copyWith({
    Set<String>? available,
    Set<String>? complete,
    Map<String, ChallengeBest>? challengeBest,
    bool? unlockAll,
    CustomRecords? custom,
  }) => Profile(
    available: available ?? this.available,
    complete: complete ?? this.complete,
    challengeBest: challengeBest ?? this.challengeBest,
    unlockAll: unlockAll ?? this.unlockAll,
    custom: custom ?? this.custom,
  );

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'available': available.toList()..sort(),
    'complete': complete.toList()..sort(),
    'challengeBest': {
      for (final k in challengeBest.keys.toList()..sort()) k: challengeBest[k]!.toJson(),
    },
    'unlockAll': unlockAll,
    'custom': custom.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is Profile &&
      setEquals(other.available, available) &&
      setEquals(other.complete, complete) &&
      mapEquals(other.challengeBest, challengeBest) &&
      other.unlockAll == unlockAll &&
      other.custom == custom;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(available),
    Object.hashAllUnordered(complete),
    Object.hashAllUnordered(challengeBest.entries.map((e) => Object.hash(e.key, e.value))),
    unlockAll,
    custom,
  );
}
