import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../app/camera_rig.dart';
import '../../app/theme.dart';
import '../../services/assets/asset_pack.dart';
import '../../services/assets/pack_sprite.dart';
import 'editor_controller.dart';

/// What the palette drops on the map.
enum PaletteItem { start, base }

/// Screen sizes of the canvas handles (logical px; not game data).
abstract final class EditorHandles {
  /// Finger slop around a handle: a 44 pt target (tenet 6).
  static const double touchRadius = 22;
  static const double waypoint = 9;
  static const double midpoint = 8;
  static const double start = 13;
}

/// The editor's map view: the play area with the road, base, start,
/// waypoints and "+" handles, over the off-map margin. One finger on a
/// handle drags it, on empty ground pans (when zoomed) or, as a tap, adds a
/// waypoint; two fingers pinch-zoom; the mouse wheel zooms. Palette items
/// dropped on it (or an [armed] item and a tap) place the start or base.
class EditorCanvas extends StatefulWidget {
  const EditorCanvas({
    super.key,
    required this.controller,
    this.pack,
    this.insets = EdgeInsets.zero,
    this.fill = false,
    this.armed,
    this.onPlaced,
    this.onHover,
  });

  final MapEditorController controller;
  final AssetPack? pack;

  /// Screen edges covered by the editor's toolbars.
  final EdgeInsets insets;

  /// The map fills the free area (portrait), upright, the rest a pan away;
  /// otherwise it is fitted whole.
  final bool fill;

  /// A palette item waiting for a tap on the map.
  final PaletteItem? armed;

  /// Called after [armed] (or a dropped item) was placed.
  final VoidCallback? onPlaced;

  /// The world point under the mouse (desktop key shortcuts), or null.
  final ValueChanged<Vec2?>? onHover;

  @override
  State<EditorCanvas> createState() => EditorCanvasState();
}

class EditorCanvasState extends State<EditorCanvas> {
  late final CameraRig rig = CameraRig(
    world: Rect.fromLTWH(
      0,
      0,
      widget.controller.world.playWidth,
      widget.controller.world.playHeight,
    ),
  );

  _Gesture _gesture = _Gesture.none;
  double _startZoom = 1;
  Offset _lastFocal = Offset.zero;

  /// Where the last finger went down: a drag grabs what was under it, not
  /// what is under the finger once it has moved past the touch slop.
  Offset? _down;

  MapEditorController get _c => widget.controller;

  /// Fits the whole play area.
  void fit() => setState(rig.fit);

  /// Zooms by [factor] about the centre of the free area.
  void zoomBy(double factor) => setState(() => rig.zoomBy(factor, rig.free.center));

  Vec2 _world(Offset screen) {
    final w = rig.screenToWorld(screen);
    return Vec2(w.dx, w.dy);
  }

  double get _slop => EditorHandles.touchRadius / rig.zoom;

  void _place(PaletteItem item, Vec2 at) {
    switch (item) {
      case PaletteItem.start:
        _c.placeStart(at);
      case PaletteItem.base:
        _c.placeBase(at);
    }
    widget.onPlaced?.call();
  }

  void _onTapUp(TapUpDetails d) {
    final at = _world(d.localPosition);
    final armed = widget.armed;
    if (armed != null) return _place(armed, at);
    _c.tap(at, _slop);
  }

