import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show TextPainter;
import 'package:onslaught_core/onslaught_core.dart';

import '../colour_badges.dart';
import '../effect_settings.dart';
import '../game_view_model.dart';
import 'art_resolver.dart';
import 'instant_shot_view.dart';
import 'ordnance_views.dart';
import 'smoke_view.dart';
import 'super_views.dart';

/// Draw order of the world layers (ground −10, road 0, base 1).
abstract final class WorldLayers {
  static const int turrets = 10;
  static const int creeps = 20;

  /// Rocket smoke: over turrets and creeps, under the projectiles.
  static const int smoke = 25;
  static const int projectiles = 30;
  static const int overlay = 40;
}

/// Frame rate of the original's movie clips (SWF header: 31 fps).
const double clipFps = 31;

/// Keeps one component per sim entity: adds components for new creeps,
/// turrets and projectiles, drops those whose entity is gone, and lets each
/// copy its entity's state every frame. Views only; nothing here writes to
/// the simulation. Everything is cut off at [stage], as the original's stage
/// cuts off a creep walking in from the edge of the map.
class EntityLayer extends Component {
  EntityLayer({
    required this.viewModel,
    required this.art,
    ValueListenable<EffectSettings>? effects,
    this.stage,
  }) : effects = effects ?? ValueNotifier(EffectSettings.of(viewModel.data));

  final GameViewModel viewModel;
  final ArtResolver art;
  final Rect? stage;

  /// The player's display settings (rocket smoke, colour badges).
  final ValueListenable<EffectSettings> effects;

  /// The interface language, for the colour badges' letters.
  String locale = 'en';
  final Map<String, List<ResolvedFrame>> _frames = {};
  final Map<int, CreepView> _creeps = {};
  final Map<int, TurretView> _turrets = {};
  final Map<int, PositionComponent> _projectiles = {};
  final Map<int, BlastView> _blasts = {};
  final Map<int, WalkerView> _walkers = {};
  StreamSubscription<GameEvent>? _events;

  /// The freakout warning sign (`TurretFreakWarning`).
  static const String freakWarningArt = 'fx.freak-warning';

  /// The combo signs on the leader and its helpers.
  static const String specialFireArt = 'fx.special-fire';
  static const String specialTakeArt = 'fx.special-take';

  @override
  void renderTree(Canvas canvas) {
    final stage = this.stage;
    if (stage == null) return super.renderTree(canvas);
    canvas
      ..save()
      ..clipRect(stage);
    super.renderTree(canvas);
    canvas.restore();
  }

  @override
  Future<void> onLoad() async {
    final data = viewModel.data;
    final ids = <String>{
      for (final t in data.turrets.values) ...t.art.ids,
      for (final c in data.creeps.types) c.sprite,
      for (final p in data.projectiles.values) ?p.sprite,
      for (final b in data.blasts.values) ?b.sprite,
      ?data.world.art['rocketSmoke'],
      freakWarningArt,
      specialFireArt,
      specialTakeArt,
      BlackHoleView.debrisArt,
      brassArt,
      ...FusionGlowView.art,
    };
    for (final id in ids) {
      final frames = await art.frames(id);
      if (frames.isNotEmpty) _frames[id] = frames;
    }
    await add(TargeterOverlay(this));
    await add(
      RocketSmokeLayer(
        viewModel: viewModel,
        frames: framesOf(data.world.art['rocketSmoke']),
        settings: effects,
      ),
    );
  }

  /// A spent Sniper casing (`BarrattBrass`).
  static const String brassArt = 'fx.brass';

  @override
  void onMount() {
    super.onMount();
    _events = viewModel.events.listen(_onEvent);
  }

  @override
  void onRemove() {
    unawaited(_events?.cancel());
    _events = null;
    super.onRemove();
  }

