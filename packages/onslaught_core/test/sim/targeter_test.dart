import 'package:onslaught_core/onslaught_core.dart';
import 'package:onslaught_core/testing.dart';
import 'package:test/test.dart';

import '../support/combo_bench.dart';
import '../support/repo_data.dart';
import '../support/sim_helpers.dart';

/// The Targeter (`turrets/TurretTargeter.as`, `TurretJoiner.as`;
/// `docs/legacy/ENGINE_NOTES.md` §4.6).
void main() {
  late GameData data;
  late SimTestHarness harness;
  setUpAll(() {
    data = loadClassicData();
    harness = SimTestHarness(data);
  });

  GameSession lyne() {
    final s = harness.session(const GameConfig(mapId: 'map9', mode: 'sandbox', seed: 4))
      ..debugCash = 1e12;
    unlockAll(s);
    return s;
  }

  /// 48 px from Lyne's road, so a Targeter there paints passing creeps.
  const targeterAt = ComboBench.leaderAt;

  /// ~236 px from the road: out of a Blue's own range.
  const farAt = Vec2(500, 60);

  /// The first creep of a wave, alone and toughened.
  Creep onlyCreep(GameSession s) {
    final c = firstCreep(s)..hp = 1e12;
    s.waves.spawners.clear();
    return c;
  }

  List<GameEvent> join(GameSession s, Turret t, Turret other) {
    s.enqueue(JoinTurret(t.uid, other.uid));
    return s.step();
  }

  test('the sandbox opens the Targeter; joining toggles, a fourth drops the oldest', () {
    final s = lyne();
    final t = build(s, 'targeter', targeterAt);
    final blues = [for (var i = 0; i < 4; i++) build(s, 'blue', farAt + Vec2(0, 40.0 * i))];
    for (final b in blues.take(3)) {
      final e = join(s, t, b).whereType<TurretJoined>().single;
      expect(e.joined, isTrue);
    }
    expect(TargeterSpecial.stateOf(t).joins, [for (final b in blues.take(3)) b.uid]);
    final e = join(s, t, blues[3]).whereType<TurretJoined>().single;
    expect(e.joins, [blues[1].uid, blues[2].uid, blues[3].uid], reason: 'FIFO at joinMax 3');
    final off = join(s, t, blues[2]).whereType<TurretJoined>().single;
    expect(off.joined, isFalse);
    expect(TargeterSpecial.stateOf(t).joins, [blues[1].uid, blues[3].uid]);
  });

  test('it cannot join itself or a modifier; only a Targeter joins; not while paused', () {
    final s = lyne();
    final t = build(s, 'targeter', targeterAt);
    final mod = build(s, 'damage-up', ComboBench.ring[0]);
    final blue = build(s, 'blue', ComboBench.ring[2]);
    String reason(GameCommand c) {
      s.enqueue(c);
      return s.step().whereType<CommandRejected>().single.reason;
    }

    expect(reason(JoinTurret(t.uid, t.uid)), 'self');
    expect(reason(JoinTurret(t.uid, mod.uid)), 'notJoinable');
    expect(reason(JoinTurret(blue.uid, t.uid)), 'notTargeter');
    s
      ..enqueue(const SetPaused(true))
      ..step();
    expect(reason(JoinTurret(t.uid, blue.uid)), 'paused');
  });

  test('Targeters can join Targeters; a sold or moved turret is let go', () {
    final s = lyne();
    final t = build(s, 'targeter', targeterAt);
    final t2 = build(s, 'targeter', farAt);
    final a = build(s, 'blue', farAt + const Vec2(0, 50));
    final b = build(s, 'blue', farAt + const Vec2(0, 100));
    join(s, t, t2);
    join(s, t, a);
    join(s, t, b);
    s.enqueue(SellTurret(a.uid));
    final gone = s.step().whereType<TurretJoined>().single;
    expect(gone.joined, isFalse);
    expect(gone.target, a.uid);
    s.enqueue(MoveTurret(b.uid, 450, 100));
    s.step();
    expect(TargeterSpecial.stateOf(t).joins, [t2.uid], reason: 'notifyMove = gone + new');
  });

  test('with no target it spins idly at 90 °/s', () {
    final s = lyne();
    final t = build(s, 'targeter', targeterAt);
    s.run(10);
    final before = t.rotation;
    s.run(60);
    final turned = (t.rotation - before + 360) % 360;
    expect(turned, closeTo(90, 10));
    expect(TargeterSpecial.stateOf(t).painted, isNull);
  });

  test('a joined turret fires at the painted creep beyond its own range', () {
    for (final joined in [false, true]) {
      final s = lyne();
      final t = build(s, 'targeter', targeterAt);
      final blue = build(s, 'blue', farAt);
      if (joined) join(s, t, blue);
      final creep = onlyCreep(s);
      final shots = <TurretFired>[];
      for (var i = 0; i < 900; i++) {
        shots.addAll(s.step().whereType<TurretFired>().where((e) => e.uid == blue.uid));
      }
      if (!joined) {
        expect(shots, isEmpty, reason: 'out of its own range');
        continue;
      }
      expect(shots, isNotEmpty);
      expect(shots.map((e) => e.target).toSet(), {creep.uid});
      expect(creep.hp, lessThan(1e12));
    }
  });

  test('it paints only once it faces the target, triggers at its rate and drops the target', () {
    final s = lyne();
    final t = build(s, 'targeter', targeterAt);
    final blue = build(s, 'blue', farAt);
    join(s, t, blue);
    onlyCreep(s);
    final st = TargeterSpecial.stateOf(t);
    final fired = <double>[];
    var paintedBeforeFacing = false;
    for (var i = 0; i < 1200; i++) {
      final before = t.firedAtMs;
      s.step();
      final ticked = t.updatedAtMs == s.clock.nowMs;
      if (ticked && st.painted != null) {
        final c = s.creepByUid(st.painted!)!;
        final off = normalizeRotation(bearingDeg(t.position, c.position) - t.rotation);
        if (off.abs() > 1) paintedBeforeFacing = true;
      }
      if (t.firedAtMs != before) {
        fired.add(t.firedAtMs);
        expect(t.targetUid, isNull, reason: 'lock off drops the target after a trigger');
      }
    }
    expect(paintedBeforeFacing, isFalse);
    expect(fired.length, greaterThan(3));
    for (var i = 1; i < fired.length; i++) {
      expect(fired[i] - fired[i - 1], greaterThan(250), reason: '240/min');
    }
  });

  test('sent turrets turn toward the painted creep while they have no target', () {
    final s = lyne();
    final t = build(s, 'targeter', targeterAt);
    final blue = build(s, 'blue', farAt);
    join(s, t, blue);
    final creep = onlyCreep(s);
    stepUntil<TurretFired>(s, test: (e) => e.uid == blue.uid);
    expect(blue.bearCreepUid, creep.uid);
  });

  test('a joined Targeter passes the trigger on to its own joins', () {
    final s = lyne();
    final t = build(s, 'targeter', targeterAt);
    final t2 = build(s, 'targeter', const Vec2(560, 160));
    final blue = build(s, 'blue', farAt);
    join(s, t, t2);
    join(s, t2, blue);
    final creep = onlyCreep(s);
    final shot = stepUntil<TurretFired>(s, test: (e) => e.uid == blue.uid, maxSteps: 900);
    expect(shot?.target, creep.uid);
  });
}
