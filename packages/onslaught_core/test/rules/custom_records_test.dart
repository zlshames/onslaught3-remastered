import 'package:onslaught_core/onslaught_core.dart';
import 'package:test/test.dart';

import '../support/repo_data.dart';

/// Custom games' own records (owner decision, 2026-10-19): kept per map
/// version, mod, mode, difficulty and challenge, apart from the standard
/// progress.
void main() {
  late GameData data;
  setUpAll(() => data = loadClassicData());

  MapDefinition player(MapDefinition m, {String? name, List<Vec2>? road}) => MapDefinition(
    id: 'custom-mine',
    name: name ?? 'Mine',
    base: m.base,
    road: road ?? m.road,
    builtIn: false,
  );

  test('a map version is its shape: renaming keeps it, reshaping changes it', () {
    final classic = data.maps['map1']!;
    final v1 = mapVersionHash(player(classic));
    expect(v1, matches(RegExp(r'^[0-9a-f]{8}$')));
    expect(mapVersionHash(player(classic, name: 'Renamed')), v1);
    expect(mapVersionHash(classic), v1, reason: 'the id and name are not part of it');
    final moved = [...classic.road]..[1] = classic.road[1] + const Vec2(20, 0);
    expect(mapVersionHash(player(classic, road: moved)), isNot(v1));
  });

  test('keys tell the custom games apart and round-trip', () {
    const plain = CustomRecordKey(
      mapId: 'custom-mine',
      mapVersion: 'aaaa0001',
      mode: 'normal',
      difficulty: 'hard',
    );
    const modded = CustomRecordKey(
      mapId: 'custom-mine',
      mapVersion: 'aaaa0001',
      mod: '0420522f',
      mode: 'normal',
      difficulty: 'hard',
    );
    const v2 = CustomRecordKey(
      mapId: 'custom-mine',
      mapVersion: 'bbbb0002',
      mode: 'normal',
      difficulty: 'hard',
    );
    expect({plain.id, modded.id, v2.id}, hasLength(3));
    expect(CustomRecordKey.fromJson(modded.toJson()), modded);
    expect(CustomRecordKey.fromJson(modded.toJson()).id, modded.id);
  });

  test('the best custom game: wave, then kills, then score', () {
    const best = CustomResult(wave: 50, kills: 400, score: 1000);
    expect(improvesCustomBest(null, best), isTrue);
    expect(improvesCustomBest(best, const CustomResult(wave: 51, kills: 1, score: 1)), isTrue);
    expect(improvesCustomBest(best, const CustomResult(wave: 49, kills: 999, score: 9e9)), isFalse);
    expect(improvesCustomBest(best, const CustomResult(wave: 50, kills: 401, score: 1)), isTrue);
    expect(improvesCustomBest(best, const CustomResult(wave: 50, kills: 400, score: 1001)), isTrue);
    expect(improvesCustomBest(best, best), isFalse, reason: 'strictly better');
  });
}
