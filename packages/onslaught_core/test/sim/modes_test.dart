import 'package:onslaught_core/onslaught_core.dart';
import 'package:onslaught_core/testing.dart';
import 'package:test/test.dart';

import '../support/repo_data.dart';

/// The tutorial (`GameManagerTutorial`, `GameTutorial`), the attract demo
/// (`GameManagerIntro`) and the wave settings (`GameManager.settingsApply`).
void main() {
  late GameData data;
  late SimTestHarness harness;
  setUpAll(() {
    data = loadClassicData();
    harness = SimTestHarness(data);
  });

  void autokill(GameSession s) {
    for (final c in List.of(s.creeps)) {
      if (c.targetable) s.hitCreep(c, double.infinity);
    }
  }

  group('tutorial', () {
    GameSession tutorial({RulesProfile profile = RulesProfile.classicFixed}) =>
        harness.session(GameConfig(mapId: data.tutorial.map, mode: 'tutorial', profile: profile));

    test('v1 (tutorialWaveLimit): ends after 50 waves once the field is clear', () {
      final s = tutorial();
      expect(s.objectives.waveLimit, 50);
      final events = <GameEvent>[];
      for (var i = 0; i < 20000 && !s.gameOver; i++) {
        if (!s.objectives.noMoreWaves) s.enqueue(const SendNextWave());
        s.step();
        autokill(s);
        events.addAll(s.events);
      }
      expect(events.whereType<ObjectiveReached>().map((e) => e.kind), ['waves']);
      expect(events.whereType<GameWon>(), hasLength(1));
      expect(s.waves.wave, 50);
      expect(progressOnWin(data.progression, const ProgressState(), s.config).map((c) => c.id), [
        'challenge',
        'tutorial',
      ]);
    });

    test('freeplay past the 50-wave end', () {
      final s = tutorial();
      while (!s.won) {
        if (!s.objectives.noMoreWaves) s.enqueue(const SendNextWave());
        s.step();
        autokill(s);
      }
      s.enqueue(const ContinuePlaying());
      s.step();
      for (var i = 0; i < 5; i++) {
        s.enqueue(const SendNextWave());
        s.step();
      }
      expect(s.waves.wave, 55);
    });

    test('classic: resetGame wipes the limit, so it never ends', () {
      final s = tutorial(profile: RulesProfile.classic);
      expect(s.objectives.any, isFalse);
      for (var i = 0; i < 60; i++) {
        s.enqueue(const SendNextWave());
        s.step();
        autokill(s);
      }
      expect(s.waves.wave, 60);
      expect(s.won, isFalse);
    });

    test('"Show me" on the cash page sets the cash once, even while paused', () {
      final s = tutorial();
      final page = data.tutorial.pages.indexWhere((p) => p.setCash != null);
      expect(data.tutorial.pages[page].title, 'Your First Combo');
      s
        ..enqueue(const SetPaused(true))
        ..enqueue(TutorialShow(page));
      final set = s.step().whereType<TutorialCashSet>().single;
      expect(set.cash, 14500);
      expect(s.cash, 14500);
      expect(s.totalSpent, 0);
      s.debugCash = 3;
      s.enqueue(TutorialShow(page));
      expect(s.step().whereType<TutorialCashSet>(), isEmpty);
      expect(s.cash, 3);
      s.enqueue(const TutorialShow(0));
      expect(s.step().whereType<TutorialCashSet>(), isEmpty);
    });

    test('"Show me" is refused outside the tutorial', () {
      final s = harness.session(const GameConfig(mapId: 'map1'));
      s.enqueue(const TutorialShow(14));
      expect(s.step().whereType<CommandRejected>().single.reason, 'notTutorial');
    });

    test('pages: 36 with the joke pages, show-now flags from the source', () {
      final pages = data.tutorial.pages;
      expect(pages, hasLength(36));
      expect(pages.where((p) => p.title == 'Back Home'), hasLength(2));
      expect(
        [
          for (var i = 0; i < pages.length; i++)
            if (pages[i].showNow) i + 1,
        ],
        [1, 2, 3, 10, 17, 20],
      );
      for (final p in pages.where((p) => p.showNow)) {
        expect(p.pointer, isNotNull, reason: p.title);
      }
    });
  });

  group('attract demo', () {
    test('places its 19 turrets for free on the first step', () {
      final s = harness.session(const GameConfig.attractDemo());
      final built = s.step().whereType<TurretBuilt>().toList();
      expect(built, hasLength(19));
      expect(built.every((b) => b.cost == 0), isTrue);
      expect({for (final t in s.turrets) t.def.id}, {'blue', 'green', 'red', 'yellow'});
      expect(s.map.id, AttractDef.mapId);
      expect(s.map.road, hasLength(12));
      expect(s.cash, data.difficulty.levels.first.startingCash);
    });

    test('one tough creep every 6 s, of the first three types', () {
      final s = harness.session(const GameConfig.attractDemo());
      final waves = <WaveStarted>[];
      final times = <double>[];
      while (waves.length < 4) {
        final w = s.step().whereType<WaveStarted>();
        if (w.isNotEmpty) times.add(s.clock.nowMs);
        waves.addAll(w);
      }
      expect(times, [6200, 12400, 18600, 24800]);
      expect([for (final w in waves) w.size], [1, 1, 1, 1]);
      expect([for (final w in waves) w.creepType], [0, 1, 2, 0]);
      // 1050 grown by easy's wave-1 rate, ×10 for a one-creep wave.
      expect(waves.first.hp, closeTo(1050 * 1.3 * 10, 1e-9));
      final c = s.run(30).whereType<CreepSpawned>().first;
      expect(s.creepByUid(c.uid)!.scaleBump, 1, reason: 'no size bump');
    });

    test('never loses a life and never counts a kill', () {
      final s = harness.session(const GameConfig.attractDemo());
      final events = s.run(60 * 400);
      expect(events.whereType<BaseHit>(), isNotEmpty);
      expect(s.lives, data.rules.lives);
      expect(s.gameOver, isFalse);
      // The level-1 turrets fire, but rarely finish a 10× creep.
      expect(events.whereType<TurretFired>(), isNotEmpty);
      s.hitCreep(s.creeps.firstWhere((c) => c.targetable), double.infinity);
      expect(s.events.whereType<CreepKilled>().single.kills, 0);
      expect(s.kills, 0);
      expect(events.whereType<WeaponUnlocked>(), isEmpty);
    });
  });

  group('wave settings', () {
    test('spacing applies to the wave clock, within the settings bounds', () {
      final s = harness.session(const GameConfig(mapId: 'map1'));
      s
        ..enqueue(const SetPaused(true))
        ..enqueue(const SetWaveSettings(spacingMs: 10000, follow: false));
      final changed = s.step().whereType<WaveSettingsChanged>().single;
      expect(changed.spacingMs, 10000);
      s.enqueue(const SetPaused(false));
      final first = <double>[];
      while (first.isEmpty) {
        if (s.step().whereType<WaveStarted>().isNotEmpty) first.add(s.clock.nowMs);
      }
      expect(first.single, 10200);
      s.enqueue(const SetWaveSettings(spacingMs: 1000, follow: false));
      s.step();
      expect(s.waveSpacingMs, data.waves.spacingPrefMinS * 1000);
      s.enqueue(const SetWaveSettings(spacingMs: 1e9, follow: false));
      s.step();
      expect(s.waveSpacingMs, data.waves.spacingPrefMaxS * 1000);
    });

    test('a config spacing and follow start the game with them', () {
      final s = harness.session(
        const GameConfig(mapId: 'map1', waveSpacingMs: 15000, waveFollow: true),
      );
      expect(s.waveSpacingMs, 15000);
      expect(s.waveFollow, isTrue);
    });

    test('wave follow sends the next wave as soon as the field is clear', () {
      final s = harness.session(const GameConfig(mapId: 'map1', waveFollow: true));
      s.enqueue(const SendNextWave());
      var sent = 0;
      for (var i = 0; i < 60 * 30; i++) {
        sent += s.step().whereType<WaveStarted>().length;
        autokill(s);
      }
      // Each wave takes ~8 s to send its ten creeps; without follow there
      // would be 2 waves in these 30 s (the one asked for and one at 20.2 s).
      expect(sent, greaterThanOrEqualTo(3));
    });
  });
}
