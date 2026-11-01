import 'dart:ui' show Color, Rect, Size;

import 'package:flutter/foundation.dart';

/// Where one sprite frame lives: an atlas image, the frame's rectangle in
/// it, and the frame's registration point (the original symbol's origin).
/// Atlases come in several densities; [scale] says how many image pixels
/// cover one world pixel, so the frame is drawn at `rect.size / scale`.
/// A pack that ships several densities lists them in [densities] so a
/// renderer can pick the one that stays sharp at its zoom ([atDensity]).
@immutable
class SpriteFrame {
  const SpriteFrame({
    required this.image,
    required this.rect,
    required this.anchorX,
    required this.anchorY,
    required this.scale,
    this.densities = const [],
  });

  /// Bundle path of the atlas image.
  final String image;

  /// Frame rectangle inside the atlas image, in image pixels.
  final Rect rect;

  /// Registration point inside the frame, in image pixels.
  final double anchorX;
  final double anchorY;

  /// Image pixels per world pixel (1, 2, 3, … as the pack ships them).
  final double scale;

  /// This frame at every density the pack ships, sparsest first (this
  /// frame's own density among them). Empty when the pack ships one.
  final List<SpriteFrame> densities;

  /// Size in world px.
  Size get worldSize => rect.size / scale;

  /// Upscaling this little (5%) is invisible, and saves loading a denser
  /// atlas when the screen needs only a hair more than one density offers.
  static const double densitySlack = 0.95;

  /// The density to draw when one world px covers [pixelsPerWorldPx] device
  /// pixels: the sparsest one at least that sharp, else the densest.
  SpriteFrame atDensity(double pixelsPerWorldPx) {
    if (densities.isEmpty) return this;
    for (final d in densities) {
      if (d.scale >= pixelsPerWorldPx * densitySlack) return d;
    }
    return densities.last;
  }
}

/// A sprite: one or more frames (animations keep the original frame order).
@immutable
class SpriteAsset {
  const SpriteAsset(this.id, this.frames);
  final String id;
  final List<SpriteFrame> frames;
  bool get isAnimated => frames.length > 1;
}

/// How a pack draws the ground (`docs/history/SCREEN_FIT_PLAN.md` §7.3): an image
/// sprite (the original's ground), or a fragment shader that paints it at
/// any zoom and to any distance (the sharp ground).
@immutable
sealed class GroundSource {
  const GroundSource();
}

/// The ground as a sprite stretched over the play area.
final class ImageGround extends GroundSource {
  const ImageGround(this.sprite);
  final SpriteAsset sprite;
}

/// The ground painted by the fragment shader at bundle path [shader] in
/// world coordinates, with its colour [palette] (light to dark).
final class ShaderGround extends GroundSource {
  const ShaderGround({required this.shader, required this.palette});
  final String shader;
  final List<Color> palette;
}

/// HUD colour tokens a pack may override.
@immutable
class PackTheme {
  const PackTheme({required this.background, required this.offMap});

  /// Ground colour under the play area.
  final Color background;

  /// Colour beyond the play area (the margin seen on wide screens).
  final Color offMap;
}

/// Resolves logical asset ids (`turret.red.base`, `sfx.fire.rocket`) to art
/// and sound. Data and rules only ever name ids (rule R5); a pack decides
/// what they look and sound like. Classic, HD and procedural packs all
/// implement this; [AssetPackChain] layers them.
abstract interface class AssetPack {
  String get id;

  /// Reads the pack's manifest. Must complete before lookups.
  Future<void> load();

  Set<String> get spriteIds;
  Set<String> get soundIds;

  /// The sprite for [id], or null when this pack does not provide it.
  SpriteAsset? sprite(String id);

  /// Bundle path of one variant of sound [id], or null.
  List<String>? sound(String id);

  /// How ground [id] (the world's `ground` art) is drawn, or null when this
  /// pack does not provide it.
  GroundSource? ground(String id);

  /// Theme tokens, or null to inherit.
  PackTheme? get theme;
}

/// Resolves each id through [packs] in order (`[user?, hd?, classic]`), so a
/// pack only needs to provide what it changes.
class AssetPackChain implements AssetPack {
  AssetPackChain(this.packs) : assert(packs.isNotEmpty);

  final List<AssetPack> packs;

  @override
  String get id => packs.map((p) => p.id).join('>');

  @override
  Future<void> load() async {
    for (final p in packs) {
      await p.load();
    }
  }

  @override
  Set<String> get spriteIds => {for (final p in packs) ...p.spriteIds};

  @override
  Set<String> get soundIds => {for (final p in packs) ...p.soundIds};

  @override
  SpriteAsset? sprite(String id) {
    for (final p in packs) {
      final s = p.sprite(id);
      if (s != null) return s;
    }
    return null;
  }

  @override
  List<String>? sound(String id) {
    for (final p in packs) {
      final s = p.sound(id);
      if (s != null) return s;
    }
    return null;
  }

  @override
  GroundSource? ground(String id) {
    for (final p in packs) {
      final g = p.ground(id);
      if (g != null) return g;
    }
    return null;
  }

  @override
  PackTheme? get theme {
    for (final p in packs) {
      final t = p.theme;
      if (t != null) return t;
    }
    return null;
  }
}
