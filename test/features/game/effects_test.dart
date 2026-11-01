import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/features/game/effect_settings.dart';
import 'package:onslaught3_remastered/features/game/flame/art_resolver.dart';
import 'package:onslaught3_remastered/features/game/flame/entity_layer.dart';
import 'package:onslaught3_remastered/features/game/flame/onslaught_flame_game.dart';
import 'package:onslaught3_remastered/features/game/flame/smoke_view.dart';
import 'package:onslaught3_remastered/features/game/game_haptics.dart';
import 'package:onslaught3_remastered/services/assets/asset_pack.dart';
import 'package:onslaught3_remastered/services/haptics/haptics.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../support/fake_game_view_model.dart';
import '../../support/fakes.dart';
import '../../support/log_capture.dart';
import '../../support/test_data.dart';

/// Serves only the rocket trail, from an image the test puts in the cache.
class _TrailPack extends EmptyAssetPack {
  @override
  SpriteAsset? sprite(String id) => id == 'fx.rocket-trail'
      ? SpriteAsset(id, [
          for (var i = 0; i < 31; i++)
            const SpriteFrame(
              image: 'trail.png',
              rect: ui.Rect.fromLTWH(0, 0, 4, 4),
              anchorX: 2,
              anchorY: 2,
              scale: 1,
            ),
        ])
      : null;
}

class _Recorder implements HapticSink {
  final List<HapticCue> played = [];
  @override
  Future<void> play(HapticCue cue) async => played.add(cue);
}

class _Broken implements HapticSink {
  @override
  Future<void> play(HapticCue cue) async => throw StateError('no vibrator');
}

