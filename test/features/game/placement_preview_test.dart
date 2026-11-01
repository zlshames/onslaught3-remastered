import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/features/game/placement_preview.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../support/test_data.dart';

void main() {
  late GameData data;
  setUpAll(() => data = loadTestGameData());

  /// Lyne (map9): road (0, 0) → (590, 410); these spots are clear of it.
  const spot = Vec2(300, 150);

  GameSession lyne() {
    final s = GameSession(
      data: data,
      config: const GameConfig(mapId: 'map9', seed: 3),
    )..debugCash = 1e7;
    for (final id in data.turrets.keys) {
      s.debugMakeAvailable(id);
    }
    return s;
  }

  test('a ghost locks only on the map, and a locked ghost builds the same way', () {
    final s = lyne();
    final locked = placementPreview(s, 'blue', spot, locked: true)!;
    expect((locked.locked, locked.valid), (true, true));
    expect(placementPreview(s, 'blue', null, locked: true)!.locked, isFalse);
    expect(placementPreview(s, 'blue', spot)!.locked, isFalse);
    final build = placementCommand(locked)! as BuildTurret;
    expect((build.turret, build.x, build.y), ('blue', spot.x, spot.y));
  });

  test('unknown turret ids have no ghost; off the map it is invalid', () {
    final s = lyne();
    expect(placementPreview(s, 'nope', spot), isNull);
    final off = placementPreview(s, 'blue', null)!;
    expect((off.valid, off.range), (false, data.turrets['blue']!.stats.range));
  });

  test('the ghost range includes the modifier auras covering it', () {
    final s = lyne();
    s.enqueue(const BuildTurret('range-up', 360, 150));
    s.step();
    final p = placementPreview(s, 'blue', spot)!;
    expect(p.valid, isTrue);
    expect(p.range, data.turrets['blue']!.stats.range + 100);
    // A modifier ghost is not modifiable: its own range.
    expect(placementPreview(s, 'damage-up', const Vec2(300, 90))!.range, 80);
  });

  test('a valid ghost places as a build or a move; anything else places nothing', () {
    final s = lyne();
    final build = placementPreview(s, 'blue', spot)!;
    expect(placementCommand(build)?.toJson(), const BuildTurret('blue', 300, 150).toJson());
    s.enqueue(const BuildTurret('blue', 300, 150));
    s.step();
    final uid = s.turrets.single.uid;
    final move = placementPreview(s, 'blue', const Vec2(200, 60), moving: uid)!;
    expect(move.moving, uid);
    expect(placementCommand(move)?.toJson(), MoveTurret(uid, 200, 60).toJson());
    expect(placementCommand(null), isNull);
    expect(placementCommand(placementPreview(s, 'blue', null)), isNull);
    // On top of the turret just built: not placeable.
    final blocked = placementPreview(s, 'green', spot)!;
    expect(blocked.valid, isFalse);
    expect(placementCommand(blocked), isNull);
  });
}
