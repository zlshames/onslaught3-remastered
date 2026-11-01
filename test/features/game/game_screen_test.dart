import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/app/app.dart';
import 'package:onslaught3_remastered/app/feature_flags.dart';
import 'package:onslaught3_remastered/features/game/camera/camera_controls.dart';
import 'package:onslaught3_remastered/features/game/flame/onslaught_flame_game.dart';
import 'package:onslaught3_remastered/features/game/game_view_model.dart';
import 'package:onslaught3_remastered/features/game/hud/camera_debug_overlay.dart';
import 'package:onslaught3_remastered/features/game/hud/stats_bar.dart';
import 'package:onslaught3_remastered/features/game/hud/tower_tray.dart';
import 'package:onslaught3_remastered/features/game/hud/turret_sheet.dart';
import 'package:onslaught3_remastered/features/game/hud/unsupported_shape.dart';
import 'package:onslaught3_remastered/services/assets/asset_pack.dart';
import 'package:onslaught3_remastered/services/data/asset_bundle_data_source.dart';
import 'package:onslaught3_remastered/services/persistence/document_store.dart';
import 'package:onslaught3_remastered/services/persistence/settings.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../support/pump.dart';
import '../../support/test_data.dart';

class _Controls implements CameraControls {
  final calls = <String>[];
  final _readout = ValueNotifier(
    const CameraReadout(
      zoom: 1.5,
      relativeZoom: 1.75,
      center: Offset(100, 200),
      viewport: Size(800, 400),
    ),
  );
  @override
  ValueListenable<CameraReadout> get cameraReadout => _readout;
  @override
  void fitMap() => calls.add('fit');
  @override
  void zoomIn() => calls.add('in');
  @override
  void zoomOut() => calls.add('out');
}

/// A bundle distinct from the default one, to prove the data source uses
/// the bundle it is given.
class _DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final bytes = await rootBundle.load(key);
    return bytes;
  }
}

