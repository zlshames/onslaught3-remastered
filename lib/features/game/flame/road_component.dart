import 'dart:ui';

import 'package:flame/components.dart';
import 'package:onslaught_core/onslaught_core.dart';

/// Draws a map's road like the original (`RoadManager`): a round-capped
/// polyline in the outer colour with a narrower core on top. Recorded once
/// into a [Picture] and replayed every frame. Roads start and end on the edge
/// of the map, where the original's stage cuts off the round cap; [stage] does
/// the same here.
class RoadComponent extends Component {
  RoadComponent({required this.road, required this.style, this.stage});

  final List<Vec2> road;
  final RoadStyle style;
  final Rect? stage;
  late final Picture _picture = _record();

  Picture _record() {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    if (stage case final stage?) canvas.clipRect(stage);
    final path = Path()..moveTo(road.first.x, road.first.y);
    for (final p in road.skip(1)) {
      path.lineTo(p.x, p.y);
    }
    Paint stroke(double width, int rgb) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true
      ..color = Color(0xFF000000 | rgb);
    canvas
      ..drawPath(path, stroke(style.outerWidth, style.outerColor))
      ..drawPath(path, stroke(style.innerWidth, style.innerColor));
    return recorder.endRecording();
  }

  @override
  void render(Canvas canvas) => canvas.drawPicture(_picture);

  @override
  void onRemove() {
    _picture.dispose();
    super.onRemove();
  }
}
