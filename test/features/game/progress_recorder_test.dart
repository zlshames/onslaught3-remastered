import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/features/game/progress_recorder.dart';
import 'package:onslaught3_remastered/services/persistence/profile.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../support/log_capture.dart';
import '../../support/test_data.dart';

void main() {
  late GameData data;
  setUpAll(() => data = loadTestGameData());

  ({ProgressRecorder recorder, List<String> said, Profile Function() profile}) recorder(
    GameConfig config, {
    String? difficulty,
    Profile start = const Profile(),
    bool modded = false,
    CustomGameIdentity? custom,
    String locale = 'en',
  }) {
    var profile = start;
    final said = <String>[];
    final r = ProgressRecorder(
      data: data,
      config: config,
      records: recordsProgress(config, modded: modded),
      custom: custom,
      difficulty: difficulty ?? config.difficulty,
      read: () => profile,
      save: (edit) => profile = edit(profile),
      announce: said.add,
      locale: () => locale,
      clock: () => DateTime.utc(2026, 10, 18, 12),
    );
    return (recorder: r, said: said, profile: () => profile);
  }

  CreepKilled kill(int kills) =>
      CreepKilled(0, uid: 1, turret: null, bounty: 1, cash: 0, kills: kills, x: 0, y: 0);

  test('kill milestones of a normal game unlock and announce, once', () {
    final r = recorder(const GameConfig(mapId: 'map1', difficulty: 'medium'));
    r.recorder
      ..onEvent(kill(1999))
      ..onEvent(kill(2000))
      ..onEvent(kill(4000))
      ..onEvent(kill(4000));
    expect(r.profile().available, {'extreme', 'sandbox'});
    expect(r.profile().complete, {'medium'});
    // The difficulty's name, where the original printed its id
    // (DEVIATIONS `difficultyNames`).
    expect(r.said, [
      data.text('flow.unlockExtreme'),
      'Well done, you have managed to defeat 4000 kills in Medium mode!  You can tick that one off.',
      'Excellent work!  400 waves in Medium mode has unlocked the sandbox.  Congrats!',
    ]);
  });

  test('announcements are in the interface language, difficulty name included', () {
    final r = recorder(
      const GameConfig(mapId: 'map1', difficulty: 'medium'),
      locale: 'de',
    );
    r.recorder.onEvent(kill(4000));
    expect(r.said, [
      'Gut gemacht, du hast 4000 Abschüsse im Modus Mittel geschafft! Den kannst du abhaken.',
      'Hervorragend! 400 Wellen im Modus Mittel haben die Sandbox freigeschaltet. Glückwunsch!',
    ]);
  });

  test('sandbox kills count for nothing', () {
    final r = recorder(const GameConfig(mapId: 'map1', mode: 'sandbox2'));
    r.recorder.onEvent(kill(4000));
    expect(r.profile(), const Profile());
    expect(r.said, isEmpty);
  });

  SessionStarted start(GameConfig c) => SessionStarted(
    0,
    map: c.mapId,
    mode: c.mode,
    difficulty: c.difficulty,
    profile: c.profile.id,
    seed: c.seed,
    cash: 30,
    lives: 10,
  );

  test('starting the tutorial unlocks challenges and says so, once', () {
    const config = GameConfig(mapId: 'tutorial', mode: 'tutorial');
    final r = recorder(config);
    r.recorder.onEvent(start(config));
    expect(r.profile().available, {'challenge'});
    expect(r.profile().complete, isEmpty);
    expect(r.said, [data.text('flow.tutorialUnlockChallenge')]);
    final again = recorder(config, start: r.profile());
    again.recorder.onEvent(start(config));
    expect(again.said, isEmpty);
  });

  test('starting a normal game unlocks nothing', () {
    const config = GameConfig(mapId: 'map1');
    final r = recorder(config);
    r.recorder.onEvent(start(config));
    expect(r.profile(), const Profile());
    expect(r.said, isEmpty);
  });

  test('a modded tutorial (a custom game) unlocks nothing as it starts', () {
    const config = GameConfig(mapId: 'tutorial', mode: 'tutorial');
    final r = recorder(config, modded: true);
    r.recorder.onEvent(start(config));
    expect(r.profile(), const Profile());
  });

  test('winning the tutorial unlocks challenges', () {
    final r = recorder(const GameConfig(mapId: 'tutorial', mode: 'tutorial'));
    r.recorder.onEvent(const GameWon(0, wave: 50, kills: 500, shots: 1, spent: 10, score: 5000));
    expect(r.profile().available, {'challenge'});
    expect(r.profile().complete, {'tutorial'});
    expect(r.said, [data.text('flow.unlockChallenge')]);
  });

  test('a challenge keeps its best game, passed or failed, and its pass', () {
    final warmup = data.challenges.presets.firstWhere((c) => c.id == 'warmup');
    final config = GameConfig(
      mapId: 'map1',
      mode: 'challenge',
      difficulty: warmup.difficulty,
      challenge: warmup,
    );
    final key = challengeKey(warmup);
    final r = recorder(config);
    r.recorder.onEvent(const GameOver(0, wave: 2, kills: 5, shots: 9, spent: 30, score: 150));
    expect(r.profile().challengeBest[key]!.score, 150);
    expect(r.profile().complete, isEmpty);
    r.recorder.onEvent(const GameWon(0, wave: 2, kills: 20, shots: 30, spent: 30, score: 600));
    expect(r.profile().challengeBest[key]!.score, 600);
    expect(
      r.profile().challengeBest[key]!.dateMs,
      DateTime.utc(2026, 10, 18, 12).millisecondsSinceEpoch,
    );
    expect(r.profile().complete, {key});
    // A worse game later does not replace it.
    r.recorder.onEvent(const GameOver(0, wave: 1, kills: 1, shots: 1, spent: 10, score: 10));
    expect(r.profile().challengeBest[key]!.score, 600);
  });

  test('progress and challenge results are logged, new bests marked', () async {
    final log = LogCapture.install();
    final warmup = data.challenges.presets.firstWhere((c) => c.id == 'warmup');
    final r = recorder(
      GameConfig(
        mapId: 'map1',
        mode: 'challenge',
        difficulty: warmup.difficulty,
        challenge: warmup,
      ),
    );
    r.recorder
      ..onEvent(const GameWon(0, wave: 2, kills: 20, shots: 30, spent: 30, score: 600))
      ..onEvent(const GameOver(0, wave: 1, kills: 1, shots: 1, spent: 10, score: 10));
    final records = await log.records();
    final key = challengeKey(warmup);
    expect(
      records,
      contains(
        endsWith('[progress] progress kind=complete id=$key difficulty=null mode=challenge'),
      ),
    );
    expect(
      records,
      contains(contains('challenge result challenge=$key kills=20 score=600.0 newBest=true')),
    );
    expect(
      records,
      contains(contains('challenge result challenge=$key kills=1 score=10.0 newBest=false')),
    );
  });

  test('a custom game result is logged with the map name masked', () async {
    final log = LogCapture.install();
    final r = recorder(
      const GameConfig(mapId: 'custom-1', difficulty: 'medium'),
      custom: const CustomGameIdentity(mapId: 'custom-1', mapName: 'Jane Fortress'),
    );
    r.recorder.onEvent(const GameOver(0, wave: 7, kills: 70, shots: 9, spent: 30, score: 150));
    final line = (await log.records()).single;
    expect(line, contains('custom game result map=custom-1 mapName=J***********s'));
    expect(line, contains('wave=7'));
    expect(line, contains('newBest=true'));
    expect(line, isNot(contains('Jane')));
  });

  test('freeplay after a win leaves the record alone', () {
    final warmup = data.challenges.presets.firstWhere((c) => c.id == 'warmup');
    final config = GameConfig(
      mapId: 'map1',
      mode: 'challenge',
      difficulty: warmup.difficulty,
      challenge: warmup,
    );
    final r = recorder(config);
    r.recorder
      ..onEvent(const GameWon(0, wave: 2, kills: 20, shots: 30, spent: 30, score: 600))
      ..onEvent(const FreeplayStarted(0, wave: 2, nextWaveMs: 20000))
      ..onEvent(const GameOver(0, wave: 90, kills: 900, shots: 9, spent: 999, score: 899100));
    expect(r.profile().challengeBest[challengeKey(warmup)]!.score, 600);
  });

  test('nothing is recorded while the profile is loading', () {
    final said = <String>[];
    ProgressRecorder(
      data: data,
      config: const GameConfig(mapId: 'map1'),
      difficulty: 'easy',
      read: () => null,
      save: (_) => fail('saved'),
      announce: said.add,
    ).onEvent(kill(2000));
    expect(said, isEmpty);
  });

  group('custom games record nothing (RulesProfile.customGamesSeparate)', () {
    test('a modded normal game: no unlock, no tick, no message', () {
      final r = recorder(const GameConfig(mapId: 'map1', difficulty: 'medium'), modded: true);
      r.recorder
        ..onEvent(kill(2000))
        ..onEvent(kill(4000));
      expect(r.profile(), const Profile());
      expect(r.said, isEmpty);
    });

    test('a player map at a difficulty: no unlock', () {
      final r = recorder(GameConfig.custom(map: data.maps['map1']!, difficulty: 'hard'));
      r.recorder.onEvent(kill(4000));
      expect(r.profile(), const Profile());
    });

    test('a modded challenge preset keeps no best game and no pass', () {
      final warmup = data.challenges.presets.firstWhere((c) => c.id == 'warmup');
      final r = recorder(
        GameConfig(
          mapId: 'map1',
          mode: 'challenge',
          difficulty: warmup.difficulty,
          challenge: warmup,
        ),
        modded: true,
      );
      r.recorder
        ..onEvent(const GameWon(0, wave: 10, kills: 20, shots: 1, spent: 30, score: 600))
        ..onEvent(const GameOver(0, wave: 3, kills: 5, shots: 1, spent: 30, score: 150));
      expect(r.profile(), const Profile());
    });

    test('the classic rules still record them, as the original did', () {
      final r = recorder(
        const GameConfig(mapId: 'map1', difficulty: 'medium', profile: RulesProfile.classic),
        modded: true,
      );
      r.recorder.onEvent(kill(2000));
      expect(r.profile().available, {'extreme'});
    });
  });

  group('custom games keep their own records', () {
    const won = GameWon(0, wave: 40, kills: 400, shots: 1, spent: 900, score: 360000);
    GameOver over(int wave) =>
        GameOver(0, wave: wave, kills: wave * 10, shots: 1, spent: 900, score: wave * 9000.0);

    test('a modded game: a record under the mod, no standard progress', () {
      final r = recorder(
        const GameConfig(mapId: 'map1', difficulty: 'medium'),
        modded: true,
        custom: const CustomGameIdentity(
          mapId: 'map1',
          mapName: 'Classic',
          mod: '0420522f',
          modName: 'My mod',
        ),
      );
      r.recorder
        ..onEvent(kill(2000))
        ..onEvent(over(55));
      final p = r.profile();
      expect(p.available, isEmpty);
      final rec = p.custom.records.values.single;
      expect(
        [rec.key.mapId, rec.key.mod, rec.key.mode, rec.key.difficulty],
        ['map1', '0420522f', 'normal', 'medium'],
      );
      expect(
        [rec.wave, rec.kills, rec.modName, rec.dateMs],
        [55, 550, 'My mod', DateTime.utc(2026, 10, 18, 12).millisecondsSinceEpoch],
      );
    });

    test('a player map: the win, then freeplay raises the wave', () {
      final map = data.maps['map1']!;
      final r = recorder(
        GameConfig.custom(map: map, difficulty: 'hard'),
        custom: CustomGameIdentity(
          mapId: 'custom-mine',
          mapName: 'Mine',
          mapVersion: mapVersionHash(map),
        ),
      );
      r.recorder
        ..onEvent(won)
        ..onEvent(const FreeplayStarted(0, wave: 40, nextWaveMs: 20000))
        ..onEvent(over(30));
      expect(
        r.profile().custom.records.values.single.wave,
        40,
        reason: 'a worse end keeps the win',
      );
      r.recorder.onEvent(over(70));
      final p = r.profile();
      expect(p.custom.records.values.single.wave, 70);
      expect(p.custom.versionOf('custom-mine', mapVersionHash(map)), 1);
    });

    test('a standard game keeps no custom record', () {
      final r = recorder(const GameConfig(mapId: 'map1'));
      r.recorder.onEvent(over(20));
      expect(r.profile().custom.isEmpty, isTrue);
    });
  });
}
