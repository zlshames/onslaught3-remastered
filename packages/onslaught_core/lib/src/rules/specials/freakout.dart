import 'package:meta/meta.dart';

import '../../data/turret_def.dart';
import '../../sim/entities.dart';
import '../../sim/game_event.dart';
import '../../sim/game_session.dart';
import '../rules_registry.dart';

/// One running freakout (`FreakoutEngine`): a warning, then the active
/// multipliers, timed on the game clock.
class FreakoutRun {
  FreakoutRun(this.sinceMs);

  /// False while warning, true while the multipliers apply.
  bool active = false;

  /// Game time the current stage began.
  double sinceMs;

  Map<String, Object?> toJson() => {'active': active, 'sinceMs': sinceMs};
}

class FreakoutState extends SpecialState {
  /// Damage and rate levels reached (`freak_available`).
  bool available = false;

  /// Game time of the next automatic freakout (`freak_next`); null while
  /// none is scheduled.
  double? nextAtMs;

  final List<FreakoutRun> runs = [];

  /// Null until something is scheduled or running: [available] alone is
  /// derivable from the levels.
  @override
  Map<String, Object?>? toJson() => nextAtMs == null && runs.isEmpty
      ? null
      : {
          'next': nextAtMs,
          'runs': [for (final r in runs) r.toJson()],
        };
}

/// Blue and Yellow's freakout (`Turret.freakoutActivate/Now/Next`,
/// `FreakoutEngine`, `turrets/TurretBlue.as` and `TurretYellow.as` update).
///
/// * Available once an upgrade leaves the damage, range and rate levels at
///   or above `levelDamage/Range/Rate` (4/0/4).
/// * The first automatic freakout: under `RulesProfile.freakoutAutoStart`
///   `firstDelayMs` (60 s) after it became available. The original never
///   schedules it (an uninitialised `freak_next` fails its `== false`
///   guard), so in the classic rules none ever happens.
/// * When the time comes (checked at the start of the turret's update) the
///   next one is scheduled `spacing/2 + U(0, spacing/2) − rate level ×
///   rateMult s` later, and this one warns for more than `warnMs`, then
///   adds `damageMult/rangeMult/rateMult` to the turret's multipliers for
///   more than `lengthMs`, then removes them. Runs may overlap and stack.
/// * Buying one ([buyCost]) costs `floor(seconds to the next) ×
///   buyCostPerSecond` (0 once it is overdue) and starts it now.
class FreakoutSpecial extends TurretSpecial {
  const FreakoutSpecial();

  static const String specialId = 'freakout';

  @override
  String get id => specialId;

  @override
  Set<String>? get paramKeys => const {'firstDelayMs', 'warnMs', 'jitterPx', 'buyCostPerSecond'};

  /// [Turret.stateOf] for this special: rules only (it creates the state).
  @internal
  static FreakoutState stateOf(Turret t) => t.stateOf(specialId, FreakoutState.new);

  @override
  void onUpgraded(GameSession session, Turret turret) {
    final spec = turret.def.freakout;
    if (spec == null || !spec.capable) return;
    if (turret.damageLevel < spec.levelDamage ||
        turret.rangeLevel < spec.levelRange ||
        turret.rateLevel < spec.levelRate) {
      return;
    }
    final state = stateOf(turret)..available = true;
    if (session.config.profile.freakoutAutoStart && state.nextAtMs == null) {
      state.nextAtMs = session.clock.nowMs + params(turret).number('firstDelayMs')!;
    }
  }

  @override
  void onStep(GameSession session, Turret turret, double dtMs) {
    final state = turret.stateOrNull<FreakoutState>(specialId);
    if (state != null) _advance(session, turret, state);
  }

  @override
  void beforeAim(GameSession session, Turret turret, double dtMs) {
    final state = turret.stateOrNull<FreakoutState>(specialId);
    if (state == null) return;
    final next = state.nextAtMs;
    if (state.available && next != null && session.clock.nowMs >= next) {
      freakoutNow(session, turret);
    }
  }

  /// `Turret.freakoutNow`: schedule the next one and start warning. [cost]
  /// is set when the player bought it.
  void freakoutNow(GameSession s, Turret t, {double? cost}) {
    final state = stateOf(t);
    if (state.available) state.nextAtMs = _next(s, t);
    state.runs.add(FreakoutRun(s.clock.nowMs));
    s.emit(
      FreakoutChanged(
        s.stepIndex,
        uid: t.uid,
        stage: stageWarning,
        cost: cost,
        cash: cost == null ? null : s.cash,
      ),
    );
  }

  /// What buying a freakout now costs, or null when none can be bought
  /// (not available, or nothing scheduled: the original's NaN cost).
  ///
  /// The automatic one only starts on the turret's own tick ([beforeAim]),
  /// so the scheduled time can pass before it fires; an overdue freakout
  /// costs what the formula gives at exactly zero seconds (0), never a
  /// negative amount that would pay the player.
  double? buyCost(GameSession s, Turret t) {
    final state = t.stateOrNull<FreakoutState>(specialId);
    final next = state?.nextAtMs;
    if (state == null || !state.available || next == null) return null;
    final seconds = ((next - s.clock.nowMs) / 1000).floorToDouble();
    if (seconds < 0) return 0;
    return seconds * params(t).number('buyCostPerSecond')!;
  }

  /// Game ms until [t]'s next automatic freakout, or null.
  static double? msUntilNext(GameSession s, Turret t) {
    final next = t.stateOrNull<FreakoutState>(specialId)?.nextAtMs;
    return next == null ? null : next - s.clock.nowMs;
  }

  static const String stageWarning = 'warning';
  static const String stageActive = 'active';
  static const String stageEnded = 'ended';

  /// `Turret.freakoutNext`.
  double _next(GameSession s, Turret t) {
    final spec = t.def.freakout!;
    final half = spec.spacingMs / 2;
    return s.clock.nowMs +
        half +
        s.random.nextDouble() * half -
        t.rateLevel * spec.rateMult * Duration.millisecondsPerSecond;
  }

  void _advance(GameSession s, Turret t, FreakoutState state) {
    final spec = t.def.freakout!;
    final p = params(t);
    final now = s.clock.nowMs;
    final terms = _terms(spec);
    for (final run in List.of(state.runs)) {
      if (!run.active) {
        if (now - run.sinceMs <= p.number('warnMs')!) continue;
        run
          ..active = true
          ..sinceMs = now;
        t.freak = t.freak + terms;
        s.emit(FreakoutChanged(s.stepIndex, uid: t.uid, stage: stageActive));
      } else if (now - run.sinceMs > spec.lengthMs) {
        t.freak = t.freak + -terms;
        state.runs.remove(run);
        s.emit(FreakoutChanged(s.stepIndex, uid: t.uid, stage: stageEnded));
      }
    }
  }

  static StatTerms _terms(FreakoutSpec spec) =>
      StatTerms(multDamage: spec.damageMult, multRange: spec.rangeMult, multRate: spec.rateMult);
}
