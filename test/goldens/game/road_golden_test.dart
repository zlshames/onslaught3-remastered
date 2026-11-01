import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter/material.dart';
import 'package:onslaught3_remastered/features/game/flame/road_component.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../support/test_data.dart';

/// Road-render goldens: every built-in map drawn by [RoadComponent] over the
/// 720×480 play area at 1 world px per pixel (golden-tests skill).
void main() {
  final GameData data = loadTestGameData();

  for (final map in data.maps.values) {
    testGolden(
      'road ${map.id}',
      (game, tester) async {
        game.camera.viewfinder.anchor = Anchor.topLeft;
        await game.world.addAll([
          RectangleComponent(
            size: Vector2(data.world.playWidth, data.world.playHeight),
            paint: Paint()..color = const Color(0xFFE8C9A0),
          ),
          RoadComponent(road: map.road, style: data.world.road),
          CircleComponent(
            radius: 6,
            position: Vector2(map.base.x, map.base.y),
            anchor: Anchor.center,
            paint: Paint()..color = const Color(0xFF2E7D32),
          ),
        ]);
      },
      game: FlameGame(),
      size: Vector2(data.world.playWidth, data.world.playHeight),
      goldenFile: 'goldens/road_${map.id}.png',
    );
  }
}
