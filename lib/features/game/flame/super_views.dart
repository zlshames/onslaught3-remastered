import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:onslaught_core/onslaught_core.dart';

import 'art_resolver.dart';
import 'entity_layer.dart';

/// The colours of the Railgun's strokes (widest first) for [damage]: the
/// band of the projectile's `art` that covers it (`RailLaser.railGetType`,
/// in `projectiles.json`).
List<int> railColours(EffectArt? art, double damage) => art?.bandFor(damage)?.strokes ?? const [];

/// The Railgun's beam: five round-capped strokes from the fire point to the
/// end of its 900 px line, until the projectile is removed (125 ms), their
/// widths and alphas the projectile's `art.fx` `strokeWidths` and
/// `strokeAlphas` (%).
class RailBeamView extends PositionComponent {
  RailBeamView(this.projectile, this.layer) : super(priority: WorldLayers.projectiles);

  final Projectile projectile;
  final EntityLayer layer;
  final Paint _paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  List<int> _colours = const [];
  List<double> _widths = const [];
  List<double> _alphas = const [];

  @override
  Future<void> onLoad() async {
    position.setValues(projectile.position.x, projectile.position.y);
    final art = layer.viewModel.data.projectiles[projectile.specId]?.art;
    _colours = railColours(art, projectile.damage);
    _widths = art?.fx.numbers('strokeWidths') ?? const [];
    _alphas = [for (final a in art?.fx.numbers('strokeAlphas') ?? const <double>[]) a / 100];
  }

  @override
  void render(Canvas canvas) {
    final to = projectile.lineTo;
    if (to == null) return;
    final end = Offset(to.x - projectile.position.x, to.y - projectile.position.y);
    final n = math.min(_colours.length, math.min(_widths.length, _alphas.length));
    for (var i = 0; i < n; i++) {
      _paint
        ..color = Color(0xFF000000 | _colours[i]).withValues(alpha: _alphas[i])
        ..strokeWidth = _widths[i];
      canvas.drawLine(Offset.zero, end, _paint);
    }
  }
}

/// The Sniper's tracer (`BulletSniper.onLoad`): a 1 px line, colour 0x777733
/// at 75 %, along a random stretch of the way to the target, from `a·d` to
/// `(a + b)·d` with `a = U(0, 0.5)` and `b = U(0, 0.5) + 0.1`. Cosmetic,
/// seeded by the projectile's uid.
class SniperTracerView extends PositionComponent {
  SniperTracerView(this.projectile, this.layer) : super(priority: WorldLayers.projectiles);

  final Projectile projectile;
  final EntityLayer layer;
  Offset _from = Offset.zero;
  Offset _to = Offset.zero;
  final Paint _paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;

  @override
  Future<void> onLoad() async {
    position.setValues(projectile.position.x, projectile.position.y);
    final params = layer.viewModel.data.projectiles[projectile.specId]?.params ?? Params.empty;
    final colour = int.tryParse(
      (params.string('tracerColor') ?? '#777733').substring(1),
      radix: 16,
    );
    _paint.color = Color(0xFF000000 | (colour ?? 0x777733))
        .withValues(alpha: (params.number('tracerAlpha') ?? 75) / 100);
    final to = projectile.lineTo;
    if (to == null) return;
    final d = Offset(to.x - projectile.position.x, to.y - projectile.position.y);
    final random = math.Random(projectile.uid);
    final a = random.nextDouble() / 2;
    final b = random.nextDouble() / 2 + 0.1;
    _from = d * a;
    _to = d * (a + b);
  }

  @override
  void render(Canvas canvas) {
    if (projectile.lineTo == null) return;
    canvas.drawLine(_from, _to, _paint);
  }
}

/// A spent Sniper casing (`TurretSniper.brassFire`, `BarrattBrass`): thrown
/// in `brassMs` from the weapon's BrassPoint to its BrassPointTo ± `brassJitter`
/// px, spinning `brassSpin` + U(0, `brassSpin`)°, then after `brassFadeAfterMs`
/// it fades out over `brassFadeMs` (real time). Drawn in its turret's
/// coordinates, under the weapon.
class BrassView extends PositionComponent {
  BrassView({
    required this.frame,
    required this.from,
    required this.to,
    required this.spinDeg,
    required this.throwS,
    required this.fadeAfterS,
    required this.fadeS,
  }) : super(position: Vector2(from.dx, from.dy), priority: -1);

  final ResolvedFrame frame;
  final Offset from;
  final Offset to;
  final double spinDeg;
  final double throwS;
  final double fadeAfterS;
  final double fadeS;
  late final SpriteComponent _sprite;
  double _age = 0;

  @override
  Future<void> onLoad() async {
    _sprite = frame.toComponent(position: Vector2.zero());
    await add(_sprite);
  }

