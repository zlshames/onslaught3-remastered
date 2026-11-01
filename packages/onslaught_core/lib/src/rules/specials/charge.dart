import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../../data/turret_def.dart';
import '../../sim/entities.dart';
import '../../sim/game_session.dart';
import '../rules_registry.dart';
import '../stat_rules.dart';

class ChargeState extends SpecialState {
  /// Stored charge (`charge_cur`).
  double charge = 0;

  /// The damage a charged shot would have dealt
  /// (`charge_damage`): shown by the info panel, never dealt.
  double shownDamage = 0;

  @override
  Map<String, Object?> toJson() => {'charge': charge};
}

/// Yellow's charge (`TurretYellow.chargeAccumulate/chargeFire/onUpgrade`).
///
/// * Every update the charge grows by `rateBase + ratePerRateLevel × rate
///   level` per second, up to `base + maxPerDamageLevel × damage level`.
/// * Any shot while some charge is stored is a charged shot: its poison is
///   `(poison + added + poisonBoost × charge/100) × max(mult, floor)`, then
///   `cost` charge is used (not below 0). The damage boost the info panel
///   shows (`× (mult + charge/100)`) is never applied.
/// * Every upgrade sets the base poison to `max(1, poisonMax × damage %)`,
///   the damage % rounded down to a whole percent (`upgradeAsPercent`).
class ChargeSpecial extends TurretSpecial {
  const ChargeSpecial();

  static const String specialId = 'charge';

  @override
  String get id => specialId;

  @override
  Set<String>? get paramKeys => const {
    'base',
    'rateBase',
    'cost',
    'poisonMax',
    'maxPerDamageLevel',
    'ratePerRateLevel',
    'poisonBoost',
  };

  /// [Turret.stateOf] for this special: rules only (it creates the state).
  @internal
  static ChargeState stateOf(Turret t) => t.stateOf(specialId, ChargeState.new);

  /// Most charge [t] can hold (`charge_max`).
  static double maxCharge(Turret t) {
    final p = const ChargeSpecial().params(t);
    return p.number('base')! + p.number('maxPerDamageLevel')! * t.damageLevel;
  }

  /// Charge gained per second (`charge_rate`).
  static double chargeRate(Turret t) {
    final p = const ChargeSpecial().params(t);
    return p.number('rateBase')! + p.number('ratePerRateLevel')! * t.rateLevel;
  }

  @override
  void onUpgraded(GameSession session, Turret turret) {
    final track = turret.def.upgrades.damage;
    final percent = track.isEmpty ? 0 : (turret.damageLevel / track.length * 100).floor();
    turret.poison = math.max(1, params(turret).number('poisonMax')! * percent / 100);
  }

  @override
  void beforeAim(GameSession session, Turret turret, double dtMs) {
    final state = stateOf(turret);
    final max = maxCharge(turret);
    if (state.charge >= max) return;
    state.charge = math.min(
      math.max(state.charge, 0) + chargeRate(turret) * dtMs / Duration.millisecondsPerSecond,
      max,
    );
  }

  @override
  bool fire(GameSession session, Turret turret, Creep target) {
    final state = stateOf(turret);
    if (state.charge <= 0) return false;
    final c = state.charge / 100;
    final rules = session.data.rules;
    final boost = StatTerms(addPoison: params(turret).number('poisonBoost')! * c);
    final shown = StatTerms(multDamage: c);
    session.turretFire(
      turret,
      target: target,
      damage: turretStat(turret, StatKind.damage, rules),
      poison: turretPoison(turret, rules, terms: turret.terms + boost),
    );
    state
      ..shownDamage = turretStat(turret, StatKind.damage, rules, terms: turret.terms + shown)
      ..charge = math.max(state.charge - params(turret).number('cost')!, 0);
    return true;
  }
}
