import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:onslaught_core/onslaught_core.dart';

import 'entity_layer.dart';

/// The look of a beam or spark: core line colour and width, glow colour and
/// glow size (the original's `GlowFilter` around the line).
typedef ShotStyle = ({int core, int glow, double width, double glowSize});

/// The look of a beam or spark of [damage]: the band of the projectile's
/// `art` that covers it (`LaserEngine.laserGetType`,
/// `SparkEngine.sparkGetType`, in `projectiles.json`). Without art data
/// it is a plain 1 px white line.
ShotStyle shotStyle(EffectArt? art, double damage) {
  final band = art?.bandFor(damage);
  return (
    core: band?.core ?? 0xFFFFFF,
    glow: band?.glow ?? 0xFFFFFF,
    width: band?.width ?? 1,
    glowSize: band?.glowSize ?? 0,
  );
}

/// A laser beam or spark: a line from where it was fired to where it hit,
/// fading out over its `fadeMs` of game time (pausable, as the original's
/// fade effect). Sparks are jagged: `max(3, floor(d / 11)) + U{0..5}`
/// segments with vertices jittered ±5.5 px, the last one (to the target)
/// not drawn (`SparkEngine.sparkDraw`). The jitter is cosmetic, seeded by
/// the projectile's uid so a frame redraw does not flicker.
class InstantShotView extends PositionComponent {
  InstantShotView(this.projectile, this.layer) : super(priority: WorldLayers.projectiles);

  final Projectile projectile;
  final EntityLayer layer;
  late final double _fadeMs;
  late final double _startAlpha;
  late final ShotStyle _style;
  late final bool _jagged;
  List<Offset> _points = const [];

  final Paint _core = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final Paint _glow = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  @override
  Future<void> onLoad() async {
    final spec = layer.viewModel.data.projectiles[projectile.specId];
    final params = spec?.params ?? Params.empty;
    _jagged = spec?.kind == 'spark';
    _fadeMs = params.number('fadeMs') ?? 0;
    _startAlpha = (params.number('startAlpha') ?? params.number('alpha') ?? 100) / 100;
    _style = shotStyle(spec?.art, projectile.damage);
    position.setValues(projectile.position.x, projectile.position.y);
    final to = projectile.lineTo;
    if (to == null) return;
    final d = to - projectile.position;
    _points = _jagged ? _sparkPoints(d, params) : [Offset.zero, Offset(d.x, d.y)];
  }

  List<Offset> _sparkPoints(Vec2 d, Params params) {
    final random = math.Random(projectile.uid);
    final segment = params.number('segmentLength') ?? 11;
    final minSegments = (params.number('minSegments') ?? 3).toInt();
    final extra = (params.number('extraSegmentsMax') ?? 5).toInt();
    final jitter = params.number('jitter') ?? 5.5;
    final base = math.max(minSegments, (d.length / segment).floor());
    final n = base + random.nextInt(extra + 1);
    return [
      Offset.zero,
      for (var i = 1; i < n; i++)
        Offset(
          d.x * i / n + random.nextDouble() * jitter * 2 - jitter,
          d.y * i / n + random.nextDouble() * jitter * 2 - jitter,
        ),
    ];
  }

  @override
  void render(Canvas canvas) {
    if (_points.length < 2) return;
    final age = layer.viewModel.world.nowMs - projectile.createdAtMs;
    final fade = _fadeMs <= 0 ? 1.0 : (1 - age / _fadeMs).clamp(0.0, 1.0);
    final alpha = _startAlpha * fade;
    if (alpha <= 0) return;
    final path = Path()..moveTo(_points.first.dx, _points.first.dy);
    for (final p in _points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    _glow
      ..color = Color(0xFF000000 | _style.glow).withValues(alpha: alpha * 0.6)
      ..strokeWidth = _style.width + _style.glowSize
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, _style.glowSize / 2);
    _core
      ..color = Color(0xFF000000 | _style.core).withValues(alpha: alpha)
      ..strokeWidth = _style.width;
    canvas
      ..drawPath(path, _glow)
      ..drawPath(path, _core);
  }
}