  void _onScaleStart(ScaleStartDetails d) {
    _lastFocal = d.localFocalPoint;
    _startZoom = rig.zoom;
    if (d.pointerCount > 1) {
      _gesture = _Gesture.zoom;
      return;
    }
    final down = _down ?? d.localFocalPoint;
    final hit = _c.hitTest(_world(down), _slop);
    if (hit != null) {
      _gesture = _Gesture.drag;
      _c
        ..beginDrag(hit, _world(down))
        ..dragTo(_world(d.localFocalPoint));
    } else {
      _gesture = _Gesture.pan;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    switch (_gesture) {
      case _Gesture.drag:
        _c.dragTo(_world(d.localFocalPoint));
      case _Gesture.pan || _Gesture.zoom:
        if (d.pointerCount > 1 && _gesture == _Gesture.pan) {
          _gesture = _Gesture.zoom;
          _startZoom = rig.zoom / d.scale;
        }
        setState(() {
          rig.panBy(d.localFocalPoint - _lastFocal);
          if (_gesture == _Gesture.zoom) rig.zoomAbout(_startZoom * d.scale, d.localFocalPoint);
        });
      case _Gesture.none:
        break;
    }
    _lastFocal = d.localFocalPoint;
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (_gesture == _Gesture.drag) _c.endDrag();
    _gesture = _Gesture.none;
  }

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      final factor = math.pow(2, -e.scrollDelta.dy / 400).toDouble();
      setState(() => rig.zoomBy(factor, e.localPosition));
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final size = box.biggest;
      if (rig.viewport != size) rig.resize(size);
      rig.setFrame(widget.insets, fill: widget.fill);
      return DragTarget<PaletteItem>(
        onAcceptWithDetails: (details) {
          final box = context.findRenderObject()! as RenderBox;
          _place(details.data, _world(box.globalToLocal(details.offset)));
        },
        builder: (context, candidates, rejected) => Listener(
          onPointerSignal: _onPointerSignal,
          onPointerDown: (e) => _down = e.localPosition,
          child: MouseRegion(
            onHover: (e) => widget.onHover?.call(_world(e.localPosition)),
            onExit: (_) => widget.onHover?.call(null),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: _onTapUp,
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onScaleEnd: _onScaleEnd,
              child: ListenableBuilder(
                listenable: _c,
                builder: (context, _) => Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: EditorPainter(
                          controller: _c,
                          rig: rig,
                          theme: widget.pack?.theme,
                          layer: EditorLayer.ground,
                        ),
                      ),
                    ),
                    _ground(),
                    for (final g in _c.world.groundArt) _groundDecoration(g),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: EditorPainter(controller: _c, rig: rig, theme: widget.pack?.theme),
                      ),
                    ),
                    if (_c.shown.base case final base?) _baseSprite(base),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: EditorHandlesPainter(controller: _c, rig: rig),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  /// The ground art (`world.art.ground`) over the play area, as in the game.
  Widget _ground() {
    final world = _c.world;
    final topLeft = rig.worldToScreen(Offset.zero);
    return Positioned(
      left: topLeft.dx,
      top: topLeft.dy,
      child: IgnorePointer(
        child: PackSprite(
          pack: widget.pack,
          id: world.art['ground'],
          size: world.playWidth * rig.zoom,
          height: world.playHeight * rig.zoom,
          placeholderColor: Colors.transparent,
        ),
      ),
    );
  }

  /// A decoration on the ground (`world.groundArt`), as in the original's editor
  /// (main timeline frame 42).
  Widget _groundDecoration(GroundArt g) {
    final frame = widget.pack?.sprite(g.art)?.frames.first;
    if (frame == null) return const SizedBox.shrink();
    final scale = g.scale * rig.zoom;
    final size = frame.worldSize * scale;
    final anchor = Offset(frame.anchorX, frame.anchorY) / frame.scale * scale;
    final at = rig.worldToScreen(Offset(g.x, g.y)) - anchor;
    return Positioned(
      left: at.dx,
      top: at.dy,
      child: IgnorePointer(
        child: Transform.rotate(
          angle: g.rotation * math.pi / 180,
          origin: anchor - size.center(Offset.zero),
          child: PackSprite(
            pack: widget.pack,
            id: g.art,
            size: size.width,
            height: size.height,
            placeholderColor: Colors.transparent,
          ),
        ),
      ),
    );
  }

  /// The base art (`world.art.base`) over its footprint; the sprite is
  /// drawn fitted into a square as wide as the base.
  Widget _baseSprite(Vec2 base) {
    final p = _c.world.placement;
    final topLeft = rig.worldToScreen(Offset(base.x, base.y));
    final side = p.baseWidth * rig.zoom;
    final drag = _c.drag;
    final faded = drag != null && drag.target is BaseTarget && !drag.valid;
    return Positioned(
      left: topLeft.dx,
      top: topLeft.dy + (p.baseHeight * rig.zoom - side) / 2,
      child: IgnorePointer(
        child: PackSprite(
          pack: widget.pack,
          id: _c.world.art['base'],
          size: side,
          placeholderColor: Colors.transparent,
          opacity: faded ? 0.4 : 1,
        ),
      ),
    );
  }
}

enum _Gesture { none, drag, pan, zoom }

Paint _stroke(double width, Color color) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..color = color;

/// Which part of the world an [EditorPainter] draws: the ground goes under
/// the ground art, the map (grid, road, base footprint) over it.
enum EditorLayer { ground, map }

/// The world layer: off-map margin and ground colour, or the grid, road and
/// base footprint.
class EditorPainter extends CustomPainter {
  EditorPainter({
    required this.controller,
    required this.rig,
    this.theme,
    this.layer = EditorLayer.map,
  }) : super(repaint: controller);

  final MapEditorController controller;
  final CameraRig rig;
  final PackTheme? theme;
  final EditorLayer layer;

  static const Color _ground = AppColours.ground;
  static const Color _offMap = Color(0xFF2C3A20);
  static const Color _gridLine = Color(0x33333333);
  static const Color _bad = Color(0xFFE53935);

