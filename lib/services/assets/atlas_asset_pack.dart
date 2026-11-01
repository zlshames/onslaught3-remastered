import 'dart:convert';

import 'package:flutter/services.dart';

import '../logging/logging.dart';
import 'asset_pack.dart';

const Logger _log = Logger('assets');

/// A pack built by `tool/pack_atlas.dart`: atlases at several densities
/// (1× to 9×) plus a manifest naming the pack, its sprites, sounds and
/// theme. Every frame lists all its densities ([SpriteFrame.densities]);
/// [preferredScale] picks the one [sprite] returns first, which a renderer
/// keeps loaded as its fallback. [ClassicAssetPack] and [EnhancedAssetPack]
/// are the two packs the tool builds.
class AtlasAssetPack implements AssetPack {
  AtlasAssetPack({
    required this.id,
    required this.manifestPath,
    AssetBundle? bundle,
    this.preferredScale = 3,
  }) : _bundle = bundle ?? rootBundle;

  @override
  final String id;

  final AssetBundle _bundle;
  final String manifestPath;

  /// Density of the frames [sprite] returns (the closest available is
  /// used); denser ones are reached through [SpriteFrame.atDensity].
  final int preferredScale;

  final Map<String, SpriteAsset> _sprites = {};
  final Map<String, List<String>> _sounds = {};
  PackTheme? _theme;

  @override
  Future<void> load() async {
    final watch = Stopwatch()..start();
    try {
      final json = jsonDecode(await _bundle.loadString(manifestPath)) as Map<String, Object?>;
      parseManifest(json);
    } on Object catch (e, st) {
      _log.error('asset pack cannot be loaded', error: e, stackTrace: st, fields: {'pack': id});
      rethrow;
    }
    _log.debug(
      'asset pack loaded',
      fields: {
        'pack': id,
        'sprites': _sprites.length,
        'sounds': _sounds.length,
        'ms': watch.elapsedMilliseconds,
      },
    );
  }

  /// Fills the pack from a decoded manifest (exposed for tests).
  void parseManifest(Map<String, Object?> json) {
    final version = json['schemaVersion'];
    if (version != 2) {
      throw FormatException('$id manifest schemaVersion $version, expected 2');
    }
    if (json['pack'] != id) {
      throw FormatException('$manifestPath is pack ${json['pack']}, expected $id');
    }
    final atlases = (json['atlases']! as Map).cast<String, Object?>();

    _sprites.clear();
    final sprites = (json['sprites']! as Map).cast<String, Object?>();
    sprites.forEach((spriteId, value) {
      final frames = ((value! as Map)['frames']! as List<Object?>).map((f) {
        final m = (f! as Map).cast<String, Object?>();
        // A frame may stop short of the densest scale (the ground is a
        // bitmap with nothing to gain above 3×).
        final rects = (m['rects']! as Map).cast<String, Object?>();
        final densities = [
          for (final e in rects.entries)
            _frame(m, int.parse(e.key), (e.value! as List<Object?>), atlases),
        ]..sort((a, b) => a.scale.compareTo(b.scale));
        final preferred = densities.lastWhere(
          (d) => d.scale <= preferredScale,
          orElse: () => densities.first,
        );
        return SpriteFrame(
          image: preferred.image,
          rect: preferred.rect,
          anchorX: preferred.anchorX,
          anchorY: preferred.anchorY,
          scale: preferred.scale,
          densities: List.unmodifiable(densities),
        );
      }).toList();
      _sprites[spriteId] = SpriteAsset(spriteId, List.unmodifiable(frames));
    });

    _sounds.clear();
    final sounds = (json['sounds'] as Map?)?.cast<String, Object?>() ?? const {};
    sounds.forEach((k, v) => _sounds[k] = [v! as String]);

    final theme = (json['theme'] as Map?)?.cast<String, Object?>();
    if (theme != null) {
      _theme = PackTheme(
        background: _hex(theme['background']! as String),
        offMap: _hex(theme['offMap']! as String),
      );
    }
  }

  @override
  Set<String> get spriteIds => _sprites.keys.toSet();

  @override
  Set<String> get soundIds => _sounds.keys.toSet();

  @override
  SpriteAsset? sprite(String id) => _sprites[id];

  /// An atlas pack's ground is its sprite of that id.
  @override
  GroundSource? ground(String id) => switch (_sprites[id]) {
    final s? => ImageGround(s),
    null => null,
  };

  @override
  List<String>? sound(String id) => _sounds[id];

  @override
  PackTheme? get theme => _theme;
}

SpriteFrame _frame(
  Map<String, Object?> m,
  int scale,
  List<Object?> rect,
  Map<String, Object?> atlases,
) {
  final r = rect.map((e) => (e! as num).toDouble()).toList();
  return SpriteFrame(
    image: (atlases['$scale']! as List<Object?>)[r[0].toInt()]! as String,
    rect: Rect.fromLTWH(r[1], r[2], r[3], r[4]),
    anchorX: (m['ax']! as num).toDouble() * scale,
    anchorY: (m['ay']! as num).toDouble() * scale,
    scale: scale.toDouble(),
  );
}

Color _hex(String s) => Color(0xFF000000 | int.parse(s.substring(1), radix: 16));