  /// `Turret.comboFired` / `comboTake`: the SpecialFire sign on the leader,
  /// turned with its weapon, and SpecialTake on each helper; a Sniper's
  /// casing; turrets a Combonly plate consumes sliding into it.
  void _onEvent(GameEvent e) {
    switch (e) {
      case TurretFired(:final uid):
        _turrets[uid]?.ejectBrass();
      case CombonlyChanged(:final uid, :final consumed):
        final plate = _turrets[uid];
        if (plate == null) return;
        final ms =
            plate.turret.def.specialParams[CombonlySpecial.specialId]?.number('consumeMs') ?? 0;
        for (final c in consumed) {
          _turrets[c]?.consumeInto(plate.turret.position, ms / 1000);
        }
      case ComboFired(:final uid, :final helpers):
        final fire = framesOf(specialFireArt);
        final take = framesOf(specialTakeArt);
        final leader = _turrets[uid];
        if (leader != null && fire.isNotEmpty) {
          leader.add(ComboSign(fire, angle: degToRad(leader.turret.rotation)));
        }
        for (final h in helpers) {
          final helper = _turrets[h];
          if (helper != null && take.isNotEmpty) helper.add(ComboSign(take));
        }
      // No one-off animation here: [update] draws every creep, turret,
      // projectile, blast and walker from the world each frame.
      case SessionStarted() ||
          PausedChanged() ||
          SpeedChanged() ||
          CommandRejected() ||
          WaveStarted() ||
          CreepSpawned() ||
          CreepKilled() ||
          BaseHit() ||
          GameOver() ||
          GameWon() ||
          FreeplayStarted() ||
          ObjectiveReached() ||
          ObjectiveMissed() ||
          TutorialCashSet() ||
          WaveSettingsChanged() ||
          TurretBuilt() ||
          TurretUpgraded() ||
          TurretSold() ||
          TurretMoved() ||
          TargetModeChanged() ||
          TurretJoined() ||
          TurretConsumed() ||
          FreakoutChanged() ||
          WeaponUnlocked() ||
          BlastStarted() ||
          BlackHoleOpened() ||
          CreepSwallowed():
        break;
    }
  }

  List<ResolvedFrame> framesOf(String? id) => id == null ? const [] : _frames[id] ?? const [];

  @override
  void update(double dt) {
    final world = viewModel.world;
    _sync(_creeps, world.creeps, (c) => c.uid, (c) => CreepView(c, this));
    _sync(_turrets, world.turrets, (t) => t.uid, (t) => TurretView(t, this));
    _sync(_projectiles, world.projectiles, (p) => p.uid, _projectileView);
    _sync(_blasts, world.blasts, (b) => b.uid, (b) => BlastView(b, this));
    _sync(_walkers, world.walkers, (w) => w.uid, (w) => WalkerView(w, this));
    final selected = viewModel.selection.value?.uid;
    for (final v in _turrets.values) {
      v.selected = v.turret.uid == selected;
    }
    super.update(dt);
  }

  /// Instant shots (beams, sparks) are drawn lines, black holes have their
  /// own view; the rest are sprites.
  PositionComponent _projectileView(Projectile p) => switch (p.kind) {
    _blackHoleKind => BlackHoleView(p, this),
    'rail' => RailBeamView(p, this),
    'sniper-shot' => SniperTracerView(p, this),
    _ when p.lineTo != null || _instantKinds.contains(p.kind) => InstantShotView(p, this),
    _ => ProjectileView(p, this),
  };

  static const String _blackHoleKind = 'black-hole';

  /// How much of its size a creep, projectile or blast pulled into a black
  /// hole loses over the pull (0…1): the black hole's `art.fx`
  /// `captureShrink` %.
  late final double captureShrink =
      (viewModel.data.projectiles.values
              .where((p) => p.kind == _blackHoleKind)
              .firstOrNull
              ?.art
              ?.fx
              .number('captureShrink') ??
          0) /
      100;

  static const Set<String> _instantKinds = {'beam', 'spark'};

