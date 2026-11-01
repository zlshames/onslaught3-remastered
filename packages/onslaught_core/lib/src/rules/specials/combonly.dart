import 'package:meta/meta.dart';

import '../../data/combo_recipe.dart';
import '../../sim/entities.dart';
import '../../sim/game_event.dart';
import '../../sim/game_session.dart';
import '../../sim/sim_constants.dart';
import '../aiming.dart';
import '../rules_registry.dart';
import '../stat_rules.dart';
import 'combo.dart';

/// What a Combonly plate is doing (`combo_mode`).
enum CombonlyMode {
  /// Nothing to offer: it rescans every cycle.
  choose,

  /// Showing its options one colour at a time.
  cycle,

  /// Locked in: consuming its turrets, then a combo weapon.
  fire,
}

class CombonlyState extends SpecialState {
  CombonlyMode mode = CombonlyMode.choose;

  /// What it can become now, in the order it cycles through them
  /// (`combo_types` with `combo_weapons` / `combo_needs`).
  List<CombonlyOption> options = const [];

  /// Index of the option last shown (`combo_type_count`).
  int index = 0;

  /// Colour of the option last shown (`weapon_colour`); kept, unseen, when
  /// the glow is cancelled.
  String? shown;

  /// Whether the colour glow is showing (`TheColour`).
  bool glow = false;

  /// The option it locked in (`combo_to_fire`).
  CombonlyOption? chosen;

  /// Real ms since its last cycle update (its 1000 ms interval).
  double sinceCycleMs = 0;

  /// Turrets being consumed, and real ms since they started to go.
  List<int> consuming = const [];
  double consumeMs = 0;

  /// Real ms its weapon has been fading in, and whether it is in place.
  double armMs = 0;
  bool armed = false;

  @override
  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'options': [for (final o in options) o.recipe],
    'index': index,
    'shown': ?shown,
    'glow': glow,
    'chosen': ?chosen?.recipe,
    'cycleMs': sinceCycleMs,
    if (consuming.isNotEmpty) 'consuming': [consuming, consumeMs],
    if (chosen != null) 'arm': [armMs, armed],
  };
}

/// The Combonly plate (`turrets/TurretCombonly.as`, `CombonlyPlate.as`;
/// `docs/legacy/ENGINE_NOTES.md` §4.8).
///
/// * Until it is locked in it updates every `cycleMs` of real time (also
///   while paused). It scans the combo-capable colour turrets within
///   `scanRange` (whether reloaded or not) against the `combos.json`
///   `combonly` rules: for each colour the last rule whose counts are met is
///   that colour's option. With none it waits (`choose`); with some it
///   shows one colour per update, in turn (`cycle`). Building, selling or
///   moving any turret, or moving the plate, sends it back to `choose` and
///   rescans.
/// * The player clicks it while a colour shows ([choose]): it rechecks the
///   counts and, if they still hold, consumes the turrets the option needs,
///   picked at random per colour. Consumed turrets stop at once, their
///   value goes into the plate's (no refund now) and they are removed
///   `consumeMs` later. The plate takes on the colour's weapon, which is in
///   place `activateMs` later; meanwhile it is inactive.
/// * Then it updates like a turret: it aims at targets within its range and,
///   once facing one, reloaded (its rate) and past its recipe's recharge,
///   fires its recipe silently: no helpers are taken, a helper's link pool
///   adds 0 and a helper's poison is 20 (its helper lists hold the consumed
///   turrets); a BFG still pools its own link turrets (greens within its
///   range). Its leader damage is its own (0, so napalm rockets hit for 0)
///   through its modifiers.
///
/// Options cycle in reverse order of each colour's first match: AS2's
/// `for…in` over `combo_weapons`, assumed to walk properties newest first
/// as elsewhere (not observed). The first colour shown after a scan is the
/// second option (the count was reset to 0 and is advanced before showing).
/// Assumptions where the original breaks: a click on a colour that is no
/// longer an option is refused (the original would lock in nothing and
/// never fire); selling a plate while its turrets are being consumed
/// removes them at once.
class CombonlySpecial extends TurretSpecial {
  const CombonlySpecial();

