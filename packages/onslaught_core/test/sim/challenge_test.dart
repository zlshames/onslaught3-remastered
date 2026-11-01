import 'package:onslaught_core/onslaught_core.dart';
import 'package:onslaught_core/testing.dart';
import 'package:test/test.dart';

import '../support/repo_data.dart';

/// Challenges (`GameManager.resetGame` challenge branch, `waveLimitHit`,
/// `killTargetHit`, `timeLimitUpdate`/`timeLimitHit`, `gameWinCheck`;
/// `AttackerManager.waveSend`/`update`), run for every preset.
void main() {
  late GameData data;
  late SimTestHarness harness;
  setUpAll(() {
    data = loadClassicData();
    harness = SimTestHarness(data);
  });

  ChallengeDef preset(String id) => data.challenges.presets.firstWhere((p) => p.id == id);

  GameSession challenge(ChallengeDef c, {RulesProfile profile = RulesProfile.classicFixed}) =>
      harness.session(
        GameConfig(
          mapId: 'map1',
          mode: 'challenge',
          difficulty: c.difficulty,
          challenge: c,
          profile: profile,
          seed: 7,
        ),
      );

  /// Kills every creep on the road (credited to no turret), as perfect
  /// defences would.
  void autokill(GameSession s) {
    for (final c in List.of(s.creeps)) {
      if (c.targetable) s.hitCreep(c, double.infinity);
    }
  }

  /// Runs [s] until it ends or [maxSeconds] of game time pass. [rush] asks
  /// for a wave every step; [defend] kills every creep at once. Returns
  /// every event.
  List<GameEvent> play(
    GameSession s, {
    required bool rush,
    required bool defend,
    double maxSeconds = 4000,
    double speed = 2,
  }) {
    final events = <GameEvent>[];
    s.enqueue(SetSpeed(speed));
    while (!s.gameOver && s.clock.nowMs < maxSeconds * 1000) {
      if (rush && !s.objectives.noMoreWaves) s.enqueue(const SendNextWave());
      s.step();
      if (defend) autokill(s);
      // The step's events and those of the kills just made.
      events.addAll(s.events);
    }
    return events;
  }

  String outcome(List<GameEvent> events) {
    final won = events.whereType<GameWon>().firstOrNull;
    final lost = events.whereType<GameOver>().firstOrNull;
    if (won != null) return 'won';
    if (lost != null) return 'lost:${lost.reason}';
    return 'running';
  }

  test('there are 14 presets, plus the debug-only test one', () {
    expect(
      [
        for (final p in data.challenges.presets)
          if (!p.debugOnly) p.id,
      ],
      [
        'warmup',
        'threetown',
        'spiffles',
        'limitations',
        'problem-3',
        'bounce',
        'bludgeon',
        'longshine',
        'speedshine',
        'hardshine',
        'duration',
        'clockers',
        'ripples',
        'smollocks',
      ],
    );
  });

  group('every preset', () {
    for (final id in [
      'warmup',
      'threetown',
      'spiffles',
      'limitations',
      'problem-3',
      'bounce',
      'bludgeon',
      'longshine',
      'speedshine',
      'hardshine',
      'duration',
      'clockers',
      'ripples',
      'smollocks',
    ]) {
      group(id, () {
        test('starts with its cash and difficulty and cycles its wave sizes and speeds', () {
          final c = preset(id);
          final s = challenge(c);
          s.step();
          expect(s.cash, c.cash);
          expect(s.difficulty.id, c.difficulty);
          expect(s.objectives.waveLimit, c.objective?.type == 'waves' ? c.objective!.target : null);
          expect(
            s.objectives.killTarget,
            c.objective?.type == 'kills' ? c.objective!.target : null,
          );
          expect(s.objectives.timeLimitMs, c.timeLimitS == null ? null : c.timeLimitS! * 1000);
          final started = <WaveStarted>[];
          for (var i = 0; i < 12; i++) {
            s.enqueue(const SendNextWave());
            started.addAll(s.step().whereType<WaveStarted>());
          }
          expect(started, hasLength(12));
          for (var i = 0; i < started.length; i++) {
            final w = started[i];
            final size = c.waveSizes[i % c.waveSizes.length];
            expect(w.size, size, reason: 'wave ${i + 1} size');
            expect(w.speed, c.waveSpeeds[i % c.waveSpeeds.length], reason: 'wave ${i + 1} speed');
            expect(w.bounty, creepBounty(w.wave, size, data.waves.waveSize));
            final hp =
                creepHpForWave(data.difficulty, s.difficulty, w.wave) *
                waveSizeScale(size, data.waves.waveSize);
            expect(w.hp, closeTo(hp, hp * 1e-12), reason: 'wave ${i + 1} hp');
          }
        });

        test('its turret limit refuses the next build', () {
          final c = preset(id);
          final s = challenge(c)..debugCash = 1e9;
          final limit = c.turretLimit;
          final spots = <Vec2>[];
          for (var y = 30.0; y < 470 && spots.length < (limit ?? 20) + 1; y += 40) {
            for (var x = 30.0; x < 700 && spots.length < (limit ?? 20) + 1; x += 40) {
              final at = Vec2(x, y);
              if (s.placementIssueAt(at) == null &&
                  spots.every((p) => p.distanceTo(at) >= data.world.placement.turretSpacing)) {
                spots.add(at);
              }
            }
          }
          final rejected = <String>[];
          for (final at in spots) {
            s.enqueue(BuildTurret('blue', at.x, at.y));
            rejected.addAll(s.step().whereType<CommandRejected>().map((e) => e.reason));
          }
          if (limit == null) {
            expect(rejected, isEmpty);
            expect(s.turrets, hasLength(spots.length));
          } else {
            expect(s.turrets, hasLength(limit));
            expect(rejected, ['turretLimit']);
          }
        });

        test('losing every life fails it', () {
          final events = play(challenge(preset(id)), rush: true, defend: false);
          expect(outcome(events), 'lost:lives');
          expect(events.whereType<GameWon>(), isEmpty);
        });

        ChallengeDef c0() => preset(id);
        test('perfect defence with every wave sent at once passes it', () {
          final c = c0();
          final events = play(challenge(c), rush: true, defend: true);
          if (c.objective == null) {
            // Nothing to rush towards: it lasts until its time limit.
            expect(outcome(events), c.timeLimitS == null ? 'running' : 'won');
          } else {
            expect(outcome(events), 'won');
            expect(events.whereType<ObjectiveReached>().first.kind, c.objective!.type);
          }
        });

        test('perfect defence at the wave clock\'s pace: the time limit decides', () {
          final c = c0();
          final s = challenge(c);
          final events = play(s, rush: false, defend: true);
          if (c.timeLimitS == null) {
            expect(outcome(events), 'running');
            return;
          }
          // None of the timed objectives can be reached at 20 s a wave.
          final reached = events.whereType<ObjectiveReached>().map((e) => e.kind).toList();
          final missed = events.whereType<ObjectiveMissed>().map((e) => e.kind).toList();
          if (c.objective == null) {
            expect(outcome(events), 'won');
            expect(reached, ['time']);
            expect(missed, isEmpty);
          } else {
            expect(outcome(events), 'lost:timeLimit');
            expect(reached, isEmpty);
            expect(missed, [c.objective!.type, 'time']);
          }
        });
      });
    }
  });

  group('timing', () {
    test('Warmup: time is up at 59.6 s and won on the next win check once clear', () {
      final s = challenge(preset('warmup'));
      ObjectiveReached? up;
      double? upAt;
      GameWon? won;
      double? wonAt;
      while (won == null && s.clock.nowMs < 70000) {
        for (final e in s.step()) {
          if (e is ObjectiveReached) {
            up = e;
            upAt = s.clock.nowMs;
          }
          if (e is GameWon) {
            won = e;
            wonAt = s.clock.nowMs;
          }
        }
        autokill(s);
      }
      expect(up?.kind, 'time');
      // `Math.round((end - now) / 1000) <= 0` from 59.5 s, checked every 200 ms.
      expect(upAt, closeTo(59600, 1e-6));
      expect(s.objectives.noMoreWaves, isTrue);
      expect(won, isNotNull);
      expect(wonAt, closeTo(60600, 1e-6));
      expect(s.won, isTrue);
      expect(s.gameOver, isTrue);
      expect(s.timeLimitSecondsLeft, 0);
    });

    test('the win waits for the field to clear', () {
      final s = challenge(preset('threetown'));
      for (var i = 0; i < 301; i++) {
        s.enqueue(const SendNextWave());
        s.step();
      }
      expect(s.objectives.waveLimitHit, isTrue);
      expect(s.objectives.noMoreWaves, isTrue);
      // Waves already sending carry on.
      final spawned = s.run(600).whereType<CreepSpawned>();
      expect(spawned, isNotEmpty);
      expect(s.won, isFalse);
      s.enqueue(const SendNextWave());
      expect(s.step().whereType<CommandRejected>().single.reason, 'noMoreWaves');
      expect(s.msUntilNextWave, 0);
      for (var i = 0; i < 6000 && !s.won && !s.gameOver; i++) {
        s.step();
        autokill(s);
      }
      expect(s.won, isTrue);
      expect(s.waves.wave, 300);
    });

    test('the kill target ends the waves at once', () {
      final s = challenge(preset('longshine'));
      while (s.kills < 1000 && !s.gameOver) {
        s.enqueue(const SendNextWave());
        s.step();
        autokill(s);
      }
      expect(s.objectives.killTargetHit, isTrue);
      final wave = s.waves.wave;
      s.enqueue(const SendNextWave());
      expect(s.step().whereType<CommandRejected>().single.reason, 'noMoreWaves');
      expect(s.waves.wave, wave);
    });

    test('the win check runs on real time, also while paused', () {
      final s = challenge(preset('warmup'));
      while (!s.objectives.timeLimitHit) {
        s.step();
        autokill(s);
      }
      s.enqueue(const SetPaused(true));
      final events = s.run(61);
      expect(events.whereType<GameWon>(), hasLength(1));
    });

    test('freeplay: continue after a win; waves resume, no time limit, no second win', () {
      final s = challenge(preset('warmup'));
      while (!s.won) {
        s.step();
        autokill(s);
      }
      final wonAt = s.clock.nowMs;
      final wave = s.waves.wave;
      expect(s.gameOver, isTrue);
      s.enqueue(const SendNextWave());
      expect(s.step().whereType<CommandRejected>().single.reason, 'gameOver');
      s.enqueue(const ContinuePlaying());
      final started = s.step().whereType<FreeplayStarted>().single;
      expect(started.wave, wave);
      expect(started.nextWaveMs, data.waves.waveSpacingMs);
      expect([s.freeplay, s.won, s.gameOver], [isTrue, isTrue, isFalse]);
      expect(s.snapshot()['freeplay'], isTrue);
      // The wave clock starts a fresh spacing from the continue.
      final events = <GameEvent>[];
      while (s.clock.nowMs < wonAt + 120000) {
        s.step();
        autokill(s);
        events.addAll(s.events);
      }
      final waves = events.whereType<WaveStarted>().toList();
      expect(waves, isNotEmpty);
      expect(waves.first.wave, wave + 1);
      expect(events.whereType<GameWon>(), isEmpty);
      expect(events.whereType<ObjectiveReached>(), isEmpty);
      expect(events.whereType<GameOver>(), isEmpty, reason: 'the time limit no longer applies');
      // "Send now" works again.
      s.enqueue(const SendNextWave());
      expect(s.step().whereType<WaveStarted>(), hasLength(1));
      s.enqueue(const ContinuePlaying());
      expect(s.step().whereType<CommandRejected>().single.reason, 'notWon');
    });

    test('freeplay ends when the lives run out', () {
      final s = challenge(preset('longshine'))..debugCash = 0;
      while (!s.won) {
        if (!s.objectives.noMoreWaves) s.enqueue(const SendNextWave());
        s.step();
        autokill(s);
      }
      s.enqueue(const ContinuePlaying());
      s.step();
      final events = play(s, rush: true, defend: false);
      expect(outcome(events), 'lost:lives');
      expect(events.whereType<GameOver>().single.kills, greaterThanOrEqualTo(1000));
    });

    test('continue is refused before a win and under the classic rules', () {
      final s = challenge(preset('warmup'));
      s.enqueue(const ContinuePlaying());
      expect(s.step().whereType<CommandRejected>().single.reason, 'notWon');
      final c = challenge(preset('warmup'), profile: RulesProfile.classic);
      while (!c.won) {
        c.step();
        autokill(c);
      }
      c.enqueue(const ContinuePlaying());
      expect(c.step().whereType<CommandRejected>().single.reason, 'notAllowed');
      expect(c.gameOver, isTrue);
    });

    test('a normal game has no objectives and never wins', () {
      final s = harness.session(const GameConfig(mapId: 'map1'));
      expect(s.objectives.any, isFalse);
      final events = play(s, rush: true, defend: true, maxSeconds: 200);
      expect(events.whereType<GameWon>(), isEmpty);
      expect(events.whereType<ObjectiveReached>(), isEmpty);
      expect(s.snapshot().containsKey('objectives'), isFalse);
    });
  });
}