void main() {
  late GameData data;
  setUpAll(() => data = loadTestGameData());

  /// A store holding a drag-and-drop choice: these tests build by dragging,
  /// and the test platform (Android) would otherwise default to drop and lock.
  DocumentStore dragAndDropStore() {
    final store = MemoryDocumentStore();
    // MemoryDocumentStore writes synchronously.
    unawaited(
      store.write(
        Settings.key,
        const Settings(placementChoice: PlacementMode.dragAndDrop).toJson(),
      ),
    );
    return store;
  }

  Widget app({
    bool debugOverlay = false,
    String initial = '/game/map2',
    bool enhancedSkin = false,
    DocumentStore? store,
  }) => ProviderScope(
    overrides: appOverrides(
      data: data,
      store: store ?? dragAndDropStore(),
      flags: FeatureFlags(debugOverlay: debugOverlay, enhancedSkin: enhancedSkin),
    ),
    child: OnslaughtApp(initialLocation: initial),
  );

  testWidgets('game route shows the map and HUD; back returns to the menu', (tester) async {
    tester.view
      ..physicalSize = const Size(923, 411)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(GameWidget<OnslaughtFlameGame>), findsOneWidget);
    expect(find.text('Incoming'), findsOneWidget);
    expect(find.byType(CameraDebugOverlay), findsNothing);
    await tester.tap(find.byTooltip('Back to menu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('ONSLAUGHT 3'), findsOneWidget);
  });

  testWidgets('an unknown map id falls back to the first map', (tester) async {
    await tester.pumpWidget(app(initial: '/game/nope'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Classic'), findsOneWidget);
  });

  testWidgets('debug overlay flag adds the camera overlay', (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 720)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(debugOverlay: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(CameraDebugOverlay), findsOneWidget);
  });

  for (final size in const [Size(375, 667), Size(411, 923)]) {
    testWidgets('portrait $size: the debug overlay fits and stays clear of the tray', (
      tester,
    ) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(debugOverlay: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull, reason: 'no overflow');
      final zoomIn = tester.getRect(find.byTooltip('Zoom in'));
      final tray = tester.getRect(find.byType(TowerTray));
      expect(zoomIn.bottom, lessThanOrEqualTo(tray.top));
      expect(tester.getRect(find.byType(CameraDebugOverlay)).right, lessThanOrEqualTo(size.width));
    });
  }

  testWidgets('camera debug overlay shows the readout and drives the controls', (tester) async {
    final controls = _Controls();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CameraDebugOverlay(controls: controls)),
      ),
    );
    expect(find.textContaining('zoom 1.500 (1.75× fit)'), findsOneWidget);
    expect(find.textContaining('centre 100.0,200.0'), findsOneWidget);
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.tap(find.byTooltip('Zoom out'));
    await tester.tap(find.byTooltip('Fit map'));
    expect(controls.calls, ['in', 'out', 'fit']);
  });

  testWidgets('game data loads from the asset bundle', (tester) async {
    final loaded = await tester.runAsync(
      () => GameData.load(
        AssetBundleDataSource(bundle: _DiskBundle()),
        behaviours: RulesRegistry.classic(),
      ),
    );
    expect(loaded!.turrets.length, 16);
  });

  // ------------------------------------------------------------ screen fit

  OnslaughtFlameGame gameOf(WidgetTester tester) => tester
      .widget<GameWidget<OnslaughtFlameGame>>(find.byType(GameWidget<OnslaughtFlameGame>))
      .game!;

  SessionGameViewModel vmOf(WidgetTester tester) =>
      gameOf(tester).viewModel as SessionGameViewModel;

  Future<void> resize(WidgetTester tester, Size size) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> openGame(
    WidgetTester tester,
    Size size, {
    bool enhancedSkin = false,
    DocumentStore? store,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(enhancedSkin: enhancedSkin, store: store));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// A buildable world point near the middle of the map (clear of the
  /// toasts and hints at its edges), on screen.
  Offset buildSpot(WidgetTester tester) {
    final vm = vmOf(tester);
    final spots =
        [
          for (var x = 100.0; x < 640; x += 20)
            for (var y = 100.0; y < 400; y += 20)
              if (vm.session.placementIssueAt(Vec2(x, y)) == null) Offset(x, y),
        ]..sort(
          (a, b) => (a - const Offset(360, 240)).distance.compareTo(
            (b - const Offset(360, 240)).distance,
          ),
        );
    return gameOf(tester).rig.worldToScreen(spots.first);
  }

  Finder firstCell() =>
      find.descendant(of: find.byType(TowerTray), matching: find.byType(InkWell)).first;

  for (final size in const [Size(402, 874), Size(375, 667)]) {
    testWidgets('portrait $size: stats on top, the tray along the bottom, the map between', (
      tester,
    ) async {
      await openGame(tester, size);
      expect(tester.takeException(), isNull);
      expect(gameOf(tester).rig.fill, isTrue);
      expect(tester.widget<TowerTray>(find.byType(TowerTray)).axis, Axis.horizontal);
      final tray = tester.getRect(find.byType(TowerTray));
      expect(tray.bottom, size.height);
      expect(tray.width, size.width);
      final stats = tester.getRect(find.byType(StatsBar));
      expect(stats.top, 0);
      expect(stats.width, size.width);
      // The upright map starts as far out as turrets stay big enough to tap:
      // nearly its whole width, centred between them.
      final rig = gameOf(tester).rig;
      expect(rig.isAtHome, isTrue);
      expect(rig.zoom * 36, greaterThanOrEqualTo(20));
      final seen = rig.screenToWorld(Offset(size.width, 0)).dx - rig.screenToWorld(Offset.zero).dx;
      expect(seen, greaterThan(0.9 * 720));
      expect(rig.screenToWorld(rig.free.center).dx, closeTo(360, 1e-6));
      expect(rig.worldToScreen(Offset.zero).dy, greaterThan(stats.bottom));
      expect(rig.worldToScreen(const Offset(0, 480)).dy, lessThan(tray.top));
      // A double tap goes in to cover the height between them.
      rig.toggleZoom(rig.free.center);
      expect(rig.worldToScreen(Offset.zero).dy, closeTo(stats.bottom, 1e-6));
      expect(rig.worldToScreen(const Offset(0, 480)).dy, closeTo(tray.top, 1e-6));
    });
  }

  testWidgets('portrait: drag a strip cell up to build; releasing over the strip cancels', (
    tester,
  ) async {
    await openGame(tester, const Size(402, 874));
    final vm = vmOf(tester);
    final spot = buildSpot(tester);
    var g = await tester.startGesture(tester.getCenter(firstCell()));
    await g.moveBy(const Offset(0, -30));
    await g.moveTo(spot);
    await tester.pump();
    expect(vm.placement.value?.at, isNotNull);
    await g.moveTo(tester.getCenter(find.byType(TowerTray)));
    await tester.pump();
    expect(vm.placement.value?.at, isNull);
    await g.up();
    await tester.pump(const Duration(milliseconds: 100));
    expect(vm.placement.value, isNull);
    expect(vm.world.turrets, isEmpty);

    g = await tester.startGesture(tester.getCenter(firstCell()));
    await g.moveBy(const Offset(0, -30));
    await g.moveTo(spot);
    await tester.pump();
    await g.up();
    await tester.pump(const Duration(milliseconds: 100));
    expect(vm.world.turrets, hasLength(1));
  });

  Future<DocumentStore> dropAndLockStore() async {
    final store = MemoryDocumentStore();
    await store.write(
      Settings.key,
      const Settings(placementChoice: PlacementMode.dropAndLock).toJson(),
    );
    return store;
  }

  testWidgets('drop and lock: release drops the ghost, a map drag nudges it, Place builds', (
    tester,
  ) async {
    final store = await tester.runAsync(dropAndLockStore);
    await openGame(tester, const Size(402, 874), store: store);
    final vm = vmOf(tester);
    final g = await tester.startGesture(tester.getCenter(firstCell()));
    await g.moveBy(const Offset(0, -30));
    await g.moveTo(buildSpot(tester));
    await tester.pump();
    await g.up();
    await tester.pump(const Duration(milliseconds: 100));
    expect(vm.world.turrets, isEmpty);
    final dropped = vm.placement.value!;
    expect(dropped.locked, isTrue);
    expect(find.text('Place'), findsOneWidget);

    // A drag well away from the ghost moves it and does not pan.
    final centre = gameOf(tester).rig.center;
    Future<void> nudge(Offset by) async {
      final d = await tester.startGesture(const Offset(80, 200));
      await d.moveBy(Offset(0, by.dy.sign * 30));
      await d.moveBy(by);
      await d.up();
      await tester.pump(const Duration(milliseconds: 500));
    }

    await nudge(const Offset(0, 24));
    final nudged = vm.placement.value!;
    expect(nudged.locked, isTrue);
    expect(nudged.at!.y, greaterThan(dropped.at!.y));
    expect(gameOf(tester).rig.center, centre);
    // And back by the same drag: the ghost is where it was dropped.
    await nudge(const Offset(0, -24));
    expect(vm.placement.value!.at!.distanceTo(dropped.at!), lessThan(1e-6));
    expect(vm.placement.value!.valid, isTrue);
    expect(vm.world.turrets, isEmpty);

    await tester.tap(find.text('Place'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(vm.world.turrets, hasLength(1));
    expect(vm.placement.value, isNull);
  });

  testWidgets('drop and lock: a tap on the map drops an armed turret; Cancel builds nothing', (
    tester,
  ) async {
    final store = await tester.runAsync(dropAndLockStore);
    await openGame(tester, const Size(923, 411), store: store);
    final vm = vmOf(tester);
    await tester.tap(firstCell());
    await tester.pump();
    await tester.tapAt(buildSpot(tester));
    await tester.pump(const Duration(milliseconds: 500));
    expect(vm.placement.value!.locked, isTrue);
    expect(vm.world.turrets, isEmpty);
    // A locked ghost stays locked across a turn.
    await resize(tester, const Size(411, 923));
    expect(vm.placement.value!.locked, isTrue);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(vm.placement.value, isNull);
    expect(vm.world.turrets, isEmpty);
  });

  testWidgets('turning the device keeps the selection and reopens its panel', (tester) async {
    await openGame(tester, const Size(923, 411));
    final vm = vmOf(tester);
    await tester.tap(firstCell());
    await tester.pump();
    await tester.tapAt(buildSpot(tester));
    // A map tap lands once the double-tap window has passed.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 100));
    expect(vm.world.turrets, hasLength(1));
    final turret = vm.world.turrets.single;
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tapAt(
      gameOf(tester).rig.worldToScreen(Offset(turret.position.x, turret.position.y)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(vm.selection.value?.uid, turret.uid);

    await resize(tester, const Size(411, 923));
    expect(tester.takeException(), isNull);
    expect(gameOf(tester).rig.fill, isTrue);
    expect(vm.selection.value?.uid, turret.uid);
    expect(find.byTooltip('Close'), findsOneWidget);
    expect(find.byType(TurretSheet), findsOneWidget);

    await resize(tester, const Size(923, 411));
    expect(gameOf(tester).rig.fill, isFalse);
    expect(vm.selection.value?.uid, turret.uid);
  });

  testWidgets('portrait: a panel opened at the top fades out at the top when dismissed', (
    tester,
  ) async {
    await openGame(tester, const Size(402, 874));
    final vm = vmOf(tester);
    final rig = gameOf(tester).rig;
    // A buildable spot in the lower half of the map, so its panel opens
    // against the top edge.
    final free = rig.free.deflate(40);
    final low = Offset(free.center.dx, free.top + free.height * 0.75);
    final spot = [
      for (var x = 0.0; x < 720; x += 10)
        for (var y = 0.0; y < 480; y += 10)
          if (vm.session.placementIssueAt(Vec2(x, y)) == null &&
              free.contains(rig.worldToScreen(Offset(x, y))))
            rig.worldToScreen(Offset(x, y)),
    ]..sort((a, b) => (a - low).distance.compareTo((b - low).distance));
    final g = await tester.startGesture(tester.getCenter(firstCell()));
    await g.moveBy(const Offset(0, -30));
    await g.moveTo(spot.first);
    await tester.pump();
    await g.up();
    await tester.pump(const Duration(milliseconds: 100));
    final turret = vm.world.turrets.single;
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tapAt(rig.worldToScreen(Offset(turret.position.x, turret.position.y)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(vm.selection.value?.uid, turret.uid);
    // Let the panel finish fading in.
    await tester.pump(const Duration(milliseconds: 300));
    final open = tester.getRect(find.byType(TurretSheet));
    expect(open.center.dy, lessThan(874 / 2));

    vm.select(null);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // Mid fade-out: the closing panel is still where it opened.
    expect(find.byTooltip('Close'), findsOneWidget);
    expect(tester.getRect(find.byType(TurretSheet)), open);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byTooltip('Close'), findsNothing);
  });

  for (final enhancedSkin in const [false, true]) {
    testWidgets('turning the device pans to show the selected turret (enhanced: $enhancedSkin)', (
      tester,
    ) async {
      await openGame(tester, const Size(923, 411), enhancedSkin: enhancedSkin);
      final vm = vmOf(tester);
      // A buildable spot near the left end of the map, which the filled
      // portrait view (centred on the map) does not show.
      final spot = [
        for (var x = 60.0; x < 200; x += 10)
          for (var y = 100.0; y < 400; y += 10)
            if (vm.session.placementIssueAt(Vec2(x, y)) == null) Offset(x, y),
      ].first;
      await tester.tap(firstCell());
      await tester.pump();
      await tester.tapAt(gameOf(tester).rig.worldToScreen(spot));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 100));
      final turret = vm.world.turrets.single;
      final at = Offset(turret.position.x, turret.position.y);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tapAt(gameOf(tester).rig.worldToScreen(at));
      await tester.pump(const Duration(milliseconds: 500));
      expect(vm.selection.value?.uid, turret.uid);

      await resize(tester, const Size(411, 923));
      await tester.pump();
      final rig = gameOf(tester).rig;
      expect(rig.fill, isTrue);
      expect(vm.selection.value?.uid, turret.uid);
      final shown = rig.worldToScreen(at);
      expect(rig.free.contains(shown), isTrue, reason: '$shown outside ${rig.free}');
      expect(tester.getRect(find.byType(TurretSheet)).contains(shown), isFalse);
    });
  }

  testWidgets('turning the device during a tray drag builds nothing', (tester) async {
    await openGame(tester, const Size(923, 411));
    final vm = vmOf(tester);
    final g = await tester.startGesture(tester.getCenter(firstCell()));
    await g.moveBy(const Offset(-30, 0));
    await g.moveTo(buildSpot(tester));
    await tester.pump();
    expect(vm.placement.value?.at, isNotNull);
    await resize(tester, const Size(411, 923));
    await g.moveBy(const Offset(0, -10));
    await g.up();
    await tester.pump(const Duration(milliseconds: 100));
    expect(vm.world.turrets, isEmpty);
    expect(vm.placement.value, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an armed tap-to-build stays armed across a turn', (tester) async {
    await openGame(tester, const Size(923, 411));
    final vm = vmOf(tester);
    await tester.tap(firstCell());
    await tester.pump();
    expect(vm.placement.value, isNotNull);
    await resize(tester, const Size(411, 923));
    expect(vm.placement.value, isNotNull);
  });

  testWidgets('a tiny window pauses the game behind a prompt until it is playable', (tester) async {
    await openGame(tester, const Size(923, 411));
    final vm = vmOf(tester);
    expect(vm.hud.value.paused, isFalse);
    await resize(tester, const Size(300, 200));
    await tester.pump();
    expect(find.byType(UnsupportedShape), findsOneWidget);
    expect(find.text('Make the window bigger'), findsOneWidget);
    expect(vm.hud.value.paused, isTrue);
    await resize(tester, const Size(923, 411));
    await tester.pump();
    expect(find.byType(UnsupportedShape), findsNothing);
    expect(vm.hud.value.paused, isFalse);
  });

  testWidgets('a game the player paused stays paused after a tiny window', (tester) async {
    await openGame(tester, const Size(923, 411));
    final vm = vmOf(tester);
    await tester.tap(find.byTooltip('Pause'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(vm.hud.value.paused, isTrue);
    await resize(tester, const Size(300, 200));
    await tester.pump();
    await resize(tester, const Size(923, 411));
    await tester.pump();
    expect(vm.hud.value.paused, isTrue);
  });

  testWidgets('Classic landscape keeps the top bar and right tray', (tester) async {
    await openGame(tester, const Size(923, 411));
    expect(tester.widget<StatsBar>(find.byType(StatsBar)).axis, Axis.horizontal);
    expect(tester.getRect(find.byType(StatsBar)), const Rect.fromLTWH(0, 0, 923, 48));
    expect(tester.getRect(find.byType(TowerTray)), const Rect.fromLTRB(923 - 76.0, 48, 923, 411));
    expect(gameOf(tester).rig.insets, const EdgeInsets.only(top: 48, right: 76));
  });

  testWidgets('the Enhanced skin moves a landscape phone\'s HUD into rails', (tester) async {
    await openGame(tester, const Size(923, 411), enhancedSkin: true);
    expect(tester.takeException(), isNull);
    expect(tester.widget<StatsBar>(find.byType(StatsBar)).axis, Axis.vertical);
    final stats = tester.getRect(find.byType(StatsBar));
    expect(stats.left, 0);
    expect(stats.height, 411);
    expect(gameOf(tester).rig.insets, const EdgeInsets.only(left: 76, right: 76));
  });

  for (final size in const [Size(923, 411), Size(411, 923), Size(375, 667)]) {
    testWidgets('$size: the game screen meets the tap-target guidelines', (tester) async {
      final handle = tester.ensureSemantics();
      await openGame(tester, size);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      handle.dispose();
    });
  }

  Future<DocumentStore> sharpGroundStore() async {
    final store = MemoryDocumentStore();
    await store.write(Settings.key, const Settings(sharpGround: true).toJson());
    return store;
  }

  testWidgets('Ground: Sharp draws the shader ground in an Enhanced game', (tester) async {
    final store = await tester.runAsync(sharpGroundStore);
    await openGame(tester, const Size(923, 411), enhancedSkin: true, store: store);
    expect(gameOf(tester).pack.ground('ground.classic'), isA<ShaderGround>());
  });

  testWidgets('Ground: Sharp is ignored by a Classic game', (tester) async {
    final store = await tester.runAsync(sharpGroundStore);
    await openGame(tester, const Size(923, 411), store: store);
    expect(gameOf(tester).pack.ground('ground.classic'), isNot(isA<ShaderGround>()));
  });

  for (final enhanced in [false, true]) {
    testWidgets('the in-game settings offer Ground ${enhanced ? 'with' : 'not without'} '
        'the Enhanced skin', (tester) async {
      await openGame(tester, const Size(923, 411), enhancedSkin: enhanced);
      await tester.tap(find.byTooltip('Settings'));
      // The game never settles; let the dialog open.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.dragUntilVisible(
        find.text('Language'),
        find.byType(SingleChildScrollView).last,
        const Offset(0, -200),
      );
      await tester.drag(find.byType(SingleChildScrollView).last, const Offset(0, -400));
      await tester.pump();
      expect(find.text('Ground'), enhanced ? findsOneWidget : findsNothing);
    });
  }
}
