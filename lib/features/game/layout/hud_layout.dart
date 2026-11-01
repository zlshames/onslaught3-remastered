import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../../app/camera_rig.dart';
import '../../../app/ui_skin.dart';

/// The HUD's shape on a screen (`docs/history/SCREEN_FIT_PLAN.md` §4).
enum HudLayoutKind {
  /// Stats bar on top, tower tray down the right: landscape (Classic's only
  /// landscape layout, exactly as v1).
  bars,

  /// Stats down the left, tray down the right, the map full height
  /// (Enhanced, wide landscape screens).
  rails,

  /// Tall screens: stats on top, tray as a strip along the bottom, the map
  /// upright and filling the space between (the player pans along it).
  portrait,

  /// No layout gives turrets big enough to tap (a tiny desktop window).
  unsupported,
}

/// The screen edge the selected-turret panel opens against.
enum SheetEdge { bottom, top, left, right }

/// HUD sizes (presentation tuning, like `CameraSettings`; not balance data).
abstract final class HudMetrics {
  /// Height of the horizontal stats bar.
  static const double statsBarHeight = 48;

  /// Width of the tray (and the stats rail) down a side.
  static const double trayRailWidth = 76;

  /// Height of the tray as a strip along the bottom.
  static const double trayStripHeight = 88;

  /// Height of the wide selected-turret sheet.
  static const double sheetHeight = 112;

  /// Width of the side panel in `rails`.
  static const double sidePanelWidth = 240;

  /// Below this width the stats bar and turret sheet use their compact
  /// forms. Less than the narrowest landscape map area (iPhone SE: 667 − 76
  /// = 591) so landscape keeps v1's forms.
  static const double compactBelow = 560;

  /// A new layout must beat the current one's fit zoom by this share to
  /// replace it (a window being resized does not flicker between layouts).
  static const double hysteresis = 0.05;

  /// The smallest on-screen turret (logical px) a layout may give at fit.
  static const double minTurretPt = 20;

  /// A turret's footprint in world px, for [minTurretPt]: the default of
  /// [HudLayout.resolve] for tests; the game passes the data's
  /// `placement.turretSpacing` (`world.json`).
  static const double turretWorldPx = 36;

  /// The play area the layouts fit, in world px: the default of
  /// [HudLayout.resolve] for tests; the game passes the data's `playArea`
  /// (`world.json`).
  static const Size world = Size(720, 480);
}

/// Where the HUD goes on one screen: the chosen [kind], the rects of the
/// fixed HUD regions, and the rect the map is framed in. A pure function of
/// the screen size, safe area and skin; the game screen positions every
/// overlay from it, the camera takes [mapInsets] and [fillsMap], and tray
/// drags ask [isOverHud].
@immutable
class HudLayout {
  const HudLayout._({
    required this.kind,
    required this.skin,
    required this.screen,
    required this.safe,
    required this.stats,
    required this.tray,
    required this.map,
    required this.fitZoom,
    required this.world,
    required this.turretWorldPx,
  });

  /// The layout for a [screen] with [safe] insets under [skin], fitting the
  /// play area [world] (world px) whose turrets are [turretWorldPx] across;
  /// the game passes both from its data (`world.json`: `playArea`,
  /// `placement.turretSpacing`), the defaults are for tests. Candidates
  /// are `bars`, `rails` when the skin offers it, and `portrait` on a screen
  /// taller than wide; the one whose whole map fits biggest wins, but
  /// [previous] stays unless it is beaten by more than
  /// [HudMetrics.hysteresis]. When even the best gives turrets under
  /// [HudMetrics.minTurretPt] in its home view the kind is `unsupported`
  /// (with the best candidate's regions, drawn under the prompt).
  static HudLayout resolve(
    Size screen,
    EdgeInsets safe, {
    required UiSkin skin,
    HudLayout? previous,
    Size world = HudMetrics.world,
    double turretWorldPx = HudMetrics.turretWorldPx,
  }) {
    final candidates = [
      _candidate(HudLayoutKind.bars, screen, safe, skin, world, turretWorldPx),
      if (skin.offersRails)
        _candidate(HudLayoutKind.rails, screen, safe, skin, world, turretWorldPx),
      if (screen.height > screen.width)
        _candidate(HudLayoutKind.portrait, screen, safe, skin, world, turretWorldPx),
    ];
    var best = candidates.reduce((a, b) => b.fitZoom > a.fitZoom ? b : a);
    final kept = previous?.kind == HudLayoutKind.unsupported ? null : previous?.kind;
    for (final c in candidates) {
      if (c.kind == kept && c.fitZoom >= best.fitZoom * (1 - HudMetrics.hysteresis)) best = c;
    }
    if (best.closeZoom * turretWorldPx >= HudMetrics.minTurretPt) return best;
    return HudLayout._(
      kind: HudLayoutKind.unsupported,
      skin: skin,
      screen: screen,
      safe: safe,
      stats: best.stats,
      tray: best.tray,
      map: best.map,
      fitZoom: best.fitZoom,
      world: world,
      turretWorldPx: turretWorldPx,
    );
  }

