import 'package:onslaught_core/onslaught_core.dart';
import 'package:onslaught_core/testing.dart';
import 'package:test/test.dart';

import '../support/repo_data.dart';
import '../support/sim_helpers.dart';

void main() {
  late GameData data;
  late SimTestHarness harness;
  setUpAll(() {
    data = loadClassicData();
    harness = SimTestHarness(data);
  });

  GameSession lyne() => harness.session(const GameConfig(mapId: 'map9', seed: 2))..debugCash = 1e6;

  /// Kills one creep of a freshly sent wave.
  List<GameEvent> killOne(GameSession s) {
    final creep = s.creeps.firstOrNull ?? firstCreep(s);
    s.hitCreep(creep, double.infinity);
    return s.events;
  }

  test('the four colours are available from the start, the rest locked', () {
    final s = lyne();
    for (final def in data.turrets.values) {
      expect(s.isAvailable(def), def.availableInitially, reason: def.id);
    }
    expect(
      [
        for (final d in data.turrets.values)
          if (d.availableInitially) d.id,
      ],
      ['blue', 'green', 'red', 'yellow'],
    );
    s.enqueue(const BuildTurret('range-up', 300, 150));
    expect(s.step().whereType<CommandRejected>().single.reason, 'locked');
  });

  test(
    'a turret unlocks on the kill that reaches its threshold (GameManager.weaponStoreUpdate)',
    () {
      final s = lyne();
      s.debugKills = 298;
      expect(killOne(s).whereType<WeaponUnlocked>(), isEmpty);
      s.step();
      final unlocked = killOne(s).whereType<WeaponUnlocked>().single;
      expect(unlocked.turret, 'range-up');
      expect(unlocked.kills, 300);
      expect(s.unlocked, ['range-up']);
      expect(s.snapshot()['unlocked'], ['range-up']);
      build(s, 'range-up', const Vec2(300, 150));
    },
  );

  test('every threshold in turn: 300 … 1600', () {
    final s = lyne();
    final order = <String>[];
    for (final def in data.turrets.values.where((d) => d.unlockKills > 0)) {
      s
        ..debugKills = def.unlockKills - 1
        ..step();
      order.addAll(killOne(s).whereType<WeaponUnlocked>().map((e) => e.turret));
    }
    expect(order, [
      'range-up',
      'damage-up',
      'rate-up-exchange',
      'range-up-exchange',
      'rate-up',
      'damage-up-big',
      'damage-up-big-exchange',
      'targeter',
      'sniper',
      'fusion',
      'railgun',
      'combonly',
    ]);
  });
}
