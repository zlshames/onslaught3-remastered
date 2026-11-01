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

  test('starting cash and lives come from data', () {
    final s = harness.session(const GameConfig(mapId: 'map1', difficulty: 'hard'));
    expect(s.cash, data.difficulty.levels.firstWhere((l) => l.id == 'hard').startingCash);
    expect(s.lives, data.rules.lives);
    final sandbox = harness.session(const GameConfig(mapId: 'map1', mode: 'sandbox'));
    expect(sandbox.cash, data.difficulty.modeCash['sandbox']);
  });

  test('unknown map or difficulty is rejected', () {
    expect(() => harness.session(const GameConfig(mapId: 'nope')), throwsArgumentError);
    expect(
      () => harness.session(const GameConfig(mapId: 'map1', difficulty: 'nope')),
      throwsArgumentError,
    );
  });

  test('the first step announces the session once', () {
    final s = harness.session(const GameConfig(mapId: 'map9', seed: 7));
    final first = s.step();
    expect(first.single, isA<SessionStarted>());
    expect((first.single as SessionStarted).seed, 7);
    expect(s.step(), isEmpty);
  });

  test('game clock: fixed steps × speed, frozen while paused', () {
    final s = harness.session(const GameConfig(mapId: 'map9'));
    final stepMs = 1000 / data.rules.tickHz;
    s.run(data.rules.tickHz);
    expect(s.clock.nowMs, closeTo(1000, 1e-6));
    s.enqueue(const SetPaused(true));
    final ev = s.run(30);
    expect(ev.whereType<PausedChanged>().single.paused, isTrue);
    expect(s.clock.nowMs, closeTo(1000, 1e-6));
    expect(s.tick, data.rules.tickHz + 30);
    s
      ..enqueue(const SetPaused(false))
      ..enqueue(const SetSpeed(2))
      ..step();
    expect(s.clock.nowMs, closeTo(1000 + 2 * stepMs, 1e-6));
  });

  test('speed is clamped to the data bounds and only changes emit', () {
    final s = harness.session(const GameConfig(mapId: 'map9'));
    s.enqueue(const SetSpeed(10));
    expect(s.step().whereType<SpeedChanged>().single.speed, data.rules.speedFactorMax);
    s.enqueue(const SetSpeed(10));
    expect(s.step().whereType<SpeedChanged>(), isEmpty);
    s.enqueue(const SetSpeed(0));
    expect(s.step().whereType<SpeedChanged>().single.speed, data.rules.speedFactorMin);
  });

  test('turrets whose mechanics the registry lacks are rejected, not ignored', () {
    // The classic registry without the sniper special.
    final classic = RulesRegistry.classic();
    final registry = RulesRegistry();
    for (final id in classic.turretSpecialIds.where((id) => id != 'sniper')) {
      registry.registerTurretSpecial(classic.turretSpecial(id));
    }
    for (final id in classic.projectileKindIds) {
      registry.registerProjectileKind(classic.projectileKind(id));
    }
    for (final id in classic.blastKindIds) {
      registry.registerBlastKind(classic.blastKind(id));
    }
    for (final id in classic.creepBehaviourIds) {
      registry.registerCreepBehaviour(classic.creepBehaviour(id));
    }
    final s =
        SimTestHarness(harness.data, registry: registry).session(const GameConfig(mapId: 'map9'))
          ..debugCash = 1e6
          ..debugMakeAvailable('sniper');
    expect(s.isBuildable(s.data.turrets['sniper']!), isFalse);
    s.enqueue(const BuildTurret('sniper', 300, 150));
    final rejected = s.step().whereType<CommandRejected>().single;
    expect(rejected.command, 'build');
    expect(rejected.reason, 'notImplemented');
  });

  test('every classic turret is buildable (Phase 4: all 16)', () {
    final s = harness.session(const GameConfig(mapId: 'map9'));
    for (final def in s.data.turrets.values) {
      expect(s.isBuildable(def), isTrue, reason: def.id);
    }
    expect(s.data.turrets, hasLength(16));
  });

  test('commands and events round-trip through JSON', () {
    const commands = <GameCommand>[
      BuildTurret('red', 1, 2),
      UpgradeTurret(3, 'range'),
      UpgradeTurretMax(3, 'damage'),
      SellTurret(3),
      MoveTurret(3, 4, 5),
      SetTargetMode(3, 'fast'),
      SetTargetLock(3, lockOff: true),
      SendNextWave(),
      SetPaused(true),
      SetSpeed(1.5),
      BuyFreakout(3),
      JoinTurret(3, 4),
      ChooseCombonly(3),
    ];
    for (final c in commands) {
      expect(GameCommand.fromJson(c.toJson()).toJson(), c.toJson());
    }
    expect(() => GameCommand.fromJson({'type': 'nope'}), throwsArgumentError);
  });

  test('state hash is deterministic and sensitive to state', () {
    final a = harness.session(const GameConfig(mapId: 'map1', seed: 3))..run(10);
    final b = harness.session(const GameConfig(mapId: 'map1', seed: 3))..run(10);
    expect(a.stateHash(), b.stateHash());
    b.random.nextUint32();
    expect(a.stateHash(), isNot(b.stateHash()));
  });

  test('harness applies scheduled commands on their tick', () {
    final run = harness.run(
      const Scenario(
        id: 't',
        description: 'pause on tick 5, resume on tick 10',
        mapId: 'map9',
        ticks: 20,
        hashEvery: 10,
        commands: [ScheduledCommand(5, SetPaused(true)), ScheduledCommand(10, SetPaused(false))],
      ),
    );
    expect(run.eventsOf<PausedChanged>().map((e) => (e.tick, e.paused)), [(5, true), (10, false)]);
    expect(run.hashes.map((h) => h.tick), [10, 20]);
    expect(run.session.clock.nowMs, closeTo(15 * 1000 / data.rules.tickHz, 1e-6));
  });
}
