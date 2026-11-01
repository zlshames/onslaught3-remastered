import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:onslaught_core/onslaught_core.dart';

import 'art_resolver.dart';
import 'entity_layer.dart';

/// Scale of a creep, projectile or blast being pulled into a black hole:
/// it loses [shrink] (0…1, the black hole's `art.fx` `captureShrink` %,
/// 75 % in the original) over the pull (`OnslaughtObject.as:blackHoled`).
double captureScale(Capture? c, double shrink) => c == null ? 1 : 1 - shrink * c.t;

/// A blast (`BlastEngine`): its sprite drawn [Blast.size] px across and
/// faded by [Blast.alpha]. The napalm spawner keeps its 10 px start size
/// (its sprite never grows); clusters are instant and draw nothing. The
/// shockwave also throws its 15 decorative sparks (`BlastShockwave.blastSpark`:
/// colour 0x9999FF, one every 100–799 ms, fading by count; the blast's
/// `art.fx` timings) — cosmetic, with their own randomness.
class BlastView extends PositionComponent {
  BlastView(this.blast, this.layer) : super(priority: WorldLayers.projectiles - 1);

  final Blast blast;
  final EntityLayer layer;
  SpriteComponent? _sprite;
  double _frameWidth = 1;
  late final bool _shockwave;
  final math.Random _sparkRandom = math.Random();
  final List<_DecorSpark> _sparks = [];
  double _nextSparkS = 0;
  double _ageS = 0;
  int _sparkTotal = 0;
  int _sparkDelayMinMs = 0;
  int _sparkDelayRangeMs = 0;
  double _sparkFadeS = 0;

  static const double _napalmSize = 10;

  @override
  Future<void> onLoad() async {
    final spec = layer.viewModel.data.blasts[blast.specId];
    _shockwave = spec?.kind == 'shockwave';
    _sparkTotal = (spec?.params.number('decorativeSparks') ?? 0).toInt();
    final fx = spec?.art?.fx ?? Params.empty;
    _sparkDelayMinMs = (fx.number('sparkDelayMinMs') ?? 0).toInt();
    _sparkDelayRangeMs = (fx.number('sparkDelayRangeMs') ?? 1).toInt();
    _sparkFadeS = (fx.number('sparkFadeMs') ?? 0) / 1000;
    final frames = layer.framesOf(spec?.sprite);
    if (frames.isNotEmpty && !(spec?.kind.startsWith('cluster-') ?? true)) {
      _frameWidth = frames.first.size.x;
      _sprite = frames.first.toComponent(position: Vector2.zero());
      await add(_sprite!);
    }
    _copy();
  }

  @override
  void update(double dt) {
    _copy();
    if (_shockwave) _decorate(dt);
    super.update(dt);
  }

  void _copy() {
    position.setValues(blast.position.x, blast.position.y);
    final sprite = _sprite;
    if (sprite == null) return;
    final size = blast.kind == 'napalm' ? _napalmSize : blast.size;
    sprite
      ..scale = Vector2.all(size / _frameWidth * captureScale(blast.capture, layer.captureShrink))
      ..opacity = blast.alpha.clamp(0, 1);
  }

  void _decorate(double dt) {
    _ageS += dt;
    final total = _sparkTotal;
    if (_sparks.length < total && _ageS >= _nextSparkS) {
      final reach = blast.size / 4;
      _sparks.add(
        _DecorSpark(
          to: Offset(
            _sparkRandom.nextDouble() * reach * 2 - reach,
            _sparkRandom.nextDouble() * reach * 2 - reach,
          ),
          alpha: 1 - _sparks.length / total,
          bornS: _ageS,
        ),
      );
      _nextSparkS = _ageS + (_sparkDelayMinMs + _sparkRandom.nextInt(_sparkDelayRangeMs)) / 1000;
    }
  }

  static final Paint _sparkPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2
    ..strokeCap = StrokeCap.round;

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    for (final s in _sparks) {
      final fade = _sparkFadeS <= 0 ? 0.0 : 1 - (_ageS - s.bornS) / _sparkFadeS;
      if (fade <= 0) continue;
      _sparkPaint.color = const Color(0xFF9999FF).withValues(alpha: s.alpha * fade);
      canvas.drawLine(Offset.zero, s.to, _sparkPaint);
    }
  }
}

class _DecorSpark {
  _DecorSpark({required this.to, required this.alpha, required this.bornS});
  final Offset to;
  final double alpha;
  final double bornS;
}

/// A shockwave walker (`Shockwave`): at each of its zaps a short spark
/// across it (colour 0x55FF55, white glow, alpha `f × 100 + 10`), redrawn
/// with fresh jitter.
class WalkerView extends PositionComponent {
  WalkerView(this.walker, this.layer) : super(priority: WorldLayers.projectiles);

  final ShockwaveWalker walker;
  final EntityLayer layer;
  final math.Random _jitter = math.Random();
  int _zaps = -1;
  List<Offset> _points = const [];

  static final Paint _core = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  static final Paint _glow = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 8
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