  static const String specialId = 'combonly';

  @override
  String get id => specialId;

  @override
  Set<String>? get paramKeys => const {'cycleMs', 'consumeMs', 'activateMs', 'scanRange'};

  /// [Turret.stateOf] for this special: rules only (it creates the state).
  @internal
  static CombonlyState stateOf(Turret t) => t.stateOf(specialId, CombonlyState.new);

  /// The combo-capable colour turrets [t] scans, by turret id, in build
  /// order (`comboCountColoursRegardless`).
  static Map<String, List<Turret>> scanned(GameSession s, Turret t) {
    final range = const CombonlySpecial().params(t).number('scanRange')!;
    final out = <String, List<Turret>>{};
    final near = s.turretsNear(
      t,
      range,
      where: (o) => !o.def.comboNever && isComboCapable(o.def, o.damageLevel),
    );
    for (final o in near) {
      out.putIfAbsent(o.def.id, () => []).add(o);
    }
    return out;
  }

  /// The options [counts] allow, in cycle order (`comboScan`).
  static List<CombonlyOption> optionsFor(GameSession s, Map<String, List<Turret>> counts) {
    final byColour = <String, CombonlyOption>{};
    for (final o in s.data.combonly) {
      if (_meets(o.needs, counts)) byColour[o.colour] = o;
    }
    return byColour.values.toList().reversed.toList();
  }

  static bool _meets(ComboRequirement needs, Map<String, List<Turret>> counts) =>
      needs.counts.entries.every((e) => (counts[e.key]?.length ?? 0) >= e.value);

  @override
  void onBuilt(GameSession session, Turret turret) {
    turret.firedAtMs = session.clock.nowMs;
    _scan(session, turret, stateOf(turret));
  }

  @override
  void onRealTime(GameSession session, Turret turret, double realMs) {
    final st = stateOf(turret);
    final p = params(turret);
    if (st.chosen == null) {
      final cycleMs = p.number('cycleMs')!;
      st.sinceCycleMs += realMs;
      while (st.chosen == null && st.sinceCycleMs >= cycleMs - epsilonMs) {
        st.sinceCycleMs -= cycleMs;
        _cycle(session, turret, st);
      }
      return;
    }
    if (st.consuming.isNotEmpty) {
      st.consumeMs += realMs;
      if (st.consumeMs >= p.number('consumeMs')! - epsilonMs) _removeConsumed(session, turret, st);
    }
    if (!st.armed) {
      st.armMs += realMs;
      if (st.armMs >= p.number('activateMs')! - epsilonMs) _arm(session, turret, st);
    }
  }

  /// One cycle update (`update` in `choose` or `cycle` mode).
  void _cycle(GameSession s, Turret t, CombonlyState st) {
    switch (st.mode) {
      case CombonlyMode.choose:
        st.glow = false;
        _scan(s, t, st);
        st.index = 0;
      case CombonlyMode.cycle:
        _scan(s, t, st);
        if (st.options.isEmpty) {
          st
            ..shown = null
            ..glow = false
            ..mode = CombonlyMode.choose;
          return;
        }
        st
          ..index = (st.index + 1) % st.options.length
          ..shown = st.options[st.index].colour
          ..glow = true;
      case CombonlyMode.fire:
        break;
    }
  }

  void _scan(GameSession s, Turret t, CombonlyState st) {
    if (st.chosen != null) return;
    st
      ..options = optionsFor(s, scanned(s, t))
      ..mode = st.options.isEmpty ? CombonlyMode.choose : CombonlyMode.cycle;
  }

  void _rescan(GameSession s, Turret t) {
    final st = stateOf(t);
    if (st.chosen != null) return;
    st
      ..mode = CombonlyMode.choose
      ..glow = false;
    _scan(s, t, st);
  }

  @override
  void onTurretAdded(GameSession session, Turret turret, Turret other) => _rescan(session, turret);

