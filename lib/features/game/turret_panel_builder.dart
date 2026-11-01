import 'dart:math' as math;

import 'package:onslaught_core/onslaught_core.dart';

import 'game_snapshots.dart';

/// What the selected-turret sheet shows for turret [uid] of [session] (null
/// when there is no such turret): its stats, upgrade rows and special cards,
/// with names in [locale]. [joining] is the Targeter whose joins the player
/// is editing, if any. Reads the session; changes nothing.
TurretPanel? buildTurretPanel(
  GameSession session,
  int? uid, {
  required String locale,
  int? joining,
}) => _PanelBuilder(session, locale, joining).panel(uid);

class _PanelBuilder {
  const _PanelBuilder(this.session, this.locale, this.joining);

  final GameSession session;
  final String locale;
  final int? joining;

  GameData get data => session.data;

  TurretPanel? panel(int? uid) {
    final t = uid == null ? null : session.turretByUid(uid);
    if (t == null) return null;
    final s = session;
    return TurretPanel(
      uid: t.uid,
      turretId: t.def.id,
      typeName: data.turretName(t.def.id, locale: locale),
      displayName: t.displayName,
      icon: t.def.art.icon,
      kills: t.kills,
      shots: t.shots,
      stats: [
        for (final stat in StatKind.values)
          if (t.def.upgrades.track(stat).isNotEmpty) _row(t, stat),
      ],
      refund: sellRefund(t.cashValue, data.rules.sellRefund),
      moveCost: data.world.placement.moveCost,
      canAffordMove: s.cash >= data.world.placement.moveCost,
      targetMode: t.targetMode,
      targetModeIndex: t.targetModeIndex,
      targetModes: data.targeting.modes,
      lockOff: t.lockOff,
      locked: s.clock.paused || s.gameOver || !t.active,
      cards: [for (final id in t.def.specials) ?_card(t, id)],
      auraRadius: t.def.modifierAura == null ? null : ModifierSpecial.auraRadius(t),
    );
  }