  @override
  void update(double dt) {
    position.setValues(walker.position.x, walker.position.y);
    if (walker.zaps != _zaps) {
      _zaps = walker.zaps;
      final across = degToRad(walker.heading + 90);
      final half =
          (layer.viewModel.data.blasts[walker.specId]?.params.number('walkerHitBox') ?? 10);
      _points = [
        for (var i = 0; i <= 4; i++)
          Offset(
            math.cos(across) * half * (i / 2 - 1) + _jitter.nextDouble() * 4 - 2,
            math.sin(across) * half * (i / 2 - 1) + _jitter.nextDouble() * 4 - 2,
          ),
      ];
    }
    super.update(dt);
  }

  @override
  void render(Canvas canvas) {
    if (_points.length < 2) return;
    final duration =
        layer.viewModel.data.blasts[walker.specId]?.params.number('walkerDurationMs') ?? 1;
    final f = (1 - (layer.viewModel.world.nowMs - walker.startedAtMs) / duration).clamp(0.0, 1.0);
    final alpha = (f * 100 + 10).clamp(0, 100) / 100;
    final path = Path()..moveTo(_points.first.dx, _points.first.dy);
    for (final p in _points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    _glow.color = const Color(0xFFFFFFFF).withValues(alpha: alpha * 0.5);
    _core.color = const Color(0xFF55FF55).withValues(alpha: alpha);
    canvas
      ..drawPath(path, _glow)
      ..drawPath(path, _core);
  }
}

/// A black hole (`BlackHole`): it opens (scale and alpha 0 → 100 %) and
/// closes (back to 0) over its tweens, its swirl turns 29° a frame, and a
/// piece of debris falls into the core every frame from up to half its
/// radius out (`BlackHoleDebris`, 100 ms; both the projectile's `art.fx`).
/// Cosmetic randomness only.
class BlackHoleView extends PositionComponent {
  BlackHoleView(this.hole, this.layer) : super(priority: WorldLayers.projectiles - 1);

  final Projectile hole;
  final EntityLayer layer;
  SpriteComponent? _sprite;
  ResolvedFrame? _debris;
  final math.Random _random = math.Random();
  final List<_Debris> _falling = [];
  Params _params = Params.empty;
  double _swirlRadPerFrame = 0;
  double _debrisFallS = 0;

  static const String debrisArt = 'fx.black-hole-debris';

  @override
  Future<void> onLoad() async {
    final spec = layer.viewModel.data.projectiles[hole.specId];
    _params = spec?.params ?? Params.empty;
    final fx = spec?.art?.fx ?? Params.empty;
    _swirlRadPerFrame = degToRad(fx.number('swirlDegPerFrame') ?? 0);
    _debrisFallS = (fx.number('debrisFallMs') ?? 0) / 1000;
    final frames = layer.framesOf(spec?.sprite);
    if (frames.isNotEmpty) {
      _sprite = frames.first.toComponent(position: Vector2.zero());
      await add(_sprite!);
    }
    final debris = layer.framesOf(debrisArt);
    _debris = debris.isEmpty ? null : debris.first;
    _copy(0);
  }

  @override
  void update(double dt) {
    _copy(dt);
    super.update(dt);
  }

  void _copy(double dt) {
    position.setValues(hole.position.x, hole.position.y);
    final params = _params;
    final st = hole.state is BlackHoleState ? hole.state! as BlackHoleState : null;
    final open = switch (st?.stage) {
      BlackHoleStage.opening => (st!.stageMs / (params.number('openMs') ?? 1)).clamp(0.0, 1.0),
      BlackHoleStage.closing => 1 - (st!.stageMs / (params.number('closeMs') ?? 1)).clamp(0.0, 1.0),
      _ => 1.0,
    };
    final sprite = _sprite;
    if (sprite != null) {
      sprite
        ..scale = Vector2.all(open)
        ..opacity = open
        ..angle += _swirlRadPerFrame * dt * clipFps;
    }
    final radius = hole.load?.hole?.radius ?? 0;
    for (final d in _falling) {
      d.t = _debrisFallS <= 0 ? 1 : d.t + dt / _debrisFallS;
    }
    _falling.removeWhere((d) => d.t >= 1);
    if (dt > 0 && _debris != null && open > 0) {
      final half = radius / 2;
      _falling.add(
        _Debris(
          from: Offset(
            (_random.nextDouble() * radius - half).floorToDouble(),
            (_random.nextDouble() * radius - half).floorToDouble(),
          ),
        ),
      );
    }
  }

  @override
  void render(Canvas canvas) {
    final debris = _debris;
    if (debris != null) {
      for (final d in _falling) {
        final at = d.from * (1 - d.t);
        canvas
          ..save()
          ..translate(at.dx, at.dy)
          ..rotate(math.atan2(-d.from.dy, -d.from.dx));
        debris.sprite.render(canvas, size: debris.size, anchor: debris.anchor);
        canvas.restore();
      }
    }
    super.render(canvas);
  }
}

class _Debris {
  _Debris({required this.from});
  final Offset from;
  double t = 0;
}

/// A one-shot clip on a turret: `SpecialFire` on a combo's leader (turned
/// with its weapon), `SpecialTake` on each helper it took.
class ComboSign extends SpriteAnimationComponent {
  ComboSign(List<ResolvedFrame> frames, {double angle = 0})
    : super(
        animation: SpriteAnimation.spriteList(
          [for (final f in frames) f.sprite],
          stepTime: 1 / clipFps,
          loop: false,
        ),
        size: frames.first.size,
        anchor: frames.first.anchor,
        angle: angle,
        priority: 2,
        removeOnFinish: true,
      );
}
