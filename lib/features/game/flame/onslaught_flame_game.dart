import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kDoubleTapSlop, kDoubleTapTimeout;
import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/widgets.dart' show MediaQuery;
import 'package:onslaught_core/onslaught_core.dart';

import '../../../app/camera_rig.dart';
import '../../../app/ui_skin.dart';
import '../../../services/assets/asset_pack.dart';
import '../../../services/logging/logging.dart';
import '../../../services/persistence/settings.dart' show PlacementMode;
import '../camera/camera_controls.dart';
import '../effect_settings.dart';
import '../game_view_model.dart';
import '../layout/hud_layout.dart';
import 'art_resolver.dart';
import 'entity_layer.dart';
import 'ground_component.dart';
import 'road_component.dart';

const Logger _log = Logger('render');

/// Default colours when the asset pack has no theme.
const _fallbackTheme = PackTheme(background: Color(0xFF5B7F3A), offMap: Color(0xFF3E5A27));

/// The Flame view of a game: a world in original pixels (720×480 play area)
/// drawn behind a pan/zoom camera. Components only read state; input becomes
/// [GameViewModel.dispatch] commands or camera moves.
class OnslaughtFlameGame extends FlameGame implements CameraControls {
  OnslaughtFlameGame({
    required this.viewModel,
    required this.pack,
    this.cameraSettings = const CameraSettings(),
    this.driveSimulation = true,
    this.drawBase = true,
    this.skin = UiSkin.classic,
    Size? worldSize,
    List<GroundArt>? groundArt,
    ValueListenable<EffectSettings>? effects,
    ValueListenable<PlacementMode>? placementMode,
  }) : groundArt = groundArt ?? viewModel.data.world.groundArt,
       effects = effects ?? ValueNotifier(EffectSettings.of(viewModel.data)),
       placementMode = placementMode ?? ValueNotifier(PlacementMode.dragAndDrop),
       rig = CameraRig(
         world:
             Offset.zero &
             (worldSize ?? Size(viewModel.data.world.playWidth, viewModel.data.world.playHeight)),
         settings: cameraSettings,
       );

  final GameViewModel viewModel;
  final AssetPack pack;
  final CameraSettings cameraSettings;

  /// Whether [update] advances the simulation (off in goldens/tests).
  final bool driveSimulation;

  /// Whether the player's base is drawn (the attract demo has none).
  final bool drawBase;

  /// The decorations on the ground.
  final List<GroundArt> groundArt;

  /// The game's skin: the turret hit zone and the ground follow it.
  final UiSkin skin;

  /// The player's cosmetic effect settings (rocket smoke); may change
  /// while the game runs.
  final ValueListenable<EffectSettings> effects;

  /// How the player puts turrets down (drag and drop, or drop and lock);
  /// may change while the game runs.
  final ValueListenable<PlacementMode> placementMode;

  /// The interface language (for the colour badges' letters); the screen
  /// keeps it current.
  String get locale => _locale;
  set locale(String value) {
    _locale = value;
    _entities?.locale = value;
  }

  String _locale = 'en';
  EntityLayer? _entities;
  final CameraRig rig;
  final ValueNotifier<CameraReadout> _readout = ValueNotifier(CameraReadout.initial);

  PackTheme get theme => pack.theme ?? _fallbackTheme;

  /// Resolves art ids for every view; set in [onLoad].
  ArtResolver? _art;

  @visibleForTesting
  ArtResolver? get art => _art;

  /// Device pixels per logical px of the screen the game is on.
  double get _devicePixelRatio {
    final context = buildContext;
    return (context == null ? null : MediaQuery.maybeDevicePixelRatioOf(context)) ??
        PlatformDispatcher.instance.implicitView?.devicePixelRatio ??
        1;
  }

  @override
  ValueListenable<CameraReadout> get cameraReadout => _readout;

  @override
  Color backgroundColor() => theme.offMap;

  @override
  Future<void> onLoad() async {
    images.prefix = '';
    camera.viewfinder.anchor = Anchor.center;
    final data = viewModel.data;
    final map = viewModel.map;
    final art = _art = ArtResolver(pack, images);
    // The whole stage: the original stretches the ground over the taller
    // stage of its menu demo too (main timeline frame 35, ENGINE_NOTES §8.5).
    final play = rig.world;
    final playSize = Vector2(play.width, play.height);
    final groundId = data.world.art['ground'] ?? '';
    final shader = await _shaderGround(pack.ground(groundId));
    if (shader != null) {
      await world.add(shader);
    } else {
      final ground = await art.frame(groundId);
      await world.add(
        ground != null
            ? (ground.toComponent(position: Vector2.zero())
                ..size = playSize
                ..anchor = Anchor.topLeft
                ..priority = GroundLayers.ground)
            : RectangleComponent(
                size: playSize,
                paint: Paint()..color = theme.background,
                priority: GroundLayers.ground,
              ),
      );
      await world.add(
        GroundBeyond(
          play: play,
          visible: () => rig.visible,
          colour: theme.background,
          image: ground?.sprite.toImageSync,
        ),
      );
      await world.add(
        GroundDecorations(
          stage: play,
          children: [
            for (final g in groundArt)
              if (await art.frame(g.art) case final frame?)
                frame.toComponent(position: Vector2(g.x, g.y))
                  ..scale = Vector2.all(g.scale)
                  ..angle = g.rotation * math.pi / 180,
          ],
        ),
      );
    }
    await world.add(PlayAreaEdge(play: play, visible: () => rig.visible, offMap: theme.offMap));
    await world.add(RoadComponent(road: map.road, style: data.world.road, stage: play));
    final base = drawBase ? await art.frame(data.world.art['base'] ?? '') : null;
    if (base != null) {
      await world.add(base.toComponent(position: Vector2(map.base.x, map.base.y))..priority = 1);
    }
    final entities = _entities = EntityLayer(
      viewModel: viewModel,
      art: art,
      effects: effects,
      stage: play,
    )..locale = _locale;
    await world.add(entities);
    await world.add(PlacementGhost(viewModel: viewModel, layer: entities));
    await camera.viewport.add(CameraInputLayer(this));
    _applyCamera();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    rig.resize(Size(size.x, size.y));
    if (isLoaded) _applyCamera();
  }

