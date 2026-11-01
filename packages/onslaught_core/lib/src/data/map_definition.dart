import 'package:meta/meta.dart';

import '../math/vec2.dart';
import 'json_reader.dart';

/// A map: one road polyline (first point = spawn, last = where the road meets
/// the base) and a base position. Built-in maps, editor maps and generated
/// maps all use this type.
@immutable
class MapDefinition {
  const MapDefinition({
    required this.id,
    required this.name,
    required this.base,
    required this.road,
    this.builtIn = true,
    this.order = 0,
  });

  factory MapDefinition.fromJson(JsonReader r) {
    r.expectOnlyKeys({'schemaVersion', 'id', 'name', 'order', 'builtIn', 'base', 'road'});
    return MapDefinition(
      id: r.string('id'),
      name: r.string('name'),
      order: r.optInteger('order', min: 0) ?? 0,
      builtIn: r.optBoolean('builtIn', fallback: true),
      base: r.point('base'),
      road: r.list('road', (c) => c.asPoint(), minLength: 2),
    );
  }

  static const int schemaVersion = 1;

  final String id;
  final String name;

  /// Position in the map picker.
  final int order;
  final bool builtIn;
  final Vec2 base;
  final List<Vec2> road;

  Vec2 get spawn => road.first;

  /// The form a map is shared in (a share string's payload): the original's
  /// custom-map record `{name, base, road}` plus the schema version. Ids are
  /// local to a library, so they are not shared.
  Map<String, Object?> toShareJson() => {
    'schemaVersion': schemaVersion,
    'name': name,
    'base': base.toJson(),
    'road': [for (final p in road) p.toJson()],
  };

  /// A shared map ([toShareJson]) as a player map with [id]. Throws a
  /// [DataValidationException] listing every problem with the payload.
  static MapDefinition fromShareJson(Object? json, {required String id}) {
    final sink = IssueSink();
    final r = JsonReader.root(json, 'map', sink);
    r.expectOnlyKeys({'schemaVersion', 'name', 'base', 'road'});
    final version = r.integer('schemaVersion', min: 1);
    if (version > schemaVersion) r.child('schemaVersion').issue('made by a newer version');
    final map = MapDefinition(
      id: id,
      name: r.string('name'),
      base: r.point('base'),
      road: r.list('road', (c) => c.asPoint(), minLength: 2),
      builtIn: false,
    );
    sink.throwIfAny();
    return map;
  }

  /// The `maps/<id>.json` document (and a player map as stored).
  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'id': id,
    'name': name,
    'order': order,
    'builtIn': builtIn,
    'base': pointToJson(base),
    'road': [for (final p in road) pointToJson(p)],
  };
}