  void _sync<E, V extends Component>(
    Map<int, V> views,
    List<E> entities,
    int Function(E) uidOf,
    V Function(E) create,
  ) {
    final live = <int>{};
    for (final e in entities) {
      final uid = uidOf(e);
      live.add(uid);
      if (!views.containsKey(uid)) {
        final v = create(e);
        views[uid] = v;
        add(v);
      }
    }
    views.removeWhere((uid, v) {
      if (live.contains(uid)) return false;
      v.removeFromParent();
      return true;
    });
  }
}

/// A creep: its sprite (scaled by the wave-size bump, turned to face its leg
/// for types that repoint), a 225 ms fade-in and an HP bar once damaged.
class CreepView extends PositionComponent {
  CreepView(this.creep, this.layer) : super(priority: WorldLayers.creeps);

  final Creep creep;
  final EntityLayer layer;
  SpriteComponent? _sprite;
  double _age = 0;
  late final bool _repoint;
  late final double _fadeInS;
  double _baseScale = 1;

  static final Paint _barBack = Paint()..color = const Color(0xCC000000);
  static final Paint _barFill = Paint();

  @override
  Future<void> onLoad() async {
    final data = layer.viewModel.data;
    final type = data.creeps.types[creep.typeIndex];
    _repoint = type.repoint;
    _fadeInS = (data.creeps.movement.number('fadeInMs') ?? 0) / 1000;
    final bump = data.creeps.movement.number('scaleBumpPercent') ?? 0;
    _baseScale = creepScalePercent(creep.scaleBump, bump) / 100;
    scale = Vector2.all(_baseScale);
    final frames = layer.framesOf(type.sprite);
    if (frames.isNotEmpty) {
      _sprite = frames.first.toComponent(position: Vector2.zero());
      await add(_sprite!);
    }
    _copy();
  }

  @override
  void update(double dt) {
    _age += dt;
    _copy();
    super.update(dt);
  }

  void _copy() {
    position.setValues(creep.position.x, creep.position.y);
    if (creep.capture != null) {
      scale = Vector2.all(_baseScale * captureScale(creep.capture, layer.captureShrink));
    }
    final sprite = _sprite;
    if (sprite == null) return;
    if (_repoint) sprite.angle = degToRad(creep.heading);
    sprite.opacity = _fadeInS <= 0 ? 1 : (_age / _fadeInS).clamp(0, 1);
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (creep.hp >= creep.hpStart) return;
    const w = 18.0;
    const h = 3.0;
    const y = -16.0;
    final f = (creep.hp / creep.hpStart).clamp(0.0, 1.0);
    canvas.drawRect(const Rect.fromLTWH(-w / 2 - 0.5, y - 0.5, w + 1, h + 1), _barBack);
    _barFill.color = Color.lerp(const Color(0xFFE53935), const Color(0xFF43A047), f)!;
    canvas.drawRect(Rect.fromLTWH(-w / 2, y, w * f, h), _barFill);
  }
}

/// A turret drawn in layers like its movie clip: base, body, legs (turned
/// at random), weapon (turned toward the target, playing its firing frames
/// after each shot), plus the range circle while selected.
class TurretView extends PositionComponent {
  TurretView(this.turret, this.layer) : super(priority: WorldLayers.turrets);

  final Turret turret;
  final EntityLayer layer;
  SpriteComponent? _weapon;
  List<ResolvedFrame> _weaponFrames = const [];
  int _shots = 0;
  double _firingTime = -1;
  bool selected = false;
  SpriteAnimationComponent? _warning;
  double _jitterTime = 0;
  final List<BrassView> _brass = [];
  final math.Random _brassRandom = math.Random();

  /// Sliding into a Combonly plate: where to, over how long, how far along.
  Vec2? _consumeTo;
  double _consumeS = 0;
  double _consumeAge = 0;

  /// Cosmetic weapon twitch while freaking out (`FreakoutEngine.freakoutJitter`:
  /// up to `jitterPx` a frame toward the rest point); not the sim's RNG.
  final math.Random _twitch = math.Random();

