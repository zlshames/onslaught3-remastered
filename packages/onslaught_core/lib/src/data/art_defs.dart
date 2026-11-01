import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'json_reader.dart';
import 'params.dart';

/// How a drawn effect looks, beside the behaviour's `params`: its looks by
/// damage ([bands]) and its cosmetic timings and factors ([fx]). These are
/// the original's visual values, not balance; the sim never reads them.
@immutable
class EffectArt {
  const EffectArt({this.bands = const [], this.fx = Params.empty});

  factory EffectArt.fromJson(JsonReader r) {
    r.expectOnlyKeys({'bands', 'fx'});
    return EffectArt(
      bands: r.optList('bands', DamageBand.fromJson),
      fx: r.has('fx') ? Params.fromJson(r.child('fx')) : Params.empty,
    );
  }

  /// Looks by damage in ascending order of their bound; the last has no
  /// bound and covers every higher damage.
  final List<DamageBand> bands;

  /// Named cosmetic timings and factors (`captureShrink`, `swirlDegPerFrame`,
  /// `strokeWidths` …) as the drawing view requires.
  final Params fx;

  /// The first band that covers [damage] (the original tests its bands in
  /// order), or null when there are no bands.
  DamageBand? bandFor(double damage) => bands.firstWhereOrNull((b) => b.covers(damage));

  Map<String, Object?> toJson() => {
    if (bands.isNotEmpty) 'bands': [for (final b in bands) b.toJson()],
    if (!fx.isEmpty) 'fx': fx.toJson(),
  };
}

/// One look of a damage-tiered effect (`LaserEngine.laserGetType`,
/// `SparkEngine.sparkGetType`, `RailLaser.railGetType`). It covers damage up
/// to and including [upTo] (the original's `<=`) or below [below] (its `<`);
/// a band with neither covers everything.
@immutable
class DamageBand {
  const DamageBand({
    this.upTo,
    this.below,
    this.core,
    this.glow,
    this.width,
    this.glowSize,
    this.strokes = const [],
  }) : assert(upTo == null || below == null, 'a band has one bound');

  factory DamageBand.fromJson(JsonReader r) {
    r.expectOnlyKeys({'upTo', 'below', 'core', 'glow', 'width', 'glowSize', 'strokes'});
    if (r.has('upTo') && r.has('below')) r.issue('a band has upTo or below, not both');
    return DamageBand(
      upTo: r.optNumber('upTo'),
      below: r.has('upTo') ? null : r.optNumber('below'),
      core: r.optRgb('core'),
      glow: r.optRgb('glow'),
      width: r.optNumber('width', min: 0),
      glowSize: r.optNumber('glowSize', min: 0),
      strokes: r.optList('strokes', (c) => c.asRgb()),
    );
  }

  /// Inclusive upper bound.
  final double? upTo;

  /// Exclusive upper bound.
  final double? below;

  /// Line colour, 0xRRGGBB.
  final int? core;

  /// Glow colour, 0xRRGGBB.
  final int? glow;

  /// Line width in px.
  final double? width;

  /// Glow size in px (the original's `GlowFilter` blur).
  final double? glowSize;

  /// Colours of several strokes drawn on top of each other, widest first
  /// (the Railgun's five).
  final List<int> strokes;

  /// The bound, whichever kind; null for the last band.
  double? get bound => upTo ?? below;

  bool covers(double damage) => switch ((upTo, below)) {
    (final double u, _) => damage <= u,
    (_, final double b) => damage < b,
    _ => true,
  };

  Map<String, Object?> toJson() => {
    'upTo': ?optJsonNumber(upTo),
    'below': ?optJsonNumber(below),
    if (core != null) 'core': rgbToJson(core!),
    if (glow != null) 'glow': rgbToJson(glow!),
    'width': ?optJsonNumber(width),
    'glowSize': ?optJsonNumber(glowSize),
    if (strokes.isNotEmpty) 'strokes': [for (final s in strokes) rgbToJson(s)],
  };
}
