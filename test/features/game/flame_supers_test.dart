import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/features/game/flame/entity_layer.dart';
import 'package:onslaught3_remastered/features/game/flame/instant_shot_view.dart';
import 'package:onslaught3_remastered/features/game/flame/onslaught_flame_game.dart';
import 'package:onslaught3_remastered/features/game/flame/super_views.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../support/fake_game_view_model.dart';
import '../../support/fakes.dart';
import '../../support/test_data.dart';

/// Phase 4 views: rail beams, sniper tracers, the Targeter overlay, Fusion
/// glows and the Combonly plate.
void main() {
  late GameData data;
  setUpAll(() => data = loadTestGameData());

  testWidgets('rail beams and sniper tracers get their views; plates and fusions theirs', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(923, 411)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = GameSession(
      data: data,
      config: const GameConfig(mapId: 'map9', mode: 'sandbox2'),
    );
    for (final (id, at) in [
      ('railgun', const Vec2(300, 150)),
      ('sniper', const Vec2(420, 200)),
      ('fusion', const Vec2(330, 90)),
      ('combonly', const Vec2(200, 300)),
      ('targeter', const Vec2(500, 60)),
    ]) {
      s.enqueue(BuildTurret(id, at.x, at.y));
    }
    s.enqueue(const SendNextWave());
    while (s.creeps.isEmpty) {
      s.step();
    }
    final creep = s.creeps.first..hp = 1e12;
    final rail = s.turrets.firstWhere((t) => t.def.id == 'railgun');
    final sniper = s.turrets.firstWhere((t) => t.def.id == 'sniper');
    s
      ..debugTurretFire(rail, target: creep, damage: 4e6)
      ..debugTurretFire(sniper, target: creep, damage: 3e6);
    final vm = FakeGameViewModel(data: data, mapId: 'map9', world: SessionWorldView(s));
    final game = OnslaughtFlameGame(viewModel: vm, pack: EmptyAssetPack(), driveSimulation: false);
    await tester.pumpWidget(GameWidget(game: game));
    await tester.pump();
    await tester.pump();
    final layer = game.world.children.whereType<EntityLayer>().single;
    expect(layer.children.whereType<RailBeamView>(), hasLength(1));
    expect(layer.children.whereType<SniperTracerView>(), hasLength(1));
    expect(layer.children.whereType<TargeterOverlay>(), hasLength(1));
    final turretViews = layer.children.whereType<TurretView>().toList();
    expect(turretViews.expand((v) => v.children.whereType<FusionGlowView>()), hasLength(1));
    expect(turretViews.expand((v) => v.children.whereType<CombonlyPlateView>()), hasLength(1));
    expect(layer.children.whereType<InstantShotView>(), isEmpty);
  });

  test('rail colour tiers (RailLaser.railGetType)', () {
    List<int> railColoursAt(double damage) =>
        railColours(data.projectiles['rail-laser']!.art, damage);
    expect(railColoursAt(4e6), [0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0x33CC33]);
    expect(railColoursAt(9e6).where((c) => c == 0x33CC33), hasLength(2));
    expect(railColoursAt(15e6).where((c) => c == 0x33CC33), hasLength(3));
    expect(railColoursAt(25e6).last, 0xFF3333);
    expect(railColoursAt(26e6).last, 0xFF33FF);
  });

  test('spark tiers reach the Fusion cannon\'s discharges', () {
    ShotStyle sparkStyle(double damage) => shotStyle(data.projectiles['spark']!.art, damage);
    expect(sparkStyle(25).width, 1);
    expect(sparkStyle(60).width, 6);
    expect(sparkStyle(2.5e6).glow, 0x9999FF);
    expect(sparkStyle(3.5e6).glow, 0xFF99FF, reason: 'the shadowed 2M–4M band');
    expect(sparkStyle(35e6), (core: 0x3333CC, glow: 0xFFFFFF, width: 8, glowSize: 8));
    expect(sparkStyle(2e8).width, 32);
  });

  test('laser tiers (LaserEngine.laserGetType) include their upper bound', () {
    ShotStyle laserStyle(double damage) => shotStyle(data.projectiles['laser-beam']!.art, damage);
    expect(laserStyle(49.999), (core: 0x00FF00, glow: 0x00FF00, width: 1, glowSize: 5));
    expect(laserStyle(50).glow, 0xFF0000);
    expect(laserStyle(8000000), (core: 0x333333, glow: 0x00FF00, width: 10, glowSize: 5));
    expect(laserStyle(8000001), (core: 0xFFFFFF, glow: 0xAA0000, width: 10, glowSize: 8));
  });

  test('fusion glow sizes by stored damage', () {
    final p = data.turrets['fusion']!.specialParams['fusion'];
    List<double>? sizes(double units, {bool pulse = true}) => FusionGlowView.glowSizes(
      p,
      FusionState(null)
        ..storeDamage = units * 500000
        ..pulse = pulse,
    );
    expect(sizes(0), [0, 0, 0]);
    expect(sizes(0.5), isNull);
    expect(sizes(10), [10, 0, 0]);
    expect(sizes(90), [80, 10, 0]);
    expect(sizes(170), [80, 80, 10]);
    expect(sizes(300), [80, 80, 80]);
    expect(sizes(300, pulse: false)!.first, closeTo(88, 1e-9));
  });

  test('plate tints (TurretCombonly.update)', () {
    expect(combonlyTint(data, 'red'), 0xFF0000);
    expect(combonlyTint(data, 'green'), 0x01BA01);
    expect(combonlyTint(data, 'blue'), 0x0000FF);
    expect(combonlyTint(data, 'yellow'), 0xFFCC00);
  });
}
