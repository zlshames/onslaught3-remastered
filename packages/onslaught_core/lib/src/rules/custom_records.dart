import 'package:meta/meta.dart';

import '../data/json_reader.dart';
import '../data/map_definition.dart';
import '../sim/stable_hash.dart';

/// The shape of a player's map as a short hash of its base and road (not its
/// name or id), so a renamed map keeps its custom records and a reshaped road
/// starts a new version of them (owner decision, 2026-10-19).
String mapVersionHash(MapDefinition map) => fnv1a32Hex(
  canonicalJson({
    'base': map.base.toJson(),
    'road': [for (final p in map.road) p.toJson()],
  }),
);

/// Which custom game a record belongs to: the map (a player map's id and the
/// [mapVersion] of its shape, or a built-in map's id with no version), the
/// mod's signature when one was on, the mode, the difficulty and, in the
/// challenge mode, the challenge's key. A game with both a mod and a player
/// map has one combined record (owner decision, 2026-10-19).
@immutable
class CustomRecordKey {
  const CustomRecordKey({
    required this.mapId,
    required this.mode,
    required this.difficulty,
    this.mapVersion,
    this.mod,
    this.challenge,
  });

  factory CustomRecordKey.fromJson(Map<String, Object?> j) {
    final sink = IssueSink();
    final k = CustomRecordKey.read(JsonReader.root(j, 'customRecordKey', sink));
    sink.throwIfAny();
    return k;
  }

  /// Reads a key through [r], recording missing or mistyped fields in its
  /// sink.
  factory CustomRecordKey.read(JsonReader r) => CustomRecordKey(
    mapId: r.string('map'),
    mapVersion: r.optString('mapVersion'),
    mod: r.optString('mod'),
    mode: r.string('mode'),
    difficulty: r.string('difficulty'),
    challenge: r.optString('challenge'),
  );

  final String mapId;

  /// [mapVersionHash] of a player map; null for a built-in map.
  final String? mapVersion;

  /// The mod's signature (`modSignature`); null when no mod was on.
  final String? mod;
  final String mode;
  final String difficulty;

  /// The challenge's key (`challengeKey`) in the challenge mode.
  final String? challenge;

  /// One string per key, for storing records in a map.
  String get id => canonicalJson(toJson());

  Map<String, Object?> toJson() => {
    'map': mapId,
    'mapVersion': mapVersion,
    'mod': mod,
    'mode': mode,
    'difficulty': difficulty,
    'challenge': challenge,
  };

  @override
  bool operator ==(Object other) => other is CustomRecordKey && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// How far a custom game got.
@immutable
class CustomResult {
  const CustomResult({required this.wave, required this.kills, required this.score});

  final int wave;
  final int kills;
  final double score;
}

/// Whether [next] beats the stored [best] of the same custom game: a higher
/// wave, then more kills, then a higher score (custom games are endless
/// survival, so the wave reached comes first).
bool improvesCustomBest(CustomResult? best, CustomResult next) {
  if (best == null) return true;
  if (next.wave != best.wave) return next.wave > best.wave;
  if (next.kills != best.kills) return next.kills > best.kills;
  return next.score > best.score;
}
