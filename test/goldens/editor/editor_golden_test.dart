import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onslaught3_remastered/app/providers.dart';
import 'package:onslaught3_remastered/features/editor/map_editor_screen.dart';
import 'package:onslaught3_remastered/features/editor/map_library_screen.dart';
import 'package:onslaught3_remastered/services/persistence/map_library.dart';
import 'package:onslaught3_remastered/services/persistence/profile.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../support/pump.dart';
import '../../support/test_data.dart';
import '../devices.dart';

/// Goldens for Phase 6 Map Tools at phone sizes: the editor (new map with
/// its help, a finished map) and the map library. No asset pack is given,
/// so the ground and base art are left out (colours and outlines only).
void main() {
  final GameData data = loadTestGameData();

  const zigzag = MapDefinition(
    id: 'custom-zig-zag',
    name: 'Zig Zag',
    base: Vec2(500, 300),
    road: [
      Vec2(0, 100),
      Vec2(200, 100),
      Vec2(200, 380),
      Vec2(400, 380),
      Vec2(400, 160),
      Vec2(508.5, 320.5),
    ],
    builtIn: false,
  );
  final library = const MapLibrary()
      .saving(zigzag)
      .saving(
        MapDefinition(
          id: 'custom-looping',
          name: 'Looping copy',
          base: data.maps['map4']!.base,
          road: data.maps['map4']!.road,
          builtIn: false,
        ),
      );

  Widget screen(Widget child) => ProviderScope(
    overrides: appOverrides(
      data: data,
      fakes: false,
      extra: [
        assetPackProvider.overrideWith((ref) => Future.error('no pack in goldens')),
        profileProvider.overrideWith(() => _FixedProfile(const Profile())),
        mapLibraryProvider.overrideWith(() => _FixedLibrary(library)),
      ],
    ),
    child: MaterialApp(debugShowCheckedModeBanner: false, home: child),
  );

  goldenTest(
    'map editor',
    fileName: 'map_editor',
    pumpBeforeTest: (tester) async => tester.pump(const Duration(milliseconds: 50)),
    builder: () => GoldenTestGroup(
      columns: 1,
      children: [
        for (final (name, size) in [
          ('phone', GoldenDevices.phone),
          ('phoneSmall', GoldenDevices.phoneSmall),
        ]) ...[
          GoldenTestScenario(
            name: '$name new map',
            constraints: BoxConstraints.tight(size),
            child: screen(const MapEditorScreen()),
          ),
          GoldenTestScenario(
            name: '$name Zig Zag',
            constraints: BoxConstraints.tight(size),
            child: screen(MapEditorScreen(mapId: zigzag.id)),
          ),
        ],
      ],
    ),
  );

  goldenTest(
    'map library',
    fileName: 'map_library',
    pumpBeforeTest: (tester) async => tester.pump(const Duration(milliseconds: 50)),
    builder: () => GoldenTestGroup(
      columns: 1,
      children: [
        GoldenTestScenario(
          name: 'two maps',
          constraints: BoxConstraints.tight(GoldenDevices.phone),
          child: screen(const MapLibraryScreen()),
        ),
      ],
    ),
  );

  goldenTest(
    'map tools in portrait',
    fileName: 'map_tools_portrait',
    pumpBeforeTest: (tester) async => tester.pump(const Duration(milliseconds: 50)),
    builder: () => GoldenTestGroup(
      columns: 3,
      children: [
        GoldenTestScenario(
          name: 'phonePortrait Zig Zag',
          constraints: BoxConstraints.tight(GoldenDevices.phonePortrait),
          child: screen(MapEditorScreen(mapId: zigzag.id)),
        ),
        GoldenTestScenario(
          name: 'phoneSmallPortrait new map',
          constraints: BoxConstraints.tight(GoldenDevices.phoneSmallPortrait),
          child: screen(const MapEditorScreen()),
        ),
        GoldenTestScenario(
          name: 'phonePortrait library',
          constraints: BoxConstraints.tight(GoldenDevices.phonePortrait),
          child: screen(const MapLibraryScreen()),
        ),
      ],
    ),
  );
}

class _FixedProfile extends ProfileNotifier {
  _FixedProfile(this.profile);

  final Profile profile;

  @override
  Future<Profile> build() async => profile;
}

class _FixedLibrary extends MapLibraryNotifier {
  _FixedLibrary(this.library);

  final MapLibrary library;

  @override
  Future<MapLibrary> build() async => library;
}
