import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/services/logging/log_level.dart';
import 'package:onslaught3_remastered/services/persistence/custom_records.dart';
import 'package:onslaught3_remastered/services/persistence/document_store.dart';
import 'package:onslaught3_remastered/services/persistence/game_in_progress.dart';
import 'package:onslaught3_remastered/services/persistence/map_library.dart';
import 'package:onslaught3_remastered/services/persistence/mod_library.dart';
import 'package:onslaught3_remastered/services/persistence/profile.dart';
import 'package:onslaught3_remastered/services/persistence/settings.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../support/test_data.dart';

/// A store whose reads fail as a broken disk would, not as a bad document.
class _FailingStore extends MemoryDocumentStore {
  @override
  Future<String?> readRaw(String key) async => throw StateError('disk gone');
}

Map<String, Object?> _fixture(String name) =>
    (jsonDecode(File('test/fixtures/persistence/$name').readAsStringSync()) as Map)
        .cast<String, Object?>();

void main() {
  test('settings default when nothing is stored, and round-trip', () async {
    final p = PersistenceService(MemoryDocumentStore());
    final s = await p.loadSettings();
    expect(s.soundOn, isTrue);
    expect(s.volume, isNull, reason: 'null = use the data default');
    await p.saveSettings(s.copyWith(soundOn: false, leftHanded: true, timeScale: 1.5));
    final back = await p.loadSettings();
    expect(back.soundOn, isFalse);
    expect(back.leftHanded, isTrue);
    expect(back.timeScale, 1.5);
  });

  test('stored documents carry their schema version', () async {
    final store = MemoryDocumentStore();
    await PersistenceService(store).saveSettings(const Settings());
    expect((await store.read(Settings.key))!['schemaVersion'], Settings.schemaVersion);
  });

  test('migrator chains steps and rejects newer documents', () {
    final m = Migrator(
      currentVersion: 3,
      steps: [
        (d) => {...d, 'b': 1},
        (d) => {...d, 'c': (d['b']! as int) + 1},
      ],
    );
    expect(m.migrate({'schemaVersion': 1, 'a': 0}), {'schemaVersion': 3, 'a': 0, 'b': 1, 'c': 2});
    expect(m.migrate({'schemaVersion': 3}), {'schemaVersion': 3});
    expect(() => m.migrate({'schemaVersion': 4}), throwsFormatException);
    expect(() => Migrator(currentVersion: 2), throwsArgumentError);
  });

  test('settings v1 fixture migrates to v2 (wave settings not remembered)', () async {
    final store = MemoryDocumentStore();
    await store.write(Settings.key, _fixture('settings.v1.json'));
    final s = await PersistenceService(store).loadSettings();
    expect(
      [s.soundOn, s.volume, s.waveSpacingS, s.waveFollow, s.timeScale, s.leftHanded],
      [false, 40, 10, true, 2, true],
    );
    expect(s.waveRemember, isFalse);
    expect(s.toJson()['schemaVersion'], Settings.schemaVersion);
  });

  test(
    'settings v2 fixture migrates to v3 (smoke from the data, no badges, device language)',
    () async {
      final store = MemoryDocumentStore();
      await store.write(Settings.key, _fixture('settings.v2.json'));
      final s = await PersistenceService(store).loadSettings();
      expect([s.waveSpacingS, s.waveRemember, s.timeScale, s.haptics], [15, true, 1.5, false]);
      expect([s.rocketSmoke, s.smokeMax, s.colourBadges, s.locale], [null, null, false, null]);
      final data = loadTestGameData();
      expect(s.smokeOn(data), data.world.effects.rocketSmoke.enabled);
      expect(s.smokeLimit(data), data.world.effects.rocketSmoke.max);
      expect(s.toJson()['schemaVersion'], Settings.schemaVersion);
    },
  );

  test('settings v3 fixture migrates to v4 (the original ground)', () async {
    final store = MemoryDocumentStore();
    await store.write(Settings.key, _fixture('settings.v3.json'));
    final s = await PersistenceService(store).loadSettings();
    expect(
      [s.volume, s.waveSpacingS, s.waveFollow, s.rocketSmoke, s.smokeMax],
      [70, 12, true, false, 20],
    );
    expect([s.colourBadges, s.locale], [true, 'de']);
    expect(s.sharpGround, isFalse);
    expect(s.toJson()['schemaVersion'], Settings.schemaVersion);
    final round = Settings.fromJson(s.copyWith(sharpGround: true).toJson());
    expect(round.sharpGround, isTrue);
  });

  test('settings v4 fixture migrates to v6 (placement follows the platform)', () async {
    final store = MemoryDocumentStore();
    await store.write(Settings.key, _fixture('settings.v4.json'));
    final s = await PersistenceService(store).loadSettings();
    expect(
      [s.volume, s.waveSpacingS, s.waveRemember, s.timeScale, s.haptics, s.smokeMax],
      [55, 14, true, 1.25, false, 30],
    );
    expect([s.rocketSmoke, s.locale, s.sharpGround], [true, 'en', true]);
    expect(s.placementChoice, isNull);
    expect(s.placement, PlacementMode.platformDefault);
    expect(s.toJson()['schemaVersion'], Settings.schemaVersion);
    final round = Settings.fromJson(s.copyWith(placement: PlacementMode.dropAndLock).toJson());
    expect(round.placement, PlacementMode.dropAndLock);
    expect(round.toJson()['placement'], 'lock');
  });

  test(
    'settings v5 fixture migrates to v6: a stored drag was the old default, lock was chosen',
    () {
      final v5 = _fixture('settings.v5.json');
      final drag = Settings.fromJson(Settings.migrator.migrate(v5));
      expect(drag.placementChoice, isNull, reason: 'v5 wrote drag for everyone');
      final lock = Settings.fromJson(Settings.migrator.migrate({...v5, 'placement': 'lock'}));
      expect(lock.placementChoice, PlacementMode.dropAndLock);
      expect(lock.toJson()['schemaVersion'], Settings.schemaVersion);
    },
  );

  test('settings v6 fixture migrates to v7 (the log keeps the build default)', () async {
    final store = MemoryDocumentStore();
    await store.write(Settings.key, _fixture('settings.v6.json'));
    final s = await PersistenceService(store).loadSettings();
    expect(s.placementChoice, PlacementMode.dropAndLock, reason: 'earlier fields survive');
    expect(s.logLevelChoice, isNull);
    expect(s.toJson()['schemaVersion'], 7);
    final round = Settings.fromJson(s.copyWith(logLevel: LogLevel.warning).toJson());
    expect(round.logLevelChoice, LogLevel.warning);
    expect(round.toJson()['logLevel'], 'warning');
    expect(Settings.fromJson({...s.toJson(), 'logLevel': 'loud'}).logLevelChoice, isNull);
  });

  test(
    'with no choice, placement is drop and lock on Android and iOS, drag and drop elsewhere',
    () {
      const s = Settings();
      expect(s.toJson()['placement'], isNull);
      for (final (platform, mode) in [
        (TargetPlatform.android, PlacementMode.dropAndLock),
        (TargetPlatform.iOS, PlacementMode.dropAndLock),
        (TargetPlatform.macOS, PlacementMode.dragAndDrop),
        (TargetPlatform.windows, PlacementMode.dragAndDrop),
        (TargetPlatform.linux, PlacementMode.dragAndDrop),
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        try {
          expect(s.placement, mode, reason: '$platform');
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      }
      expect(
        const Settings(placementChoice: PlacementMode.dragAndDrop).placement,
        PlacementMode.dragAndDrop,
      );
    },
  );

  test('an unknown placement mode reads as no choice', () {
    final s = Settings.fromJson({...const Settings().toJson(), 'placement': 'hover'});
    expect(s.placementChoice, isNull);
  });

  test('gameInProgress v1 fixture loads, and round-trips unchanged', () async {
    final store = MemoryDocumentStore();
    final v1 = _fixture('gameInProgress.v1.json');
    await store.write(GameInProgress.key, v1);
    final g = (await PersistenceService(store).loadGameInProgress())!;
    expect(
      [g.mapId, g.mode, g.difficulty, g.profileId, g.seed],
      ['map1', 'normal', 'medium', 'classicFixed', 1],
    );
    expect([g.tick, g.stateHash, g.wave, g.lives, g.cash], [901, 123456789, 2, 9, 42.5]);
    expect(g.commands.map((c) => (c.tick, c.command.type)), [
      (0, 'speed'),
      (12, 'build'),
      (300, 'sendWave'),
      (900, 'pause'),
    ]);
    expect([g.challengeKey, g.customMap, g.waveSpacingMs, g.waveFollow], [null, null, null, false]);
    expect(GameInProgress.fromJson(g.toJson()).toJson(), g.toJson());
    expect(g.toJson(), v1);
  });

  test('no game in progress reads as null; saving null forgets it', () async {
    final store = MemoryDocumentStore();
    final p = PersistenceService(store);
    expect(await p.loadGameInProgress(), isNull);
    await store.write(GameInProgress.key, _fixture('gameInProgress.v1.json'));
    await p.saveGameInProgress(null);
    expect(await store.read(GameInProgress.key), isNull);
  });

  test('an unreadable game in progress is kept aside and reads as none', () async {
    final store = MemoryDocumentStore();
    await store.write(GameInProgress.key, {
      ..._fixture('gameInProgress.v1.json'),
      'commands': [
        {
          'tick': 3,
          'command': {'type': 'teleport'},
        },
      ],
    });
    final p = PersistenceService(store);
    expect(await p.loadGameInProgress(), isNull);
    expect(p.recoveredKeys, [GameInProgress.key]);
    expect(await store.readRaw(PersistenceService.corruptKey(GameInProgress.key)), isNotNull);
  });

  test('smoke settings override the data within its bounds; locale can be cleared', () {
    final data = loadTestGameData();
    final r = data.world.effects.rocketSmoke;
    expect([r.enabled, r.max, r.maxPrefMin, r.maxPrefMax], [true, 200, 1, 500]);
    const s = Settings(rocketSmoke: false, smokeMax: 9999, locale: 'en');
    expect(s.smokeOn(data), isFalse);
    expect(s.smokeLimit(data), r.maxPrefMax);
    expect(s.copyWith(smokeMax: 0).smokeLimit(data), r.maxPrefMin);
    expect(s.withLocale(null).locale, isNull);
    expect(s.copyWith(haptics: false, colourBadges: true).toJson(), {
      ...s.toJson(),
      'haptics': false,
      'colourBadges': true,
    });
  });

  group('custom records (profile v2)', () {
    test('a v1 profile migrates with no custom records', () async {
      final store = MemoryDocumentStore();
      await store.write(Profile.key, _fixture('profile.v1.json'));
      final p = await PersistenceService(store).loadProfile();
      expect(p.custom, const CustomRecords());
      expect(p.custom.isEmpty, isTrue);
      expect(p.available, {'challenge', 'extreme', 'sandbox'});
      expect(p.toJson()['schemaVersion'], 2);
    });

    test('the v2 fixture loads and round-trips', () async {
      final store = MemoryDocumentStore();
      await store.write(Profile.key, _fixture('profile.v2.json'));
      final service = PersistenceService(store);
      final p = await service.loadProfile();
      expect(p.custom.records, hasLength(3));
      expect(p.custom.versionOf('custom-loop', '5e6f7a8b'), 2);
      expect(p.custom.forMap('custom-loop').map((r) => r.wave), unorderedEquals([87, 140]));
      final modded = p.custom.records.values.firstWhere((r) => r.key.mapId == 'map1');
      expect(
        [modded.key.mod, modded.modName, modded.key.mapVersion],
        ['0420522f', 'Cheap blues', null],
      );
      await service.saveProfile(p);
      expect(await service.loadProfile(), p);
      expect(p.available, {'extreme'}, reason: 'custom records leave standard progress alone');
    });

    CustomRecord rec(String version, int wave, {String? mod, int kills = 10}) => CustomRecord(
      key: CustomRecordKey(
        mapId: 'custom-loop',
        mapVersion: version,
        mod: mod,
        mode: 'normal',
        difficulty: 'easy',
      ),
      mapName: 'Loop',
      wave: wave,
      kills: kills,
      score: wave * 100.0,
      spent: 0,
      dateMs: wave,
    );

    test('an edited map gets a new version; the old record stays', () {
      var c = const CustomRecords().withResult(rec('aaaa0001', 30));
      c = c.withResult(rec('aaaa0001', 20));
      expect(c.forMap('custom-loop').single.wave, 30, reason: 'a worse game keeps the best');
      c = c.withResult(rec('bbbb0002', 12));
      expect(c.versionOf('custom-loop', 'aaaa0001'), 1);
      expect(c.versionOf('custom-loop', 'bbbb0002'), 2);
      expect(c.forMap('custom-loop').map((r) => r.wave), unorderedEquals([30, 12]));
      // Back to the first shape: it is version 1 again, not a third version.
      c = c.withResult(rec('aaaa0001', 31));
      expect(c.mapVersions['custom-loop'], ['aaaa0001', 'bbbb0002']);
      expect(c.forMap('custom-loop').map((r) => r.wave), unorderedEquals([31, 12]));
    });

    test('a mod on a player map is its own record', () {
      final c = const CustomRecords()
          .withResult(rec('aaaa0001', 30))
          .withResult(rec('aaaa0001', 90, mod: '0420522f'));
      expect(c.records, hasLength(2));
      expect(c.forMap('custom-loop').where((r) => r.key.mod == null).single.wave, 30);
    });

    test('Profile.withCustomRecord touches only the custom section', () {
      const start = Profile(available: {'extreme'}, complete: {'easy'});
      final p = start.withCustomRecord(rec('aaaa0001', 30));
      expect(p.custom.records, hasLength(1));
      expect(
        [p.available, p.complete, p.challengeBest],
        [start.available, start.complete, start.challengeBest],
      );
    });
  });

  group('profile', () {
    test('a new player has nothing unlocked', () async {
      final p = await PersistenceService(MemoryDocumentStore()).loadProfile();
      expect(p, const Profile());
      expect(p.available, isEmpty);
      expect(p.unlockAll, isFalse);
    });

    test('v1 fixture loads (migration contract) and round-trips', () async {
      final store = MemoryDocumentStore();
      await store.write(Profile.key, _fixture('profile.v1.json'));
      final service = PersistenceService(store);
      final p = await service.loadProfile();
      expect(p.available, {'challenge', 'extreme', 'sandbox'});
      expect(p.complete, contains('tutorial'));
      expect(p.challengeBest, hasLength(2));
      final warmup = p.challengeBest['challenge;easy;undefined;30;60;undefined;10;60']!;
      expect([warmup.kills, warmup.spent, warmup.score], [20, 30, 600]);
      await service.saveProfile(p);
      expect(await service.loadProfile(), p);
      // Saved again as v2: the v1 content plus an empty custom section.
      expect((await store.read(Profile.key))!, {
        ..._fixture('profile.v1.json'),
        'schemaVersion': 2,
        'custom': {'records': <Object?>[], 'mapVersions': <String, Object?>{}},
      });
    });

    test('progress changes and the best-game rule', () {
      final data = loadTestGameData();
      final threetown = data.challenges.presets.firstWhere((c) => c.id == 'threetown');
      final problem3 = data.challenges.presets.firstWhere((c) => c.id == 'problem-3');
      var p = const Profile().applying(const [
        ProgressChange(ProgressChange.unlock, 'extreme'),
        ProgressChange(ProgressChange.completion, 'easy'),
      ]);
      expect(p.available, {'extreme'});
      expect(p.complete, {'easy'});
      const a = ChallengeBest(kills: 100, spent: 50, score: 5000, dateMs: 1);
      const b = ChallengeBest(kills: 101, spent: 10, score: 1010, dateMs: 2);
      p = p.withResult(threetown, a).withResult(problem3, a);
      expect(p.withResult(threetown, b).challengeBest[challengeKey(threetown)], a);
      expect(p.withResult(problem3, b).challengeBest[challengeKey(problem3)], b);
    });
  });

  group('an unreadable document is kept aside and reset', () {
    final loaders = <String, Future<Map<String, Object?>> Function(PersistenceService)>{
      Settings.key: (p) async => (await p.loadSettings()).toJson(),
      Profile.key: (p) async => (await p.loadProfile()).toJson(),
      MapLibrary.key: (p) async => (await p.loadMaps()).toJson(),
      ModLibrary.key: (p) async => (await p.loadMods()).toJson(),
    };
    final defaults = <String, Map<String, Object?>>{
      Settings.key: const Settings().toJson(),
      Profile.key: const Profile().toJson(),
      MapLibrary.key: const MapLibrary().toJson(),
      ModLibrary.key: const ModLibrary().toJson(),
    };
    final newer = <String, int>{
      Settings.key: Settings.schemaVersion + 1,
      Profile.key: Profile.schemaVersion + 1,
      MapLibrary.key: MapLibrary.schemaVersion + 1,
      ModLibrary.key: ModLibrary.schemaVersion + 1,
    };
    // Each document with one field of the wrong type.
    final wrongType = <String, Map<String, Object?>>{
      Settings.key: {...const Settings().toJson(), 'soundOn': 'no'},
      Profile.key: {...const Profile().toJson(), 'available': 'extreme'},
      MapLibrary.key: {'schemaVersion': 1, 'maps': 'none'},
      ModLibrary.key: {...const ModLibrary().toJson(), 'active': 'yes'},
    };

    /// Stores [text] under [key], loads it, and checks the defaults came
    /// back, the text was kept under `<key>.corrupt` and the key recorded.
    Future<void> expectReset(String key, String text) async {
      final store = MemoryDocumentStore();
      await store.writeRaw(key, text);
      final service = PersistenceService(store);
      expect(await loaders[key]!(service), defaults[key]);
      expect(await store.readRaw(PersistenceService.corruptKey(key)), text);
      expect(service.recoveredKeys, [key]);
      expect(await store.readRaw(key), text, reason: 'left in place until the next save');
    }

    for (final key in loaders.keys) {
      test('$key: damaged JSON', () async {
        await expectReset(key, '{"schemaVersion": 1, "a": [tru');
      });

      test('$key: a newer schemaVersion (after a downgrade)', () async {
        await expectReset(key, jsonEncode({...defaults[key]!, 'schemaVersion': newer[key]}));
      });

      test('$key: a field of the wrong type', () async {
        await expectReset(key, jsonEncode(wrongType[key]));
      });

      test('$key: not a JSON object', () async {
        await expectReset(key, '[1, 2, 3]');
      });
    }

    test('profile: a mistyped best game or custom record resets the profile', () async {
      final best = {
        ..._fixture('profile.v2.json'),
        'challengeBest': {
          'k': {'kills': 'many'},
        },
      };
      await expectReset(Profile.key, jsonEncode(best));
      final records = _fixture('profile.v2.json');
      final custom = (records['custom']! as Map).cast<String, Object?>();
      final first = {...(custom['records']! as List).first as Map}..remove('map');
      await expectReset(
        Profile.key,
        jsonEncode({
          ...records,
          'custom': {
            ...custom,
            'records': [first],
          },
        }),
      );
    });

    test('settings: a wrong-typed number resets the settings', () async {
      await expectReset(
        Settings.key,
        jsonEncode({...const Settings().toJson(), 'timeScale': 'fast'}),
      );
    });

    test('a newer copy replaces an older corrupt one; each key is recorded once', () async {
      final store = MemoryDocumentStore();
      final service = PersistenceService(store);
      await store.writeRaw(Settings.key, 'first');
      await service.loadSettings();
      await store.writeRaw(Settings.key, 'second');
      await service.loadSettings();
      await store.writeRaw(Profile.key, '{');
      await service.loadProfile();
      expect(await store.readRaw(PersistenceService.corruptKey(Settings.key)), 'second');
      expect(service.recoveredKeys, [Settings.key, Profile.key]);
    });

    test('a save replaces the unreadable document; readable ones are untouched', () async {
      final store = MemoryDocumentStore();
      final service = PersistenceService(store);
      await store.writeRaw(Profile.key, 'not json');
      await store.write(Settings.key, const Settings(soundOn: false).toJson());
      expect((await service.loadSettings()).soundOn, isFalse);
      final profile = await service.loadProfile();
      await service.saveProfile(profile.copyWith(available: {'extreme'}));
      expect((await service.loadProfile()).available, {'extreme'});
      expect(service.recoveredKeys, [Profile.key]);
      expect(await store.readRaw(PersistenceService.corruptKey(Settings.key)), isNull);
    });

    test('a failing store is not mistaken for a bad document', () async {
      final service = PersistenceService(_FailingStore());
      await expectLater(service.loadSettings(), throwsStateError);
      expect(service.recoveredKeys, isEmpty);
    });

    test('a mistyped field is reported with its path', () {
      expect(
        () => Profile.fromJson({
          ...const Profile().toJson(),
          'available': const [1],
        }),
        throwsA(
          isA<DataValidationException>().having((e) => e.issues.map((i) => '$i'), 'issues', [
            contains('profile:/available/0'),
          ]),
        ),
      );
      expect(
        () => Settings.fromJson(const {'smokeMax': 'lots'}),
        throwsA(
          isA<DataValidationException>().having(
            (e) => '${e.issues.single}',
            'issue',
            contains('settings:/smokeMax'),
          ),
        ),
      );
    });
  });
}
