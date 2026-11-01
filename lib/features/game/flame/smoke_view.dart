import 'dart:collection';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';

import '../effect_settings.dart';
import '../game_view_model.dart';
import 'art_resolver.dart';
import 'entity_layer.dart';

/// Rocket smoke (`SmokeManager.rocketSmoke`): every rocket-engine projectile
/// drops one trail clip where it is on each of its engine ticks (`tickMs`
/// of game time); a clip plays its frames once at the original's frame rate
/// and goes. Only the newest [EffectSettings.smokeMax] clips are kept (the
/// manager's ring of depths), and none are dropped while smoke is off.
///
/// Drawn above turrets and creeps and under the projectiles, as the smoke
/// manager is attached after the turret manager and before the bullet
/// manager (`GameManager.gameInit`). All puffs are drawn by this one
/// component, so a full ring costs one draw call per puff and no
/// components.
class RocketSmokeLayer extends Component {
  RocketSmokeLayer({required this.viewModel, required this.frames, required this.settings})
    : _clipS = frames.length / clipFps,
      super(priority: WorldLayers.smoke);

  final GameViewModel viewModel;

  /// The trail clip's frames (`world.art.rocketSmoke`); none = no smoke.
  final List<ResolvedFrame> frames;
  final ValueListenable<EffectSettings> settings;

  /// Engine kind whose projectiles smoke (`RocketEngine.update`).
  static const String rocketKind = 'rocket';

  final ListQueue<_Puff> _puffs = ListQueue();
  final Map<int, _Trail> _trails = {};
  final double _clipS;

  /// Puffs alive now, oldest first (tests).
  List<({double x, double y})> get puffs => [for (final p in _puffs) (x: p.x, y: p.y)];

  @override
  void update(double dt) {
    super.update(dt);
    for (final p in _puffs) {
      p.age += dt;
    }
    while (_puffs.isNotEmpty && _puffs.first.age >= _clipS) {
      _puffs.removeFirst();
    }
    final world = viewModel.world;
    final s = settings.value;
    if (!s.rocketSmoke || frames.isEmpty) {
      _trails.clear();
      return;
    }
    final now = world.nowMs;
    final live = <int>{};
    for (final p in world.projectiles) {
      if (p.kind != rocketKind) continue;
      live.add(p.uid);
      final trail = _trails[p.uid];
      if (trail == null) {
        final params = viewModel.data.projectiles[p.specId]?.params;
        _trails[p.uid] = _Trail(
          tickMs: params?.number('tickMs') ?? 0,
          lastMs: now,
          lastX: p.position.x,
          lastY: p.position.y,
        );
        _drop(p.position.x, p.position.y, s.smokeMax);
        continue;
      }
      if (trail.tickMs <= 0) continue;
      final ticks = ((now - trail.lastMs) / trail.tickMs).floor();
      if (ticks <= 0) continue;
      // When several engine ticks pass in one frame (fast speeds), spread
      // their puffs along the path flown since the last one.
      for (var i = 1; i <= ticks; i++) {
        final f = i / ticks;
        _drop(
          trail.lastX + (p.position.x - trail.lastX) * f,
          trail.lastY + (p.position.y - trail.lastY) * f,
          s.smokeMax,
        );
      }
      trail
        ..lastMs += ticks * trail.tickMs
        ..lastX = p.position.x
        ..lastY = p.position.y;
    }
    _trails.removeWhere((uid, _) => !live.contains(uid));
  }

  void _drop(double x, double y, int max) {
    _puffs.addLast(_Puff(x, y));
    while (_puffs.length > max) {
      _puffs.removeFirst();
    }
  }

  final Vector2 _at = Vector2.zero();

  @override
  void render(Canvas canvas) {
    if (frames.isEmpty) return;
    for (final p in _puffs) {
      final f = frames[(p.age * clipFps).floor().clamp(0, frames.length - 1)];
      f.sprite.render(canvas, position: _at..setValues(p.x, p.y), size: f.size, anchor: f.anchor);
    }
  }
}

class _Puff {
  _Puff(this.x, this.y);
  final double x;
  final double y;
  double age = 0;
}

class _Trail {
  _Trail({required this.tickMs, required this.lastMs, required this.lastX, required this.lastY});
  final double tickMs;
  double lastMs;
  double lastX;
  double lastY;
}