  static HudLayout _candidate(
    HudLayoutKind kind,
    Size screen,
    EdgeInsets safe,
    UiSkin skin,
    Size world,
    double turretWorldPx,
  ) {
    final w = screen.width;
    final h = screen.height;
    final (stats, tray, insets) = switch (kind) {
      HudLayoutKind.rails => (
        Rect.fromLTRB(0, 0, HudMetrics.trayRailWidth + safe.left, h),
        Rect.fromLTRB(w - HudMetrics.trayRailWidth - safe.right, 0, w, h),
        EdgeInsets.fromLTRB(
          HudMetrics.trayRailWidth + safe.left,
          safe.top,
          HudMetrics.trayRailWidth + safe.right,
          safe.bottom,
        ),
      ),
      HudLayoutKind.portrait => (
        Rect.fromLTRB(0, 0, w, HudMetrics.statsBarHeight + safe.top),
        Rect.fromLTRB(0, h - HudMetrics.trayStripHeight - safe.bottom, w, h),
        EdgeInsets.fromLTRB(
          safe.left,
          HudMetrics.statsBarHeight + safe.top,
          safe.right,
          HudMetrics.trayStripHeight + safe.bottom,
        ),
      ),
      _ => (
        Rect.fromLTRB(0, 0, w, HudMetrics.statsBarHeight + safe.top),
        Rect.fromLTRB(
          w - HudMetrics.trayRailWidth - safe.right,
          HudMetrics.statsBarHeight + safe.top,
          w,
          h,
        ),
        EdgeInsets.fromLTRB(
          safe.left,
          HudMetrics.statsBarHeight + safe.top,
          HudMetrics.trayRailWidth + safe.right,
          safe.bottom,
        ),
      ),
    };
    return HudLayout._(
      kind: kind,
      skin: skin,
      screen: screen,
      safe: safe,
      stats: stats,
      tray: tray,
      map: insets.deflateRect(Offset.zero & screen),
      fitZoom: CameraRig.fitZoomFor(screen, insets, world),
      world: world,
      turretWorldPx: turretWorldPx,
    );
  }

  final HudLayoutKind kind;
  final UiSkin skin;
  final Size screen;

  /// The screen's safe-area insets (notch, home indicator).
  final EdgeInsets safe;

  /// The stats bar (or rail), safe-area padding included.
  final Rect stats;

  /// The tower tray, safe-area padding included.
  final Rect tray;

  /// The part of the screen the map is fitted into (the camera's free area).
  final Rect map;

  /// The zoom (screen px per world px) that shows the whole map in [map].
  final double fitZoom;

  /// The play area's size in world px.
  final Size world;

  /// A turret's footprint in world px (the tap-size check, pan paddings).
  final double turretWorldPx;

  /// The map fills [map] (portrait): upright, with the ground running on past
  /// it, and a double tap away from covering it.
  bool get fillsMap => kind == HudLayoutKind.portrait;

  /// The closest whole-area view: [fitZoom], or the covering zoom when
  /// [fillsMap]. A layout is playable when its turrets are big enough here.
  double get closeZoom => fillsMap ? CameraRig.fillZoomFor(screen, mapInsets, world) : fitZoom;

  /// When [fillsMap], how far the game starts zoomed out: as much of the map
  /// as fits with turrets still [HudMetrics.minTurretPt] across.
  double? get homeFloor => fillsMap ? HudMetrics.minTurretPt / turretWorldPx : null;

  /// The tray scrolls along this axis.
  Axis get trayAxis => kind == HudLayoutKind.portrait ? Axis.horizontal : Axis.vertical;

  /// The stats run along this axis.
  Axis get statsAxis => kind == HudLayoutKind.rails ? Axis.vertical : Axis.horizontal;

  /// What [stats]' controls keep clear of (a notch, a punch hole); its
  /// background still runs to the screen's edges.
  EdgeInsets get statsInset =>
      kind == HudLayoutKind.rails ? safe.copyWith(right: 0) : safe.copyWith(bottom: 0);

  /// What [tray]'s cells keep clear of; its background still runs to the
  /// screen's edges.
  EdgeInsets get trayInset => switch (kind) {
    HudLayoutKind.rails => safe.copyWith(left: 0),
    HudLayoutKind.portrait => safe.copyWith(top: 0),
    _ => safe.copyWith(left: 0, top: 0),
  };

