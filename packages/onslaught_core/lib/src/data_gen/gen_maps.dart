/// The built-in maps (`maps/<id>.json`) from the legacy table.
library;

import '../data/map_definition.dart';
import 'legacy_table.dart';

/// The built-in maps in picker order.
List<MapDefinition> generateMaps(LegacyTable l) {
  final list = objects(l['maps']['maps']);
  return [
    for (var i = 0; i < list.length; i++)
      MapDefinition(
        id: list[i]['key']! as String,
        name: list[i]['name']! as String,
        order: i,
        base: pointFromObject(list[i]['base']),
        road: [for (final p in listOf(list[i]['road'])) pointFromObject(p)],
      ),
  ];
}
