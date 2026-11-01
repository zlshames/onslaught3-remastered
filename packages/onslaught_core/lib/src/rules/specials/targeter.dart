import 'package:meta/meta.dart';

import '../../sim/entities.dart';
import '../../sim/game_event.dart';
import '../../sim/game_session.dart';
import '../aiming.dart';
import '../rules_registry.dart';
import '../targeting_rules.dart';
import 'combo.dart';

class TargeterState extends SpecialState {
  /// Joined turrets' uids, oldest first (`join_to`).
  final List<int> joins = [];

  /// The creep its beam is on (painted once it faces it), for the views.
  int? painted;

  @override
  Map<String, Object?> toJson() => {'joins': joins, 'painted': ?painted};
}

/// The Targeter (`turrets/TurretTargeter.as`, `TurretJoiner.as`).
///
/// * It has no weapon. Each update it keeps or acquires a target by its
///   mode (fastest creep by default, lock off) within its range, which
///   modifiers affect. With none it spins idly at `idleRotate` °/s.
/// * It turns toward the target at its rotate speed; once facing it, it
///   paints it with its beam and, when reloaded (its "rate" is how often it
///   triggers), sends every joined turret at it: each runs its own
///   `turretTryFiring` at that creep, ignoring its own range (it still has
///   to turn to face it and be reloaded), and turns toward that creep while
///   it has no target of its own. With lock off it then drops the target.
/// * The player joins turrets with the joiner: any turret except the
///   modifiers (`joinable`) and itself, at any distance; joining a joined
///   turret lets it go; joining one more than `joinMax` drops the oldest.
///   A turret that is sold, consumed or moved is let go (`notifyMove` is a
///   gone plus a new). Targeters can join Targeters (it then triggers that
///   one's joins).
///
/// Joined turrets are triggered newest first: AS2's `for…in` over
/// `join_to`, assumed to walk arrays from the end as elsewhere (not
/// observed; it only matters when two joined turrets share a helper).
class TargeterSpecial extends TurretSpecial {
  const TargeterSpecial();

  static const String specialId = 'targeter';

  @override
  String get id => specialId;

  @override
  Set<String>? get paramKeys => const {'joinSnap', 'joinSearchBox', 'joinMax', 'idleRotate'};

  /// [Turret.stateOf] for this special: rules only (it creates the state).
  @internal
  static TargeterState stateOf(Turret t) => t.stateOf(specialId, TargeterState.new);

  /// The turrets [t] has joined, oldest first.
  static List<Turret> joinedTurrets(GameSession s, Turret t) => [
    for (final uid in stateOf(t).joins) ?s.turretByUid(uid),
  ];

  /// Joins [other] to [t], or lets it go when it is joined already; the
  /// reason it cannot, or null.
  String? toggleJoin(GameSession s, Turret t, Turret other) {
    if (other == t) return 'self';
    if (!other.def.joinable) return 'notJoinable';
    final joins = stateOf(t).joins;
    final joined = !joins.contains(other.uid);
    if (joined) {
      if (joins.length >= params(t).number('joinMax')!) joins.removeAt(0);
      joins.add(other.uid);
    } else {
      joins.remove(other.uid);
    }
    _emitJoined(s, t, other, joined: joined);
    return null;
  }

  /// Reports that [other] was joined to [t] or let go, with [t]'s joins now.
  static void _emitJoined(GameSession s, Turret t, Turret other, {required bool joined}) => s.emit(
    TurretJoined(
      s.stepIndex,
      uid: t.uid,
      target: other.uid,
      joined: joined,
      joins: List.of(stateOf(t).joins),
    ),
  );

  @override
  bool get ownsUpdate => true;

  @override
  void update(GameSession session, Turret turret, double dtMs) {
    final s = session;
    final st = stateOf(turret);
    final target = acquireFor(s, turret);
    if (target == null) {
      st.painted = null;
      turret.rotation = normalizeRotation(
        turret.rotation + dtMs / 1000 * params(turret).number('idleRotate')!,
      );
      return;
    }
    final faced = turnToward(s, turret, target.position, dtMs);
    st.painted = faced ? target.uid : null;
    if (!faced) return;
    trigger(s, turret, target);
  }

  /// Its own `turretTryFiring`, also run when another Targeter joined to it
  /// fires: no turning, just the trigger.
  @override
  bool tryFiring(GameSession session, Turret turret, Creep target, double dtMs) {
    trigger(session, turret, target);
    return true;
  }

  /// `TurretTargeter.turretTryFiring`: when reloaded, sends every joined
  /// turret at [target].
  static void trigger(GameSession s, Turret t, Creep target) {
    if (!s.canFire(t)) return;
    final now = s.clock.nowMs;
    t.firedAtMs = now;
    final joined = joinedTurrets(s, t);
    // With nothing joined it keeps its target even with lock off.
    if (joined.isEmpty) return;
    for (final j in joined.reversed) {
      if (!j.active || !s.turrets.contains(j)) continue;
      final last = j.updatedAtMs;
      turretTryFiring(s, j, target, last == null ? 0 : now - last);
      // `turretBearTarget(target)`: replaces a combo helper's leader.
      j.bearCreepUid = target.uid;
      j.stateOrNull<ComboState>(ComboSpecial.specialId)?.bearTo = null;
    }
    if (t.lockOff) t.targetUid = null;
  }

  @override
  void onTurretGone(GameSession session, Turret turret, Turret other) {
    if (stateOf(turret).joins.remove(other.uid)) _emitJoined(session, turret, other, joined: false);
  }
}
