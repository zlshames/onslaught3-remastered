import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/services/assets/asset_pack.dart';
import 'package:onslaught3_remastered/services/assets/classic_asset_pack.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../support/test_data.dart';

ClassicAssetPack _pack({int scale = 3}) => ClassicAssetPack(preferredScale: scale)
  ..parseManifest(
    (jsonDecode(File(ClassicAssetPack.defaultManifestPath).readAsStringSync()) as Map)
        .cast<String, Object?>(),
  );

/// Asset-manifest tests (docs/REMASTER_PLAN.md §8.10): every id the data
/// refers to resolves in the classic pack, and every file the pack names exists.
void main() {
  late GameData data;
  setUpAll(() => data = loadTestGameData());

  test('every art id referenced by data resolves in the classic pack', () {
    final pack = AssetPackChain([_pack()]);
    final missing = data.referencedArtIds.where((id) => pack.sprite(id) == null).toList()..sort();
    expect(missing, isEmpty);
  });

  test('every turret icon has a turret-sized or modifier-sized base about its anchor', () {
    // PackSprite(anchored: true) scales tray and sheet icons by this base
    // (twice the anchor's distance to the nearest frame edge), so the bases
    // come out one size however far a barrel reaches: the blue cannon's
    // frame is taller than it is wide, which plain fitting shrank it by.
    final pack = _pack();
    final odd = <String>[];
    for (final t in data.turrets.values) {
      final id = t.art.icon;
      if (id == null) continue;
      final f = pack.sprite(id)!.frames.first;
      final w = f.rect.width;
      final h = f.rect.height;
      final half = [
        f.anchorX,
        w - f.anchorX,
        f.anchorY,
        h - f.anchorY,
      ].reduce((a, b) => a < b ? a : b);
      final base = 2 * half / f.scale;
      if ((base - 43.7).abs() > 0.3 && (base - 33).abs() > 0.3) odd.add('$id $base');
    }
    expect(odd, isEmpty);
    final blue = pack.sprite(data.turrets['blue']!.art.icon!)!.frames.first;
    expect(blue.rect.height, greaterThan(blue.rect.width), reason: 'the case this guards');
  });

  test('every clip referenced by audio events resolves to a file', () {
    final pack = _pack();
    for (final clip in data.referencedClipIds) {
      final paths = pack.sound(clip);
      expect(paths, isNotNull, reason: clip);
      expect(File(paths!.single).existsSync(), isTrue, reason: paths.single);
    }
  });

  test(
    'every audio event used by data has at least one clip, except the originally silent ones',
    () {
      const silent = {'attacker-hit', 'message'}; // no asset in the SWF
      for (final e in data.audio.events.entries) {
        if (silent.contains(e.key)) continue;
        expect(e.value, isNotEmpty, reason: e.key);
      }
    },
  );

  test('every atlas image exists and every density of every frame lies inside it', () {
    final pack = _pack();
    final sizes = <String, Size>{};
    for (final id in pack.spriteIds) {
      for (final f in pack.sprite(id)!.frames) {
        expect(
          f.densities.where((d) => d.image == f.image && d.rect == f.rect && d.scale == f.scale),
          hasLength(1),
          reason: id,
        );
        for (final d in f.densities) {
          final file = File(d.image);
          expect(file.existsSync(), isTrue, reason: d.image);
          expect(d.rect.left, greaterThanOrEqualTo(0));
          expect(d.rect.top, greaterThanOrEqualTo(0));
          if (!d.image.endsWith('.png')) continue;
          final size = sizes[d.image] ??= _pngSize(file);
          expect(d.rect.right, lessThanOrEqualTo(size.width), reason: '$id ${d.image}');
          expect(d.rect.bottom, lessThanOrEqualTo(size.height), reason: '$id ${d.image}');
          // The same art at every density: world size agrees within a pixel.
          expect(d.worldSize.width, closeTo(f.worldSize.width, 1), reason: id);
          expect(d.anchorX / d.scale, closeTo(f.anchorX / f.scale, 1e-9), reason: id);
        }
      }
    }
  });

  test('ships densities up to 9× so max zoom on a phone or retina screen stays sharp', () {
    final densities = _pack().sprite('turret.red')!.frames.single.densities;
    expect(densities.map((d) => d.scale), [1, 2, 3, 4, 6, 9]);
    // The ground is a 720×480 bitmap: nothing to gain above 3×.
    expect(_pack().sprite('ground.classic')!.frames.single.densities.last.scale, 3);
  });

  test('animations keep their original frame counts', () {
    final pack = _pack();
    expect(pack.sprite('turret.blue.weapon')!.frames, hasLength(20)); // Cannon
    expect(pack.sprite('fx.rocket-trail')!.frames, hasLength(31));
    expect(pack.sprite('projectile.landmine')!.frames, hasLength(19));
    expect(pack.sprite('base.player')!.frames, hasLength(1));
  });

  test('classic creeps are the original bitmaps, not the Enhanced redraws', () {
    final map = (jsonDecode(File('tool/asset_map.json').readAsStringSync()) as Map)
        .cast<String, Object?>();
    final sprites = (map['sprites']! as Map).cast<String, Object?>();
    for (var i = 0; i <= 8; i++) {
      expect((sprites['creep.$i']! as Map).containsKey('svg'), isFalse, reason: 'creep.$i');
    }
    expect(_pack().sprite('creep.0')!.frames.single.image, startsWith('assets/images/classic/'));
  });

  test('a manifest for another pack is refused', () {
    final json = (jsonDecode(File(ClassicAssetPack.defaultManifestPath).readAsStringSync()) as Map)
        .cast<String, Object?>();
    expect(
      () => ClassicAssetPack().parseManifest({...json, 'pack': 'enhanced'}),
      throwsFormatException,
    );
  });

  test('the preferred density falls back to the closest available scale', () {
    expect(_pack(scale: 2).sprite('base.player')!.frames.single.scale, 2);
    expect(_pack(scale: 5).sprite('base.player')!.frames.single.scale, 4);
    expect(_pack(scale: 12).sprite('base.player')!.frames.single.scale, 9);
    expect(_pack(scale: 12).sprite('ground.classic')!.frames.single.scale, 3);
    expect(_pack(scale: 0).sprite('base.player')!.frames.single.scale, 1);
  });

  test('atDensity picks the sparsest density at least as sharp as the screen', () {
    final f = _pack().sprite('base.player')!.frames.single;
    double at(double px) => f.atDensity(px).scale;
    expect(at(0.5), 1);
    expect(at(2), 2);
    expect(at(2.2), 3);
    expect(at(3.1), 3, reason: 'within the 5% slack');
    expect(at(3.3), 4);
    expect(at(5), 6);
    // Pixel 10 AVD: 2.625 dpr × fit zoom ≈ 1.1 × max zoom 3.
    expect(at(2.625 * 1.1 * 3), 9);
    expect(at(30), 9, reason: 'beyond the densest it upscales the densest');
    expect(f.atDensity(9).image, contains('atlas_9x_'));
  });

  test('a frame without densities is its own only density', () {
    final f = _FakePack({'x'}).sprite('x')!.frames.single;
    expect(f.atDensity(9), same(f));
  });

  test('a chain resolves through packs in order', () {
    final override = _FakePack({'base.player'});
    final chain = AssetPackChain([override, _pack()]);
    expect(chain.sprite('base.player')!.frames.single.image, 'override.png');
    expect(chain.sprite('creep.0'), isNotNull);
    expect(chain.id, 'fake>classic');
  });
}

class _FakePack implements AssetPack {
  _FakePack(this.ids);
  final Set<String> ids;
  @override
  String get id => 'fake';
  @override
  Future<void> load() async {}
  @override
  Set<String> get spriteIds => ids;
  @override
  Set<String> get soundIds => const {};
  @override
  SpriteAsset? sprite(String id) => ids.contains(id)
      ? SpriteAsset(id, const [
          SpriteFrame(
            image: 'override.png',
            rect: Rect.fromLTWH(0, 0, 1, 1),
            anchorX: 0,
            anchorY: 0,
            scale: 1,
          ),
        ])
      : null;
  @override
  List<String>? sound(String id) => null;
  @override
  PackTheme? get theme => null;
  @override
  GroundSource? ground(String id) => null;
}

/// Width and height from a PNG's IHDR chunk.
Size _pngSize(File file) {
  final header = ByteData.sublistView(file.openSync().readSync(24));
  return Size(header.getUint32(16).toDouble(), header.getUint32(20).toDouble());
}
