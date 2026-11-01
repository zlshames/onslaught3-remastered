import '../../math/vec2.dart';
import '../../sim/entities.dart';
import '../../sim/game_event.dart';
import '../../sim/game_session.dart';
import '../rules_registry.dart';
import 'ordnance.dart';

/// Where a black hole is in its life.
enum BlackHoleStage { opening, open, closing }

class BlackHoleState extends KindState {
  BlackHoleState(this.openedAtMs);

  /// Game time it was made (`hole_opened`); its duration counts from here.
  final double openedAtMs;
  BlackHoleStage stage = BlackHoleStage.opening;

  /// Ms into the open or close tween.
  double stageMs = 0;

  /// Ms since the last scan.
  double sinceScanMs = 0;

  @override
  Map<String, Object?> toJson() => {'stage': stage.name, 'ms': stageMs, 'scan': sinceScanMs};
}

/// The Yellow black hole (`BlackHole.as`, `AttackerEngine.attackerBlackHoled`,
/// `Projectile.projectileBlackHoled`, `OnslaughtObject.as:blackHoled`).
///
/// * It opens on its combo's hole point over `openMs`, then scans at once
///   and every `scanIntervalMs`.
/// * Each scan catches every creep inside the radius (square box, then
///   distance) that is not caught yet: it stops moving, slowing and taking
///   damage, its bounty becomes 0, and it is pulled to the centre at
///   `gravity` px/s and removed there as a dirty kill. It stays on the road
///   and targetable meanwhile, so turrets waste shots on it.
/// * It also catches every projectile and blast inside the square box
///   (no distance check) except instant shots (`blackHoleImmune`) and other
///   black holes: they stop and are pulled in and removed without effect.
/// * The scan that finds `holeDurationMs` of game time gone since it opened
///   starts the close tween (`closeMs`), after which it is removed.
///
/// The original runs the tweens, the scan interval and the pulls on its
/// real-time clock: they go on while paused (the duration, on game time,
/// does not) and ignore the game speed. `RulesProfile.blackHoleGameClock`
/// runs them on game time.
class BlackHoleKind implements RealTimeProjectileKind {
  const BlackHoleKind();

  @override
  String get id => 'black-hole';

  @override
  Set<String>? get paramKeys => const {
    'scanIntervalMs',
    'gravity',
    'openMs',
    'closeMs',
    'debrisRange',
    'pointRange',
  };

  @override
  void launch(GameSession session, Projectile p) {
    final place = p.load?.place;
    if (place == null) {
      p.done = true;
      return;
    }
    p
      ..position = place
      ..state = BlackHoleState(session.clock.nowMs);
    session.emit(BlackHoleOpened(session.stepIndex, uid: p.uid, x: place.x, y: place.y));
  }

  @override
  void step(GameSession session, Projectile p, double dtMs) {
    if (session.config.profile.blackHoleGameClock) _advance(session, p, dtMs);
  }

  @override
  void stepRealTime(GameSession session, Projectile p, double realMs) {
    if (!session.config.profile.blackHoleGameClock) _advance(session, p, realMs);
  }

  void _advance(GameSession s, Projectile p, double ms) {
    final st = p.state! as BlackHoleState;
    final params = s.data.projectiles[p.specId]!.params;
    switch (st.stage) {
      case BlackHoleStage.opening:
        st.stageMs += ms;
        if (st.stageMs < params.number('openMs')!) return;
        st
          ..stage = BlackHoleStage.open
          ..stageMs = 0;
        _scan(s, p, st);
      case BlackHoleStage.open:
        final interval = params.number('scanIntervalMs')!;
        st.sinceScanMs += ms;
        while (st.stage == BlackHoleStage.open && st.sinceScanMs >= interval) {
          st.sinceScanMs -= interval;
          _scan(s, p, st);
        }
      case BlackHoleStage.closing:
        st.stageMs += ms;
        if (st.stageMs >= params.number('closeMs')!) p.done = true;
    }
  }

  void _scan(GameSession s, Projectile hole, BlackHoleState st) {
    final load = hole.load!;
    final radius = load.hole?.radius ?? 0;
    final gravity = s.data.projectiles[hole.specId]!.params.number('gravity')!;
    Capture capture(Vec2 from) => Capture(
      hole: hole.uid,
      from: from,
      to: hole.position,
      durationMs: from.distanceTo(hole.position) / gravity * Duration.millisecondsPerSecond,
    );
    for (final c in s.creeps) {
      if (c.gone || c.blackHoled || !inBox(c.position, hole.position, radius)) continue;
      if (c.position.distanceTo(hole.position) > radius) continue;
      c
        ..blackHoled = true
        ..bountyBeforeHole = c.bounty
        ..bounty = 0
        ..recoverAtMs = null
        ..capture = capture(c.position);
    }
    for (final q in s.projectiles) {
      if (q == hole || q.done || q.capture != null || !inBox(q.position, hole.position, radius)) {
        continue;
      }
      final spec = s.data.projectiles[q.specId]!;
      if (spec.kind == id || (spec.params.boolean('blackHoleImmune') ?? false)) continue;
      q.capture = capture(q.position);
    }
    for (final b in s.blasts) {
      if (b.done || b.capture != null || !inBox(b.position, hole.position, radius)) continue;
      b.capture = capture(b.position);
    }
    if (s.clock.nowMs - st.openedAtMs >= (load.hole?.durationMs ?? 0)) {
      st
        ..stage = BlackHoleStage.closing
        ..stageMs = 0;
    }
  }
}
