import 'dart:async';
import 'dart:ui' as ui;

import 'package:flame/cache.dart';
import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';

import '../../../services/assets/asset_pack.dart';
import '../../../services/logging/logging.dart';

const Logger _log = Logger('render');

/// Turns logical asset ids into Flame sprites through the [AssetPack] chain
/// and keeps them sharp at every zoom.
///
/// Each frame's first density (the pack's preferred one) is loaded up front
/// and stays loaded as the fallback. While drawing, a sprite asks for the
/// density that covers [pixelsPerWorldPx] ([SpriteFrame.atDensity]) and draws
/// the densest page already loaded until that one is ready. Pages no sprite
/// has drawn for [idleSeconds] are released, so zooming out (or a turret type
/// leaving the field) gives the memory back. The renderer never sees
/// densities or files (rule R5).
///
/// Loading is kept off the frame budget: denser pages are only fetched once
/// the zoom has held for [settleSeconds] (a pinch from fit to max does not
/// stop at every density on the way), they decode off the UI thread, and at
/// most one newly decoded page per frame starts being drawn (its first use
/// costs the GPU an upload).
class ArtResolver {
  ArtResolver(this.pack, this.images, {this.idleSeconds = 3, this.settleSeconds = 0.25});

  final AssetPack pack;
  final Images images;

  /// How long an unused page beyond the fallback stays loaded.
  final double idleSeconds;

  /// How long the zoom must hold before denser pages are fetched.
  final double settleSeconds;

  /// Device pixels per world px (camera zoom × device pixel ratio).
  double get pixelsPerWorldPx => _pixelsPerWorldPx;
  set pixelsPerWorldPx(double value) {
    if ((value - _pixelsPerWorldPx).abs() > _pixelsPerWorldPx * 0.01) _steadySince = _clock;
    _pixelsPerWorldPx = value;
  }

  double _pixelsPerWorldPx = 1;
  double _steadySince = 0;
  final Set<String> _pinned = {};
  final Map<String, ui.Image> _ready = {};
  final Map<String, Future<void>> _loading = {};
  final Map<String, ui.Image> _arrived = {};
  final Map<String, double> _lastUsed = {};
  double _clock = 0;

  /// Every frame of [id], or empty when no pack provides it.
  Future<List<ResolvedFrame>> frames(String id) async {
    final asset = pack.sprite(id);
    if (asset == null) return const [];
    return [
      for (final f in asset.frames)
        ResolvedFrame(
          _DensitySprite(this, f, await _pin(f.image)),
          size: Vector2(f.rect.width, f.rect.height) / f.scale,
          anchor: Anchor(f.anchorX / f.rect.width, f.anchorY / f.rect.height),
        ),
    ];
  }

  /// The first frame of [id], or null.
  Future<ResolvedFrame?> frame(String id) async {
    final all = await frames(id);
    return all.isEmpty ? null : all.first;
  }

  /// Advances the clock, lets one newly decoded page be drawn, and releases
  /// pages unused for [idleSeconds].
  void tick(double dt) {
    _clock += dt;
    if (_arrived.isNotEmpty) {
      final path = _arrived.keys.first;
      _ready[path] = _arrived.remove(path)!;
    }
    _ready.removeWhere((path, _) {
      if (_pinned.contains(path) || _clock - (_lastUsed[path] ?? _clock) < idleSeconds) {
        return false;
      }
      _lastUsed.remove(path);
      images.clear(path);
      return true;
    });
  }

  /// Paths of the pages currently loaded.
  @visibleForTesting
  Set<String> get loadedPages => _ready.keys.toSet();

  Future<ui.Image> _pin(String path) async {
    _pinned.add(path);
    try {
      return _ready[path] ??= await images.load(path);
    } on Object catch (e, st) {
      _log.error('atlas page cannot be loaded', error: e, stackTrace: st, fields: {'path': path});
      rethrow;
    }
  }

  /// [path]'s image when ready, else null after starting its load (once
  /// the zoom has settled).
  ui.Image? _request(String path) {
    _lastUsed[path] = _clock;
    final image = _ready[path];
    if (image != null ||
        _loading.containsKey(path) ||
        _arrived.containsKey(path) ||
        _clock - _steadySince < settleSeconds) {
      return image;
    }
    _loading[path] = images
        .load(path)
        .then<void>(
          (img) {
            _arrived[path] = img;
            _log.trace('atlas page loaded', fields: {'path': path});
          },
          onError: (Object e, StackTrace st) => _log.warning(
            'sharper atlas page cannot be loaded; keeping the loaded one',
            error: e,
            stackTrace: st,
            fields: {'path': path},
          ),
        )
        .whenComplete(() => _loading.remove(path));
    return null;
  }
}

/// A [Sprite] that draws the density of its frame matching the resolver's
/// current zoom. Its [image] and [src] stay the fallback density's.
class _DensitySprite extends Sprite {
  _DensitySprite(this.resolver, this.frame, ui.Image image)
    : super(
        image,
        srcPosition: Vector2(frame.rect.left, frame.rect.top),
        srcSize: Vector2(frame.rect.width, frame.rect.height),
      );

  final ArtResolver resolver;
  final SpriteFrame frame;

  /// Sprites are drawn scaled, so sample smoothly (mipmapped when shrinking
  /// a denser page) rather than with the default nearest-pixel filter.
  static const _quality = ui.FilterQuality.medium;

  @override
  void render(
    ui.Canvas canvas, {
    Vector2? position,
    Vector2? size,
    Anchor anchor = Anchor.topLeft,
    ui.Paint? overridePaint,
    double? bleed,
  }) {
    var raster = frame;
    var img = image;
    // Sparser densities than the fallback are never loaded: the fallback
    // shrinks cleanly (mipmaps) and is already in memory.
    final want = frame.atDensity(resolver.pixelsPerWorldPx);
    if (want.scale > frame.scale) {
      final wanted = resolver._request(want.image);
      if (wanted != null) {
        raster = want;
        img = wanted;
      } else {
        // Keep the sharpest page already loaded until the wanted one arrives.
        for (final d in frame.densities.reversed) {
          if (d.scale <= frame.scale) break;
          final ready = resolver._ready[d.image];
          if (ready != null) {
            resolver._lastUsed[d.image] = resolver._clock;
            raster = d;
            img = ready;
            break;
          }
        }
      }
    }
    // The box the fallback frame fills; another density covers the same
    // world area from the same registration point, so only its extent
    // (rounded per density) differs.
    final w = size?.x ?? frame.worldSize.width;
    final h = size?.y ?? frame.worldSize.height;
    var x = (position?.x ?? 0) - anchor.x * w;
    var y = (position?.y ?? 0) - anchor.y * h;
    var dw = raster.worldSize.width * w / frame.worldSize.width;
    var dh = raster.worldSize.height * h / frame.worldSize.height;
    if (bleed != null) {
      x -= bleed;
      y -= bleed;
      dw += bleed * 2;
      dh += bleed * 2;
    }
    final paint = overridePaint ?? this.paint;
    if (paint.filterQuality != _quality) paint.filterQuality = _quality;
    canvas.drawImageRect(img, raster.rect, ui.Rect.fromLTWH(x, y, dw, dh), paint);
  }
}

/// A sprite with its size in world px and its registration anchor.
class ResolvedFrame {
  ResolvedFrame(this.sprite, {required this.size, required this.anchor});
  final Sprite sprite;
  final Vector2 size;
  final Anchor anchor;

  SpriteComponent toComponent({required Vector2 position}) =>
      SpriteComponent(sprite: sprite, size: size, anchor: anchor, position: position);
}
