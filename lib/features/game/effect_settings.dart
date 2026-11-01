import 'package:flutter/foundation.dart';
import 'package:onslaught_core/onslaught_core.dart';

/// The player's display settings a running game reads, in the world and in
/// the HUD: rocket smoke (the original's `GameStatus.rocket_smoke` /
/// `rocket_smoke_max`, applied when the settings window closes) and the
/// remaster's colour badges.
@immutable
class EffectSettings {
  const EffectSettings({
    required this.rocketSmoke,
    required this.smokeMax,
    this.colourBadges = false,
  });

  /// The data's defaults, no badges.
  EffectSettings.of(GameData data)
    : rocketSmoke = data.world.effects.rocketSmoke.enabled,
      smokeMax = data.world.effects.rocketSmoke.max,
      colourBadges = false;

  final bool rocketSmoke;
  final int smokeMax;

  /// Shape-and-letter badges on the colour turrets.
  final bool colourBadges;

  @override
  bool operator ==(Object other) =>
      other is EffectSettings &&
      other.rocketSmoke == rocketSmoke &&
      other.smokeMax == smokeMax &&
      other.colourBadges == colourBadges;

  @override
  int get hashCode => Object.hash(rocketSmoke, smokeMax, colourBadges);
}

/// Settings that never change (screens and tests without a settings
/// source).
class FixedEffects implements ValueListenable<EffectSettings> {
  const FixedEffects(this.value);

  @override
  final EffectSettings value;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
