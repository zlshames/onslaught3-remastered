import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/features/game/flame/art_resolver.dart';
import 'package:onslaught3_remastered/services/assets/classic_asset_pack.dart';

/// Records the image draws a sprite makes.
class _Canvas implements ui.Canvas {
  final draws = <({ui.Image image, ui.Rect src, ui.Rect dst, ui.Paint paint})>[];

  @override
  void drawImageRect(ui.Image image, ui.Rect src, ui.Rect dst, ui.Paint paint) =>
      draws.add((image: image, src: src, dst: dst, paint: paint));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Runs frames (in real time, inside `runAsync`) until [page] is ready.
Future<void> _loaded(ArtResolver art, String page) async {
  for (var i = 0; i < 500 && !art.loadedPages.contains(page); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    art.tick(0.016);
  }
  expect(art.loadedPages, contains(page));
}

void main() {
  late ClassicAssetPack pack;
  setUp(() {
    pack = ClassicAssetPack()
      ..parseManifest(
        (jsonDecode(File(ClassicAssetPack.defaultManifestPath).readAsStringSync()) as Map)
            .cast<String, Object?>(),
      );
  });

  testWidgets(
    'draws the density the zoom needs, the fallback while it loads, and frees idle pages',
    (tester) async {
      await tester.runAsync(() async {
        final art = ArtResolver(pack, Images(prefix: ''));
        final resolved = (await art.frame('turret.red'))!;
        final base = pack.sprite('turret.red')!.frames.single;
        final hd = base.atDensity(9);
        expect(base.scale, 3);
        expect(hd.scale, 9);
        expect(art.loadedPages, {base.image});

        final canvas = _Canvas();
        void draw() => resolved.sprite.render(canvas, size: resolved.size);

        // Fit zoom on a phone: the preloaded 3× page.
        art.pixelsPerWorldPx = 2.4;
        draw();
        expect(canvas.draws.last.src, base.rect);
        expect(canvas.draws.last.paint.filterQuality, ui.FilterQuality.medium);
        expect(art.loadedPages, {base.image}, reason: 'sparser pages are never loaded');

        // Max zoom: 3× until the 9× page arrives, then 9× over the same box.
        art.pixelsPerWorldPx = 8.7;
        draw();
        expect(canvas.draws.last.src, base.rect);
        art.tick(0.3); // the zoom has settled: now it fetches
        draw();
        await _loaded(art, hd.image);
        draw();
        final last = canvas.draws.last;
        expect(last.src, hd.rect);
        expect(last.image.width, greaterThanOrEqualTo(hd.rect.right));
        expect(last.dst.topLeft, ui.Offset.zero);
        expect(last.dst.width, closeTo(resolved.size.x, 1 / 3));
        expect(last.dst.height, closeTo(resolved.size.y, 1 / 3));
        expect(art.loadedPages, {base.image, hd.image});

        // Zoomed back out: the 9× page goes once idle; the fallback stays.
        art.pixelsPerWorldPx = 2.4;
        draw();
        art.tick(2);
        expect(art.loadedPages, contains(hd.image));
        art.tick(1.5);
        expect(art.loadedPages, {base.image});
        draw();
        expect(canvas.draws.last.src, base.rect);
      });
    },
  );

  testWidgets('keeps drawing a denser loaded page while the wanted one loads', (tester) async {
    await tester.runAsync(() async {
      final art = ArtResolver(pack, Images(prefix: ''));
      final resolved = (await art.frame('creep.0'))!;
      final base = pack.sprite('creep.0')!.frames.first;
      final canvas = _Canvas();
      art
        ..pixelsPerWorldPx = 9
        ..tick(0.3);
      resolved.sprite.render(canvas, size: resolved.size);
      await _loaded(art, base.atDensity(9).image);
      // Zooming out a step wants 6×, which is not loaded yet: 9× beats 3×.
      art.pixelsPerWorldPx = 5.5;
      resolved.sprite.render(canvas, size: resolved.size);
      expect(canvas.draws.last.src, base.atDensity(9).rect);
      art.tick(0.3);
      resolved.sprite.render(canvas, size: resolved.size);
      await _loaded(art, base.atDensity(6).image);
      resolved.sprite.render(canvas, size: resolved.size);
      expect(canvas.draws.last.src, base.atDensity(6).rect);
    });
  });

  testWidgets('fetches nothing while the zoom moves, and admits one new page per frame', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final art = ArtResolver(pack, Images(prefix: ''));
      final ids = ['turret.red', 'creep.0'];
      final sprites = [for (final id in ids) (await art.frame(id))!];
      final pages = {for (final id in ids) pack.sprite(id)!.frames.first.atDensity(9).image};
      expect(pages, hasLength(2), reason: 'the two sprites sit on different 9× pages');
      final before = art.loadedPages;
      final canvas = _Canvas();
      void drawAll() {
        for (final s in sprites) {
          s.sprite.render(canvas, size: s.size);
        }
      }

      // A pinch: zoom changes every frame, so no denser page is fetched.
      for (var i = 0; i < 30; i++) {
        art
          ..pixelsPerWorldPx = 3 + i * 0.2
          ..tick(0.016);
        drawAll();
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      art.tick(0.016);
      expect(art.loadedPages, before);

      // Held: both pages are fetched, then become drawable one frame at a time.
      art.tick(0.3);
      drawAll();
      await Future<void>.delayed(const Duration(seconds: 1));
      art.tick(0.016);
      expect(art.loadedPages.difference(before), hasLength(1));
      art.tick(0.016);
      expect(art.loadedPages.difference(before), pages);
    });
  });
}
