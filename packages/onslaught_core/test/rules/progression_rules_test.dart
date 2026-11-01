import 'package:onslaught_core/onslaught_core.dart';
import 'package:test/test.dart';

import '../support/repo_data.dart';

/// `GameManager.modeUpdate`, `gameWin`, `challengeEncode` and
/// `challengeSaveBest`, against the data in `progression.json` and
/// `challenges.json`.
void main() {
  late GameData data;
  late ProgressionDefs defs;
  setUpAll(() {
    data = loadClassicData();
    defs = data.progression;
  });

  List<String> kill(
    ProgressState state, {
    String mode = 'normal',
    required String difficulty,
    required int kills,
  }) => [
    for (final c in progressOnKill(defs, state, mode: mode, difficulty: difficulty, kills: kills))
      '$c',
  ];

  group('unlock milestones (GameManager.modeUpdate)', () {
    const none = ProgressState();

    // (difficulty, kills, state before) → changes, in announcement order.
    final table = <(String, int, ProgressState, List<String>)>[
      ('easy', 1999, none, []),
      ('easy', 2000, none, ['unlock extreme (flow.unlockExtreme)']),
      ('medium', 2000, none, ['unlock extreme (flow.unlockExtreme)']),
      ('hard', 2000, none, ['unlock extreme (flow.unlockExtreme)']),
      ('extreme', 2000, none, ['unlock extreme (flow.unlockExtreme)']),
      ('easy', 2001, none, []),
      ('easy', 2000, const ProgressState(available: {'extreme'}), []),
      ('easy', 4000, none, ['complete easy (flow.completeDifficulty)']),
      (
        'medium',
        4000,
        none,
        ['complete medium (flow.completeDifficulty)', 'unlock sandbox (flow.unlockSandbox)'],
      ),
      (
        'hard',
        4000,
        none,
        ['complete hard (flow.completeDifficulty)', 'unlock sandbox2 (flow.unlockSandbox2)'],
      ),
      ('extreme', 4000, none, ['complete extreme (flow.completeDifficulty)']),
      ('easy', 4001, none, []),
      // Already complete: nothing to say (the original stays silent too).
      ('easy', 4000, const ProgressState(complete: {'easy'}), []),
      (
        'medium',
        4000,
        const ProgressState(complete: {'medium'}),
        ['unlock sandbox (flow.unlockSandbox)'],
      ),
      // The third difficulty completed unlocks modding.
      (
        'hard',
        4000,
        const ProgressState(available: {'sandbox2'}, complete: {'easy', 'medium'}),
        ['complete hard (flow.completeDifficulty)', 'unlock modding (flow.unlockModding)'],
      ),
      (
        'easy',
        4000,
        const ProgressState(available: {'modding'}, complete: {'medium', 'hard'}),
        ['complete easy (flow.completeDifficulty)'],
      ),
    ];
    for (final (difficulty, kills, state, expected) in table) {
      test('$difficulty at $kills kills from ${state.available}/${state.complete}', () {
        expect(kill(state, difficulty: difficulty, kills: kills), expected);
      });
    }

    test('only normal games count', () {
      for (final mode in ['sandbox', 'sandbox2', 'challenge', 'tutorial']) {
        expect(
          kill(none, mode: mode, difficulty: 'medium', kills: 4000),
          isEmpty,
          reason: mode,
        );
        expect(
          kill(none, mode: mode, difficulty: 'easy', kills: 2000),
          isEmpty,
          reason: mode,
        );
      }
    });

    test('a new profile unlocks extreme, the sandboxes and modding through play', () {
      var s = none;
      for (final d in ['easy', 'medium', 'hard']) {
        for (final k in [2000, 4000]) {
          s = s.apply(progressOnKill(defs, s, mode: 'normal', difficulty: d, kills: k));
        }
      }
      expect(s.available, {'extreme', 'sandbox', 'sandbox2', 'modding'});
      expect(s.complete, {'easy', 'medium', 'hard'});
      s = s.apply(progressOnWin(defs, s, const GameConfig(mapId: 'tutorial', mode: 'tutorial')));
      expect(s.available, containsAll(['challenge']));
      expect(s.complete, contains('tutorial'));
      for (final m in defs.modes) {
        expect(isModeAvailable(defs, s, m), isTrue, reason: m);
      }
    });

    test('availability: always-modes, unlocked modes and the debug toggle', () {
      expect(isModeAvailable(defs, none, 'normal'), isTrue);
      expect(isModeAvailable(defs, none, 'tutorial'), isTrue);
      expect(isModeAvailable(defs, none, 'mapping'), isTrue);
      for (final m in ['extreme', 'sandbox', 'sandbox2', 'modding', 'challenge']) {
        expect(isModeAvailable(defs, none, m), isFalse, reason: m);
        expect(isModeAvailable(defs, none, m, unlockAll: true), isTrue, reason: m);
        expect(isModeAvailable(defs, ProgressState(available: {m}), m), isTrue, reason: m);
      }
    });
  });

  group('starts (GameManagerTutorial.setupFinal)', () {
    test('starting the tutorial unlocks challenges, once', () {
      const config = GameConfig(mapId: 'tutorial', mode: 'tutorial');
      expect(
        ['${progressOnStart(defs, const ProgressState(), config)}'],
        ['[unlock challenge (flow.tutorialUnlockChallenge)]'],
      );
      expect(progressOnStart(defs, const ProgressState(available: {'challenge'}), config), isEmpty);
    });

    test('no other game unlocks anything as it starts', () {
      for (final mode in ['normal', 'extreme', 'sandbox', 'sandbox2']) {
        expect(
          progressOnStart(defs, const ProgressState(), GameConfig(mapId: 'map1', mode: mode)),
          isEmpty,
          reason: mode,
        );
      }
    });
  });

  group('wins (GameManager.gameWin)', () {
    test('the tutorial unlocks challenges and is ticked off, once', () {
      const config = GameConfig(mapId: 'tutorial', mode: 'tutorial');
      expect(
        ['${progressOnWin(defs, const ProgressState(), config)}'],
        ['[unlock challenge (flow.unlockChallenge), complete tutorial]'],
      );
      expect(
        progressOnWin(
          defs,
          const ProgressState(available: {'challenge'}, complete: {'tutorial'}),
          config,
        ),
        isEmpty,
      );
    });

    test('a challenge is ticked off under its key', () {
      final warmup = data.challenges.presets.firstWhere((p) => p.id == 'warmup');
      final config = GameConfig(mapId: 'map1', mode: 'challenge', challenge: warmup);
      final changes = progressOnWin(defs, const ProgressState(), config);
      expect(changes, [
        const ProgressChange(
          ProgressChange.completion,
          'challenge;easy;undefined;30;60;undefined;10;60',
        ),
      ]);
      expect(progressOnWin(defs, const ProgressState().apply(changes), config), isEmpty);
    });

    test('normal and sandbox games have nothing to win', () {
      expect(progressOnWin(defs, const ProgressState(), const GameConfig(mapId: 'map1')), isEmpty);
    });
  });

  group('challenge keys (GameManager.challengeEncode)', () {
    test('every preset encodes as the original does', () {
      // The original's preset objects, encoded with its own string rules.
      final legacy = (loadLegacyTable()['challenges']! as Map)['presets']! as List<Object?>;
      String orig(Object? v) => v == null ? 'undefined' : '$v';
      final expected = {
        for (final p in legacy.cast<Map<String, Object?>>())
          if (p['debugOnly'] != true)
            p['name']: [
              'challenge',
              p['difficulty'],
              orig(p['objective']),
              orig(p['cash']),
              orig(p['timelimit']),
              orig(p['turretlimit']),
              orig(p['wavesize']),
              orig(p['wavespeed']),
            ].join(';'),
      };
      final actual = {
        for (final p in data.challenges.presets)
          if (!p.debugOnly) p.name: challengeKey(p),
      };
      expect(actual, expected);
      expect(
        actual['Bounce'],
        'challenge;medium;k,4000;3000;1200;undefined;10,9,8,7,6,5,4,3,2,1;60',
      );
      expect(actual['Smollocks'], 'challenge;hard;w,500;30;1800;15;10;60,40');
    });

    test('a key gives back its preset, or a custom challenge', () {
      for (final p in data.challenges.presets) {
        expect(challengeFromKey(challengeKey(p), data.challenges), same(p), reason: p.id);
      }
      const key = 'challenge;hard;k,2000;500;300;20;1,2,3;40,60,90';
      final custom = challengeFromKey(key, data.challenges)!;
      expect(custom.id, customChallengeId);
      expect(custom.difficulty, 'hard');
      expect(custom.objective!.type, ChallengeObjective.kills);
      expect(custom.objective!.target, 2000);
      expect(custom.cash, 500);
      expect(custom.timeLimitS, 300);
      expect(custom.turretLimit, 20);
      expect(custom.waveSizes, [1, 2, 3]);
      expect(custom.waveSpeeds, [40, 60, 90]);
      expect(challengeKey(custom), key);
      const survive = 'challenge;easy;undefined;30;undefined;undefined;10;60';
      final s = challengeFromKey(survive, data.challenges)!;
      expect(s.objective, isNull);
      expect(s.timeLimitS, isNull);
      expect(s.turretLimit, isNull);
      expect(challengeKey(s), survive);
    });

    test('malformed keys are refused', () {
      for (final bad in [
        '',
        'challenge;easy',
        'normal;easy;undefined;30;undefined;undefined;10;60',
        'challenge;easy;x,10;30;undefined;undefined;10;60',
        'challenge;easy;undefined;lots;undefined;undefined;10;60',
        'challenge;easy;undefined;30;undefined;undefined;0;60',
        'challenge;easy;undefined;30;undefined;undefined;10;fast',
      ]) {
        expect(challengeFromKey(bad, data.challenges), isNull, reason: bad);
      }
    });
  });

  group('best game (GameManager.challengeSaveBest)', () {
    late ChallengeDef byKills;
    late ChallengeDef byScore;
    setUpAll(() {
      byKills = data.challenges.presets.firstWhere((p) => p.id == 'problem-3');
      byScore = data.challenges.presets.firstWhere((p) => p.id == 'threetown');
    });
    const a = ChallengeResult(kills: 100, spent: 50, score: 5000);
    const moreKillsLowerScore = ChallengeResult(kills: 101, spent: 10, score: 1010);
    const fewerKillsHigherScore = ChallengeResult(kills: 99, spent: 100, score: 9900);

    test('the first game is always kept', () {
      expect(improvesBest(null, a, byKills), isTrue);
      expect(improvesBest(null, a, byScore), isTrue);
    });

    test('kill-target challenges compare kills', () {
      expect(improvesBest(a, moreKillsLowerScore, byKills), isTrue);
      expect(improvesBest(a, fewerKillsHigherScore, byKills), isFalse);
      expect(improvesBest(a, a, byKills), isFalse, reason: 'strictly more');
    });

    test('every other challenge compares score', () {
      expect(improvesBest(a, moreKillsLowerScore, byScore), isFalse);
      expect(improvesBest(a, fewerKillsHigherScore, byScore), isTrue);
      expect(improvesBest(a, a, byScore), isFalse, reason: 'strictly higher');
    });
  });

  group('challenge pickers (RulesProfile.challengePickerData)', () {
    test('classic offers the original data, classicFixed the corrections', () {
      final fixed = data.challenges.pickersFor(corrected: true);
      final classic = data.challenges.pickersFor(corrected: false);
      expect(fixed.keys, classic.keys);
      expect([for (final o in classic['difficulty']!) o.value], ['easy', 'medium', 'hard']);
      expect(
        [for (final o in fixed['difficulty']!) o.value],
        ['easy', 'medium', 'hard', 'extreme'],
      );
      expect(fixed['difficulty']!.last.requiresMode, 'extreme');
      String label(Map<String, List<PickerOption>> p, String id, Object v) =>
          p[id]!.firstWhere((o) => o.value == v).label;
      expect(label(classic, 'timeLimit', 280), '3 mins');
      expect(label(fixed, 'timeLimit', 180), '3 mins');
      expect([for (final o in classic['turretLimit']!) o.label], contains('8 Turrets'));
      for (final o in fixed['turretLimit']!) {
        if (o.value != null) expect(o.label, '${o.value} Turrets');
      }
      expect({for (final o in fixed['turretLimit']!) o.value}.length, fixed['turretLimit']!.length);
      expect(fixed['objective'], same(classic['objective']));
    });
  });

  group('custom games (RulesProfile.customGamesSeparate)', () {
    test('a mod or a player map makes a game custom', () {
      final player = data.maps['map1']!;
      const standard = GameConfig(mapId: 'map1');
      final ownMap = GameConfig.custom(map: player);
      expect(customGameReasons(standard, modded: false), isEmpty);
      expect(customGameReasons(standard, modded: true), {CustomGameReason.mod});
      expect(customGameReasons(ownMap, modded: false), {CustomGameReason.playerMap});
      expect(customGameReasons(ownMap, modded: true), {
        CustomGameReason.mod,
        CustomGameReason.playerMap,
      });
    });

    test('custom games record no progress, except under the classic rules', () {
      final player = data.maps['map1']!;
      const standard = GameConfig(mapId: 'map1');
      expect(recordsProgress(standard, modded: false), isTrue);
      expect(recordsProgress(standard, modded: true), isFalse);
      expect(recordsProgress(GameConfig.custom(map: player), modded: false), isFalse);
      const classic = GameConfig(mapId: 'map1', profile: RulesProfile.classic);
      expect(recordsProgress(classic, modded: true), isTrue, reason: 'the original counts them');
    });
  });
}
