import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../logging/logging.dart';
import 'asset_pack.dart';

const Logger _log = Logger('assets');

/// Draws the first frame of sprite [id] from [pack] fitted into [size], or
/// stretched over [size] × [height] when [height] is given (rule R5:
/// widgets name art by logical id), from the pack's density that stays
/// sharp at that size on this screen. Shows [placeholderColor] as a
/// disc while the atlas loads, when the pack has no such sprite, or when
/// [pack] is null (goldens and widget tests).
class PackSprite extends StatefulWidget {
  const PackSprite({
    super.key,
    required this.pack,
    required this.id,
    required this.size,
    this.placeholderColor = const Color(0xFF607D8B),
    this.opacity = 1,
    this.height,
    this.anchored = false,
  });

  final AssetPack? pack;
  final String? id;
  final double size;
  final Color placeholderColor;
  final double opacity;

  /// Fill a [size] × [height] box (e.g. a ground texture) instead of fitting
  /// a square.
  final double? height;

  /// Draw a turret icon by its base rather than its whole frame. A turret's
  /// base is centred on the registration point and reaches the frame's
  /// nearest edge, so it is the square of side twice that distance (43.7
  /// world px for every turret, 33 for every modifier); barrels, rails and
  /// flames reach further and give some frames extra height (the blue
  /// cannon's frame is 43.7 × 68.8, mostly empty above a short barrel).
  /// Fitting whole frames shrinks those turrets; this scales every frame so
  /// its base spans [baseFraction] of [size], centred, resting on the box's
  /// bottom edge. What rises above the box spills out; what hangs below it
  /// is clipped.
  final bool anchored;

  /// The share of [size] an [anchored] icon's base spans.
  static const double baseFraction = 0.9;

  @override
  State<PackSprite> createState() => _PackSpriteState();
}

class _PackSpriteState extends State<PackSprite> {
  static final Map<String, Future<ui.Image>> _cache = {};
  ui.Image? _image;
  SpriteFrame? _frame;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(PackSprite old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id ||
        old.pack != widget.pack ||
        old.size != widget.size ||
        old.height != widget.height ||
        old.anchored != widget.anchored) {
      _resolve();
    }
  }

  void _resolve() {
    final id = widget.id;
    final first = id == null ? null : widget.pack?.sprite(id)?.frames.first;
    final frame = first?.atDensity(_pixelsPerWorldPx(first));
    if (frame == _frame && frame != null) return;
    _frame = frame;
    _image = null;
    if (frame == null) return;
    final future = _cache.putIfAbsent(frame.image, () => _load(frame.image));
    future.then(
      (img) {
        if (mounted && _frame == frame) setState(() => _image = img);
      },
      onError: (Object e, StackTrace st) => _log.warning(
        'sprite image cannot be loaded; drawing a placeholder',
        error: e,
        stackTrace: st,
        fields: {'path': frame.image},
      ),
    );
  }

  /// Device pixels per world px at which [frame] is painted.
  double _pixelsPerWorldPx(SpriteFrame frame) {
    final world = frame.worldSize;
    final sx = widget.size / world.width;
    final sy = (widget.height ?? widget.size) / world.height;
    final fit = widget.anchored
        ? widget.size * PackSprite.baseFraction / (2 * _baseHalf(frame) / frame.scale)
        : widget.height != null
        ? (sx > sy ? sx : sy)
        : (sx < sy ? sx : sy);
    return fit * (MediaQuery.maybeDevicePixelRatioOf(context) ?? 1);
  }

  static Future<ui.Image> _load(String path) async {
    final data = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    return (await codec.getNextFrame()).image;
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.size,
    height: widget.height ?? widget.size,
    child: CustomPaint(
      painter: _SpritePainter(
        _image,
        _frame,
        widget.placeholderColor,
        widget.opacity,
        fill: widget.height != null,
        anchored: widget.anchored,
      ),
    ),
  );
}

/// Half the side of [f]'s base, in image px: the registration point's
/// distance to the nearest frame edge.
double _baseHalf(SpriteFrame f) {
  final w = f.rect.width;
  final h = f.rect.height;
  return math.min(math.min(f.anchorX, w - f.anchorX), math.min(f.anchorY, h - f.anchorY));
}

class _SpritePainter extends CustomPainter {
  _SpritePainter(
    this.image,
    this.frame,
    this.placeholder,
    this.opacity, {
    this.fill = false,
    this.anchored = false,
  });

  final ui.Image? image;
  final SpriteFrame? frame;
  final Color placeholder;
  final double opacity;
  final bool fill;
  final bool anchored;

  @override
  void paint(Canvas canvas, Size size) {
    final img = image;
    final f = frame;
    if (img == null || f == null) {
      canvas.drawCircle(
        size.center(Offset.zero),
        size.shortestSide * 0.38,
        Paint()..color = placeholder.withValues(alpha: placeholder.a * opacity),
      );
      return;
    }
    if (fill) {
      canvas.drawImageRect(
        img,
        f.rect,
        Offset.zero & size,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..color = Color.fromRGBO(0, 0, 0, opacity),
      );
      return;
    }
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..color = Color.fromRGBO(0, 0, 0, opacity);
    if (anchored) {
      final half = _baseHalf(f);
      final scale = size.width * PackSprite.baseFraction / (2 * half);
      final dst = Rect.fromLTWH(
        size.width / 2 - f.anchorX * scale,
        size.height - half * scale - f.anchorY * scale,
        f.rect.width * scale,
        f.rect.height * scale,
      );
      canvas
        ..save()
        ..clipRect(Rect.fromLTRB(-size.width, -size.height, 2 * size.width, size.height));
      canvas
        ..drawImageRect(img, f.rect, dst, paint)
        ..restore();
      return;
    }
    final scale = size.width / f.rect.width < size.height / f.rect.height
        ? size.width / f.rect.width
        : size.height / f.rect.height;
    final w = f.rect.width * scale;
    final h = f.rect.height * scale;
    final dst = Rect.fromLTWH((size.width - w) / 2, (size.height - h) / 2, w, h);
    canvas.drawImageRect(img, f.rect, dst, paint);
  }

  @override
  bool shouldRepaint(_SpritePainter old) =>
      old.image != image ||
      old.frame != frame ||
      old.opacity != opacity ||
      old.fill != fill ||
      old.anchored != anchored;
}