  @override
  void update(double dt) {
    _age += dt;
    final t = throwS <= 0 ? 1.0 : (_age / throwS).clamp(0.0, 1.0);
    final p = Offset.lerp(from, to, t)!;
    position.setValues(p.dx, p.dy);
    angle = degToRad(spinDeg * t);
    if (_age > fadeAfterS) {
      final f = fadeS <= 0 ? 0.0 : 1 - (_age - fadeAfterS) / fadeS;
      if (f <= 0) {
        removeFromParent();
      } else {
        _sprite.opacity = f;
      }
    }
    super.update(dt);
  }
}

/// The Targeters' beams (`TurretTargeter.targetPaint`: 1 px 0xFF4444 at
/// 60 % with a glow, from the beacon's fire point to the painted creep) and
/// the join lines of the selected Targeter or the one being joined
/// (`joinShow`: 5 px 0xFF9900 at 20 % with a glow), with a ring on each
/// joined turret while joining.
class TargeterOverlay extends Component {
  TargeterOverlay(this.layer) : super(priority: WorldLayers.overlay - 1);

  final EntityLayer layer;

  static final Paint _beam = Paint()
    ..color = const Color(0x99FF4444)
    ..strokeWidth = 1;
  static final Paint _beamGlow = Paint()
    ..color = const Color(0x66FF4444)
    ..strokeWidth = 4
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
  static final Paint _join = Paint()
    ..color = const Color(0x33FF9900)
    ..strokeWidth = 5
    ..strokeCap = StrokeCap.round;
  static final Paint _joinGlow = Paint()
    ..color = const Color(0x44FF9900)
    ..strokeWidth = 9
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
  static final Paint _ring = Paint()
    ..color = const Color(0xCCFF9900)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;

  @override
  void render(Canvas canvas) {
    final vm = layer.viewModel;
    final world = vm.world;
    final shown = {vm.selection.value?.uid, vm.joining.value};
    final creeps = {for (final c in world.creeps) c.uid: c};
    final turrets = {for (final t in world.turrets) t.uid: t};
    for (final t in world.turrets) {
      final state = t.specialState[TargeterSpecial.specialId];
      if (state is! TargeterState) continue;
      final painted = state.painted == null ? null : creeps[state.painted];
      if (painted != null) {
        final points = t.def.firePoints;
        final from = t.position + rotateVec(points.isEmpty ? Vec2.zero : points.first, t.rotation);
        final a = Offset(from.x, from.y);
        final b = Offset(painted.position.x, painted.position.y);
        canvas
          ..drawLine(a, b, _beamGlow)
          ..drawLine(a, b, _beam);
      }
      if (!shown.contains(t.uid)) continue;
      final joining = vm.joining.value == t.uid;
      for (final uid in state.joins) {
        final j = turrets[uid];
        if (j == null) continue;
        final a = Offset(t.position.x, t.position.y);
        final b = Offset(j.position.x, j.position.y);
        canvas
          ..drawLine(a, b, _joinGlow)
          ..drawLine(a, b, _join);
        if (joining) canvas.drawCircle(b, vm.data.world.placement.turretSpacing / 2, _ring);
      }
    }
  }
}

/// The Fusion cannon's glow (`fusionSetGlow`): white, blue and red glow
/// clips sized by the stored damage. With `u = floor(store / glowUnit)` and
/// `m = u mod glowTierSize`: hidden at an empty store; white `m` px below
/// one tier; white full and blue `m` in the second; plus red `m` in the
/// third; all full above. The white one is drawn `glowPulse` × larger on
/// alternate updates. A store under one unit keeps the last look.
class FusionGlowView extends PositionComponent {
  FusionGlowView({required this.turret, required this.layer}) : super(priority: 2);

  final Turret turret;
  final EntityLayer layer;
  final List<SpriteComponent?> _glows = [null, null, null];
  final List<double> _frameWidths = [1, 1, 1];

  static const List<String> art = [
    'fx.fusion-glow-white',
    'fx.fusion-glow-blue',
    'fx.fusion-glow-red',
  ];

  @override
  Future<void> onLoad() async {
    for (var i = 0; i < art.length; i++) {
      final frames = layer.framesOf(art[i]);
      if (frames.isEmpty) continue;
      _frameWidths[i] = frames.first.size.x;
      final s = frames.first.toComponent(position: Vector2.zero())..opacity = 0;
      _glows[i] = s;
      await add(s);
    }
  }

  @override
  void update(double dt) {
    _apply();
    super.update(dt);
  }

  void _apply() {
    final state = turret.specialState[FusionSpecial.specialId];
    if (state is! FusionState) return;
    final sizes = glowSizes(turret.def.specialParams[FusionSpecial.specialId], state);
    if (sizes == null) return;
    for (var i = 0; i < _glows.length; i++) {
      final g = _glows[i];
      if (g == null) continue;
      final size = sizes[i];
      g
        ..opacity = size > 0 ? 1 : 0
        ..scale = Vector2.all(size / _frameWidths[i]);
    }
  }

