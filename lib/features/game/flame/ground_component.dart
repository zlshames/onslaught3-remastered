import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/components.dart';

/// Draw order of the ground layers: beyond the play area under the original
/// ground sprite, its decorations on it, the off-map tint and border over them.
abstract final class GroundLayers {
  static const int beyond = -12;
  static const int ground = -11;
  static const int decorations = -10;
  static const int edge = -9;
}

/// The original's faint decorations on the ground (`world.groundArt`,
/// `attract.groundArt`), under the road and cut off at the [stage] like
/// everything else on it. Its children are the sprites.
class GroundDecorations extends Component {
  GroundDecorations({required this.stage, super.children})
    : super(priority: GroundLayers.decorations);

  final Rect stage;

  @override
  void renderTree(Canvas canvas) {
    canvas
      ..save()
      ..clipRect(stage);
    super.renderTree(canvas);
    canvas.restore();
  }
}

/// The original ground image continued past the play area
/// (`docs/history/SCREEN_FIT_PLAN.md` §7.1): mirror-tiled, so it has no seams even
/// though the texture does not tile, over whatever the camera shows. The
/// play area itself keeps the original sprite drawn over it. Without an image
/// it fills with [colour].
class GroundBeyond extends Component {
  GroundBeyond({required this.play, required this.visible, required this.colour, this.image})
    : super(priority: GroundLayers.beyond);

  /// The play area in world px.
  final Rect play;

  /// The world rect the camera shows.
  final Rect Function() visible;
  final Color colour;

  /// Makes the ground image (once, the first time it is needed).
  final Image Function()? image;
  Paint? _paint;

  Paint _make() {
    final make = image;
    if (make == null) return Paint()..color = colour;
    final picture = make();
    final m = Float64List(16)
      ..[0] = play.width / picture.width
      ..[5] = play.height / picture.height
      ..[10] = 1
      ..[12] = play.left
      ..[13] = play.top
      ..[15] = 1;
    return Paint()
      ..shader = ImageShader(
        picture,
        TileMode.mirror,
        TileMode.mirror,
        m,
        filterQuality: FilterQuality.medium,
      );
  }

  @override
  void render(Canvas canvas) {
    canvas.drawRect(visible().inflate(4), _paint ??= _make());
  }
}

/// A ground drawn by a fragment shader in world coordinates (the sharp
/// ground, `docs/history/SCREEN_FIT_PLAN.md` §7.3): it covers whatever the camera
/// shows, inside the play area and beyond. Drawn in the world, so the
/// shader's fragment coordinates (the canvas's local space on every
/// renderer) are world px and the camera needs no uniforms.
class ShaderGroundComponent extends Component {
  ShaderGroundComponent({required this.shader, required this.palette, required this.visible})
    : super(priority: GroundLayers.ground) {
    var i = 0;
    for (final c in palette.take(3)) {
      shader
        ..setFloat(i++, c.r)
        ..setFloat(i++, c.g)
        ..setFloat(i++, c.b)
        ..setFloat(i++, c.a);
    }
  }

  final FragmentShader shader;

  /// Light, middle and dark.
  final List<Color> palette;
  final Rect Function() visible;
  late final Paint _paint = Paint()..shader = shader;

  @override
  void render(Canvas canvas) => canvas.drawRect(visible().inflate(4), _paint);
}

/// Marks the edge of the play area when the ground runs on past it
/// (`docs/history/SCREEN_FIT_PLAN.md` §7.2): everything outside is tinted with the
/// pack's off-map colour, and a thin border runs along the edge (the
/// original draws border lines there, `ENGINE_NOTES.md` §8.5).
class PlayAreaEdge extends Component {
  PlayAreaEdge({required this.play, required this.visible, required Color offMap})
    : _tint = Paint()..color = offMap.withValues(alpha: tintAlpha),
      super(priority: GroundLayers.edge);

  /// How strongly the outside is tinted.
  static const double tintAlpha = 0.45;

  /// Border width in world px.
  static const double borderWidth = 1.5;

  final Rect play;
  final Rect Function() visible;
  final Paint _tint;
  static final Paint _border = Paint()
    ..color = const Color(0x66000000)
    ..style = PaintingStyle.stroke
    ..strokeWidth = borderWidth;

  @override
  void render(Canvas canvas) {
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(visible().inflate(4))
      ..addRect(play);
    canvas
      ..drawPath(outside, _tint)
      ..drawRect(play, _border);
  }
}