  /// The colour badge's centre (over the turret's top-right) and size, in
  /// world px.
  static const Offset _badgeAt = Offset(12, -12);
  static const double _badgeSize = 11;
  final TextPainter _badgeText = TextPainter();
  ColourBadge? _badge;
  String? _badgeLocale;

  static final Paint _rangeFill = Paint()..color = const Color(0x22FFFFFF);
  static final Paint _rangeStroke = Paint()
    ..color = const Color(0xAAFFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;

  @override
  Future<void> onLoad() async {
    final art = turret.def.art;
    for (final id in [art.base, art.body]) {
      final f = layer.framesOf(id);
      if (f.isNotEmpty) await add(f.first.toComponent(position: Vector2.zero()));
    }
    final legs = layer.framesOf(art.legs);
    if (legs.isNotEmpty) {
      // The original turns the legs by Math.random() × 90°; here the angle
      // comes from the uid so a turret looks the same every time.
      await add(
        legs.first.toComponent(position: Vector2.zero())..angle = degToRad((turret.uid * 37) % 90),
      );
    }
    _weaponFrames = layer.framesOf(art.weapon);
    if (_weaponFrames.isNotEmpty) {
      _weapon = _weaponFrames.first.toComponent(position: Vector2.zero());
      await add(_weapon!);
    }
    _shots = turret.shots;
    if (turret.def.specials.contains(FusionSpecial.specialId)) {
      await add(FusionGlowView(turret: turret, layer: layer));
    }
    if (turret.def.specials.contains(CombonlySpecial.specialId)) {
      await add(CombonlyPlateView(turret: turret, layer: layer));
    }
    _copy(0);
  }

  /// `TurretSniper.brassFire`: throws a casing from the weapon's BrassPoint
  /// (a ring of `brassMax`; the oldest goes). Cosmetic randomness.
  void ejectBrass() {
    final p = turret.def.specialParams['sniper'];
    final frames = layer.framesOf(EntityLayer.brassArt);
    if (p == null || frames.isEmpty) return;
    Offset weaponToTurret(double x, double y) {
      final v = rotateVec(Vec2(x, y), turret.rotation);
      return Offset(v.x, v.y);
    }

    final from = p.numbers('brassPoint') ?? const [0, 0];
    final to = p.numbers('brassPointTo') ?? const [0, 0];
    final jitter = p.number('brassJitter') ?? 0;
    final spin = p.number('brassSpin') ?? 0;
    double jit() => _brassRandom.nextDouble() * jitter * 2 - jitter;
    final casing = BrassView(
      frame: frames.first,
      from: weaponToTurret(from[0], from[1]),
      to: weaponToTurret(to[0] + jit(), to[1] + jit()),
      spinDeg: spin + _brassRandom.nextDouble() * spin,
      throwS: (p.number('brassMs') ?? 0) / 1000,
      fadeAfterS: (p.number('brassFadeAfterMs') ?? 0) / 1000,
      fadeS: (p.number('brassFadeMs') ?? 0) / 1000,
    );
    _brass.add(casing);
    add(casing);
    final max = (p.number('brassMax') ?? 0).toInt();
    while (_brass.length > max) {
      _brass.removeAt(0).removeFromParent();
    }
  }

  /// Fades and slides this turret into a Combonly plate at [to] over
  /// [seconds] (`comboChoose`: a 2 s blur, fade and slide).
  void consumeInto(Vec2 to, double seconds) {
    _consumeTo = to;
    _consumeS = seconds;
    _consumeAge = 0;
  }

  void _renderConsumed(Canvas canvas) {
    final t = _consumeS <= 0 ? 1.0 : (_consumeAge / _consumeS).clamp(0.0, 1.0);
    canvas.saveLayer(
      null,
      Paint()
        ..color = Color.fromRGBO(255, 255, 255, 1 - t)
        ..imageFilter = ImageFilter.blur(sigmaX: 1 + 6 * t, sigmaY: 1 + 6 * t),
    );
    super.renderTree(canvas);
    canvas.restore();
  }

  @override
  void update(double dt) {
    _copy(dt);
    super.update(dt);
  }

  void _copy(double dt) {
    final to = _consumeTo;
    if (to != null) {
      _consumeAge += dt;
      final t = _consumeS <= 0 ? 1.0 : (_consumeAge / _consumeS).clamp(0.0, 1.0);
      final p = turret.position.lerp(to, t);
      position.setValues(p.x, p.y);
    } else {
      position.setValues(turret.position.x, turret.position.y);
    }
    _freakout(dt);
    final weapon = _weapon;
    if (weapon == null) return;
    weapon.angle = degToRad(turret.rotation);
    if (turret.shots != _shots) {
      _shots = turret.shots;
      _firingTime = 0;
    }
    if (_firingTime >= 0 && _weaponFrames.length > 1) {
      _firingTime += dt;
      final frame = 1 + (_firingTime * clipFps).floor();
      if (frame >= _weaponFrames.length) {
        _firingTime = -1;
        weapon.sprite = _weaponFrames.first.sprite;
      } else {
        weapon.sprite = _weaponFrames[frame].sprite;
      }
    }
  }

  /// Shows the warning sign while a freakout warms up and twitches the
  /// weapon while one runs.
  void _freakout(double dt) {
    final state = turret.specialState[FreakoutSpecial.specialId] as FreakoutState?;
    final runs = state?.runs ?? const <FreakoutRun>[];
    final warning = runs.any((r) => !r.active);
    final active = runs.any((r) => r.active);
    if (warning && _warning == null) {
      final frames = layer.framesOf(EntityLayer.freakWarningArt);
      if (frames.isNotEmpty) {
        _warning = SpriteAnimationComponent(
          animation: SpriteAnimation.spriteList([
            for (final f in frames) f.sprite,
          ], stepTime: 1 / clipFps),
          size: frames.first.size,
          anchor: Anchor.center,
          position: Vector2(0, -24),
          priority: 1,
        );
        add(_warning!);
      }
    } else if (!warning && _warning != null) {
      _warning!.removeFromParent();
      _warning = null;
    }
    final weapon = _weapon;
    if (weapon == null) return;
    if (!active) {
      weapon.position.setZero();
      return;
    }
    _jitterTime += dt;
    if (_jitterTime < 1 / clipFps) return;
    _jitterTime = 0;
    final px = (turret.def.specialParams[FreakoutSpecial.specialId]?.number('jitterPx') ?? 0);
    double step(double offset) {
      final d = (_twitch.nextDouble() * px).floorToDouble();
      return offset > 0 ? offset - d : offset + d;
    }

    weapon.position.setValues(step(weapon.position.x), step(weapon.position.y));
  }

  @override
  void render(Canvas canvas) {
    if (selected) {
      final panel = layer.viewModel.selection.value;
      final r =
          panel?.auraRadius ??
          panel?.stats.where((s) => s.stat == StatKind.range).firstOrNull?.value ??
          turret.def.stats.range;
      canvas
        ..drawCircle(Offset.zero, r, _rangeFill)
        ..drawCircle(Offset.zero, r, _rangeStroke);
    }
    super.render(canvas);
  }

  /// The colour badge goes over the turret's own sprites (children).
  @override
  void renderTree(Canvas canvas) {
    if (_consumeTo == null) {
      super.renderTree(canvas);
    } else {
      _renderConsumed(canvas);
    }
    if (!layer.effects.value.colourBadges) return;
    final locale = layer.locale;
    if (_badgeLocale != locale) {
      _badgeLocale = locale;
      _badge = colourBadgeFor(layer.viewModel.data, turret.def.id, locale: locale);
    }
    final badge = _badge;
    if (badge == null) return;
    canvas
      ..save()
      ..translate(position.x, position.y);
    paintColourBadge(canvas, _badgeAt, _badgeSize, badge, _badgeText);
    canvas.restore();
  }
}

/// A projectile sprite, turned along its heading; clips with several
/// frames (the BFG orb, landmines) loop them at the original's frame rate.
/// One being pulled into a black hole shrinks as it goes.
class ProjectileView extends PositionComponent {
  ProjectileView(this.projectile, this.layer) : super(priority: WorldLayers.projectiles);