  /// Widths in px of the white, blue and red glows (0 = hidden), or null to
  /// keep the last ones.
  static List<double>? glowSizes(Params? p, FusionState state) {
    if (p == null) return null;
    final store = state.storeDamage;
    if (store == 0) return const [0, 0, 0];
    final unit = p.number('glowUnit')!;
    final tier = p.number('glowTierSize')!;
    final pulse = p.number('glowPulse') ?? 1;
    final u = (store / unit).floor();
    if (u <= 0) return null;
    final m = (u % tier).toDouble();
    // The pulse toggles before it is used: an update that set it to false
    // drew the larger glow.
    final big = state.pulse ? 1.0 : pulse;
    if (u >= tier * 3) return [tier * big, tier, tier];
    if (u >= tier * 2) return [tier * big, tier, m];
    if (u >= tier) return [tier * big, m, 0];
    return [m * big, 0, 0];
  }
}

/// The colour a Combonly plate glows while it shows [colour] (a colour
/// turret id): that turret's `art.tint` (`TurretCombonly.update`: Red
/// 0xFF0000, Green 0x01BA01, Blue 0x0000FF, Yellow 0xFFCC00), else the
/// original's 0xFF9933.
int combonlyTint(GameData data, String? colour) =>
    data.turrets[colour]?.art.tint ?? _combonlyOtherTint;

const int _combonlyOtherTint = 0xFF9933;

/// A Combonly plate's look on top of its base: the colour glow
/// (`TheColour`, blurred, tweened to 75 % in 0.5 s, cancelled in 0.25 s:
/// the turret's `art.fx` `glowAlpha`, `glowInMs`, `glowOutMs`, `glowRadius`
/// and `glowBlur`)
/// and, once it locks in, the colour weapon (and Blue's or Yellow's legs)
/// fading in over `activateMs` (`comboWeaponAttach`), turned with the
/// plate's rotation.
class CombonlyPlateView extends PositionComponent {
  CombonlyPlateView({required this.turret, required this.layer}) : super(priority: 2);

  final Turret turret;
  final EntityLayer layer;
  double _glowAlpha = 0;
  int _tint = 0xFFFFFF;
  SpriteComponent? _weapon;
  SpriteComponent? _legs;
  double _armS = 0;
  final Paint _glow = Paint();
  double _glowTarget = 0;
  double _glowInS = 0;
  double _glowOutS = 0;
  double _glowRadius = 0;
  double _activateS = 0;

  @override
  Future<void> onLoad() async {
    final fx = turret.def.art.fx;
    _glowTarget = (fx.number('glowAlpha') ?? 0) / 100;
    _glowInS = (fx.number('glowInMs') ?? 0) / 1000;
    _glowOutS = (fx.number('glowOutMs') ?? 0) / 1000;
    _glowRadius = fx.number('glowRadius') ?? 0;
    _glow.maskFilter = MaskFilter.blur(BlurStyle.normal, fx.number('glowBlur') ?? 0);
    _activateS =
        (turret.def.specialParams[CombonlySpecial.specialId]?.number('activateMs') ?? 0) / 1000;
  }

  @override
  void update(double dt) {
    final state = turret.specialState[CombonlySpecial.specialId];
    if (state is CombonlyState) _follow(state, dt);
    super.update(dt);
  }

  void _follow(CombonlyState state, double dt) {
    final target = state.glow ? _glowTarget : 0.0;
    final tweenS = state.glow ? _glowInS : _glowOutS;
    if (state.glow) _tint = combonlyTint(layer.viewModel.data, state.shown);
    if (tweenS <= 0) {
      _glowAlpha = target;
    } else {
      final rate = _glowTarget / tweenS;
      _glowAlpha = _glowAlpha < target
          ? math.min(target, _glowAlpha + rate * dt)
          : math.max(target, _glowAlpha - rate * dt);
    }
    final chosen = state.chosen;
    if (chosen == null) return;
    if (_weapon == null) _attach(chosen.colour);
    _armS += dt;
    final f = _activateS <= 0 || state.armed ? 1.0 : (_armS / _activateS).clamp(0.0, 1.0);
    _weapon
      ?..opacity = f
      ..angle = degToRad(turret.rotation);
    _legs?.opacity = (f / 2 + (state.armed ? 0.5 : 0)).clamp(0, 1);
  }

  /// The colour turret's weapon and its own legs (`comboWeaponAttach`:
  /// CannonLegs for Blue, ElectricLegs for Yellow, none for Red and Green).
  void _attach(String colour) {
    final def = layer.viewModel.data.turrets[colour];
    if (def == null) return;
    final legs = layer.framesOf(def.art.legs);
    if (legs.isNotEmpty) {
      _legs = legs.first.toComponent(position: Vector2.zero())
        ..opacity = 0
        ..angle = degToRad((turret.uid * 37) % 360);
      add(_legs!);
    }
    final weapon = layer.framesOf(def.art.weapon);
    if (weapon.isNotEmpty) {
      _weapon = weapon.first.toComponent(position: Vector2.zero())
        ..opacity = 0
        ..priority = 1;
      add(_weapon!);
    }
  }

  @override
  void render(Canvas canvas) {
    if (_glowAlpha <= 0) return;
    _glow.color = Color(0xFF000000 | _tint).withValues(alpha: _glowAlpha);
    canvas.drawCircle(Offset.zero, _glowRadius, _glow);
  }
}
