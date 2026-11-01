import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:onslaught3_remastered/services/assets/asset_pack.dart';
import 'package:onslaught3_remastered/services/assets/classic_asset_pack.dart';
import 'package:onslaught3_remastered/services/assets/enhanced_asset_pack.dart';

Map<String, Object?> _manifest(String path) =>
    (jsonDecode(File(path).readAsStringSync()) as Map).cast<String, Object?>();

/// The Enhanced pack (docs/ENHANCED_PLAN.md): vector redraws of the nine
/// creeps, layered over Classic for Enhanced games only.
void main() {
  late ClassicAssetPack classic;
  late EnhancedAssetPack enhanced;
  setUp(() {
    classic = ClassicAssetPack()..parseManifest(_manifest(ClassicAssetPack.defaultManifestPath));
    enhanced = EnhancedAssetPack()..parseManifest(_manifest(EnhancedAssetPack.defaultManifestPath));
  });

  test('holds exactly the nine creeps, each from its SVG redraw', () {
    expect(enhanced.spriteIds, {for (var i = 0; i <= 8; i++) 'creep.$i'});
    expect(enhanced.soundIds, isEmpty);
    expect(enhanced.theme, isNull);
    final map = _manifest('tool/asset_map_enhanced.json');
    final sprites = (map['sprites']! as Map).cast<String, Object?>();
    for (final id in enhanced.spriteIds) {
      final svg = (sprites[id]! as Map)['svg']! as String;
      expect(File(svg).existsSync(), isTrue, reason: svg);
    }
  });

  test('every density sits in its page and matches the classic frame it replaces', () {
    final sizes = <String, Size>{};
    for (final id in enhanced.spriteIds) {
      final redraw = enhanced.sprite(id)!.frames.single;
      final original = classic.sprite(id)!.frames.single;
      expect(redraw.densities.map((d) => d.scale), original.densities.map((d) => d.scale));
      for (final d in redraw.densities) {
        expect(d.image, startsWith('assets/images/enhanced/'));
        final size = sizes[d.image] ??= _pngSize(File(d.image));
        expect(d.rect.right, lessThanOrEqualTo(size.width), reason: '$id ${d.image}');
        expect(d.rect.bottom, lessThanOrEqualTo(size.height), reason: '$id ${d.image}');
        final o = original.atDensity(d.scale);
        expect(d.rect.size, o.rect.size, reason: '$id at ${d.scale}×');
        expect(d.anchorX, o.anchorX, reason: id);
        expect(d.anchorY, o.anchorY, reason: id);
      }
    }
  });

  test('a redraw is smooth at 9×, not blocks of the original pixels', () {
    final f = enhanced.sprite('creep.0')!.frames.single.atDensity(9);
    final page = img.decodePng(File(f.image).readAsBytesSync())!;
    final left = f.rect.left.toInt(), top = f.rect.top.toInt();
    var mixedBlocks = 0;
    for (var by = 0; by < 18; by++) {
      for (var bx = 0; bx < 17; bx++) {
        final first = page.getPixel(left + bx * 9, top + by * 9);
        if (page.getPixel(left + bx * 9 + 4, top + by * 9 + 4) != first) mixedBlocks++;
      }
    }
    expect(mixedBlocks, greaterThan(17 * 18 ~/ 4));
  });

  test('Enhanced games get the redrawn creeps; Classic and everything else stay original', () {
    final classicChain = AssetPackChain([classic]);
    final enhancedChain = AssetPackChain([enhanced, classic]);
    expect(
      classicChain.sprite('creep.3')!.frames.single.image,
      startsWith('assets/images/classic/'),
    );
    expect(
      enhancedChain.sprite('creep.3')!.frames.single.image,
      startsWith('assets/images/enhanced/'),
    );
    expect(
      enhancedChain.sprite('turret.red')!.frames.single.image,
      startsWith('assets/images/classic/'),
    );
    expect(enhancedChain.sound('sfx.bfg-01'), isNotNull);
    expect(enhancedChain.sound('sfx.bfg-01'), classicChain.sound('sfx.bfg-01'));
    expect(enhancedChain.theme, isNotNull);
    expect(enhancedChain.id, 'enhanced>classic');
  });
}

/// Width and height from a PNG's IHDR chunk.
Size _pngSize(File file) {
  final header = ByteData.sublistView(file.openSync().readSync(24));
  return Size(header.getUint32(16).toDouble(), header.getUint32(20).toDouble());
}
