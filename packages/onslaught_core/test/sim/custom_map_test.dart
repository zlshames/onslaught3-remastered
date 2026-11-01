import 'package:onslaught_core/onslaught_core.dart';
import 'package:onslaught_core/testing.dart';
import 'package:test/test.dart';

import '../support/repo_data.dart';

void main() {
  late GameData data;
  late SimTestHarness harness;
  setUpAll(() {
    data = loadClassicData();
    harness = SimTestHarness(data);
  });

  const map = MapDefinition(
    id: 'custom-straight',
    name: 'Straight',
    base: Vec2(600, 200),
    road: [Vec2(0, 247), Vec2(605, 247)],
    builtIn: false,
  );

  test('a custom map plays without being in the data', () {
    expect(data.maps.containsKey(map.id), isFalse);
    final s = harness.session(GameConfig.custom(map: map, difficulty: 'medium'));
    expect(s.map, same(map));
    expect(s.config.mapId, map.id);
    expect(s.road.points.first, map.road.first);
    expect(checkMapContract(data, map), isEmpty);
  });

  test('the config records the custom map (fixtures and replays)', () {
    final json = GameConfig.custom(map: map).toJson();
    expect(json['map'], map.id);
    expect(json['customMap'], map.toJson());
    expect(const GameConfig(mapId: 'map1').toJson().containsKey('customMap'), isFalse);
  });
}
