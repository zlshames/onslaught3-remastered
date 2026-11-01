import 'package:onslaught_core/onslaught_core.dart';
import 'package:onslaught_core/testing.dart';
import 'package:test/test.dart';

import '../support/repo_data.dart';

/// A stand-in procedural generator: a random zig-zag from the left edge to a
/// base on the right, built with [MapDraft] like the editor would. It exists
/// to prove any generator can be held to the same contract as the built-ins.
class _ZigZagGenerator implements MapGenerator {
  _ZigZagGenerator(this.rules);

  final MapEditorRules rules;

  @override
  String get id => 'test-zigzag';

  @override
  MapDefinition generate(int seed) {
    final rng = SimRandom(seed);
    var d = MapDraft.empty
        .withStart(Vec2(0, 40 + rng.nextDouble() * 380), rules)
        .withBase(Vec2(560, 40 + rng.nextDouble() * 300), rules);
    for (var x = 80.0; x < 520; x += 80) {
      d = d.addWaypoint(Vec2(x, 40 + rng.nextDouble() * 400), rules, snap: true);
    }
    return d.toMap(rules, id: 'gen-$seed', name: 'Generated $seed')!;
  }
}

void main() {
  late GameData data;
  setUpAll(() => data = loadClassicData());

  void expectContract(MapGenerator g, Iterable<int> seeds) {
    for (final seed in seeds) {
      final map = g.generate(seed);
      expect(checkMapContract(data, map), isEmpty, reason: '${g.id} seed $seed (${map.id})');
      expect(g.generate(seed).toJson(), map.toJson(), reason: 'same seed, same map');
    }
  }

  test('the built-in generator (every built-in map) meets the map contract', () {
    final g = BuiltInMapGenerator(data.maps.values);
    expect(g.maps, hasLength(data.maps.values.where((m) => m.builtIn).length));
    expectContract(g, Iterable.generate(g.maps.length));
  });

  test('a stub procedural generator meets the same contract', () {
    expectContract(_ZigZagGenerator(data.world.editor), Iterable.generate(8, (i) => i * 7919));
  });

  test('the contract rejects an invalid map', () {
    const bad = MapDefinition(
      id: 'bad',
      name: 'Bad',
      base: Vec2(600, 460),
      road: [Vec2(0, 100), Vec2(20, 100)],
      builtIn: false,
    );
    expect(checkMapContract(data, bad), ['invalid: noBase', 'invalid: tooShort']);
  });

  test('a built-in generator needs a built-in map', () {
    expect(() => BuiltInMapGenerator(const []), throwsArgumentError);
  });
}
