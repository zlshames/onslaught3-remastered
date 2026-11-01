import 'package:flutter/foundation.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../logging/logging.dart';
import '../share/share_codec.dart';
import 'document_store.dart' show Migrator;

const Logger _log = Logger('maps');

/// The player's maps (`maps` document; the original's `MapsSaved`, which
/// keyed maps by name). Names are unique: saving under a name that exists
/// replaces that map, as `mapSave` did. Each map also has an id, derived
/// from its name once and kept, that routes and games refer to.
@immutable
class MapLibrary {
  const MapLibrary({this.maps = const []});

  /// Reads a stored library. A map that no longer parses (or claims a
  /// built-in id) is left out rather than losing the whole library, and
  /// passed to [onDropped] ([PersistenceService.loadMaps] keeps the stored
  /// text and says so).
  factory MapLibrary.fromJson(Map<String, Object?> j, {void Function(Object? entry)? onDropped}) =>
      MapLibrary(
        maps: List.unmodifiable([
          for (final m in (j['maps'] as List?) ?? const []) ?_tryMap(m, onDropped),
        ]),
      );

  static const int schemaVersion = 1;
  static const String key = 'maps';
  static final Migrator migrator = Migrator(currentVersion: schemaVersion);

  /// Every player map id starts with this, so it never clashes with a
  /// built-in map id.
  static const String idPrefix = 'custom-';

  /// In save order (newest last).
  final List<MapDefinition> maps;

  static bool isCustomId(String id) => id.startsWith(idPrefix);

  MapDefinition? byId(String id) => maps.where((m) => m.id == id).firstOrNull;

  MapDefinition? byName(String name) => maps.where((m) => m.name == name).firstOrNull;

  /// The id a map saved as [name] gets: the existing map's id when the name
  /// is taken, otherwise a new id from the name.
  String idFor(String name) {
    final existing = byName(name);
    if (existing != null) return existing.id;
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final stem = '$idPrefix${slug.isEmpty ? 'map' : slug}';
    var id = stem;
    for (var n = 2; byId(id) != null; n++) {
      id = '$stem-$n';
    }
    return id;
  }

  /// With [map] stored: replaces the map with the same id, or appends it.
  MapLibrary saving(MapDefinition map) {
    final i = maps.indexWhere((m) => m.id == map.id);
    final next = [...maps];
    if (i < 0) {
      next.add(map);
    } else {
      next[i] = map;
    }
    return MapLibrary(maps: List.unmodifiable(next));
  }

  MapLibrary removing(String id) =>
      MapLibrary(maps: List.unmodifiable(maps.where((m) => m.id != id)));

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'maps': [for (final m in maps) m.toJson()],
  };

  static MapDefinition? _tryMap(Object? json, void Function(Object? entry)? onDropped) {
    MapDefinition? map;
    try {
      final sink = IssueSink();
      final m = MapDefinition.fromJson(JsonReader.root(json, 'maps', sink));
      sink.throwIfAny();
      if (isCustomId(m.id)) map = m;
    } on Object catch (e, st) {
      _log.warning('a stored map cannot be read and is left out', error: e, stackTrace: st);
    }
    if (map == null) onDropped?.call(json);
    return map;
  }
}

/// A map read from a share string, ready to add to the library.
@immutable
class ImportedMap {
  const ImportedMap({required this.map, required this.problems, required this.replaces});

  /// The map, with the id it will have in the library.
  final MapDefinition map;

  /// Why it cannot be played as it is (empty = fine).
  final List<MapProblem> problems;

  /// The library map with the same name that importing replaces, if any.
  final MapDefinition? replaces;
}

/// Shares and imports maps as `ons3:map:…` strings.
class MapSharing {
  const MapSharing({this.codec = const ShareCodec()});

  final ShareCodec codec;

  String encode(MapDefinition map) {
    final code = codec.encode(ShareCodec.mapKind, map.toShareJson());
    _log.debug('map code made', fields: {'map': map.id, 'length': code.length});
    return code;
  }

  /// Reads [text] as a shared map for [library]. Throws
  /// [ShareCodecException] when the text is not a readable map code. The
  /// import dialog reads on every change, so a code that cannot be read is
  /// logged at `trace` only.
  ImportedMap decode(String text, MapLibrary library, WorldDef world) {
    try {
      return _decode(text, library, world);
    } on ShareCodecException catch (e) {
      _log.trace('map code not readable', fields: {'reason': e.key, 'length': text.length});
      rethrow;
    }
  }

  ImportedMap _decode(String text, MapLibrary library, WorldDef world) {
    final json = codec.decode(ShareCodec.mapKind, text);
    final MapDefinition shared;
    try {
      shared = MapDefinition.fromShareJson(json, id: 'import');
    } on DataValidationException catch (e) {
      throw ShareCodecException('ui.share.mapMalformed', {'issue': e.issues.first.path});
    }
    final name = shared.name.trim();
    if (name.isEmpty) throw const ShareCodecException('ui.share.mapNoName');
    if (name.length > world.editor.maxNameLength) {
      throw const ShareCodecException('ui.share.mapNameTooLong');
    }
    final map = MapDefinition(
      id: library.idFor(name),
      name: name,
      base: shared.base,
      road: shared.road,
      builtIn: false,
    );
    return ImportedMap(map: map, problems: validateMap(map, world), replaces: library.byName(name));
  }
}