  @override
  void onTurretGone(GameSession session, Turret turret, Turret other) => _rescan(session, turret);

  @override
  void onMoved(GameSession session, Turret turret) => _rescan(session, turret);

  /// A click on the plate (`onPress` → `comboChoose`); the reason it does
  /// nothing, or null.
  String? choose(GameSession s, Turret t) {
    final st = stateOf(t);
    final shown = st.shown;
    if (st.mode != CombonlyMode.cycle || shown == null) return 'nothingShown';
    final option = st.options.where((o) => o.colour == shown).firstOrNull;
    if (option == null) return 'unavailable';
    final counts = scanned(s, t);
    if (!_meets(option.needs, counts)) {
      st
        ..glow = false
        ..mode = CombonlyMode.choose;
      return 'unavailable';
    }
    st
      ..mode = CombonlyMode.fire
      ..chosen = option
      ..glow = false
      ..armMs = 0;
    t
      ..active = false
      ..targetUid = null
      ..rotation = 0;
    final consumed = <int>[];
    for (final e in option.needs.counts.entries.toList().reversed) {
      for (final c in pickRandom(s.random, counts[e.key]!, e.value)) {
        s.consumeTurret(c, t);
        consumed.add(c.uid);
      }
    }
    st
      ..consuming = consumed
      ..consumeMs = 0;
    _emitChanged(s, t, 'chosen', option, consumed: consumed, cashValue: t.cashValue);
    return null;
  }

  /// Reports [stage] of [t] with [option].
  static void _emitChanged(
    GameSession s,
    Turret t,
    String stage,
    CombonlyOption option, {
    List<int> consumed = const [],
    double? cashValue,
  }) => s.emit(
    CombonlyChanged(
      s.stepIndex,
      uid: t.uid,
      stage: stage,
      colour: option.colour,
      recipe: option.recipe,
      consumed: consumed,
      cashValue: cashValue,
    ),
  );

  void _removeConsumed(GameSession s, Turret t, CombonlyState st) {
    final uids = st.consuming;
    st.consuming = const [];
    for (final uid in uids) {
      final c = s.turretByUid(uid);
      if (c != null) s.removeConsumed(c, t);
    }
  }

  /// `comboActivate`: the weapon is in place; a fresh update timer starts.
  void _arm(GameSession s, Turret t, CombonlyState st) {
    st.armed = true;
    t
      ..active = true
      ..sinceTickMs = 0
      ..updatedAtMs = null;
    _emitChanged(s, t, 'armed', st.chosen!);
  }

  @override
  bool get ownsUpdate => true;

  @override
  void update(GameSession session, Turret turret, double dtMs) {
    final s = session;
    if (!stateOf(turret).armed) return;
    final target = acquireFor(s, turret);
    if (target != null) {
      turret.bearCreepUid = null;
      tryFiring(s, turret, target, dtMs);
    } else {
      bearToCreep(s, turret, dtMs);
    }
  }

  /// Its `turretTryFiring`: once facing [target], fire the recipe if it may
  /// (`comboCanFire`). Before it has a weapon it never faces anything.
  @override
  bool tryFiring(GameSession session, Turret turret, Creep target, double dtMs) {
    final s = session;
    final st = stateOf(turret);
    final chosen = st.chosen;
    if (!st.armed || chosen == null || !turret.active) return true;
    if (!turnToward(s, turret, target.position, dtMs)) return true;
    if (!s.reloadedForCombo(turret) || s.clock.nowMs < ComboSpecial.stateOf(turret).nextAtMs) {
      return true;
    }
    ComboSpecial.fireRecipe(
      s,
      turret,
      s.data.combos[chosen.recipe]!,
      target,
      const {},
      silent: true,
      firePoints: s.data.turrets[chosen.colour]?.firePoints,
    );
    return true;
  }

  @override
  void onSold(GameSession session, Turret turret) {
    final st = stateOf(turret);
    if (st.consuming.isNotEmpty) _removeConsumed(session, turret, st);
  }
}
