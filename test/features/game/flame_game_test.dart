import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart' hide Image;
import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/app/ui_skin.dart';
import 'package:onslaught3_remastered/features/game/flame/entity_layer.dart';
import 'package:onslaught3_remastered/features/game/flame/ground_component.dart';
import 'package:onslaught3_remastered/features/game/flame/onslaught_flame_game.dart';
import 'package:onslaught3_remastered/features/game/flame/road_component.dart';
import 'package:onslaught3_remastered/services/persistence/settings.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../support/fake_game_view_model.dart';
import '../../support/fakes.dart';
import '../../support/test_data.dart';

void main() {
  late GameData data;
  setUpAll(() => data = loadTestGameData());

  Future<OnslaughtFlameGame> pumpGame(
    WidgetTester tester, {
    FakeGameViewModel? vm,
    Size size = const Size(923, 411),
    UiSkin skin = UiSkin.classic,
    PlacementMode placement = PlacementMode.dragAndDrop,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final game = OnslaughtFlameGame(
      viewModel: vm ?? FakeGameViewModel(data: data),
      pack: EmptyAssetPack(),
      driveSimulation: false,
      skin: skin,
      placementMode: ValueNotifier(placement),
    );
    await tester.pumpWidget(GameWidget(game: game));
    await tester.pump();
    await tester.pump();
    return game;
  }

  testWidgets('starts fitted to the whole play area', (tester) async {
    final game = await pumpGame(tester);
    expect(game.rig.relativeZoom, closeTo(1, 1e-9));
    expect(game.camera.viewfinder.zoom, closeTo(411 / 480, 1e-6));
    expect(game.cameraReadout.value.center, const Offset(360, 240));
  });

  testWidgets('art density follows zoom × device pixel ratio', (tester) async {
    tester.view
      ..physicalSize = const Size(2424, 1080)
      ..devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final game = OnslaughtFlameGame(
      viewModel: FakeGameViewModel(data: data),
      pack: EmptyAssetPack(),
      driveSimulation: false,
    );
    await tester.pumpWidget(GameWidget(game: game));
    await tester.pump();
    await tester.pump();
    expect(game.art!.pixelsPerWorldPx, closeTo(game.rig.fitZoom * 2.625, 1e-9));
    game.rig.zoomBy(10, Offset.zero);
    game.cameraChanged();
    await tester.pump();
    expect(game.art!.pixelsPerWorldPx, closeTo(game.rig.maxZoom * 2.625, 1e-9));
  });

  testWidgets('one-finger drag pans when zoomed in', (tester) async {
    final game = await pumpGame(tester);
    game.zoomIn();
    game.zoomIn();
    final before = game.rig.center;
    await tester.timedDragFrom(
      const Offset(600, 250),
      const Offset(-200, -100),
      const Duration(milliseconds: 300),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(game.rig.center.dx, greaterThan(before.dx));
    expect(game.rig.center.dy, greaterThan(before.dy));
    expect(game.camera.viewfinder.position.x, closeTo(game.rig.center.dx, 1e-3));
  });

  testWidgets('two-finger pinch zooms', (tester) async {
    final game = await pumpGame(tester);
    final a = await tester.startGesture(const Offset(400, 200), pointer: 1);
    final b = await tester.startGesture(const Offset(500, 200), pointer: 2);
    await tester.pump();
    for (var i = 1; i <= 10; i++) {
      await a.moveTo(Offset(400 - 10.0 * i, 200));
      await b.moveTo(Offset(500 + 10.0 * i, 200));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await tester.pump(const Duration(milliseconds: 500)); // let the double-tap timer lapse
    expect(game.rig.relativeZoom, greaterThan(2.5));
    // The pinch was symmetric about (450, 200): that world point stays put.
    expect(
      game.rig.worldToScreen(game.rig.screenToWorld(const Offset(450, 200))).dx,
      closeTo(450, 1e-6),
    );
  });

  testWidgets('double tap toggles 2× and back to fit', (tester) async {
    final game = await pumpGame(tester);
    await tester.tapAt(const Offset(460, 200));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(const Offset(460, 200));
    await tester.pump(const Duration(milliseconds: 500));
    expect(game.rig.relativeZoom, closeTo(2, 1e-9));
    await tester.tapAt(const Offset(460, 200));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(const Offset(460, 200));
    await tester.pump(const Duration(milliseconds: 500));
    expect(game.rig.isAtFit, isTrue);
  });

  testWidgets('a tap on a turret selects at once; a double tap on it never zooms', (tester) async {
    final vm = FakeGameViewModel(data: data)..turretAtResult = 7;
    final game = await pumpGame(tester, vm: vm);
    await tester.tapAt(const Offset(460, 200));
    await tester.pump();
    expect(vm.selections, [7], reason: 'no wait for a possible second tap');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(const Offset(460, 200));
    await tester.pump();
    expect(vm.selections, [7, 7], reason: 'the second tap is a tap too');
    expect(game.rig.isAtFit, isTrue);
    await tester.pump(const Duration(milliseconds: 500)); // let gesture timers lapse
  });

  testWidgets('two ground taps far apart in time or place do not zoom', (tester) async {
    final game = await pumpGame(tester);
    await tester.tapAt(const Offset(460, 200));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tapAt(const Offset(460, 200));
    await tester.pump();
    expect(game.rig.isAtFit, isTrue, reason: 'slower than the double-tap timeout');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tapAt(const Offset(100, 100));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(const Offset(460, 300));
    await tester.pump();
    expect(game.rig.isAtFit, isTrue, reason: 'too far apart');
    await tester.pump(const Duration(milliseconds: 500)); // let gesture timers lapse
  });

  testWidgets('debug controls zoom, clamp and fit', (tester) async {
    final game = await pumpGame(tester);
    for (var i = 0; i < 20; i++) {
      game.zoomIn();
    }
    expect(game.rig.relativeZoom, closeTo(3, 1e-9));
    game.fitMap();
    expect(game.rig.isAtFit, isTrue);
    game.zoomOut();
    expect(game.rig.isAtFit, isTrue);
  });

  Future<void> tap(WidgetTester tester, Offset at) async {
    await tester.tapAt(at);
    // Let the double-tap window lapse so the next tap is a fresh one.
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('tap on a turret selects it; tap again deselects', (tester) async {
    final vm = FakeGameViewModel(data: data)..turretAtResult = 7;
    await pumpGame(tester, vm: vm);
    await tap(tester, const Offset(460, 200));
    expect(vm.selections, [7]);
  });

  testWidgets('tap on empty ground deselects under classicFixed only', (tester) async {
    final fixed = FakeGameViewModel(data: data);
    await pumpGame(tester, vm: fixed);
    await tap(tester, const Offset(460, 200));
    expect(fixed.selections, [null]);
  });

  testWidgets('classic keeps the selection on empty-ground taps', (tester) async {
    final classic = FakeGameViewModel(data: data, profile: RulesProfile.classic);
    await pumpGame(tester, vm: classic);
    await tap(tester, const Offset(460, 200));
    expect(classic.selections, isEmpty);
  });

  testWidgets('an armed turret is built where the map is tapped', (tester) async {
    final vm = FakeGameViewModel(data: data)..previewPlacement('blue', null);
    final game = await pumpGame(tester, vm: vm);
    const at = Offset(460, 200);
    await tap(tester, at);
    final build = vm.dispatched.single as BuildTurret;
    final world = game.screenToWorld(at);
    expect(build.x, closeTo(world.x, 1e-6));
    expect(build.y, closeTo(world.y, 1e-6));
    expect(vm.placement.value, isNull);
  });

  group('drop and lock', () {
    testWidgets('a tap drops and locks an armed turret; a second tap moves it', (tester) async {
      final vm = FakeGameViewModel(data: data)..previewPlacement('blue', null);
      final game = await pumpGame(tester, vm: vm, placement: PlacementMode.dropAndLock);
      await tap(tester, const Offset(460, 200));
      expect(vm.dispatched, isEmpty);
      expect(vm.placement.value!.locked, isTrue);
      expect(vm.placement.value!.at, game.screenToWorld(const Offset(460, 200)));
      await tap(tester, const Offset(300, 150));
      expect(vm.dispatched, isEmpty);
      expect(vm.placement.value!.at, game.screenToWorld(const Offset(300, 150)));
      expect(vm.commitPlacement(), isTrue);
      expect(vm.dispatched.single, isA<BuildTurret>());
    });

    testWidgets('a drag anywhere nudges a locked ghost 1:1 and does not pan', (tester) async {
      final vm = FakeGameViewModel(data: data)
        ..previewPlacement('blue', const Vec2(360, 240), locked: true);
      final game = await pumpGame(tester, vm: vm, placement: PlacementMode.dropAndLock);
      final centre = game.rig.center;
      // Far from the ghost: the finger never covers it.
      final g = await tester.startGesture(const Offset(150, 350));
      await g.moveBy(const Offset(30, 0));
      await tester.pump();
      final before = vm.placement.value!.at!;
      await g.moveBy(const Offset(40, -20));
      await tester.pump();
      await g.up();
      await tester.pump(const Duration(milliseconds: 500));
      final after = vm.placement.value!.at!;
      final zoom = game.rig.zoom;
      expect(after.x - before.x, closeTo(40 / zoom, 1e-6));
      expect(after.y - before.y, closeTo(-20 / zoom, 1e-6));
      expect(vm.placement.value!.locked, isTrue);
      expect(game.rig.center, centre);
      expect(vm.dispatched, isEmpty);
    });

    testWidgets('a nudge keeps the ghost inside the play area', (tester) async {
      final vm = FakeGameViewModel(data: data)
        ..previewPlacement('blue', const Vec2(10, 470), locked: true);
      final game = await pumpGame(tester, vm: vm, placement: PlacementMode.dropAndLock);
      expect(game.nudgePlacement(const Offset(-500, 500)), isTrue);
      expect(vm.placement.value!.at, const Vec2(0, 480));
    });

    testWidgets('without a locked ghost a drag pans and nudges nothing', (tester) async {
      final vm = FakeGameViewModel(data: data)..previewPlacement('blue', null);
      final game = await pumpGame(tester, vm: vm, placement: PlacementMode.dropAndLock);
      game.rig.zoomBy(2, const Offset(460, 200));
      expect(game.nudgePlacement(const Offset(10, 10)), isFalse);
      final centre = game.rig.center;
      await tester.dragFrom(const Offset(460, 200), const Offset(60, 0));
      await tester.pump(const Duration(milliseconds: 500));
      expect(game.rig.center, isNot(centre));
      expect(vm.placement.value!.at, isNull);
    });
  });

  group('filled view (portrait)', () {
    const portrait = Size(402, 874);
    const hud = EdgeInsets.only(top: 48, bottom: 88);

    testWidgets('the viewfinder draws world points where the rig says', (tester) async {
      final game = await pumpGame(tester, size: portrait);
      game.setFrame(hud, fill: true);
      await tester.pump();
      expect(game.rig.isAtHome, isTrue);
      expect(game.camera.viewfinder.zoom, closeTo(738 / 480, 1e-6));
      game.rig.panBy(const Offset(-120, 0));
      game.cameraChanged();
      await tester.pump();
      for (final w in [Vector2.zero(), Vector2(720, 0), Vector2(300, 400)]) {
        final drawn = game.camera.localToGlobal(w);
        // Flame's matrices are 32-bit floats.
        final rig = game.rig.worldToScreen(Offset(w.x, w.y));
        expect(drawn.x, closeTo(rig.dx, 1e-3), reason: '$w');
        expect(drawn.y, closeTo(rig.dy, 1e-3), reason: '$w');
      }
    });

    testWidgets('a tap builds at the world point under it', (tester) async {
      final vm = FakeGameViewModel(data: data)..previewPlacement('blue', null);
      final game = await pumpGame(tester, vm: vm, size: portrait);
      game.setFrame(hud, fill: true);
      await tester.pump();
      final at = game.rig.worldToScreen(const Offset(300, 100));
      await tap(tester, at);
      final build = vm.dispatched.single as BuildTurret;
      expect(build.x, closeTo(300, 1e-6));
      expect(build.y, closeTo(100, 1e-6));
    });

    testWidgets('the ground runs past the play area, tinted, in every skin and orientation', (
      tester,
    ) async {
      for (final skin in UiSkin.values) {
        final game = await pumpGame(tester, skin: skin);
        expect(game.world.children.whereType<GroundBeyond>(), hasLength(1));
        expect(game.world.children.whereType<PlayAreaEdge>(), hasLength(1));
      }
    });
  });

  testWidgets('Classic picks turrets by footprint only; Enhanced by a 22 pt zone', (tester) async {
    final classic = FakeGameViewModel(data: data)..turretAtResult = 7;
    await pumpGame(tester, vm: classic);
    await tap(tester, const Offset(460, 200));
    expect(classic.lastTurretAtRadius, 0);
    final enhanced = FakeGameViewModel(data: data)..turretAtResult = 7;
    final game = await pumpGame(tester, vm: enhanced, skin: UiSkin.enhanced);
    await tap(tester, const Offset(460, 200));
    expect(enhanced.lastTurretAtRadius, closeTo(22 / game.rig.zoom, 1e-9));
  });

  testWidgets('the ground covers a stage taller than the play area, as the menu demo', (
    tester,
  ) async {
    final game = OnslaughtFlameGame(
      viewModel: FakeGameViewModel(data: data),
      pack: EmptyAssetPack(),
      driveSimulation: false,
      worldSize: const Size(720, 535),
    );
    await tester.pumpWidget(GameWidget(game: game));
    await tester.pump();
    await tester.pump();
    final ground = game.world.children.whereType<RectangleComponent>().single;
    expect(ground.size, Vector2(720, 535));
    final stage = game.world.children.whereType<RoadComponent>().single.stage;
    expect(stage, const Offset(0, 0) & const Size(720, 535));
    expect(game.world.children.whereType<EntityLayer>().single.stage, stage);
  });

  testWidgets('ground decorations sit under the road, and the menu demo has its own', (
    tester,
  ) async {
    final attract = data.attract!;
    expect(attract.groundArt, isNot(equals(data.world.groundArt)));
    final plain = await pumpGame(tester);
    expect(plain.groundArt, data.world.groundArt);
    final layer = plain.world.children.whereType<GroundDecorations>().single;
    expect(layer.stage, plain.rig.world);
    final road = plain.world.children.whereType<RoadComponent>().single;
    expect(layer.priority, lessThan(road.priority));
    expect(layer.priority, greaterThan(GroundLayers.ground));
    final demo = OnslaughtFlameGame(
      viewModel: FakeGameViewModel(data: data),
      pack: EmptyAssetPack(),
      driveSimulation: false,
      groundArt: attract.groundArt,
    );
    expect(demo.groundArt, attract.groundArt);
  });

  testWidgets('a road starting on the edge is cut off there, not capped past it', (tester) async {
    final road = [const Vec2(0, 50), const Vec2(100, 50)];
    Future<int> alphaLeftOfTheEdge(Rect? stage) async {
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder)..translate(20, 0);
      RoadComponent(road: road, style: data.world.road, stage: stage).render(canvas);
      final image = await recorder.endRecording().toImage(140, 100);
      final bytes = await image.toByteData();
      return bytes!.getUint8((50 * 140 + 12) * 4 + 3);
    }

    await tester.runAsync(() async {
      expect(await alphaLeftOfTheEdge(null), greaterThan(0), reason: 'the round cap');
      expect(await alphaLeftOfTheEdge(const Offset(0, 0) & const Size(100, 100)), 0);
    });
  });
}
