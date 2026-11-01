import 'package:onslaught_core/onslaught_core.dart';
import 'package:onslaught_core/testing.dart';
import 'package:test/test.dart';

import '../support/repo_data.dart';
import '../support/sim_helpers.dart';

/// The session's shape after audit A1, A2 and A10: the world is read-only
/// from outside, the debug surface is the one sanctioned bypass, the
/// objectives are their own system, and the reshaped ordnance and rocket
/// state serialise as the fields they replaced did (so recorded state hashes
/// hold).
void main() {
  late SimTestHarness harness;
  setUpAll(() => harness = SimTestHarness(loadClassicData()));

  GameSession sandbox() {
    final s = harness.session(const GameConfig(mapId: 'map9', mode: 'sandbox', seed: 4))
      ..debugCash = 1e12;
    unlockAll(s);
    return s;
  }

  group('read-only world', () {
    test('the lists are live views that refuse every change', () {
      final s = sandbox();
      final view = s.turrets;
      final t = build(s, 'blue', const Vec2(500, 60));
      expect(identical(view, s.turrets), isTrue, reason: 'one view for the session');
      expect(view, [t]);
      expect(() => s.turrets.add(t), throwsUnsupportedError);
      expect(() => s.turrets.remove(t), throwsUnsupportedError);
      expect(() => s.creeps.clear(), throwsUnsupportedError);
      expect(() => s.projectiles.removeWhere((_) => true), throwsUnsupportedError);
      expect(() => s.blasts.length = 0, throwsUnsupportedError);
      expect(() => s.walkers.clear(), throwsUnsupportedError);
      expect(() => s.unlocked.add('blue'), throwsUnsupportedError);
      expect(() => s.turrets[0] = t, throwsUnsupportedError);
    });

    test('the debug surface sets the counters the getters and snapshot report', () {
      final s = sandbox()
        ..debugCash = 123
        ..debugLives = 7
        ..debugKills = 9;
      expect((s.cash, s.lives, s.kills), (123, 7, 9));
      final snap = s.snapshot();
      expect((snap['cash'], snap['lives'], snap['kills']), (123, 7, 9));
    });
  });

  group('objectives', () {
    test('run by the session itself, not one of the classic systems', () {
      expect(classicSystems().whereType<ObjectiveSystem>(), isEmpty);
      final system = ObjectiveSystem(Objectives(killTarget: 3));
      expect(system.name, 'objectives');
      expect(system.objectives.any, isTrue);
      expect(system.objectives.toJson()['killTargetHit'], isFalse);
    });
  });

  group('ordnance and rocket state', () {
    test('a rocket keeps its holding fields at the top of its snapshot', () {
      final s = sandbox();
      final p = s.addProjectile(
        specId: 'rocket-1',
        kind: s.data.projectiles['rocket-1']!.kind,
        position: const Vec2(300, 200),
        heading: 0,
        damage: 1,
        targetUid: null,
        turretUid: null,
      )..state = (RocketState()..holdingCapable = true);
      s.launchProjectile(p);
      final json = p.toJson();
      expect(json.containsKey('state'), isFalse);
      expect(json['holding'], [false, RocketState.of(p).holdingDir]);
      expect(RocketState.of(p), same(p.state), reason: 'made once');
    });

    test('a plain rocket adds nothing to its snapshot', () {
      final p = Projectile(
        uid: 1,
        specId: 'rocket-1',
        kind: 'rocket',
        position: Vec2.zero,
        heading: 0,
        damage: 1,
        targetUid: null,
        turretUid: null,
        createdAtMs: 0,
      );
      final before = p.toJson();
      RocketState.of(p);
      expect(p.toJson(), before);
    });

    test('records serialise as the old fields did; empty blocks are left out', () {
      final load = Ordnance(
        combo: 'x',
        blast: const BlastLoad(type: 'blast-small', damage: 2, poison: 1),
        cluster: const ClusterLoad(
          type: 'cluster-rockets',
          qty: 4,
          damage: 3,
          holding: true,
          laser: false,
          laserDamage: 0,
        ),
        laser: const OnboardWeapon(projectile: 'spark', damage: 5, range: 200, intervalMs: 500),
        laserFiredAtMs: 10,
        napalm: const NapalmLoad(qty: 0, timingMs: 100, jitter: 2),
        laserBlast: const LaserBlastLoad(qty: 0, damage: 1, range: 1),
        hole: const HoleLoad(radius: 0, durationMs: 3000),
      );
      expect(load.toJson(), {
        'combo': 'x',
        'blast': ['blast-small', 2, 1],
        'cluster': ['cluster-rockets', 4, 3, true, false, 0],
        'laser': ['spark', 5, 200, 500, 10],
      });
      final copy = load.copy();
      expect(copy.toJson(), {
        'combo': 'x',
        'cluster': ['cluster-rockets', 4, 3, true, false, 0],
      });
      expect(copy.napalm, same(load.napalm));
    });
  });
}
