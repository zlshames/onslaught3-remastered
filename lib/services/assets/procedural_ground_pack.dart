import 'dart:ui' show Color;

import 'asset_pack.dart';

/// The sharp ground (`docs/history/SCREEN_FIT_PLAN.md` §7.3): the original ground
/// redrawn by a fragment shader in world coordinates, so it is crisp at any
/// zoom and continues past the play area. It provides only the ground and is
/// layered in front of the other packs (`[procedural, classic]`) when the
/// player picks Ground: Sharp (Enhanced skin only).
class ProceduralGroundPack implements AssetPack {
  const ProceduralGroundPack();

  /// The world art id it redraws.
  static const String groundId = 'ground.classic';

  /// The shader, a bundle path (`pubspec.yaml` `flutter: shaders:`).
  static const String shader = 'shaders/ground.frag';

  /// Light, middle and dark sand, sampled from the original ground (its
  /// 90th, 50th and 5th brightness percentiles).
  static const List<Color> palette = [Color(0xFFFFDCB9), Color(0xFFF7CFAA), Color(0xFFDFB18E)];

  @override
  String get id => 'procedural-ground';

  @override
  Future<void> load() async {}

  @override
  Set<String> get spriteIds => const {};

  @override
  Set<String> get soundIds => const {};

  @override
  SpriteAsset? sprite(String id) => null;

  @override
  List<String>? sound(String id) => null;

  @override
  GroundSource? ground(String id) =>
      id == groundId ? const ShaderGround(shader: shader, palette: palette) : null;

  @override
  PackTheme? get theme => null;
}
