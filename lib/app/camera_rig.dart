import 'dart:math' as math;
import 'dart:ui' show Canvas, Offset, Rect, Size;

import 'package:flutter/painting.dart' show EdgeInsets;

/// Presentation tuning for the game camera (not balance data).
class CameraSettings {
  const CameraSettings({this.maxZoom = 3.0, this.margin = 40, this.doubleTapZoom = 2.0});

  /// Upper zoom bound as a multiple of the fit-whole-map zoom
  /// (`docs/REMASTER_PLAN.md` §3.1: zoom clamped to `[fitWholeMap, 3.0]`;
  /// read relative to fit so it means the same on every screen size).
  final double maxZoom;

  /// World px the view may pan beyond the play area when zoomed in.
  final double margin;

  /// Zoom factor (relative to fit) a double tap toggles to.
  final double doubleTapZoom;
}

/// Camera state and its rules, independent of Flame so it can be unit
/// tested: zoom clamped to `[fit, max]`, centre clamped so the visible rect
/// stays inside the play area plus margin (centred on an axis where the view
/// is larger), pinch zooms about the focal point.
///
/// Zoom is screen logical px per world px. "fit" shows the whole 720×480
/// play area inside the part of the screen the HUD leaves free ([insets]);
/// on a wide phone the extra width shows the off-map margin.
///
/// The home view (where a game starts, and what a resize keeps) is fit, or
/// with [fill] (portrait screens, `docs/history/PORTRAIT_PLAN.md`) the zoom at which
/// the play area covers the whole free area: the map stays upright, fills
/// the screen, and the player pans along it or pinches out to see all of it.
class CameraRig {
  CameraRig({required this.world, this.settings = const CameraSettings()}) : center = world.center;

  /// The play area in world px.
  final Rect world;
  final CameraSettings settings;

  Size viewport = Size.zero;
  double zoom = 1;
  Offset center;

  /// Screen edges covered by HUD (top bar, tower tray). Fit and pan limits
  /// apply to the rest of the screen; the map still draws under the HUD.
  EdgeInsets insets = EdgeInsets.zero;

  /// The home view fills the free area (portrait) instead of fitting the
  /// whole play area into it.
  bool get fill => _fill;
  bool _fill = false;

  /// With [fill], how far the home view zooms out instead of covering the
  /// free area: this zoom, kept between fit and covering (the game's portrait
  /// view, which starts showing as much of the map as it can). Null covers.
  double? _homeFloor;

  /// The part of the viewport not covered by HUD, in screen px.
  Rect get free => _freeIn(viewport, insets);

  static Rect _freeIn(Size viewport, EdgeInsets insets) {
    final r = insets.deflateRect(Offset.zero & viewport);
    return r.width > 0 && r.height > 0 ? r : Offset.zero & viewport;
  }

  /// The zoom that fits a [world]-sized play area into [viewport] less
  /// [insets]; 1 for an empty viewport. The HUD layout compares these to
  /// pick the shape that shows the biggest whole map.
  static double fitZoomFor(Size viewport, EdgeInsets insets, Size world) {
    if (viewport.isEmpty) return 1;
    final free = _freeIn(viewport, insets);
    return math.min(free.width / world.width, free.height / world.height);
  }

  /// The zoom at which a [world]-sized play area covers [viewport] less
  /// [insets] (the [fill] home view); 1 for an empty viewport.
  static double fillZoomFor(Size viewport, EdgeInsets insets, Size world) {
    if (viewport.isEmpty) return 1;
    final free = _freeIn(viewport, insets);
    return math.max(free.width / world.width, free.height / world.height);
  }

  double get fitZoom => fitZoomFor(viewport, insets, world.size);

  double get _coverZoom => fillZoomFor(viewport, insets, world.size);

  /// The zoom of the home view: fit, or with [fill] the covering zoom or the
  /// floor it was given.
  double get homeZoom {
    if (!_fill) return fitZoom;
    return _homeFloor?.clamp(fitZoom, _coverZoom) ?? _coverZoom;
  }

  double get minZoom => fitZoom;

  /// [CameraSettings.maxZoom] × fit, and at least double-tap × the covering
  /// zoom so a filled view can still zoom in.
  double get maxZoom => math.max(
    fitZoom * math.max(1, settings.maxZoom),
    (_fill ? _coverZoom : fitZoom) * math.max(1, settings.doubleTapZoom),
  );

  /// Zoom relative to fit (1 = whole map).
  double get relativeZoom => zoom / fitZoom;

  bool get isAtFit => (zoom - fitZoom).abs() < fitZoom * 0.01;

  /// Whether the view is at the home zoom.
  bool get isAtHome => (zoom - homeZoom).abs() < homeZoom * 0.01;

  /// The world rect currently visible.
  Rect get visible =>
      Rect.fromCenter(center: center, width: viewport.width / zoom, height: viewport.height / zoom);

  /// Updates the viewport (resize/rotation); keeps the zoom relative to
  /// home, and a view at home (or the first) stays at home.
  void resize(Size size) {
    if (size == viewport) return;
    _reframe(() => viewport = size);
  }

  /// Shows the whole play area.
  void fit() {
    zoom = fitZoom;
    center = world.center - _freeOffset;
    _clampCenter();
  }

