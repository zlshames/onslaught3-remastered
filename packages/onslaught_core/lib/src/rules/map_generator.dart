import '../data/map_definition.dart';

/// Makes a map from a seed (`docs/REMASTER_PLAN.md` §5.4). Built-in, editor
/// and generated maps are all [MapDefinition]s, and every generator must
/// pass the same contract (`checkMapContract` in `testing.dart`): the map
/// validates and creeps can walk its road to the base. Same seed ⇒ same map.
abstract interface class MapGenerator {
  /// Stable id (persisted with a game that used it).
  String get id;

  MapDefinition generate(int seed);
}

/// The classic generator: the original's built-in maps, picked by seed.
class BuiltInMapGenerator implements MapGenerator {
  BuiltInMapGenerator(Iterable<MapDefinition> maps)
    : maps = List.unmodifiable(maps.where((m) => m.builtIn)) {
    if (this.maps.isEmpty) throw ArgumentError.value(maps, 'maps', 'no built-in map');
  }

  final List<MapDefinition> maps;

  @override
  String get id => 'built-in';

  @override
  MapDefinition generate(int seed) => maps[seed % maps.length];
}
