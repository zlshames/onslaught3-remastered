import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:onslaught3_remastered/app/custom_record_list.dart';
import 'package:onslaught3_remastered/services/persistence/custom_records.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../support/test_data.dart';
import '../devices.dart';

/// Goldens for the custom games' records (owner decision, 2026-10-19): an
/// edited player map's two versions, a modded run on it, and a modded
/// built-in map, at phone size with normal and large text.
void main() {
  final GameData data = loadTestGameData();
  final classic = data.maps['map1']!;
  final v1 = MapDefinition(id: 'custom-loop', name: 'Loop', base: classic.base, road: classic.road);
  final v2 = MapDefinition(
    id: 'custom-loop',
    name: 'Loop',
    base: classic.base,
    road: [...classic.road]..[1] = classic.road[1] + const Vec2(20, 0),
  );

  CustomRecord rec(MapDefinition? map, int wave, {String? mod, String mode = 'normal'}) =>
      CustomRecord(
        key: CustomRecordKey(
          mapId: map?.id ?? 'map1',
          mapVersion: map == null ? null : mapVersionHash(map),
          mod: mod,
          mode: mode,
          difficulty: 'hard',
        ),
        mapName: map?.name ?? 'Classic',
        modName: mod == null ? null : 'Cheap blues',
        wave: wave,
        kills: wave * 10,
        score: wave * 4321.0,
        spent: 0,
        dateMs: DateTime(2026, 10, 19).millisecondsSinceEpoch,
      );

  final custom = const CustomRecords()
      .withResult(rec(v1, 87))
      .withResult(rec(v2, 42))
      .withResult(rec(v2, 140, mod: '0420522f'))
      .withResult(rec(null, 60, mod: '0420522f', mode: 'sandbox'));

  Widget page(double textScale, {String? mapId}) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: MediaQuery(
      data: MediaQueryData(size: GoldenDevices.phone, textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        backgroundColor: const Color(0xFF1B1F22),
        body: CustomRecordList(
          data: data,
          custom: custom,
          mapId: mapId,
          currentVersions: {'custom-loop': mapVersionHash(v2)},
        ),
      ),
    ),
  );

  goldenTest(
    'custom records',
    fileName: 'custom_records',
    builder: () => GoldenTestGroup(
      columns: 1,
      children: [
        GoldenTestScenario(
          name: 'records page',
          constraints: BoxConstraints.tight(GoldenDevices.phone),
          child: page(1),
        ),
        GoldenTestScenario(
          name: 'records page 130 %',
          constraints: BoxConstraints.tight(GoldenDevices.phone),
          child: page(1.3),
        ),
        GoldenTestScenario(
          name: 'one map (Map Tools)',
          constraints: BoxConstraints.tight(GoldenDevices.phone),
          child: page(1, mapId: 'custom-loop'),
        ),
      ],
    ),
  );
}
