import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/app/camera_rig.dart';

void main() {
  const world = Rect.fromLTWH(0, 0, 720, 480);
  // Pixel 10 AVD in landscape: 2424×1080 px at 2.625 → 923×411 logical.
  const phone = Size(923, 411);

  CameraRig rig([Size size = phone]) => CameraRig(world: world)..resize(size);

  test('fit shows the whole play area; a wide phone sees off-map margin', () {
    final r = rig();
    expect(r.fitZoom, closeTo(411 / 480, 1e-9));
    expect(r.zoom, r.fitZoom);
    expect(r.visible.height, closeTo(480, 1e-6));
    expect(r.visible.width, greaterThan(720));
    expect(r.center, world.center);
  });

  test('zoom is clamped to [fit, 3 × fit]', () {
    final r = rig()..zoomBy(100, phone.center(Offset.zero));
    expect(r.relativeZoom, closeTo(3, 1e-9));
    r.zoomBy(0.001, phone.center(Offset.zero));
    expect(r.relativeZoom, closeTo(1, 1e-9));
  });

  test('pinch keeps the world point under the focal point fixed', () {
    // A focal point away from the edges, so clamping does not move the view.
    final r = rig();
    const focal = Offset(520, 230);
    final before = r.screenToWorld(focal);
    r.zoomAbout(r.fitZoom * 2, focal);
    expect(r.screenToWorld(focal).dx, closeTo(before.dx, 1e-6));
    expect(r.screenToWorld(focal).dy, closeTo(before.dy, 1e-6));
  });

  test('near an edge, clamping wins over the focal point', () {
    // Zooming about the top-left corner of a wide phone would put the view
    // far past the play area's left edge; it stops at the margin instead.
    final r = rig()..zoomAbout(rig().fitZoom * 2, Offset.zero);
    expect(r.visible.left, closeTo(-r.settings.margin, 1e-6));
    expect(r.visible.top, closeTo(0, 1e-6), reason: 'the top was already at the edge at fit');
  });

  test('pan is clamped to the play area plus margin', () {
    final r = rig();
    r.zoomAbout(r.maxZoom, phone.center(Offset.zero));
    r.panBy(const Offset(100000, 100000));
    expect(r.visible.left, closeTo(-r.settings.margin, 1e-6));
    expect(r.visible.top, closeTo(-r.settings.margin, 1e-6));
    r.panBy(const Offset(-100000, -100000));
    expect(r.visible.right, closeTo(720 + r.settings.margin, 1e-6));
    expect(r.visible.bottom, closeTo(480 + r.settings.margin, 1e-6));
  });

  test('at fit a too-wide view stays centred and cannot pan sideways', () {
    final r = rig()..panBy(const Offset(300, 0));
    expect(r.center.dx, closeTo(360, 1e-6));
  });

  test('double tap toggles fit and 2×', () {
    final r = rig()..toggleZoom(const Offset(100, 100));
    expect(r.relativeZoom, closeTo(2, 1e-9));
    r.toggleZoom(const Offset(100, 100));
    expect(r.isAtFit, isTrue);
    expect(r.center, world.center);
  });

  test('resize keeps relative zoom and re-clamps', () {
    final r = rig();
    r.zoomAbout(r.fitZoom * 2, phone.center(Offset.zero));
    r.resize(const Size(1280, 720));
    expect(r.relativeZoom, closeTo(2, 1e-9));
    expect(r.fitZoom, closeTo(1.5, 1e-9));
  });

  test('screen ↔ world conversion round-trips', () {
    final r = rig()..zoomAbout(1.7, const Offset(300, 200));
    const p = Offset(123, 45);
    final back = r.worldToScreen(r.screenToWorld(p));
    expect(back.dx, closeTo(p.dx, 1e-9));
    expect(back.dy, closeTo(p.dy, 1e-9));
  });

  test('HUD insets: fit puts the whole play area in the free part of the screen', () {
    final r = rig()..setInsets(const EdgeInsets.only(top: 48, right: 76));
    expect(r.fitZoom, closeTo(363 / 480, 1e-9));
    expect(r.isAtFit, isTrue);
    final topLeft = r.worldToScreen(world.topLeft);
    final bottomRight = r.worldToScreen(world.bottomRight);
    expect(topLeft.dy, closeTo(48, 1e-6));
    expect(bottomRight.dy, closeTo(411, 1e-6));
    expect(bottomRight.dx, lessThanOrEqualTo(923 - 76 + 1e-6));
    // Centred horizontally in the free width.
    expect((topLeft.dx + bottomRight.dx) / 2, closeTo((923 - 76) / 2, 1e-6));
    // Removing the insets refits to the whole screen.
    r.setInsets(EdgeInsets.zero);
    expect(r.fitZoom, closeTo(411 / 480, 1e-9));
    expect(r.center, world.center);
  });

  group('filled (portrait)', () {
    const portrait = Size(402, 874);
    const hud = EdgeInsets.only(top: 48, bottom: 88);
    CameraRig filled() => CameraRig(world: world)
      ..resize(portrait)
      ..setFrame(hud, fill: true);

    void expectNear(Offset a, Offset b, [double eps = 1e-6]) {
      expect(a.dx, closeTo(b.dx, eps), reason: '$a vs $b');
      expect(a.dy, closeTo(b.dy, eps), reason: '$a vs $b');
    }

    test('home is upright and covers the free area; pinch out shows the whole map', () {
      final r = filled();
      // 738 px of free height over 480 world px.
      expect(r.homeZoom, closeTo(738 / 480, 1e-9));
      expect(r.zoom, closeTo(r.homeZoom, 1e-9));
      expect(r.isAtHome, isTrue);
      expect(r.isAtFit, isFalse);
      // Upright: world +x runs right, +y down.
      final a = r.worldToScreen(const Offset(100, 100));
      final b = r.worldToScreen(const Offset(200, 150));
      expect(b.dx, greaterThan(a.dx));
      expect(b.dy, greaterThan(a.dy));
      // The play area's top and bottom sit on the free area's edges; it is
      // centred and cropped left and right.
      expect(r.worldToScreen(Offset.zero).dy, closeTo(r.free.top, 1e-6));
      expect(r.worldToScreen(const Offset(0, 480)).dy, closeTo(r.free.bottom, 1e-6));
      expect(r.screenToWorld(r.free.center).dx, closeTo(360, 1e-6));
      expect(r.worldToScreen(Offset.zero).dx, lessThan(0));
      expect(r.minZoom, closeTo(402 / 720, 1e-9));
      r.zoomBy(0.01, r.free.center);
      expect(r.isAtFit, isTrue);
      expect(r.zoom, closeTo(402 / 720, 1e-9));
    });

    test('the player pans along the map and stops at its ends', () {
      final r = filled();
      final before = r.center;
      r.panBy(const Offset(-100, 0));
      expect(r.center.dx, closeTo(before.dx + 100 / r.zoom, 1e-9));
      r.panBy(const Offset(-100000, 0));
      final seenRight = r.screenToWorld(Offset(r.free.right, r.free.center.dy)).dx;
      expect(seenRight, closeTo(720 + r.settings.margin, 1e-6));
      r.panBy(const Offset(100000, 0));
      final seenLeft = r.screenToWorld(Offset(r.free.left, r.free.center.dy)).dx;
      expect(seenLeft, closeTo(-r.settings.margin, 1e-6));
    });

    test('double tap toggles home and the whole map', () {
      final r = filled()..toggleZoom(const Offset(200, 400));
      expect(r.isAtFit, isTrue);
      r.toggleZoom(const Offset(200, 400));
      expect(r.isAtHome, isTrue);
      // Zoomed in from home, a double tap comes back home.
      r.zoomBy(1.5, const Offset(200, 400));
      r.toggleZoom(const Offset(200, 400));
      expect(r.isAtHome, isTrue);
    });

    group('with a home floor (the game)', () {
      const floor = 20 / 36;
      CameraRig floored(Size screen) => CameraRig(world: world)
        ..resize(screen)
        ..setFrame(hud, fill: true, homeFloor: floor);

      test('a wide enough phone starts with the whole map', () {
        final r = floored(portrait);
        expect(r.isAtHome, isTrue);
        expect(r.isAtFit, isTrue);
        expect(r.fill, isTrue, reason: 'the ground still runs on past the map');
      });

      test('a narrow phone starts as far out as turrets stay big enough', () {
        final r = floored(const Size(360, 780));
        expect(r.zoom, closeTo(floor, 1e-9));
        expect(r.isAtFit, isFalse);
      });

      test('never starts closer than covering the free area', () {
        final r = CameraRig(world: world)
          ..resize(const Size(200, 400))
          ..setFrame(EdgeInsets.zero, fill: true, homeFloor: 5);
        expect(r.zoom, closeTo(400 / 480, 1e-9));
      });

      test('double tap goes in to cover the free area and back', () {
        final r = floored(portrait)..toggleZoom(const Offset(200, 400));
        expect(r.zoom, closeTo(738 / 480, 1e-9));
        r.toggleZoom(const Offset(200, 400));
        expect(r.isAtFit, isTrue);
      });

      test('turning to portrait and back keeps a view at home at home', () {
        final r = CameraRig(world: world)
          ..resize(const Size(874, 402))
          ..setFrame(EdgeInsets.zero)
          ..resize(portrait)
          ..setFrame(hud, fill: true, homeFloor: floor);
        expect(r.isAtFit, isTrue);
        r
          ..resize(const Size(874, 402))
          ..setFrame(EdgeInsets.zero);
        expect(r.isAtFit, isTrue);
      });
    });

    test('a filled view can still zoom in', () {
      final r = filled();
      r.zoomBy(100, r.free.center);
      expect(r.zoom, closeTo(r.homeZoom * r.settings.doubleTapZoom, 1e-9));
    });

    test('turning to portrait goes home there; turning back goes home again', () {
      final r = CameraRig(world: world)
        ..resize(const Size(874, 402))
        ..setInsets(const EdgeInsets.only(top: 48, right: 76));
      r
        ..resize(portrait)
        ..setFrame(hud, fill: true);
      expect(r.isAtHome, isTrue);
      expect(r.zoom, closeTo(738 / 480, 1e-9));
      r
        ..resize(const Size(874, 402))
        ..setFrame(const EdgeInsets.only(top: 48, right: 76));
      expect(r.isAtFit, isTrue);
    });

    test('a zoomed view keeps its zoom relative to home and the point it shows', () {
      final r = CameraRig(world: world)
        ..resize(const Size(874, 402))
        ..setInsets(const EdgeInsets.only(top: 48, right: 76));
      r.zoomAbout(r.fitZoom * 2, r.free.center);
      final seen = r.screenToWorld(r.free.center);
      r
        ..resize(portrait)
        ..setFrame(hud, fill: true);
      expect(r.zoom / r.homeZoom, closeTo(2, 1e-9));
      expectNear(r.screenToWorld(r.free.center), seen);
    });

    test('the order a rotation arrives in does not matter', () {
      CameraRig zoomed() {
        final r = CameraRig(world: world)
          ..resize(const Size(874, 402))
          ..setInsets(const EdgeInsets.only(top: 48, right: 76));
        r.zoomAbout(r.fitZoom * 1.5, r.free.center);
        return r;
      }

      final a = zoomed()
        ..resize(portrait)
        ..setFrame(hud, fill: true);
      final b = zoomed()
        ..setFrame(hud, fill: true)
        ..resize(portrait);
      expect(a.zoom, closeTo(b.zoom, 1e-9));
      expectNear(a.center, b.center);
    });

    test('panToShow brings a cropped point on screen', () {
      final r = filled();
      expect(r.free.contains(r.worldToScreen(const Offset(10, 240))), isFalse);
      expect(r.panToShow(const Offset(10, 240)), isTrue);
      expect(r.free.deflate(31).contains(r.worldToScreen(const Offset(10, 240))), isTrue);
      expect(r.panToShow(const Offset(10, 240)), isFalse);
    });

    test('ensureVisible pans a covered point just clear of a panel', () {
      final r = CameraRig(world: world)
        ..resize(const Size(874, 402))
        ..setInsets(const EdgeInsets.only(top: 48, right: 76));
      r.zoomAbout(r.fitZoom * 2.5, r.free.center);
      const panel = Rect.fromLTRB(0, 402 - 112, 874 - 76, 402);
      final target = r.screenToWorld(const Offset(400, 402 - 50));
      expect(r.ensureVisible(target, panel), isTrue);
      expect(panel.contains(r.worldToScreen(target)), isFalse);
      // A point already clear of the panel does not move the view.
      expect(r.ensureVisible(r.screenToWorld(const Offset(400, 100)), panel), isFalse);
    });
  });
}