  /// The home view: at [homeZoom], centred.
  void home() {
    zoom = homeZoom;
    center = world.center - _freeOffset;
    _clampCenter();
  }

  /// Sets the HUD [insets]; keeps relative zoom (a view at home stays home).
  void setInsets(EdgeInsets value) => setFrame(value, fill: _fill, homeFloor: _homeFloor);

  /// Sets [insets], [fill] and the home view's floor together. Whatever order
  /// a rotation delivers this and [resize] in, the view ends the same: a view
  /// at home stays at home, otherwise the zoom relative to home and the world
  /// point at the middle of the free area are kept.
  void setFrame(EdgeInsets value, {bool fill = false, double? homeFloor}) {
    if (value == insets && fill == _fill && homeFloor == _homeFloor) return;
    _reframe(() {
      insets = value;
      _fill = fill;
      _homeFloor = homeFloor;
    });
  }

  void _reframe(void Function() change) {
    final first = viewport.isEmpty;
    final wasHome = first || isAtHome;
    final rel = first ? 1.0 : zoom / homeZoom;
    final seen = center + _freeOffset;
    change();
    if (wasHome) return home();
    zoom = (homeZoom * rel).clamp(minZoom, maxZoom);
    center = seen - _freeOffset;
    _clampCenter();
  }

  /// World offset from the viewport centre to the free area's centre.
  Offset get _freeOffset => (free.center - viewport.center(Offset.zero)) / zoom;

  /// Pans by a screen-space delta (finger movement).
  void panBy(Offset screenDelta) {
    center -= screenDelta / zoom;
    _clampCenter();
  }

  /// Sets zoom to [newZoom] keeping the world point under [focal] (screen
  /// position) fixed.
  void zoomAbout(double newZoom, Offset focal) {
    final anchor = screenToWorld(focal);
    zoom = newZoom.clamp(minZoom, maxZoom);
    final fromCentre = focal - viewport.center(Offset.zero);
    center = anchor - fromCentre / zoom;
    _clampCenter();
  }

  /// Multiplies zoom by [factor] about [focal].
  void zoomBy(double factor, Offset focal) => zoomAbout(zoom * factor, focal);

  /// Double tap: away from home, back home; at home, `doubleTapZoom × fit`
  /// at [focal], or with [fill] out to the whole map, or from a floored home
  /// in to the covering zoom at [focal].
  void toggleZoom(Offset focal) {
    if (!isAtHome) return home();
    if (_fill && _homeFloor == null) return fit();
    zoomAbout(_fill ? _coverZoom : fitZoom * settings.doubleTapZoom, focal);
  }

  /// Pans the least needed so [worldPoint] shows inside the free area with
  /// [pad] px to spare (a tutorial arrow's target on a filled view); true
  /// when the view moved.
  bool panToShow(Offset worldPoint, {double pad = 32}) {
    final at = worldToScreen(worldPoint);
    final area = free.deflate(pad);
    if (area.isEmpty || area.inflate(0.5).contains(at)) return false;
    final to = Offset(at.dx.clamp(area.left, area.right), at.dy.clamp(area.top, area.bottom));
    final before = center;
    panBy(to - at);
    return center != before;
  }

  /// Pans the least needed so [worldPoint], when it lies under [keepOut]
  /// (a panel over part of the map, in screen px, widened by [pad]), shows
  /// just past the panel's nearest side inside the free area; true when the
  /// view moved. Where the pan clamp forbids it, nothing moves.
  bool ensureVisible(Offset worldPoint, Rect keepOut, {double pad = 24}) {
    final at = worldToScreen(worldPoint);
    final zone = keepOut.inflate(pad);
    if (!zone.contains(at)) return false;
    final area = free.deflate(pad);
    final spots = [
      Offset(at.dx, zone.top),
      Offset(at.dx, zone.bottom),
      Offset(zone.left, at.dy),
      Offset(zone.right, at.dy),
    ].where(area.contains).toList();
    if (spots.isEmpty) return false;
    spots.sort((a, b) => (a - at).distanceSquared.compareTo((b - at).distanceSquared));
    final before = center;
    panBy(spots.first - at);
    return center != before;
  }

  Offset screenToWorld(Offset p) => center + (p - viewport.center(Offset.zero)) / zoom;

  Offset worldToScreen(Offset w) => (w - center) * zoom + viewport.center(Offset.zero);

  /// Sets [canvas] up to draw in world px (the editor's painters).
  void applyTo(Canvas canvas) {
    final c = viewport.center(Offset.zero);
    canvas
      ..translate(c.dx, c.dy)
      ..scale(zoom)
      ..translate(-center.dx, -center.dy);
  }

  /// Keeps the world seen through the free area inside the play area plus
  /// margin (centred on an axis where the free area is larger).
  void _clampCenter() {
    final bounds = world.inflate(settings.margin);
    final halfW = free.width / zoom / 2;
    final halfH = free.height / zoom / 2;
    double clampAxis(double c, double lo, double hi, double half) =>
        hi - lo <= half * 2 ? (lo + hi) / 2 : c.clamp(lo + half, hi - half);
    final seen = center + _freeOffset;
    center =
        Offset(
          clampAxis(seen.dx, bounds.left, bounds.right, halfW),
          clampAxis(seen.dy, bounds.top, bounds.bottom, halfH),
        ) -
        _freeOffset;
  }
}
