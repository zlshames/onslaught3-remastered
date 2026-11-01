import 'dart:math' as math;

import '../data/rules_constants.dart';
import '../data/turret_def.dart';
import '../sim/entities.dart';

/// Effective value of a stat after modifiers (`Turret.modifyStat`):
/// `max(0, (base + added) × max(mult, multFloor))`. [mult] starts at 1 and
/// accumulates each modifier's multiplier term.
double effectiveStat({
  required double base,
  required double added,
  required double mult,
  required double multFloor,
}) => math.max(0, (base + added) * math.max(mult, multFloor));

/// Milliseconds between shots for a rate in shots per minute
/// (`Turret.modifyUpdate`: `1000 / (rate / 60)`). Infinite for rate ≤ 0.
double fireIntervalMs(double ratePerMinute) =>
    ratePerMinute <= 0 ? double.infinity : Duration.millisecondsPerMinute / ratePerMinute;

/// The stat value at upgrade [level] of [track] (0 = not upgraded = [base]).
/// Upgrading sets the stat to the step's value; it does not add.
double statAtLevel(double base, List<UpgradeStep> track, int level) {
  if (level <= 0 || track.isEmpty) return base;
  return track[math.min(level, track.length) - 1].value;
}

/// Cost of the next upgrade from [level], or null when the track is maxed.
double? nextUpgradeCost(List<UpgradeStep> track, int level) =>
    level < track.length ? track[level].cost : null;

/// Upgrade progress as a percentage (`Turret.upgradeAsPercent`).
double upgradePercent(List<UpgradeStep> track, int level) =>
    track.isEmpty ? 0 : math.min(level, track.length) * 100 / track.length;

/// Whether a turret can lead or help combos (`Turret.comboActivate`): never
/// for `comboNever` turrets, otherwise once its damage track is 100 %
/// upgraded, or from the start when `comboCapable` is set in data.
bool isComboCapable(TurretDef def, int damageLevel) {
  if (def.comboNever) return false;
  if (def.comboCapableInitially) return true;
  final track = def.upgrades.damage;
  return track.isNotEmpty && damageLevel >= track.length;
}

/// A turret's [stat] before modifiers: the value of its current upgrade
/// level (`weapon_damage`, `weapon_range`, `weapon_rate`).
double turretBaseStat(Turret t, StatKind stat) =>
    statAtLevel(t.def.stats.stat(stat), t.def.upgrades.track(stat), t.level(stat));

/// A turret's effective [stat] (`Turret.modifyUpdate`): its base value
/// through [effectiveStat] with the `added`/`mult` terms of the modifier
/// auras around it and its running freakouts ([Turret.terms]), or with
/// [terms] when given.
double turretStat(Turret t, StatKind stat, RulesConstants rules, {StatTerms? terms}) {
  final tm = terms ?? t.terms;
  return effectiveStat(
    base: turretBaseStat(t, stat),
    added: tm.added(stat),
    mult: tm.mult(stat),
    multFloor: rules.modifierMultFloor,
  );
}

/// A turret's effective poison (`weapon_poison_effective`): its base poison
/// through the same formula with the poison terms.
double turretPoison(Turret t, RulesConstants rules, {StatTerms? terms}) {
  final tm = terms ?? t.terms;
  return effectiveStat(
    base: t.poison,
    added: tm.addPoison,
    mult: 1 + tm.multPoison,
    multFloor: rules.modifierMultFloor,
  );
}

/// The terms a modifier's [aura] adds to a turret it covers
/// (`TurretModify._modifyAssert`).
StatTerms auraTerms(ModifierAura aura) => StatTerms(
  addDamage: aura.addDamage,
  addRange: aura.addRange,
  addRate: aura.addRate,
  multDamage: aura.multDamage,
  multRange: aura.multRange,
  multRate: aura.multRate,
);

/// [amount] through [t]'s damage modifiers (`Turret.modifyDamage`): what a
/// combo does to each of its damage values.
double modifiedDamage(Turret t, double amount, RulesConstants rules) => effectiveStat(
  base: amount,
  added: t.terms.addDamage,
  mult: t.terms.mult(StatKind.damage),
  multFloor: rules.modifierMultFloor,
);