  final Projectile projectile;
  final EntityLayer layer;
  SpriteComponent? _sprite;
  List<ResolvedFrame> _frames = const [];
  double _age = 0;

  @override
  Future<void> onLoad() async {
    final spec = layer.viewModel.data.projectiles[projectile.specId];
    _frames = layer.framesOf(spec?.sprite);
    if (_frames.isNotEmpty) {
      _sprite = _frames.first.toComponent(position: Vector2.zero());
      await add(_sprite!);
    }
    _copy();
  }

  @override
  void update(double dt) {
    _age += dt;
    _copy();
    super.update(dt);
  }

  void _copy() {
    position.setValues(projectile.position.x, projectile.position.y);
    final sprite = _sprite;
    if (sprite == null) return;
    sprite.angle = degToRad(projectile.heading);
    if (_frames.length > 1) {
      sprite.sprite = _frames[(_age * clipFps).floor() % _frames.length].sprite;
    }
    if (projectile.capture != null) {
      sprite.scale = Vector2.all(captureScale(projectile.capture, layer.captureShrink));
    }
  }
}

/// The ghost turret and range circle while building or moving, green when
/// it can be placed and red when not (`BuildShape` CanBuild/CannotBuild).
class PlacementGhost extends PositionComponent {
  PlacementGhost({required this.viewModel, required this.layer})
    : super(priority: WorldLayers.overlay);

