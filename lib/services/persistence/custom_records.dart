import 'package:flutter/foundation.dart';
import 'package:onslaught_core/onslaught_core.dart';

/// The best game of one custom game ([CustomRecordKey]): how far it got,
/// what it spent and when, plus the map's and mod's names at the time so the
/// records page can name them after the map or mod is gone.
@immutable
class CustomRecord {
  const CustomRecord({
    required this.key,
    required this.mapName,
    required this.wave,
    required this.kills,
    required this.score,
    required this.spent,
    required this.dateMs,
    this.modName,
  });

  factory CustomRecord.fromJson(Map<String, Object?> j) {
    final sink = IssueSink();
    final r = CustomRecord.read(JsonReader.root(j, 'customRecord', sink));
    sink.throwIfAny();
    return r;
  }

  /// Reads a record through [r], recording mistyped fields in its sink.
  factory CustomRecord.read(JsonReader r) => CustomRecord(
    key: CustomRecordKey.read(r),
    mapName: r.optString('mapName') ?? '',
    modName: r.optString('modName'),
    wave: r.optInteger('wave') ?? 0,
    kills: r.optInteger('kills') ?? 0,
    score: r.optNumber('score') ?? 0,
    spent: r.optNumber('spent') ?? 0,
    dateMs: r.optInteger('dateMs') ?? 0,
  );

  final CustomRecordKey key;
  final String mapName;
  final String? modName;
  final int wave;
  final int kills;
  final double score;
  final double spent;

  /// When it was played, ms since the epoch (UTC).
  final int dateMs;

  CustomResult get result => CustomResult(wave: wave, kills: kills, score: score);

  Map<String, Object?> toJson() => {
    ...key.toJson(),
    'mapName': mapName,
    'modName': modName,
    'wave': wave,
    'kills': kills,
    'score': score,
    'spent': spent,
    'dateMs': dateMs,
  };

  @override
  bool operator ==(Object other) => other is CustomRecord && mapEquals(other.toJson(), toJson());

  @override
  int get hashCode => Object.hashAll(toJson().values);
}

/// Custom games' records (`profile.custom`; owner decision, 2026-10-19): the
/// best game per [CustomRecordKey], and per player map the versions of its
/// shape in the order they were first played, so an edited map's earlier
/// records stay, under its earlier version. Nothing here feeds the standard
/// progress (unlocks, completions, challenge best games).
@immutable
class CustomRecords {
  const CustomRecords({this.records = const {}, this.mapVersions = const {}});

  factory CustomRecords.fromJson(Map<String, Object?> j) {
    final sink = IssueSink();
    final c = CustomRecords.read(JsonReader.root(j, 'custom', sink));
    sink.throwIfAny();
    return c;
  }

  /// Reads the records through [r] (`profile.custom`), recording mistyped
  /// fields in its sink.
  factory CustomRecords.read(JsonReader r) {
    final list = r.optList('records', CustomRecord.read);
    final versions = r.child('mapVersions');
    return CustomRecords(
      records: {for (final rec in list) rec.key.id: rec},
      mapVersions: versions.isNull
          ? const {}
          : versions.asMapOf((v) => List<String>.unmodifiable(v.asList((e) => e.asString()))),
    );
  }

  /// [CustomRecordKey.id] → its best game.
  final Map<String, CustomRecord> records;

  /// Player map id → its versions ([mapVersionHash]), first played first.
  final Map<String, List<String>> mapVersions;

  bool get isEmpty => records.isEmpty;

  /// The 1-based version number of [hash] for map [mapId], or null.
  int? versionOf(String mapId, String hash) {
    final i = mapVersions[mapId]?.indexOf(hash) ?? -1;
    return i < 0 ? null : i + 1;
  }

  /// The records of map [mapId], every version.
  List<CustomRecord> forMap(String mapId) => [
    for (final r in records.values)
      if (r.key.mapId == mapId) r,
  ];

  /// With [next] played: its map version noted, and kept if it beats the
  /// record of its key ([improvesCustomBest]).
  CustomRecords withResult(CustomRecord next) {
    final k = next.key;
    var versions = mapVersions;
    final hash = k.mapVersion;
    if (hash != null && versionOf(k.mapId, hash) == null) {
      versions = {
        ...mapVersions,
        k.mapId: List.unmodifiable([...?mapVersions[k.mapId], hash]),
      };
    }
    final kept = improvesCustomBest(records[k.id]?.result, next.result)
        ? {...records, k.id: next}
        : records;
    if (identical(kept, records) && identical(versions, mapVersions)) return this;
    return CustomRecords(records: kept, mapVersions: versions);
  }

  Map<String, Object?> toJson() => {
    'records': [for (final id in records.keys.toList()..sort()) records[id]!.toJson()],
    'mapVersions': {for (final id in mapVersions.keys.toList()..sort()) id: mapVersions[id]},
  };

  @override
  bool operator ==(Object other) =>
      other is CustomRecords &&
      mapEquals(other.records, records) &&
      other.mapVersions.length == mapVersions.length &&
      mapVersions.entries.every((e) => listEquals(other.mapVersions[e.key], e.value));

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(records.entries.map((e) => Object.hash(e.key, e.value))),
    Object.hashAllUnordered(
      mapVersions.entries.map((e) => Object.hash(e.key, Object.hashAll(e.value))),
    ),
  );
}
