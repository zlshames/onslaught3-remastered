import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/services/persistence/document_store.dart';
import 'package:onslaught3_remastered/services/persistence/mod_library.dart';
import 'package:onslaught3_remastered/services/persistence/settings.dart';
import 'package:onslaught3_remastered/services/share/share_codec.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../support/test_data.dart';

void main() {
  late GameData data;
  late ModRules rules;
  setUpAll(() {
    data = loadTestGameData();
    rules = ModRules(data, behaviours: RulesRegistry.classic());
  });

  Map<String, Object?> fixture(String name) =>
      (jsonDecode(File('test/fixtures/persistence/$name').readAsStringSync()) as Map)
          .cast<String, Object?>();

  ModField blueDamage() => rules.field('TurretBlue.weapon_damage')!;

  group('mods document (persisted, schema-versioned)', () {
    test('a new player has an empty, inactive mod; it saves and loads back', () async {
      final service = PersistenceService(MemoryDocumentStore());
      final empty = await service.loadMods();
      expect(
        [empty.mod.isEmpty, empty.active, empty.applies, empty.name],
        [true, false, false, ModLibrary.defaultName],
      );
      final mods = ModLibrary(
        mod: rules.withValue(const ModDelta({}, name: 'Mine'), blueDamage(), 99),
        active: true,
      );
      await service.saveMods(mods);
      final back = await service.loadMods();
      expect(back, mods);
      expect(back.applies, isTrue);
      expect(
        (await service.store.read(ModLibrary.key))!['schemaVersion'],
        ModLibrary.schemaVersion,
      );
    });

    test('v1 fixture loads (migration contract) and applies', () async {
      final store = MemoryDocumentStore();
      await store.write(ModLibrary.key, fixture('mods.v1.json'));
      final mods = await PersistenceService(store).loadMods();
      expect([mods.active, mods.name], [true, 'Big Blue']);
      final modded = rules.apply(mods.mod);
      expect(modded.turrets['blue']!.stats.damage, 99);
      expect(modded.turrets['blue']!.cost, 12);
      expect(modded.difficulty.levels.first.startingCash, 500);
      expect(rules.importDelta(mods.mod).problems, isEmpty);
    });

    test('a newer document is set aside; a broken mod is dropped with its switch', () async {
      final store = MemoryDocumentStore();
      await store.write(ModLibrary.key, {...fixture('mods.v1.json'), 'schemaVersion': 2});
      final service = PersistenceService(store);
      expect(await service.loadMods(), const ModLibrary());
      expect(service.recoveredKeys, [ModLibrary.key]);
      await store.write(ModLibrary.key, {
        'schemaVersion': 1,
        'active': true,
        'mod': {'schemaVersion': 1, 'files': 'nope'},
      });
      final mods = await PersistenceService(store).loadMods();
      expect([mods.mod.isEmpty, mods.active], [true, false]);
    });

    test('a broken mod is kept under the corrupt key and reported', () async {
      final store = MemoryDocumentStore();
      await store.write(ModLibrary.key, {
        'schemaVersion': 1,
        'active': true,
        'mod': {'schemaVersion': 1, 'files': 'nope'},
      });
      final stored = await store.readRaw(ModLibrary.key);
      final service = PersistenceService(store);
      expect(await service.loadMods(), const ModLibrary());
      expect(service.recoveredKeys, [ModLibrary.key]);
      expect(await store.readRaw(PersistenceService.corruptKey(ModLibrary.key)), stored);
      expect(
        ModLibrary.fromJson(jsonDecode(stored!) as Map<String, Object?>, onDropped: (_) {}),
        const ModLibrary(),
      );
    });

    test('a readable mod reports nothing', () async {
      final store = MemoryDocumentStore();
      final service = PersistenceService(store);
      await service.saveMods(
        ModLibrary(mod: rules.withValue(const ModDelta({}), blueDamage(), 99), active: true),
      );
      Object? dropped;
      ModLibrary.fromJson((await store.read(ModLibrary.key))!, onDropped: (e) => dropped = e);
      expect(dropped, isNull);
      expect((await service.loadMods()).applies, isTrue);
      expect(service.recoveredKeys, isEmpty);
      expect(await store.readRaw(PersistenceService.corruptKey(ModLibrary.key)), isNull);
    });
  });

  group('sharing (ons3:mod: codes)', () {
    const sharing = ModSharing();

    test('a mod round-trips through its code, name and signature included', () {
      final mod = rules.withValue(
        rules.withValue(const ModDelta({}, name: 'Big Blue'), blueDamage(), 99),
        rules.field('TurretBlue.upgrade_damage')!,
        [
          {'cost': 20, 'value': 40},
          {'cost': 60, 'value': 80},
        ],
      );
      final code = sharing.encode(mod);
      expect(code, startsWith('ons3:mod:'));
      expect(sharing.encode(mod), code, reason: 'deterministic');
      final read = sharing.decode(code, rules);
      expect(read.problems, isEmpty);
      expect(read.delta.name, 'Big Blue');
      expect(read.delta.files, mod.files);
      expect(modSignature(read.delta), modSignature(mod));
      expect(rules.apply(read.delta).turrets['blue']!.stats.damage, 99);
    });

    test("a map code, a damaged code and text that isn't a code are refused", () {
      final map = const ShareCodec().encode(ShareCodec.mapKind, {'schemaVersion': 1});
      expect(
        () => sharing.decode(map, rules),
        throwsA(
          isA<ShareCodecException>()
              .having((e) => e.key, 'key', 'ui.share.wrongKind')
              .having((e) => e.args['other'], 'other', 'map'),
        ),
      );
      expect(() => sharing.decode('ons3:mod:@@@', rules), throwsA(isA<ShareCodecException>()));
      expect(() => sharing.decode('{nope', rules), throwsA(isA<ShareCodecException>()));
      final odd = const ShareCodec().encode(ShareCodec.modKind, {'files': 1});
      expect(() => sharing.decode(odd, rules), throwsA(isA<ShareCodecException>()));
    });

    test('a mod saved by the original game is read as well', () {
      final read = sharing.decode(
        '{"TurretBlue":{"weapon_damage":20,"weapon_range":2000},"GameSettings":{"wave_size":12}}',
        rules,
      );
      expect(rules.valueOf(blueDamage(), read.delta), 20);
      expect(rules.valueOf(rules.field('GameSettings.wave_size')!, read.delta), 12);
      expect(read.problems.single.kind, ModProblemKind.aboveMax);
      expect(read.usable, isTrue);
    });

    test('a share payload pasted as JSON is read as a mod code', () {
      final mod = rules.withValue(ModDelta.none, blueDamage(), 42);
      final read = sharing.decode(jsonEncode(mod.toJson()), rules);
      expect(rules.valueOf(blueDamage(), read.delta), 42);
    });
  });
}
