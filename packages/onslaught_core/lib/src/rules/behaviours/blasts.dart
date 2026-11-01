import '../../data/params.dart';
import '../../math/geometry.dart';
import '../../math/vec2.dart';
import '../../sim/entities.dart';
import '../../sim/game_session.dart';
import '../creep_rules.dart';
import '../rules_registry.dart';
import '../stat_rules.dart';
import '../targeting_rules.dart';
import 'ordnance.dart';
import 'rocket_state.dart';

class BlastGrowth extends KindState {
  /// 0 growing, 1 fading, 2 over (`blast_mode`).
  int stage = 0;

  /// Ms into the current stage.
  double ms = 0;

  @override
  Map<String, Object?> toJson() => {'stage': stage, 'ms': ms};
}

/// A plain blast (`BlastEngine`, `blasts/BlastSmall … BlastBFG`): grows from
/// `startSize` to `diameter` px over `growMs`, then deals its damage once to
/// every creep within `diameter / 2` (square box, then distance), no
/// falloff: each is slowed by its poison in divide mode, then hit. Then it
/// fades over `fadeMs` and is removed. All on game time.
///
/// The original's tweens advance on a 32 ms interval, so its damage lands
/// on the first tick at or after `growMs`; here it lands at `growMs`.
class PlainBlastKind implements BlastKind {
  const PlainBlastKind();

  @override
  String get id => 'blast';

  @override
  Set<String>? get paramKeys => blastParamKeys;

  static const Set<String> blastParamKeys = {'growMs', 'startSize', 'diameter', 'fadeMs'};

  @override
  void start(GameSession session, Blast blast) => startGrowth(session, blast);

  @override
  void step(GameSession session, Blast blast, double dtMs) => advanceGrowth(session, blast, dtMs);
}

/// Sets [b] at its start size (`BlastEngine` ctor).
void startGrowth(GameSession s, Blast b) {
  b
    ..size = _params(s, b).number('startSize')!
    ..state = BlastGrowth();
}

/// `BlastEngine.update`: grow, deal the damage, fade, done.
void advanceGrowth(GameSession s, Blast b, double dtMs) {
  final p = _params(s, b);
  final st = b.state! as BlastGrowth..ms += dtMs;
  if (st.stage == 0) {
    final grow = p.number('growMs')!;
    final start = p.number('startSize')!;
    final diameter = p.number('diameter')!;
    if (st.ms < grow) {
      b.size = start + (diameter - start) * st.ms / grow;
      return;
    }
    b.size = diameter;
    blastDamage(s, b, diameter / 2);
    st
      ..stage = 1
      ..ms -= grow;
  }
  if (st.stage == 1) {
    final fade = p.number('fadeMs')!;
    b.alpha = st.ms >= fade ? 0 : 1 - st.ms / fade;
    if (st.ms >= fade) {
      st.stage = 2;
      b.done = true;
    }
  }
}

/// `BlastEngine.blastDamage`: every creep within [radius] is slowed (divide
/// by the blast's poison) and hit with its damage, credited to its turret.
void blastDamage(GameSession s, Blast b, double radius) {
  for (final c in List.of(s.creeps)) {
    if (c.gone || !inBox(c.position, b.position, radius)) continue;
    if (c.position.distanceTo(b.position) > radius) continue;
    s
      ..slowCreep(c, b.poison, subtract: false)
      ..hitCreep(c, b.damage, by: b.turretUid);
  }
}

Params _params(GameSession s, Blast b) => s.data.blasts[b.specId]!.params;

class NapalmState extends KindState {
  NapalmState(this.cursor, this.stepBy);

  /// Where the next drop goes before its jitter, and the step between drops.
  Vec2 cursor;
  final Vec2 stepBy;
  int dropped = 0;
  double sinceDropMs = 0;

  @override
  Map<String, Object?> toJson() => {
    'cursor': cursor.toJson(),
    'dropped': dropped,
    'since': sinceDropMs,
  };
}

/// The Napalm rocket's spawner (`blasts/BlastNapalm`): it never grows or
/// hurts itself. On impact it drops a `dropBlast` (the "tiny" blast) at
/// once and then every `napalmTimingMs`, each `stepPx` further along the
/// rocket's heading and moved by a whole-pixel jitter of up to ±half
/// `napalmJitter` on each axis, until `napalmQty` have dropped; the next
/// tick it is done. The drops are silent and slow by nothing (poison 1).
///
/// The original's drops deal the `dropDamage` default (1 000 000) because
/// the combo's blast damage reaches the spawner under another name;
/// `RulesProfile.napalmUsesComboDamage` uses the combo's blast damage. Its
/// drop interval is real time skipped while paused; here it is game time.
class NapalmKind implements BlastKind {
  const NapalmKind();

  @override
  String get id => 'napalm';

  @override
  Set<String>? get paramKeys => const {'stepPx', 'dropBlast', 'dropDamage'};

  @override
  void start(GameSession session, Blast blast) {
    final step = forwardFrom(Vec2.zero, blast.angle, _params(session, blast).number('stepPx')!);
    blast.state = NapalmState(blast.position, step);
    _drop(session, blast);
  }

