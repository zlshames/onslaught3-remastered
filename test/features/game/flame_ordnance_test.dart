import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/features/game/flame/entity_layer.dart';
import 'package:onslaught3_remastered/features/game/flame/onslaught_flame_game.dart';
import 'package:onslaught3_remastered/features/game/flame/ordnance_views.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../support/fake_game_view_model.dart';
import '../../support/fakes.dart';
import '../../support/test_data.dart';

/// Phase 3 views: one Flame component per blast, walker and black hole,
/// dropped when the entity is gone.
void main() {
  late GameData data;
  setUpAll(() => data = loadTestGameData());

  testWidgets('blasts, walkers and black holes get their views', (tester) async {
    tester.view
      ..physicalSize = const Size(923, 411)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = GameSession(
      data: data,
      config: const GameConfig(mapId: 'map9'),
    );
    s.enqueue(const SendNextWave());
    while (s.creeps.isEmpty) {
      s.step();
    }
    final creep = s.creeps.first;
    s.debugSpawnBlast(
      specId: 'blast-shockwave',
      at: creep.position,
      damage: 1,
      poison: 1,
      turretUid: null,
      targetUid: creep.uid,
    );
    final hole =
        s.debugAddProjectile(
            specId: 'black-hole',
            kind: 'black-hole',
            position: Vec2.zero,
            heading: 0,
            damage: 0,
            targetUid: null,
            turretUid: null,
          )
          ..load = Ordnance(
            combo: 'blackhole',
            place: const Vec2(400, 300),
            hole: const HoleLoad(radius: 120, durationMs: 3000),
          );
    s.debugLaunchProjectile(hole);
    final vm = FakeGameViewModel(data: data, mapId: 'map9', world: SessionWorldView(s));
    final game = OnslaughtFlameGame(viewModel: vm, pack: EmptyAssetPack(), driveSimulation: false);
    await tester.pumpWidget(GameWidget(game: game));
    await tester.pump();
    await tester.pump();
    final layer = game.world.children.whereType<EntityLayer>().single;
    expect(layer.children.whereType<BlastView>(), hasLength(1));
    expect(layer.children.whereType<WalkerView>(), hasLength(s.walkers.length));
    expect(layer.children.whereType<BlackHoleView>(), hasLength(1));

    s.blasts.single.done = true;
    for (final w in s.walkers) {
      w.done = true;
    }
    s.debugRemoveFinished();
    await tester.pump();
    await tester.pump();
    expect(layer.children.whereType<BlastView>(), isEmpty);
    expect(layer.children.whereType<WalkerView>(), isEmpty);
  });

  test('pulled entities shrink to a quarter', () {
    final shrink = data.projectiles['black-hole']!.art!.fx.number('captureShrink')! / 100;
    expect(captureScale(null, shrink), 1);
    final c = Capture(hole: 1, from: Vec2.zero, to: const Vec2(10, 0), durationMs: 100)
      ..elapsedMs = 100;
    expect(captureScale(c, shrink), 0.25);
  });
}
