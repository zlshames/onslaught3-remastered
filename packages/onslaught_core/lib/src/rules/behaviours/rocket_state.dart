import '../../sim/entities.dart';

/// A rocket's holding state (`RocketEngine`'s `holding_*` and
/// `offscreen_remove`). Set before launch by whoever makes the rocket (a
/// holding-capable combo, the Holding special, a cluster) or after it (the
/// Holding special's held rockets); `RocketKind` reads and moves it.
class RocketState extends KindState {
  /// Orbit when there is no target (`holding_capable`).
  bool holdingCapable = false;

  /// Orbit until the turret dispatches it (`holding_initially`).
  bool holdingInitially = false;

  /// Orbit direction, +1 clockwise or −1 (`holding_dir`).
  double holdingDir = 1;

  /// Removed once off the stage (`offscreen_remove`).
  bool offscreenRemove = false;

  /// Game time it began orbiting without a target, for the
  /// `holdingRocketLifetime` toggle (off in every shipped profile).
  double? orbitSinceMs;

  /// [p]'s rocket state, made on first use.
  static RocketState of(Projectile p) => switch (p.state) {
    final RocketState r => r,
    _ => p.state = RocketState(),
  };

  /// These fields lived on the projectile before this class did; they stay
  /// at its top level in the snapshot.
  @override
  bool get flatInSnapshot => true;

  @override
  Map<String, Object?> toJson() => {
    if (holdingCapable) 'holding': [holdingInitially, holdingDir],
    if (offscreenRemove) 'offscreen': true,
    'orbitSinceMs': ?orbitSinceMs,
  };
}