  final GameViewModel viewModel;
  final EntityLayer layer;
  PlacementPreview? _shown;
  final List<SpriteComponent> _sprites = [];

  static final Paint _ok = Paint()..color = const Color(0x4400E676);
  static final Paint _bad = Paint()..color = const Color(0x55FF1744);
  static final Paint _okEdge = Paint()
    ..color = const Color(0xCC00E676)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;
  static final Paint _badEdge = Paint()
    ..color = const Color(0xCCFF1744)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;

  /// The ring round a dropped-and-locked ghost (drop and lock).
  static final Paint _lockedEdge = Paint()
    ..color = const Color(0xE6FFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;

  /// How far outside the footprint the locked ring sits, in world px.
  static const double _lockedGap = 3;

  @override
  void update(double dt) {
    final p = viewModel.placement.value;
    if (p?.turretId != _shown?.turretId) _rebuild(p);
    _shown = p;
    if (p?.at != null) position.setValues(p!.at!.x, p.at!.y);
    super.update(dt);
  }

  void _rebuild(PlacementPreview? p) {
    for (final s in _sprites) {
      s.removeFromParent();
    }
    _sprites.clear();
    if (p == null) return;
    final art = viewModel.data.turrets[p.turretId]!.art;
    for (final id in [art.base, art.body, art.legs, art.weapon]) {
      final f = layer.framesOf(id);
      if (f.isEmpty) continue;
      final s = f.first.toComponent(position: Vector2.zero())..opacity = 0.7;
      if (id == art.weapon) s.angle = degToRad(viewModel.data.turrets[p.turretId]!.weaponRotation);
      _sprites.add(s);
      add(s);
    }
  }

  @override
  void renderTree(Canvas canvas) {
    final p = _shown;
    if (p == null || p.at == null) return;
    super.renderTree(canvas);
  }

  @override
  void render(Canvas canvas) {
    final p = _shown!;
    final footprint = viewModel.data.world.placement.turretSpacing / 2;
    canvas
      ..drawCircle(Offset.zero, p.range, p.valid ? _ok : _bad)
      ..drawCircle(Offset.zero, p.range, p.valid ? _okEdge : _badEdge)
      ..drawCircle(Offset.zero, math.max(1, footprint), p.valid ? _okEdge : _badEdge);
    if (p.locked) canvas.drawCircle(Offset.zero, math.max(1, footprint) + _lockedGap, _lockedEdge);
  }
}