  @override
  void step(GameSession session, Blast blast, double dtMs) {
    final napalm = blast.load!.napalm;
    final st = blast.state! as NapalmState..sinceDropMs += dtMs;
    final timingMs = napalm?.timingMs ?? 0;
    if (timingMs <= 0) {
      blast.done = true;
      return;
    }
    while (!blast.done && st.sinceDropMs >= timingMs) {
      st.sinceDropMs -= timingMs;
      if (st.dropped >= (napalm?.qty ?? 0)) {
        blast.done = true;
      } else {
        _drop(session, blast);
      }
    }
  }

  static void _drop(GameSession s, Blast b) {
    final jitter = b.load!.napalm?.jitter ?? 0;
    final st = b.state! as NapalmState;
    final params = _params(s, b);
    final dx = jitterOffset(s.random, jitter);
    final dy = jitterOffset(s.random, jitter);
    s.spawnBlast(
      specId: params.string('dropBlast')!,
      at: st.cursor + Vec2(dx, dy),
      damage: s.config.profile.napalmUsesComboDamage ? b.damage : params.number('dropDamage')!,
      poison: 1,
      turretUid: b.turretUid,
      angle: b.angle,
    );
    st
      ..cursor = st.cursor + st.stepBy
      ..dropped += 1;
  }
}

/// The rocket cluster (`ClusterBlastEngine`): fans out `clusterQty`
/// `childProjectile` rockets, rocket i (from 0) heading `(i + 1) / qty ×
/// 360°` and starting `spawnOffset` px out along it, with no target (each
/// takes the nearest creep in range), the cluster's damage, holding if the
/// combo says so and, for laser clusters, an on-board laser with the
/// cluster laser damage and the default laser range and rate. Then it is
/// done.
class ClusterRocketsKind implements BlastKind {
  const ClusterRocketsKind();

  @override
  String get id => 'cluster-rockets';

  @override
  Set<String>? get paramKeys => const {'spawnOffset', 'childProjectile', 'acquireRange'};

  @override
  void start(GameSession session, Blast blast) {
    final load = blast.load!;
    final cluster = load.cluster!;
    final params = _params(session, blast);
    final defaults = session.data.comboDefaults;
    final offset = params.number('spawnOffset')!;
    final child = params.string('childProjectile')!;
    final now = session.clock.nowMs;
    for (var i = 0; i < cluster.qty; i++) {
      final heading = normalizeRotation((i + 1) / cluster.qty * 360);
      final spec = session.data.projectiles[child]!;
      final rocket = session.addProjectile(
        specId: child,
        kind: spec.kind,
        position: forwardFrom(blast.position, heading, offset),
        heading: heading,
        damage: cluster.damage,
        targetUid: null,
        turretUid: blast.turretUid,
        poison: defaults.number('bulletPoison')!,
      );
      if (cluster.holding) RocketState.of(rocket).holdingCapable = true;
      if (cluster.laser) {
        final type = defaults.string('laserType');
        final range = defaults.number('laserRange')!;
        final intervalMs = fireIntervalMs(defaults.number('laserRate')!);
        rocket.load = Ordnance(
          combo: load.combo,
          laser: type == null
              ? null
              : OnboardWeapon(
                  projectile: type,
                  damage: cluster.laserDamage,
                  range: range,
                  intervalMs: intervalMs,
                ),
          laserFiredAtMs: now,
        );
      }
      session.launchProjectile(rocket);
    }
    blast.done = true;
  }

  @override
  void step(GameSession session, Blast blast, double dtMs) {}
}

/// The spark cluster (`ClusterSparkEngine`): fans out `clusterQty`
/// `childProjectile` sparks, spark i heading `(i + 1) / qty × 360°` from
/// `spawnOffset` px out, aimed round-robin at the creeps inside the
/// `±range` square (no distance check), each with the cluster's damage and
/// `poison` (subtracted). With no creep there they hit nothing. It plays its
/// `sound` once. Then it is done.
class ClusterSparksKind implements BlastKind {
  const ClusterSparksKind();

  @override
  String get id => 'cluster-sparks';

  @override
  Set<String>? get paramKeys => const {
    'childProjectile',
    'spawnOffset',
    'range',
    'poison',
    'sound',
  };

  @override
  void start(GameSession session, Blast blast) {
    final cluster = blast.load!.cluster!;
    final params = _params(session, blast);
    final range = params.number('range')!;
    final targets = [
      for (final c in session.creeps)
        if (!c.gone && inBox(c.position, blast.position, range)) c,
    ];
    final offset = params.number('spawnOffset')!;
    for (var i = 0; i < cluster.qty; i++) {
      final heading = normalizeRotation((i + 1) / cluster.qty * 360);
      launchChild(
        session,
        specId: params.string('childProjectile')!,
        at: forwardFrom(blast.position, heading, offset),
        heading: heading,
        damage: cluster.damage,
        targetUid: targets.isEmpty ? null : targets[i % targets.length].uid,
        turretUid: blast.turretUid,
        poison: params.number('poison')!,
      );
    }
    blast.done = true;
  }

  @override
  void step(GameSession session, Blast blast, double dtMs) {}
}