  @override
  void update(double dt) {
    final vm = viewModel;
    if (driveSimulation && vm is SessionGameViewModel) vm.advance(dt);
    // Art density follows zoom × screen density (and a window moved to
    // another monitor).
    _art
      ?..pixelsPerWorldPx = rig.zoom * _devicePixelRatio
      ..tick(dt);
    super.update(dt);
  }

  /// The shader-drawn ground for [source], or null when the pack draws the
  /// ground as an image (or the shader cannot load, e.g. an unsupported web
  /// renderer: the image ground is drawn instead).
  Future<ShaderGroundComponent?> _shaderGround(GroundSource? source) async {
    if (source is! ShaderGround) return null;
    try {
      final program = await FragmentProgram.fromAsset(source.shader);
      return ShaderGroundComponent(
        shader: program.fragmentShader(),
        palette: source.palette,
        visible: () => rig.visible,
      );
    } on Object catch (error, stack) {
      _log.warning('sharp ground unavailable; drawing the image', error: error, stackTrace: stack);
      return null;
    }
  }

  void _applyCamera() {
    camera.viewfinder
      ..zoom = rig.zoom
      ..position = Vector2(rig.center.dx, rig.center.dy);
    _readout.value = CameraReadout(
      zoom: rig.zoom,
      relativeZoom: rig.relativeZoom,
      center: rig.center,
      viewport: rig.viewport,
    );
  }

  /// Applies a camera change made through [rig].
  void cameraChanged() => _applyCamera();

  /// Screen edges the HUD covers (fit and panning keep the map clear of
  /// them), whether the home view fills the rest ([CameraRig.fill]) and how
  /// far it zooms out.
  void setFrame(EdgeInsets insets, {bool fill = false, double? homeFloor}) {
    rig.setFrame(insets, fill: fill, homeFloor: homeFloor);
    if (isLoaded) _applyCamera();
  }

  /// Frames the map for the HUD [layout]: its map insets, filled in
  /// portrait.
  void setLayout(HudLayout layout) =>
      setFrame(layout.mapInsets, fill: layout.fillsMap, homeFloor: layout.homeFloor);

  /// The world point under game-widget-local [screen] position.
  Vec2 screenToWorld(Offset screen) {
    final w = rig.screenToWorld(screen);
    return Vec2(w.dx, w.dy);
  }

  /// A tap on the map at game-widget-local [screen]: places an armed ghost
  /// (tap-to-build / move), or with drop and lock drops and locks it there
  /// (a locked ghost jumps to the tap); while a Targeter's joins are being edited, joins
  /// (or lets go) the turret under the finger and ends on empty ground or
  /// on the Targeter itself; else selects the turret under the finger, else
  /// deselects when the rules profile says so (`tapEmptyDeselects`).
  /// Whether a tap at [screen] lands on nothing: no ghost armed, no join in
  /// progress and no turret under it. Only such taps pair into a double tap
  /// (zoom), so a tap that selects or places acts at once, as a click does in
  /// the original (`Turret.onPress` → `TurretManager.turretSelect`).
  bool isPlainGroundTap(Offset screen) {
    final vm = viewModel;
    if (vm.placement.value != null || vm.joining.value != null) return false;
    return vm.turretAt(screenToWorld(screen), minRadius: skin.turretHitPt / rig.zoom) == null;
  }

  void tapAt(Offset screen) {
    final at = screenToWorld(screen);
    final vm = viewModel;
    final armed = vm.placement.value;
    if (armed != null) {
      final lock = placementMode.value == PlacementMode.dropAndLock;
      vm.previewPlacement(armed.turretId, at, moving: armed.moving, locked: lock);
      if (!lock) vm.commitPlacement();
      return;
    }
    final uid = vm.turretAt(at, minRadius: skin.turretHitPt / rig.zoom);
    final joining = vm.joining.value;
    if (joining != null) {
      if (uid == null || uid == joining) {
        vm.joinFrom(null);
      } else {
        vm.dispatch(JoinTurret(joining, uid));
      }
      return;
    }
    if (uid != null) {
      vm.select(vm.selection.value?.uid == uid ? null : uid);
    } else if (vm.profile.tapEmptyDeselects) {
      vm.select(null);
    }
  }

