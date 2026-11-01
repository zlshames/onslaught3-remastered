import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/app/camera_rig.dart';
import 'package:onslaught3_remastered/app/ui_skin.dart';
import 'package:onslaught3_remastered/features/game/layout/hud_layout.dart';

void main() {
  const world = Rect.fromLTWH(0, 0, 720, 480);

  /// Screens (logical px) in both orientations, plus desktop windows.
  const screens = [
    Size(874, 402),
    Size(402, 874),
    Size(923, 411),
    Size(411, 923),
    Size(667, 375),
    Size(375, 667),
    Size(1210, 834),
    Size(834, 1210),
    Size(1280, 720),
    Size(600, 900),
    Size(800, 800),
  ];

  /// Typical safe areas for [s]: none, a notch on the long side's end in
  /// landscape (iPhone), a notch on top and a home indicator in portrait.
  List<EdgeInsets> safeFor(Size s) => [
    EdgeInsets.zero,
    if (s.width > s.height)
      const EdgeInsets.fromLTRB(62, 0, 62, 21)
    else
      const EdgeInsets.fromLTRB(0, 62, 0, 34),
  ];

  bool overlaps(Rect a, Rect b) => a.intersect(b).width > 1e-9 && a.intersect(b).height > 1e-9;

  for (final skin in UiSkin.values) {
    for (final s in screens) {
      for (final safe in safeFor(s)) {
        test('$skin $s $safe: regions are consistent', () {
          final l = HudLayout.resolve(s, safe, skin: skin);
          expect(l.kind, isNot(HudLayoutKind.unsupported));
          expect(l.kind == HudLayoutKind.portrait, s.height > s.width, reason: '$l');
          expect(l.fillsMap, l.kind == HudLayoutKind.portrait);
          if (skin == UiSkin.classic) expect(l.kind, isNot(HudLayoutKind.rails));
          // HUD regions never cover the map area, or each other.
          expect(overlaps(l.stats, l.map), isFalse, reason: 'stats ${l.stats} map ${l.map}');
          expect(overlaps(l.tray, l.map), isFalse, reason: 'tray ${l.tray} map ${l.map}');
          expect(overlaps(l.stats, l.tray), isFalse);
          // The map insets describe the map rect.
          expect(l.mapInsets.deflateRect(Offset.zero & s), l.map);
          // The map stays inside the safe area.
          expect(
            safe.deflateRect(Offset.zero & s).expandToInclude(l.map),
            safe.deflateRect(Offset.zero & s),
          );
          expect(l.isOverHud(l.stats.center), isTrue);
          expect(l.isOverHud(l.tray.center), isTrue);
          expect(l.isOverHud(l.map.center), isFalse);
          // The zooms are the camera's, which starts at home.
          final rig = CameraRig(world: world)
            ..resize(s)
            ..setFrame(l.mapInsets, fill: l.fillsMap);
          expect(l.fitZoom, closeTo(rig.fitZoom, 1e-9));
          expect(l.closeZoom, closeTo(rig.homeZoom, 1e-9));
          expect(rig.zoom, closeTo(l.closeZoom, 1e-9));
          final shown = Rect.fromPoints(
            rig.worldToScreen(world.topLeft),
            rig.worldToScreen(world.bottomRight),
          );
          if (l.fillsMap) {
            // The upright map covers the map rect; the rest is a pan away.
            expect(shown.inflate(1e-6).contains(l.map.topLeft), isTrue, reason: '$shown');
            expect(
              shown.inflate(1e-6).contains(l.map.bottomRight - const Offset(1e-3, 1e-3)),
              isTrue,
              reason: '$shown',
            );
          } else {
            // The whole fitted map lies inside the map rect.
            expect(l.map.inflate(1e-6).contains(shown.topLeft), isTrue, reason: '$shown');
            expect(
              l.map.inflate(1e-6).contains(shown.bottomRight - const Offset(1e-3, 1e-3)),
              isTrue,
              reason: '$shown',
            );
          }
        });
      }
    }
  }

  test('phones in either orientation give turrets of at least 24 pt', () {
    for (final s in [
      const Size(874, 402),
      const Size(402, 874),
      const Size(923, 411),
      const Size(411, 923),
      const Size(667, 375),
      const Size(375, 667),
    ]) {
      for (final skin in UiSkin.values) {
        final l = HudLayout.resolve(s, EdgeInsets.zero, skin: skin);
        expect(l.closeZoom * HudMetrics.turretWorldPx, greaterThanOrEqualTo(24), reason: '$s $l');
      }
    }
  });

  test('the sanity table of the plan', () {
    HudLayoutKind kind(Size s, UiSkin skin) =>
        HudLayout.resolve(s, EdgeInsets.zero, skin: skin).kind;
    expect(kind(const Size(923, 411), UiSkin.classic), HudLayoutKind.bars);
    expect(kind(const Size(923, 411), UiSkin.enhanced), HudLayoutKind.rails);
    expect(kind(const Size(402, 874), UiSkin.classic), HudLayoutKind.portrait);
    expect(kind(const Size(834, 1210), UiSkin.classic), HudLayoutKind.portrait);
    // Tablets keep the top bar: it beats rails (1.575 vs 1.47).
    expect(kind(const Size(1210, 834), UiSkin.enhanced), HudLayoutKind.bars);
    final portrait = HudLayout.resolve(const Size(402, 874), EdgeInsets.zero, skin: UiSkin.classic);
    // The whole map fits the width; the home view fills the height.
    expect(portrait.fitZoom, closeTo(402 / 720, 1e-9));
    expect(portrait.closeZoom, closeTo((874 - 48 - 88) / 480, 1e-9));
    // A square window is not portrait.
    expect(kind(const Size(800, 800), UiSkin.classic), HudLayoutKind.bars);
    expect(portrait.trayAxis, Axis.horizontal);
    expect(portrait.tray, const Rect.fromLTRB(0, 874 - 88.0, 402, 874));
  });

  test('a close call keeps the previous layout (hysteresis)', () {
    // A big desktop window just taller than wide: portrait's whole map is
    // under 5 % bigger than bars'.
    const near = Size(1600, 1700);
    final fresh = HudLayout.resolve(near, EdgeInsets.zero, skin: UiSkin.classic);
    expect(fresh.kind, HudLayoutKind.portrait);
    final bars = HudLayout.resolve(const Size(1700, 1600), EdgeInsets.zero, skin: UiSkin.classic);
    expect(bars.kind, HudLayoutKind.bars);
    final kept = HudLayout.resolve(near, EdgeInsets.zero, skin: UiSkin.classic, previous: bars);
    expect(kept.kind, HudLayoutKind.bars);
    // A clear win still switches.
    final tall = HudLayout.resolve(
      const Size(900, 1700),
      EdgeInsets.zero,
      skin: UiSkin.classic,
      previous: bars,
    );
    expect(tall.kind, HudLayoutKind.portrait);
  });

  test('a tiny window is unsupported', () {
    for (final skin in UiSkin.values) {
      for (final size in const [Size(300, 200), Size(200, 300)]) {
        final l = HudLayout.resolve(size, EdgeInsets.zero, skin: skin);
        expect(l.kind, HudLayoutKind.unsupported, reason: '$size');
      }
    }
  });

  test('the play area and turret footprint come from the caller (the game data)', () {
    const screen = Size(923, 411);
    final classic = HudLayout.resolve(screen, EdgeInsets.zero, skin: UiSkin.classic);
    expect(classic.world, HudMetrics.world);
    expect(classic.turretWorldPx, HudMetrics.turretWorldPx);
    // Twice as big a play area: the same regions, half the fit.
    const wide = Size(1440, 960);
    final fitted = HudLayout.resolve(screen, EdgeInsets.zero, skin: UiSkin.classic, world: wide);
    expect(fitted.world, wide);
    expect(fitted.map, classic.map);
    expect(fitted.fitZoom, closeTo(classic.fitZoom / 2, 1e-9));
    expect(fitted, isNot(classic));
    // A taller play area in portrait: the whole map still fits the width,
    // the home view still fills the height.
    const tall = Size(720, 960);
    final portrait = HudLayout.resolve(
      const Size(402, 874),
      EdgeInsets.zero,
      skin: UiSkin.classic,
      world: tall,
    );
    expect(portrait.kind, HudLayoutKind.portrait);
    expect(portrait.fitZoom, closeTo(402 / 720, 1e-9));
    expect(portrait.closeZoom, closeTo((874 - 48 - 88) / 960, 1e-9));
    // Smaller turrets make a screen unsupported sooner: a tablet is fine
    // at the data's 36 px footprint, not at 10 px.
    final small = HudLayout.resolve(
      screen,
      EdgeInsets.zero,
      skin: UiSkin.classic,
      turretWorldPx: 10,
    );
    expect(small.turretWorldPx, 10);
    expect(small.kind, HudLayoutKind.unsupported);
    expect(small.map, classic.map, reason: 'the best candidate\'s regions are kept');
  });

  test('the panel opens away from the turret where the skin allows', () {
    final classic = HudLayout.resolve(const Size(923, 411), EdgeInsets.zero, skin: UiSkin.classic);
    final low = Offset(400, classic.map.bottom - 10);
    final high = Offset(400, classic.map.top + 10);
    expect(classic.sheetEdgeFor(low), SheetEdge.bottom);
    expect(classic.sheetEdgeFor(high), SheetEdge.bottom);
    expect(classic.panelFor(low), const Rect.fromLTRB(0, 48, 923 - 76.0, 411));

    final portrait = HudLayout.resolve(const Size(402, 874), EdgeInsets.zero, skin: UiSkin.classic);
    expect(portrait.sheetEdgeFor(Offset(200, portrait.map.bottom - 10)), SheetEdge.top);
    expect(portrait.sheetEdgeFor(Offset(200, portrait.map.top + 10)), SheetEdge.bottom);
    expect(portrait.sheetEdgeFor(null), SheetEdge.bottom);
    // The portrait sheet covers the strip.
    expect(portrait.panelFor(null).right, 402);

    final rails = HudLayout.resolve(const Size(923, 411), EdgeInsets.zero, skin: UiSkin.enhanced);
    expect(rails.sheetEdgeFor(Offset(rails.map.right - 10, 200)), SheetEdge.left);
    expect(rails.sheetEdgeFor(Offset(rails.map.left + 10, 200)), SheetEdge.right);
    expect(rails.panelFor(Offset(rails.map.right - 10, 200)).width, HudMetrics.sidePanelWidth);

    final bars = HudLayout.resolve(const Size(1210, 834), EdgeInsets.zero, skin: UiSkin.enhanced);
    expect(bars.sheetEdgeFor(Offset(500, bars.map.bottom - 10)), SheetEdge.top);
    expect(bars.sheetEdgeFor(Offset(500, bars.map.top + 10)), SheetEdge.bottom);
  });

  test('the tutorial window sits beside the road in landscape, over the top in portrait', () {
    final land = HudLayout.resolve(const Size(923, 411), EdgeInsets.zero, skin: UiSkin.classic);
    expect(land.tutorialWindow, const Rect.fromLTWH(8, 56, 320, 411 - 48 - 24.0));
    expect(land.toasts(tutorial: true).left, 8 + 320 + 8);
    final port = HudLayout.resolve(const Size(402, 874), EdgeInsets.zero, skin: UiSkin.classic);
    expect(port.tutorialWindow.width, 402 - 16);
    expect(port.toasts(tutorial: true).top, greaterThan(port.tutorialWindow.bottom));
  });
}
