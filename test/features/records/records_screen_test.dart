import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/app/app.dart';
import 'package:onslaught3_remastered/services/persistence/custom_records.dart';
import 'package:onslaught3_remastered/services/persistence/document_store.dart';
import 'package:onslaught3_remastered/services/persistence/map_library.dart';
import 'package:onslaught3_remastered/services/persistence/profile.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../support/pump.dart';
import '../../support/test_data.dart';

/// Custom games' records (owner decision, 2026-10-19): the Records page from
/// the main menu, and each player map's records in Map Tools, by version.
void main() {
  late GameData data;
  late MapDefinition loopNow;
  late MapDefinition loopBefore;
  setUpAll(() {
    data = loadTestGameData();
    final classic = data.maps['map1']!;
    loopBefore = MapDefinition(
      id: 'custom-loop',
      name: 'Loop',
      base: classic.base,
      road: classic.road,
      builtIn: false,
    );
    // The road was edited since: version 2 is the map's shape now.
    loopNow = MapDefinition(
      id: 'custom-loop',
      name: 'Loop',
      base: classic.base,
      road: [...classic.road]..[1] = classic.road[1] + const Vec2(20, 0),
      builtIn: false,
    );
  });

  CustomRecord rec(
    String mapId,
    String mapName,
    String? version,
    int wave, {
    String? mod,
    String? modName,
    String difficulty = 'hard',
    String mode = 'normal',
  }) => CustomRecord(
    key: CustomRecordKey(
      mapId: mapId,
      mapVersion: version,
      mod: mod,
      mode: mode,
      difficulty: difficulty,
    ),
    mapName: mapName,
    modName: modName,
    wave: wave,
    kills: wave * 10,
    score: wave * 1000.0,
    spent: 0,
    dateMs: DateTime(2026, 10, 19).millisecondsSinceEpoch,
  );

  Profile seeded() => const Profile()
      .withCustomRecord(rec('custom-loop', 'Loop', mapVersionHash(loopBefore), 87))
      .withCustomRecord(rec('custom-loop', 'Loop', mapVersionHash(loopNow), 42))
      .withCustomRecord(
        rec('custom-loop', 'Loop', mapVersionHash(loopNow), 140, mod: '0420522f', modName: 'Cheap'),
      )
      .withCustomRecord(
        rec('map1', 'Classic', null, 60, mod: '0420522f', modName: 'Cheap', mode: 'sandbox'),
      );

  Future<void> app(WidgetTester tester, String initial, {Profile profile = const Profile()}) async {
    tester.view
      ..physicalSize = const Size(923, 411)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemoryDocumentStore();
    await store.write(Profile.key, profile.toJson());
    await store.write(MapLibrary.key, MapLibrary(maps: [loopNow]).toJson());
    await tester.pumpWidget(
      ProviderScope(
        overrides: appOverrides(data: data, store: store),
        child: OnslaughtApp(initialLocation: initial),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  String t(String key, [Map<String, Object?> args = const {}]) {
    var s = data.text(key);
    args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
    return s;
  }

  testWidgets('the main menu opens the Records page; a new player has none', (tester) async {
    await app(tester, '/');
    await tester.tap(find.text(t('ui.records.menu')));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text(t('ui.records.title')), findsOneWidget);
    expect(find.text(t('ui.records.empty')), findsOneWidget);
  });

  testWidgets('the Records page lists each map version and the modded built-in maps', (
    tester,
  ) async {
    await app(tester, '/records', profile: seeded());
    expect(find.text(t('ui.records.playerMaps')), findsOneWidget);
    expect(find.text('Loop · ${t('ui.records.versionCurrent', {'n': 2})}'), findsOneWidget);
    expect(find.text('Loop · ${t('ui.records.version', {'n': 1})}'), findsOneWidget);
    for (final w in [42, 140, 87]) {
      await tester.scrollUntilVisible(find.text(t('ui.records.wave', {'wave': w})), 100);
    }
    expect(find.text('Hard · ${t('ui.records.mod', {'name': 'Cheap'})}'), findsOneWidget);
    // Below: the built-in maps played with a mod.
    await tester.scrollUntilVisible(find.text(t('ui.records.wave', {'wave': 60})), 100);
    expect(find.text(t('ui.records.modded')), findsOneWidget);
    expect(find.text('Classic'), findsOneWidget);
    expect(
      find.text('${t('ui.mode.sandbox')} · ${t('ui.records.mod', {'name': 'Cheap'})}'),
      findsOneWidget,
    );
  });

  testWidgets('Map Tools shows the best wave on the road now and every version\'s records', (
    tester,
  ) async {
    await app(tester, '/maps', profile: seeded());
    // The tile: the best on version 2 (the modded 140 beats the plain 42).
    expect(find.text(t('ui.records.best', {'wave': 140})), findsOneWidget);
    await tester.tap(find.text('Loop'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text(t('ui.records.menu')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(t('ui.records.mapTitle', {'name': 'Loop'})), findsOneWidget);
    expect(find.text(t('ui.records.versionCurrent', {'n': 2})), findsOneWidget);
    expect(find.text(t('ui.records.version', {'n': 1})), findsOneWidget);
    expect(find.text(t('ui.records.wave', {'wave': 87})), findsOneWidget);
    expect(find.text('Classic'), findsNothing, reason: 'only this map');
    await tester.tap(find.byTooltip(t('ui.common.close')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(t('ui.records.mapTitle', {'name': 'Loop'})), findsNothing);
  });

  testWidgets('a map without records has no Records entry', (tester) async {
    await app(tester, '/maps');
    expect(find.textContaining('Best wave'), findsNothing);
    await tester.tap(find.text('Loop'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(t('ui.records.menu')), findsNothing);
  });
}