  /// What the panel's controls keep clear of when it opens against [edge];
  /// its background still runs to the screen's edges. In landscape it stops
  /// at the tray, which covers the right side's inset.
  EdgeInsets panelInset(SheetEdge edge) {
    final right = kind == HudLayoutKind.portrait ? safe.right : 0.0;
    return switch (edge) {
      SheetEdge.bottom => EdgeInsets.fromLTRB(safe.left, 0, right, safe.bottom),
      SheetEdge.top => EdgeInsets.fromLTRB(safe.left, 0, right, 0),
      SheetEdge.left || SheetEdge.right => EdgeInsets.zero,
    };
  }

  /// Screen edges the camera keeps the fitted map clear of.
  EdgeInsets get mapInsets =>
      EdgeInsets.fromLTRB(map.left, map.top, screen.width - map.right, screen.height - map.bottom);

  /// Whether [p] (screen px) is over a fixed HUD region (a tray drag
  /// released there cancels).
  bool isOverHud(Offset p) => stats.contains(p) || tray.contains(p);

  /// Where the selected-turret panel opens for a turret at [turretScreen]
  /// (screen px; null when unknown): away from the turret where the skin
  /// allows (`docs/history/SCREEN_FIT_PLAN.md` §4.4), otherwise at the bottom.
  SheetEdge sheetEdgeFor(Offset? turretScreen) {
    final low = turretScreen != null && turretScreen.dy > map.center.dy;
    return switch (kind) {
      HudLayoutKind.rails =>
        turretScreen != null && turretScreen.dx > map.center.dx ? SheetEdge.left : SheetEdge.right,
      HudLayoutKind.portrait => low ? SheetEdge.top : SheetEdge.bottom,
      _ when skin.farSidePanelInLandscape && low => SheetEdge.top,
      _ => SheetEdge.bottom,
    };
  }

  /// The area the panel for a turret at [turretScreen] occupies; the panel
  /// sits against [sheetEdgeFor]'s edge of it, as tall (or, at the sides,
  /// as wide) as it needs.
  Rect panelFor(Offset? turretScreen) => switch (sheetEdgeFor(turretScreen)) {
    SheetEdge.left => Rect.fromLTWH(
      map.left,
      map.top,
      math.min(HudMetrics.sidePanelWidth, map.width / 2),
      map.height,
    ),
    SheetEdge.right => Rect.fromLTRB(
      map.right - math.min(HudMetrics.sidePanelWidth, map.width / 2),
      map.top,
      map.right,
      map.bottom,
    ),
    // In portrait the bottom sheet covers the strip; in landscape it stops
    // at the tray.
    SheetEdge.bottom => Rect.fromLTRB(
      0,
      map.top,
      kind == HudLayoutKind.portrait ? screen.width : tray.left,
      screen.height,
    ),
    SheetEdge.top => Rect.fromLTRB(
      0,
      map.top,
      kind == HudLayoutKind.portrait ? screen.width : tray.left,
      map.bottom,
    ),
  };

  /// The tutorial window's area: beside the road at the top left in
  /// landscape (v1), full width over the top of the map in portrait. The
  /// window is as tall as its page needs, up to this rect's height.
  Rect get tutorialWindow => kind == HudLayoutKind.portrait
      ? Rect.fromLTWH(map.left + 8, map.top + 8, map.width - 16, math.max(160, map.height * 0.4))
      : Rect.fromLTWH(
          kind == HudLayoutKind.rails ? map.left + 8 : 8,
          map.top + 8,
          math.min(320, screen.width * 0.42),
          math.max(160, screen.height - map.top - 24),
        );

  /// Where message toasts line up (centred along the top of this rect),
  /// clear of the tutorial window when it shows.
  Rect toasts({bool tutorial = false}) {
    if (!tutorial) return map;
    final window = tutorialWindow;
    return kind == HudLayoutKind.portrait
        ? Rect.fromLTRB(map.left, window.bottom + 8, map.right, map.bottom)
        : Rect.fromLTRB(window.right + 8, map.top, map.right, map.bottom);
  }

  @override
  bool operator ==(Object other) =>
      other is HudLayout &&
      other.kind == kind &&
      other.skin == skin &&
      other.screen == screen &&
      other.safe == safe &&
      other.stats == stats &&
      other.tray == tray &&
      other.map == map &&
      other.world == world &&
      other.turretWorldPx == turretWorldPx;

  @override
  int get hashCode => Object.hash(kind, skin, screen, safe, stats, tray, map, world, turretWorldPx);

  @override
  String toString() => 'HudLayout($kind, map $map, fit $fitZoom)';
}