  /// A special's state is created by the rules on first use and is part of
  /// the hashed state, so the builder only reads it ([Turret.stateOrNull])
  /// and shows the state's initial values while there is none.
  SpecialCard? _card(Turret t, String special) {
    final s = session;
    final rules = data.rules;
    switch (special) {
      case ComboSpecial.specialId:
        return _comboCard(t);
      case FreakoutSpecial.specialId:
        if (!(t.def.freakout?.capable ?? false)) return null;
        final state = t.stateOrNull<FreakoutState>(special);
        final runs = state?.runs ?? const [];
        final next = FreakoutSpecial.msUntilNext(s, t);
        final sp = s.registry.turretSpecial(special);
        final cost = sp is FreakoutSpecial ? sp.buyCost(s, t) : null;
        return FreakoutCard(
          available: state?.available ?? false,
          stage: runs.isEmpty
              ? FreakoutCard.stageIdle
              : runs.last.active
              ? FreakoutSpecial.stageActive
              : FreakoutSpecial.stageWarning,
          nextSeconds: next == null ? null : (next / 1000).floor(),
          buyCost: cost,
          affordable: cost != null && s.cash >= cost,
        );
      case ChargeSpecial.specialId:
        final charge = t.stateOrNull<ChargeState>(special)?.charge ?? 0;
        final boost = (t.def.specialParams[special]?.number('poisonBoost') ?? 0) * charge / 100;
        return ChargeCard(
          charge: charge,
          max: ChargeSpecial.maxCharge(t),
          ratePerSecond: ChargeSpecial.chargeRate(t),
          shotPoison: turretPoison(
            t,
            rules,
            terms: charge > 0 ? t.terms + StatTerms(addPoison: boost) : null,
          ),
        );
      case HoldingSpecial.specialId:
        final state = t.stateOrNull<HoldingState>(special);
        final p = t.def.specialParams[special];
        return HoldingCard(
          unlocked: state?.pattern ?? false,
          held: state?.held.length ?? 0,
          max: (p?.number('maxRockets') ?? 0).toInt(),
          levelRange: (p?.number('levelRange') ?? 0).toInt(),
          levelRate: (p?.number('levelRate') ?? 0).toInt(),
        );
      case LinkSpecial.specialId:
        return LinkCard(
          links: LinkSpecial.neighbours(s, t).length,
          lastDamage: t.stateOrNull<LinkState>(special)?.lastDamage ?? 0,
          mult: t.def.specialParams[special]?.number('mult') ?? 1,
        );
      case ModifierSpecial.specialId:
        final aura = t.def.modifierAura;
        if (aura == null) return null;
        return AuraCard(
          terms: auraTerms(aura),
          radius: ModifierSpecial.auraRadius(t),
          covered: ModifierSpecial.covered(s, t).length,
        );
      case TargeterSpecial.specialId:
        return TargeterCard(
          joins: t.stateOrNull<TargeterState>(special)?.joins.length ?? 0,
          max: (t.def.specialParams[special]?.number('joinMax') ?? 0).toInt(),
          joining: joining == t.uid,
        );
      case FusionSpecial.specialId:
        final state = t.stateOrNull<FusionState>(special);
        final storeDamage = state?.storeDamage ?? 0;
        final p = t.def.specialParams[special] ?? Params.empty;
        return FusionCard(
          storeDamage: storeDamage,
          storePoison: state?.storePoison ?? 0,
          tier: (FusionSpecial.tierOf(p, storeDamage) ?? FusionTier.low).name,
          feeders: FusionSpecial.feedersOf(s, t).length,
        );
      case CombonlySpecial.specialId:
        final state = t.stateOrNull<CombonlyState>(special);
        CombonlyChoice choice(CombonlyOption o) =>
            (colour: o.colour, recipe: o.recipe, name: data.comboName(o.recipe, locale: locale));
        final options = state?.options ?? const <CombonlyOption>[];
        final shown = state != null && state.glow && state.mode == CombonlyMode.cycle
            ? options.where((o) => o.colour == state.shown).firstOrNull
            : null;
        final chosen = state?.chosen;
        return CombonlyCard(
          options: [for (final o in options) choice(o)],
          shown: shown == null ? null : choice(shown),
          chosen: chosen == null ? null : choice(chosen),
          armed: state?.armed ?? false,
        );
    }
    return null;
  }

  ComboCard _comboCard(Turret t) {
    final s = session;
    final state = t.stateOrNull<ComboState>(ComboSpecial.specialId);
    final capable = isComboCapable(t.def, t.damageLevel);
    final partners = <String, List<Turret>>{};
    for (final o in ComboSpecial.neighbours(s, t)) {
      if (isComboCapable(o.def, o.damageLevel)) partners.putIfAbsent(o.def.id, () => []).add(o);
    }
    final wait = (state?.nextAtMs ?? 0) - s.clock.nowMs;
    String? recipe(String? id) => id == null ? null : data.comboName(id, locale: locale);
    return ComboCard(
      capable: capable,
      damageLevelsToGo: math.max(0, t.def.upgrades.damage.length - t.damageLevel),
      nextSeconds: !capable || wait < 0 ? null : (wait / 1000).floor(),
      partners: {for (final e in partners.entries) e.key: e.value.length},
      recipe: capable ? recipe(ComboSpecial.match(data, t.def.id, partners)?.id) : null,
      led: state?.led ?? 0,
      assisted: state?.assisted ?? 0,
    );
  }

  StatRow _row(Turret t, StatKind stat) {
    final track = t.def.upgrades.track(stat);
    final level = t.level(stat);
    final cost = nextUpgradeCost(track, level);
    final terms = t.terms;
    return StatRow(
      stat: stat,
      level: level,
      maxLevel: track.length,
      value: session.statOf(t, stat),
      baseValue: turretBaseStat(t, stat),
      nextValue: cost == null
          ? null
          : effectiveStat(
              base: track[level].value,
              added: terms.added(stat),
              mult: terms.mult(stat),
              multFloor: data.rules.modifierMultFloor,
            ),
      nextCost: cost,
      affordable: cost != null && session.cash >= cost,
    );
  }
}
