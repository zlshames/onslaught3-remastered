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

  /// Step index whose end time is [ms] of game time at speed 1.
  int stepEndingAt(double ms) => (ms * data.rules.tickHz / 1000).round() - 1;

  test('wave data (AttackerManager / WaveManager)', () {
    expect(data.waves.waveSize, 10);
    expect(data.waves.waveSpacingMs, 20000);
    expect(data.waves.creepSpacingMs, 700);
    expect(data.waves.managerTickMs, 200);
  });

  test('wave 1 leaves on the first 200 ms check after 20 s; creeps every 800 ms', () {
    final s = harness.session(const GameConfig(mapId: 'map1'));
    final events = s.run(stepEndingAt(30000) + 1);
    final wave = events.whereType<WaveStarted>().single;
    expect(wave.tick, stepEndingAt(20200));
    expect(wave.early, isFalse);
    final spawns = events.whereType<CreepSpawned>().toList();
    expect(spawns, hasLength(10));
    // First check of the new wave's own interval, 200 ms after it was sent.
    expect(spawns.first.tick, stepEndingAt(20400));
    for (var i = 1; i < spawns.length; i++) {
      expect(spawns[i].tick - spawns[i - 1].tick, stepEndingAt(800) + 1, reason: 'spawn $i');
    }
  });

  test('wave 1: 13 HP (10 x 1.3), bounty 1, type 0, difficulty speed', () {
    for (final d in data.difficulty.levels) {
      final s = harness.session(GameConfig(mapId: 'map1', difficulty: d.id))
        ..enqueue(const SendNextWave());
      final w = s.step().whereType<WaveStarted>().single;
      expect(w.wave, 1);
      expect(w.size, 10);
      expect(w.hp, closeTo(data.difficulty.baseHp * d.hpSchedule.first.rate, 1e-9));
      expect(w.bounty, 1);
      expect(w.creepType, 0);
      expect(w.speed, d.creepSpeed);
      expect(w.early, isTrue);
    }
  });

  test('HP follows each difficulty curve for 120 waves; bounty = wave; types rotate', () {
    for (final d in data.difficulty.levels) {
      final s = harness.session(GameConfig(mapId: 'map1', difficulty: d.id));
      final waves = <WaveStarted>[];
      for (var i = 0; i < 120; i++) {
        s.enqueue(const SendNextWave());
        waves.addAll(s.step().whereType<WaveStarted>());
      }
      expect(waves, hasLength(120));
      for (final w in waves) {
        final expected = creepHpForWave(data.difficulty, d, w.wave);
        expect(w.hp, closeTo(expected, expected * 1e-12), reason: '${d.id} wave ${w.wave}');
        expect(w.bounty, w.wave);
        expect(w.creepType, (w.wave - 1) % data.creeps.types.length);
      }
    }
  });

  test('send-now resets the wave clock; refused while paused', () {
    final s = harness.session(const GameConfig(mapId: 'map1'))..run(600);
    expect(s.msUntilNextWave, closeTo(10000, 1e-6));
    s.enqueue(const SendNextWave());
    s.step();
    expect(s.waves.wave, 1);
    // Commands apply at the start of a step; that step's time then passes.
    expect(s.msUntilNextWave, closeTo(20000 - s.clock.stepMs, 1e-6));
    s
      ..enqueue(const SetPaused(true))
      ..enqueue(const SendNextWave());
    final rejected = s.step().whereType<CommandRejected>().single;
    expect(rejected.reason, 'paused');
    expect(s.waves.wave, 1);
  });

  test('each wave leaves 20.2 s after the previous one, creeps still on the road or not', () {
    // `now - wave_last > 20000` is false on the exact 20 s check, so every
    // wave goes one 200 ms check later: 20.2 s, 40.4 s, 60.6 s …
    final s = harness.session(const GameConfig(mapId: 'map1'));
    final events = s.run(stepEndingAt(60600) + 1);
    final waves = events.whereType<WaveStarted>().toList();
    expect(waves.map((w) => w.wave), [1, 2, 3]);
    expect(waves.map((w) => w.tick), [
      stepEndingAt(20200),
      stepEndingAt(40400),
      stepEndingAt(60600),
    ]);
    expect(s.creeps, isNotEmpty);
  });
}