  @override
  void paint(Canvas canvas, Size size) {
    final world = controller.world;
    final rules = world.editor;
    final draft = controller.shown;
    if (layer == EditorLayer.ground) {
      canvas
        ..drawRect(Offset.zero & size, Paint()..color = theme?.offMap ?? _offMap)
        ..drawRect(
          Rect.fromPoints(
            rig.worldToScreen(Offset.zero),
            rig.worldToScreen(Offset(world.playWidth, world.playHeight)),
          ),
          Paint()..color = theme?.background ?? _ground,
        );
      return;
    }
    canvas.save();
    rig.applyTo(canvas);

    // The grid while snapping is on (`gridDraw`: every 6th line heavier).
    if (controller.snap) {
      final thin = Paint()
        ..color = _gridLine
        ..strokeWidth = 1 / rig.zoom;
      final thick = Paint()
        ..color = _gridLine
        ..strokeWidth = 2 / rig.zoom;
      var i = 0;
      for (var x = 0.0; x <= world.playWidth; x += rules.gridSize, i++) {
        canvas.drawLine(Offset(x, 0), Offset(x, world.playHeight), i % 6 == 0 ? thick : thin);
      }
      i = 0;
      for (var y = 0.0; y <= world.playHeight; y += rules.gridSize, i++) {
        canvas.drawLine(Offset(0, y), Offset(world.playWidth, y), i % 6 == 0 ? thick : thin);
      }
    }

    final road = draft.roadPoints(rules);
    if (road.length > 1) {
      final path = Path()..moveTo(road.first.x, road.first.y);
      for (final p in road.skip(1)) {
        path.lineTo(p.x, p.y);
      }
      final style = world.road;
      canvas
        ..drawPath(path, _stroke(style.outerWidth, Color(0xFF000000 | style.outerColor)))
        ..drawPath(path, _stroke(style.innerWidth, Color(0xFF000000 | style.innerColor)));
    }

    final base = draft.base;
    if (base != null) {
      final drag = controller.drag;
      final bad = drag != null && drag.target is BaseTarget && !drag.valid;
      canvas.drawRect(
        Rect.fromLTWH(base.x, base.y, world.placement.baseWidth, world.placement.baseHeight),
        _stroke(2 / rig.zoom, bad ? _bad : const Color(0x99FFFFFF)),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(EditorPainter old) => true;
}

/// The handle layer, drawn at a fixed screen size: "+" handles, the start,
/// waypoints (the selected one ringed) and the road's base entry.
class EditorHandlesPainter extends CustomPainter {
  EditorHandlesPainter({required this.controller, required this.rig}) : super(repaint: controller);

  final MapEditorController controller;
  final CameraRig rig;

  static const Color _start = Color(0xFF43A047);
  static const Color _waypoint = Color(0xFFFFFFFF);
  static const Color _selected = Color(0xFFFFD54F);
  static const Color _outline = Color(0xFF212121);
  static const Color _bad = Color(0xFFE53935);

  Offset _s(Vec2 p) => rig.worldToScreen(Offset(p.x, p.y));

  @override
  void paint(Canvas canvas, Size size) {
    final rules = controller.rules;
    final draft = controller.shown;
    final drag = controller.drag;
    final fill = Paint();
    final line = _stroke(2, _outline);

    if (drag == null) {
      for (final h in draft.midpoints(rules)) {
        final c = _s(h.at);
        canvas
          ..drawCircle(c, EditorHandles.midpoint, fill..color = const Color(0xCCFFFFFF))
          ..drawCircle(c, EditorHandles.midpoint, line)
          ..drawLine(c - const Offset(4, 0), c + const Offset(4, 0), line)
          ..drawLine(c - const Offset(0, 4), c + const Offset(0, 4), line);
      }
    }

    final road = draft.roadPoints(rules);
    if (draft.base != null && road.isNotEmpty) {
      canvas.drawCircle(_s(road.last), 4, fill..color = _outline);
    }

    for (var i = 0; i < draft.waypoints.length; i++) {
      final c = _s(draft.waypoints[i]);
      final dragged =
          drag != null &&
          drag.target is WaypointTarget &&
          (drag.target as WaypointTarget).index == i;
      final color = dragged && !drag.valid ? _bad : _waypoint;
      if (controller.selected == i) {
        canvas.drawCircle(c, EditorHandles.waypoint + 6, _stroke(3, _selected));
      }
      canvas
        ..drawCircle(c, EditorHandles.waypoint, fill..color = color)
        ..drawCircle(c, EditorHandles.waypoint, line);
    }

    final start = draft.start;
    if (start != null) {
      final c = _s(start);
      final bad = drag != null && drag.target is StartTarget && !drag.valid;
      canvas
        ..drawCircle(c, EditorHandles.start, fill..color = bad ? _bad : _start)
        ..drawCircle(c, EditorHandles.start, line);
      final flag = Path()
        ..moveTo(c.dx - 4, c.dy + 7)
        ..lineTo(c.dx - 4, c.dy - 7)
        ..lineTo(c.dx + 6, c.dy - 3.5)
        ..lineTo(c.dx - 4, c.dy);
      canvas.drawPath(flag, _stroke(2, const Color(0xFFFFFFFF)));
    }
  }

  @override
  bool shouldRepaint(EditorHandlesPainter old) => true;
}
