import 'package:meta/meta.dart';

import '../../data/turret_def.dart';
import '../../sim/entities.dart';
import '../../sim/game_session.dart';
import '../behaviours/rocket_state.dart';
import '../rules_registry.dart';
import '../stat_rules.dart';
import '../targeting_rules.dart';

class HoldingState extends SpecialState {
  /// Unlocked by upgrades (`holding_pattern`); never turns off.
  bool pattern = false;

  /// Uids of the rockets fired into the holding pattern since the last
  /// dispatch (`holding_current`). Rockets destroyed since still count.
  final List<int> held = [];

  @override
  Map<String, Object?> toJson() => {'pattern': pattern, 'held': held};
}

/// Red's holding pattern (`TurretRed.update/onUpgrade/onSell`).
///
/// * Unlocked when an upgrade leaves the damage, range and rate levels at
///   or above `levelDamage/Range/Rate` (0/3/3).
/// * Once unlocked every rocket it fires may orbit when it loses its target
///   (`holding_capable`).
/// * While it has no target and has reloaded it fires a held rocket (it
///   orbits until dispatched) until `maxRockets` are held.
/// * On any update where it had a target, after its normal shot every held
///   rocket is sent at its current target (none if lock-off just dropped
///   it) and the list is cleared.
/// * When sold, held rockets are sent at the weakest creep within
///   `sellTargetRange`.
/// * When consumed by a Combonly plate nothing happens to them (they circle
///   forever), except under `holdingRocketLifetime` ([onConsumed]).
class HoldingSpecial extends TurretSpecial {
  const HoldingSpecial();

  static const String specialId = 'holding';

  @override
  String get id => specialId;

  @override
  Set<String>? get paramKeys => const {
    'maxRockets',
    'levelDamage',
    'levelRange',
    'levelRate',
    'sellTargetRange',
  };

  /// [Turret.stateOf] for this special: rules only (it creates the state).
  @internal
  static HoldingState stateOf(Turret t) => t.stateOf(specialId, HoldingState.new);

  @override
  void onUpgraded(GameSession session, Turret turret) {
    final p = params(turret);
    if (turret.damageLevel >= p.number('levelDamage')! &&
        turret.rangeLevel >= p.number('levelRange')! &&
        turret.rateLevel >= p.number('levelRate')!) {
      stateOf(turret).pattern = true;
    }
  }

  @override
  void onShot(GameSession session, Turret turret, Projectile projectile) {
    if (stateOf(turret).pattern) RocketState.of(projectile).holdingCapable = true;
  }

  @override
  void afterAim(
    GameSession session,
    Turret turret, {
    required bool hadTarget,
    required double dtMs,
  }) {
    final state = stateOf(turret);
    if (hadTarget) _dispatch(session, state, turret.targetUid);
    final max = params(turret).number('maxRockets')!;
    if (!state.pattern || !session.canFire(turret) || state.held.length >= max) return;
    final rocket = session.turretFire(
      turret,
      damage: turretStat(turret, StatKind.damage, session.data.rules),
    );
    RocketState.of(rocket)
      ..holdingCapable = true
      ..holdingInitially = true;
    state.held.add(rocket.uid);
  }

  @override
  void onSold(GameSession session, Turret turret) {
    final weakest = acquireTarget(
      creeps: session.creeps,
      from: turret.position,
      range: params(turret).number('sellTargetRange')!,
      mode: _weakest,
      nowMs: session.clock.nowMs,
    );
    _dispatch(session, stateOf(turret), weakest?.uid);
  }

  /// Under `RulesProfile.holdingRocketLifetime` the held rockets of a Red a
  /// Combonly plate consumed are let go: they circle (or find a target) and
  /// their lifetime starts now. In the original nothing dispatches them
  /// (no `onSell`), so they circle forever.
  @override
  void onConsumed(GameSession session, Turret turret) {
    if (!session.config.profile.holdingRocketLifetime) return;
    final state = turret.stateOrNull<HoldingState>(specialId);
    if (state == null) return;
    for (final uid in state.held) {
      final rocket = session.projectileByUid(uid);
      if (rocket == null) continue;
      RocketState.of(rocket)
        ..holdingInitially = false
        ..orbitSinceMs = session.clock.nowMs;
    }
    state.held.clear();
  }

  /// `RocketEngine.targetThis` on every held rocket.
  static void _dispatch(GameSession s, HoldingState state, int? targetUid) {
    for (final uid in state.held) {
      final rocket = s.projectileByUid(uid);
      if (rocket == null) continue;
      rocket.targetUid = targetUid;
      RocketState.of(rocket).holdingInitially = false;
    }
    state.held.clear();
  }

  static const String _weakest = 'weak';
}