  /// Drop and lock: moves a locked ghost by screen [delta], 1:1 with the
  /// finger wherever it is on the map (so the finger never covers the
  /// ghost), kept inside the play area. False when no ghost is locked.
  bool nudgePlacement(Offset delta) {
    final p = viewModel.placement.value;
    final at = p?.at;
    if (p == null || !p.locked || at == null) return false;
    final w = rig.world;
    final x = (at.x + delta.dx / rig.zoom).clamp(w.left, w.right);
    final y = (at.y + delta.dy / rig.zoom).clamp(w.top, w.bottom);
    viewModel.previewPlacement(p.turretId, Vec2(x, y), moving: p.moving, locked: true);
    return true;
  }

  Offset get _screenCentre => rig.viewport.center(Offset.zero);

  @override
  void zoomIn() {
    rig.zoomBy(1.25, _screenCentre);
    _applyCamera();
  }

  @override
  void zoomOut() {
    rig.zoomBy(0.8, _screenCentre);
    _applyCamera();
  }

  @override
  void fitMap() {
    rig.fit();
    _applyCamera();
  }

  /// Back to the home view (fit, or filled in portrait).
  void homeView() {
    rig.home();
    _applyCamera();
  }

  @override
  void onRemove() {
    _readout.dispose();
    super.onRemove();
  }
}

/// Full-screen input layer on the viewport: one finger pans (or, with a
/// ghost dropped and locked, nudges it), two fingers
/// pinch-zoom about their focal point (and pan with it), the mouse wheel
/// zooms, a tap selects (or places an armed ghost) at once, and a double tap
/// on empty ground toggles fit / 2×.
///
/// There is no double-tap gesture recogniser: one would hold every tap for
/// [kDoubleTapTimeout] waiting for a second, delaying selection. Instead a tap
/// on empty ground is remembered, and a second one close by in time and place
/// zooms.
///
/// Flame emits scale events only while two or more pointers are down, so the
/// one-finger pan comes from drag events; drags are ignored while more than
/// one finger is down so a pinch does not pan twice.
class CameraInputLayer extends PositionComponent
    with DragCallbacks, ScaleCallbacks, ScrollCallbacks, TapCallbacks {
  CameraInputLayer(this.game);

  final OnslaughtFlameGame game;

  /// The last tap on empty ground: where, and when by the frame clock (which
  /// tests can advance) and by a wall-clock stopwatch (in case frames stall).
  Offset? _groundTapAt;
  Duration _groundTapFrame = Duration.zero;
  Duration _groundTapWall = Duration.zero;
  final Stopwatch _wall = Stopwatch()..start();
  final Set<int> _dragPointers = {};
  double _startZoom = 1;

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    _dragPointers.add(event.pointerId);
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (_dragPointers.length != 1 || isScaling) return;
    final d = event.canvasDelta;
    if (game.nudgePlacement(Offset(d.x, d.y))) return;
    game.rig.panBy(Offset(d.x, d.y));
    game.cameraChanged();
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    _dragPointers.remove(event.pointerId);
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    _dragPointers.remove(event.pointerId);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    this.size = size;
  }

  @override
  bool containsLocalPoint(Vector2 point) => true;

  @override
  void onScaleStart(ScaleStartEvent event) {
    super.onScaleStart(event);
    _startZoom = game.rig.zoom;
  }

  @override
  void onScaleUpdate(ScaleUpdateEvent event) {
    final rig = game.rig;
    final d = event.focalPointDelta;
    rig.panBy(Offset(d.x, d.y));
    final focal = event.canvasEndPosition;
    rig.zoomAbout(_startZoom * event.scale, Offset(focal.x, focal.y));
    game.cameraChanged();
  }

  @override
  void onScroll(ScrollEvent event) {
    final dy = event.scrollDelta.y;
    if (dy == 0) return;
    final p = event.canvasPosition;
    game.rig.zoomBy(dy < 0 ? 1.1 : 1 / 1.1, Offset(p.x, p.y));
    game.cameraChanged();
  }

  @override
  void onTapUp(TapUpEvent event) {
    final p = Offset(event.canvasPosition.x, event.canvasPosition.y);
    final frame = SchedulerBinding.instance.currentSystemFrameTimeStamp;
    final wall = _wall.elapsed;
    final ground = game.isPlainGroundTap(p);
    final last = _groundTapAt;
    if (ground &&
        last != null &&
        frame - _groundTapFrame <= kDoubleTapTimeout &&
        wall - _groundTapWall <= kDoubleTapTimeout &&
        (p - last).distance <= kDoubleTapSlop) {
      _groundTapAt = null;
      game.rig.toggleZoom(p);
      game.cameraChanged();
      return;
    }
    game.tapAt(p);
    _groundTapAt = ground ? p : null;
    _groundTapFrame = frame;
    _groundTapWall = wall;
  }
}
