import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/services/persistence/document_store.dart';
import 'package:onslaught3_remastered/services/persistence/map_library.dart';
import 'package:onslaught3_remastered/services/persistence/settings.dart';
import 'package:onslaught3_remastered/services/share/share_codec.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../support/test_data.dart';

void main() {
  late GameData data;
  setUpAll(() => data = loadTestGameData());

  Map<String, Object?> fixture(String name) =>
      (jsonDecode(File('test/fixtures/persistence/$name').readAsStringSync()) as Map)
          .cast<String, Object?>();

  MapDefinition map(String id, String name, {double y = 100}) => MapDefinition(
    id: id,
    name: name,
    base: const Vec2(560, 200),
    road: [Vec2(0, y), const Vec2(400, 100), const Vec2(565, 227)],
    builtIn: false,
  );

  group('map library document (persisted, schema-versioned)', () {
    test('empty when nothing is stored; saves and loads back', () async {
      final service = PersistenceService(MemoryDocumentStore());
      expect((await service.loadMaps()).maps, isEmpty);
      final lib = const MapLibrary().saving(map('custom-a', 'A')).saving(map('custom-b', 'B'));
      await service.saveMaps(lib);
      final back = await service.loadMaps();
      expect([for (final m in back.maps) m.toJson()], [for (final m in lib.maps) m.toJson()]);
      expect(
        (await service.store.read(MapLibrary.key))!['schemaVersion'],
        MapLibrary.schemaVersion,
      );
    });

    test(
      'v1 fixture loads (migration contract); unreadable and non-player maps are dropped',
      () async {
        final store = MemoryDocumentStore();
        await store.write(MapLibrary.key, fixture('maps.v1.json'));
        final service = PersistenceService(store);
        final lib = await service.loadMaps();
        expect(lib.maps.map((m) => m.id), ['custom-zig-zag']);
        expect(service.recoveredKeys, [MapLibrary.key], reason: 'the dropped maps are kept');
        final zig = lib.byName('Zig Zag')!;
        expect(zig.builtIn, isFalse);
        expect(zig.road, hasLength(4));
        expect(validateMap(zig, data.world), isEmpty);
      },
    );

    test('one unreadable map is left out, kept under the corrupt key and reported', () async {
      final store = MemoryDocumentStore();
      final good = map('custom-a', 'A');
      final broken = {'id': 'custom-b', 'name': 'B', 'road': 'nope'};
      await store.write(MapLibrary.key, {
        'schemaVersion': MapLibrary.schemaVersion,
        'maps': [good.toJson(), broken, map('custom-c', 'C').toJson()],
      });
      final stored = await store.readRaw(MapLibrary.key);
      final dropped = <Object?>[];
      MapLibrary.fromJson((await store.read(MapLibrary.key))!, onDropped: dropped.add);
      expect(dropped, [broken]);
      final service = PersistenceService(store);
      final lib = await service.loadMaps();
      expect(lib.maps.map((m) => m.id), ['custom-a', 'custom-c']);
      expect(service.recoveredKeys, [MapLibrary.key]);
      expect(await store.readRaw(PersistenceService.corruptKey(MapLibrary.key)), stored);
    });

    test('a readable library reports nothing', () async {
      final store = MemoryDocumentStore();
      final service = PersistenceService(store);
      await service.saveMaps(const MapLibrary().saving(map('custom-a', 'A')));
      expect((await service.loadMaps()).maps, hasLength(1));
      expect(service.recoveredKeys, isEmpty);
      expect(await store.readRaw(PersistenceService.corruptKey(MapLibrary.key)), isNull);
    });

    test('a newer document is refused rather than misread', () {
      expect(
        () => MapLibrary.migrator.migrate({'schemaVersion': MapLibrary.schemaVersion + 1}),
        throwsFormatException,
      );
    });
  });

  group('names and ids', () {
    test('ids come from names, never clash, and a taken name keeps its id', () {
      var lib = const MapLibrary();
      expect(lib.idFor('My Map!'), 'custom-my-map');
      expect(lib.idFor('???'), 'custom-map');
      lib = lib.saving(map('custom-my-map', 'My Map!'));
      expect(lib.idFor('My Map!'), 'custom-my-map', reason: 'saving over a name replaces it');
      expect(lib.idFor('my map'), 'custom-my-map-2');
      lib = lib.saving(map('custom-my-map-2', 'my map'));
      expect(lib.idFor('MY MAP?'), 'custom-my-map-3');
      expect(MapLibrary.isCustomId('custom-x'), isTrue);
      expect(MapLibrary.isCustomId('map1'), isFalse);
    });

    test('saving replaces by id; removing deletes', () {
      var lib = const MapLibrary().saving(map('custom-a', 'A'));
      lib = lib.saving(map('custom-a', 'A', y: 200));
      expect(lib.maps.single.road.first, const Vec2(0, 200));
      expect(lib.removing('custom-a').maps, isEmpty);
    });
  });

  group('sharing (share string round trip)', () {
    const sharing = MapSharing();

    test('a map round-trips through its share string into another library', () {
      final original = map('custom-zz', 'Zig Zag');
      final code = sharing.encode(original);
      expect(code, startsWith('ons3:map:'));
      final imported = sharing.decode(code, const MapLibrary(), data.world);
      expect(imported.problems, isEmpty);
      expect(imported.replaces, isNull);
      expect(imported.map.id, 'custom-zig-zag');
      expect(imported.map.name, 'Zig Zag');
      expect(imported.map.base, original.base);
      expect(imported.map.road, original.road);
      expect(imported.map.builtIn, isFalse);
    });

    test('a built-in map can be shared and imported as a player map', () {
      final code = sharing.encode(data.maps['map4']!);
      final imported = sharing.decode(code, const MapLibrary(), data.world);
      expect(imported.map.id, 'custom-looping');
      expect(imported.map.road, data.maps['map4']!.road);
    });

    test('importing a name already in the library replaces that map', () {
      final lib = const MapLibrary().saving(map('custom-a', 'A'));
      final imported = sharing.decode(sharing.encode(map('elsewhere', 'A')), lib, data.world);
      expect(imported.replaces!.id, 'custom-a');
      expect(imported.map.id, 'custom-a');
    });

    test('an invalid map is read but reports its problems', () {
      const bad = MapDefinition(
        id: 'x',
        name: 'Bad',
        base: Vec2(600, 460),
        road: [Vec2(0, 470), Vec2(20, 470)],
      );
      final imported = sharing.decode(sharing.encode(bad), const MapLibrary(), data.world);
      expect(imported.problems, [MapProblem.noStart, MapProblem.noBase, MapProblem.tooShort]);
    });

    test('malformed payloads are refused with a reason', () {
      const codec = ShareCodec();
      Matcher refused(String key, {String? issue}) => throwsA(
        isA<ShareCodecException>()
            .having((e) => e.key, 'key', key)
            .having((e) => '${e.args['issue'] ?? ''}', 'issue', contains(issue ?? '')),
      );
      expect(
        () => sharing.decode(codec.encode('map', {'name': 'x'}), const MapLibrary(), data.world),
        refused('ui.share.mapMalformed'),
      );
      final unnamed = {...map('a', '  ').toShareJson()};
      expect(
        () => sharing.decode(codec.encode('map', unnamed), const MapLibrary(), data.world),
        refused('ui.share.mapNoName'),
      );
      final long = {...map('a', 'x' * (data.world.editor.maxNameLength + 1)).toShareJson()};
      expect(
        () => sharing.decode(codec.encode('map', long), const MapLibrary(), data.world),
        refused('ui.share.mapNameTooLong'),
      );
      final future = {...map('a', 'A').toShareJson(), 'schemaVersion': 99};
      expect(
        () => sharing.decode(codec.encode('map', future), const MapLibrary(), data.world),
        refused('ui.share.mapMalformed', issue: 'schemaVersion'),
      );
    });
  });
}
