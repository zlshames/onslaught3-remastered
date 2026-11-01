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

  GameSession sessionWithWave(String mapId, {int seed = 1}) =>
      harness.session(GameConfig(mapId: mapId, seed: seed))..enqueue(const SendNextWave());

  /// Runs until the first creep exists and returns it.
  Creep firstCreep(GameSession s) {
    while (s.creeps.isEmpty) {
      s.step();
    }
    return s.creeps.first;
  }

  test('creeps spawn at the first road point within the 19 px jitter', () {
    for (var seed = 1; seed <= 20; seed++) {
      final s = sessionWithWave('map1', seed: seed);
      final c = firstCreep(s);
      final start = s.road.points.first;
      final dx = c.legFrom.x - start.x;
      final dy = c.legFrom.y - start.y;
      expect(dx, inInclusiveRange(-9, 9));
      expect(dy, inInclusiveRange(-9, 9));
      expect(dx, dx.roundToDouble());
      // The leg heads for the second road point, re-jittered.
      expect((c.legTo - s.road.points[1]).x.abs(), lessThanOrEqualTo(9));
      expect(c.waypoint, 1);
    }
  });

  test('a leg lasts the distance to the un-jittered waypoint over the speed', () {
    final s = sessionWithWave('map9');
    final c = firstCreep(s);
    final target = s.road.points[1];
    expect(c.legDurationMs, closeTo(c.legFrom.distanceTo(target) / 60 * 1000, 1e-6));
    expect(c.baseSpeed, 60);
  });

  test('a creep moves linearly along its leg and hits the base at the end', () {
    final s = sessionWithWave('map9');
    final c = firstCreep(s);
    final arrival = c.createdAtMs + c.legDurationMs; // Lyne has one leg
    final stepMs = 1000 / data.rules.tickHz;
    s.run(30);
    final t = (s.clock.nowMs - c.createdAtMs) / c.legDurationMs;
    final expected = c.legFrom.lerp(c.legTo, t);
    expect(c.position.x, closeTo(expected.x, 1e-6));
    expect(c.position.y, closeTo(expected.y, 1e-6));
    BaseHit? hit;
    while (hit == null) {
      hit = s.step().whereType<BaseHit>().firstOrNull;
    }
    expect(hit.uid, c.uid);
    expect(hit.lives, data.rules.lives - 1);
    expect(s.lives, data.rules.lives - 1);
    expect(s.clock.nowMs, inInclusiveRange(arrival, arrival + stepMs));
    expect(s.creepByUid(c.uid), isNull);
  });

  test('creeps walk every waypoint of a multi-leg road in order', () {
    final s = sessionWithWave('map1');
    final c = firstCreep(s);
    var lastWaypoint = c.waypoint;
    while (!c.gone) {
      s.step();
      expect(c.waypoint, greaterThanOrEqualTo(lastWaypoint));
      lastWaypoint = c.waypoint;
    }
    expect(lastWaypoint, s.road.points.length);
  });

  test('the tenth leak ends the game: clock stops, commands are refused', () {
    final s = harness.session(const GameConfig(mapId: 'map9'));
    final events = <GameEvent>[];
    while (!s.gameOver && s.tick < 10000) {
      events.addAll(s.step());
    }
    expect(s.gameOver, isTrue);
    expect(events.whereType<BaseHit>(), hasLength(10));
    final over = events.whereType<GameOver>().single;
    expect(over.wave, s.waves.wave);
    expect(over.kills, 0);
    expect(over.score, 0);
    expect(s.lives, 0);
    final frozen = s.clock.nowMs;
    s.enqueue(const SendNextWave());
    final after = s.run(10);
    expect(after.whereType<CommandRejected>().single.reason, 'gameOver');
    expect(after.whereType<CreepSpawned>(), isEmpty);
    expect(s.clock.nowMs, frozen);
  });

  test('scale bump is 1 for normal waves', () {
    final c = firstCreep(sessionWithWave('map1'));
    expect(c.scaleBump, 1);
    expect(c.hpStart, closeTo(13, 1e-9));
    expect(c.hpPercent, 100);
  });
}
