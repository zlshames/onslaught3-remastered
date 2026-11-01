import '../../data/turret_def.dart';
import '../../math/vec2.dart';
import '../../sim/entities.dart';
import '../../sim/game_session.dart';
import '../rules_registry.dart';
import '../stat_rules.dart';

/// The seven modifier turrets (`TurretModify` and subclasses): no weapon,
/// an aura that adds its `modifierAura` terms to every modifiable turret
/// whose centre is within the modifier's own range (its *base* range at its
/// upgrade level; modifiers are not modifiable themselves). Auras stack
/// with each other and with freakouts by adding terms; the multiplier
/// floor applies once to the total (`Turret.modifyStat`).
class ModifierSpecial extends TurretSpecial {
  const ModifierSpecial();

  static const String specialId = 'modifier';

  @override
  String get id => specialId;

  @override
  Set<String>? get paramKeys => const {};

  /// The aura radius of modifier [t].
  static double auraRadius(Turret t) => turretBaseStat(t, StatKind.range);

  /// The turrets modifier [m] covers (`modify_in_range`).
  static Iterable<Turret> covered(GameSession s, Turret m) =>
      s.turretsNear(m, auraRadius(m), includeInactive: true, where: (o) => o.def.modifiable);

  /// The summed aura terms a turret centred at [point] would get from the
  /// modifiers in [s] (`TurretModify.modifyGetInRange` seen from the
  /// receiving end), in turret order like [applyRelations]. [exclude] is
  /// left out (a turret being moved does not cover its own new spot); a
  /// turret that is not [modifiable] gets [StatTerms.identity].
  static StatTerms termsAt(GameSession s, Vec2 point, {Turret? exclude, required bool modifiable}) {
    var terms = StatTerms.identity;
    if (!modifiable) return terms;
    for (final m in s.turrets) {
      final aura = m.def.modifierAura;
      if (aura == null || m == exclude) continue;
      if (m.position.distanceTo(point) <= auraRadius(m)) terms = terms + auraTerms(aura);
    }
    return terms;
  }

  @override
  void applyRelations(GameSession session, Turret turret) {
    final aura = turret.def.modifierAura;
    if (aura == null) return;
    final terms = auraTerms(aura);
    for (final o in covered(session, turret)) {
      o.aura = o.aura + terms;
    }
  }
}