/// Phase 8 juice: rocket smoke (`SmokeManager.rocketSmoke`) and vibration.
void main() {
  late GameData data;
  setUpAll(() => data = loadTestGameData());

  /// A blank trail clip with [n] frames.
  List<ResolvedFrame> clip(int n) {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 4, 4), ui.Paint());
    final image = recorder.endRecording().toImageSync(4, 4);
    return [
      for (var i = 0; i < n; i++)
        ResolvedFrame(Sprite(image), size: Vector2.all(4), anchor: Anchor.center),
    ];
  }

  /// A sandbox game with one held rocket circling (it never hits anything).
  GameSession rocketGame() {
    final s = GameSession(
      data: data,
      config: const GameConfig(mapId: 'map1', mode: 'sandbox', seed: 3),
    );
    s.debugLaunchProjectile(
      s.debugAddProjectile(
          specId: 'rocket-1',
          kind: data.projectiles['rocket-1']!.kind,
          position: const Vec2(300, 200),
          heading: 0,
          damage: 1,
          targetUid: null,
          turretUid: null,
        )
        ..state = (RocketState()
          ..holdingCapable = true
          ..holdingInitially = true),
    );
    return s;
  }

  test('the data carries the original smoke settings', () {
    final r = data.world.effects.rocketSmoke;
    // 2350-gaby's GameStatus.rocket_smoke_max (2221-nyehi: 100).
    expect([r.enabled, r.max, r.maxPrefMin, r.maxPrefMax], [true, 200, 1, 500]);
    expect(data.world.art['rocketSmoke'], 'fx.rocket-trail');
    expect(EffectSettings.of(data), const EffectSettings(rocketSmoke: true, smokeMax: 200));
  });

  testWidgets('a rocket drops one puff per engine tick, along its path', (tester) async {
    final s = rocketGame();
    final vm = FakeGameViewModel(data: data, world: SessionWorldView(s));
    final smoke = RocketSmokeLayer(
      viewModel: vm,
      frames: clip(31),
      settings: ValueNotifier(EffectSettings.of(data)),
    );
    smoke.update(0);
    expect(smoke.puffs, hasLength(1), reason: 'a puff where the rocket starts');
    final tickMs = data.projectiles['rocket-1']!.params.number('tickMs')!;
    // Six frames' worth of game time in one go (a fast speed): the puffs
    // owed are spread between the last puff and the rocket.
    for (var i = 0; i < 12; i++) {
      s.step();
    }
    smoke.update(1 / 60);
    final expected = 1 + (s.clock.nowMs / tickMs).floor();
    expect(smoke.puffs, hasLength(expected));
    final last = smoke.puffs.last;
    final rocket = s.projectiles.single.position;
    expect(last.x, closeTo(rocket.x, 1e-9));
    expect(last.y, closeTo(rocket.y, 1e-9));
    expect(smoke.puffs[1].x, isNot(closeTo(rocket.x, 0.5)));
  });

  testWidgets('the ring keeps only the newest puffs; clips end; off drops none', (tester) async {
    final s = rocketGame();
    final vm = FakeGameViewModel(data: data, world: SessionWorldView(s));
    final settings = ValueNotifier(const EffectSettings(rocketSmoke: true, smokeMax: 3));
    final smoke = RocketSmokeLayer(viewModel: vm, frames: clip(31), settings: settings);
    for (var i = 0; i < 30; i++) {
      s.step();
      smoke.update(1 / 60);
    }
    expect(smoke.puffs, hasLength(3));

    // A clip plays its 31 frames at the original's 31 fps, then goes.
    settings.value = const EffectSettings(rocketSmoke: false, smokeMax: 3);
    smoke.update(0.5);
    expect(smoke.puffs, hasLength(3), reason: 'switching off stops new puffs only');
    smoke.update(0.6);
    expect(smoke.puffs, isEmpty);
    for (var i = 0; i < 30; i++) {
      s.step();
      smoke.update(1 / 60);
    }
    expect(smoke.puffs, isEmpty);
  });

  testWidgets('no trail art, no smoke', (tester) async {
    final s = rocketGame();
    final smoke = RocketSmokeLayer(
      viewModel: FakeGameViewModel(data: data, world: SessionWorldView(s)),
      frames: const [],
      settings: ValueNotifier(EffectSettings.of(data)),
    );
    for (var i = 0; i < 10; i++) {
      s.step();
      smoke.update(1 / 60);
    }
    expect(smoke.puffs, isEmpty);
  });

  test('smoke sits over turrets and creeps, under projectiles', () {
    expect(WorldLayers.smoke, greaterThan(WorldLayers.creeps));
    expect(WorldLayers.smoke, lessThan(WorldLayers.projectiles));
  });

  test('vibration on build, move, upgrade, sell and unlock only', () {
    expect(
      hapticCueFor(const TurretBuilt(0, uid: 1, turret: 'blue', x: 0, y: 0, cost: 10, cash: 20)),
      HapticCue.medium,
    );
    expect(
      hapticCueFor(const TurretUpgraded(0, uid: 1, stat: 'damage', level: 1, cost: 20, cash: 0)),
      HapticCue.selection,
    );
    expect(hapticCueFor(const TurretSold(0, uid: 1, refund: 7, cash: 7)), HapticCue.light);
    expect(hapticCueFor(const WeaponUnlocked(0, turret: 'red', kills: 25)), HapticCue.heavy);
    expect(hapticCueFor(const PausedChanged(0, paused: true)), isNull);
  });

  test('game vibrations follow the setting', () async {
    final vm = FakeGameViewModel(data: data);
    final sink = _Recorder();
    final haptics = GameHaptics(viewModel: vm, sink: sink);
    vm.emit(const TurretSold(0, uid: 1, refund: 7, cash: 7));
    await pumpEventQueue();
    haptics.enabled = false;
    vm.emit(const TurretSold(0, uid: 1, refund: 7, cash: 7));
    await pumpEventQueue();
    expect(sink.played, [HapticCue.light]);
    await haptics.dispose();
  });

  test('a failed vibration is logged, not thrown', () async {
    final vm = FakeGameViewModel(data: data);
    final log = LogCapture.install();
    final haptics = GameHaptics(viewModel: vm, sink: _Broken());
    vm.emit(const TurretSold(0, uid: 1, refund: 7, cash: 7));
    await pumpEventQueue();
    expect(await log.records(), [
      allOf(contains('WARN  [haptics] a vibration failed'), contains('no vibrator')),
    ]);
    await haptics.dispose();
  });

  testWidgets('map turrets draw their colour badge when it is on', (tester) async {
    tester.view
      ..physicalSize = const ui.Size(923, 411)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = GameSession(
      data: data,
      config: const GameConfig(mapId: 'map1', mode: 'sandbox2'),
    );
    for (final id in data.turrets.keys) {
      s.debugMakeAvailable(id);
    }
    // A colour turret and a modifier wherever the placement rules allow.
    final spots = [
      for (var y = 40.0; y < 440; y += 40)
        for (var x = 40.0; x < 680; x += 40)
          if (s.placementIssueAt(Vec2(x, y)) == null) Vec2(x, y),
    ];
    s
      ..enqueue(BuildTurret('red', spots.first.x, spots.first.y))
      ..enqueue(BuildTurret('range-up', spots.last.x, spots.last.y))
      ..step();
    expect(s.turrets, hasLength(2));
    final effects = ValueNotifier(EffectSettings.of(data));
    final game = OnslaughtFlameGame(
      viewModel: FakeGameViewModel(data: data, world: SessionWorldView(s)),
      pack: EmptyAssetPack(),
      driveSimulation: false,
      effects: effects,
    )..locale = 'en';
    await tester.pumpWidget(GameWidget(game: game));
    await tester.pump();
    effects.value = const EffectSettings(rocketSmoke: true, smokeMax: 100, colourBadges: true);
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    final layer = game.world.children.whereType<EntityLayer>().single;
    expect(layer.locale, 'en');
    expect(layer.children.whereType<TurretView>(), hasLength(2));
  });

  testWidgets('in a running game, flying rockets leave smoke', (tester) async {
    tester.view
      ..physicalSize = const ui.Size(923, 411)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = rocketGame();
    final game = OnslaughtFlameGame(
      viewModel: FakeGameViewModel(data: data, world: SessionWorldView(s)),
      pack: _TrailPack(),
      driveSimulation: false,
    );
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 4, 4), ui.Paint());
    game.images.add('trail.png', recorder.endRecording().toImageSync(4, 4));
    await tester.pumpWidget(GameWidget(game: game));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      s.step();
      await tester.pump(const Duration(milliseconds: 16));
    }
    final layer = game.world.children.whereType<EntityLayer>().single;
    final smoke = layer.children.whereType<RocketSmokeLayer>().single;
    expect(smoke.frames, hasLength(31));
    expect(smoke.puffs, isNotEmpty);
  });
}
