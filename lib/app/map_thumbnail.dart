import 'package:flutter/rendering.dart';
import 'package:onslaught_core/onslaught_core.dart';

import 'theme.dart';

/// A map's road (the original's two-tone stroke) and base on plain ground,
/// scaled to the tile.
class MapThumbnailPainter extends CustomPainter {
  MapThumbnailPainter({required this.map, required this.data});

  final MapDefinition map;
  final GameData data;

  static const Color _ground = AppColours.ground;

  @override
  void paint(Canvas canvas, Size size) {
    final w = data.world;
    final scale = size.width / w.playWidth;
    canvas
      ..drawRect(Offset.zero & size, Paint()..color = _ground)
      ..save()
      ..scale(scale);
    final path = Path()..moveTo(map.road.first.x, map.road.first.y);
    for (final p in map.road.skip(1)) {
      path.lineTo(p.x, p.y);
    }
    Paint stroke(double width, int rgb) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = Color(0xFF000000 | rgb);
    final placement = w.placement;
    canvas
      ..drawPath(path, stroke(w.road.outerWidth, w.road.outerColor))
      ..drawPath(path, stroke(w.road.innerWidth, w.road.innerColor))
      ..drawRect(
        Rect.fromLTWH(map.base.x, map.base.y, placement.baseWidth, placement.baseHeight),
        Paint()..color = const Color(0xFF8A8F94),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(MapThumbnailPainter old) => old.map != map;
}
