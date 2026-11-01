import 'package:onslaught_core/onslaught_core.dart';
import 'package:test/test.dart';

Creep _creep(int uid, double x, double y, {double hp = 100, double speed = 60, double born = 0}) =>
    Creep(
      uid: uid,
      wave: 1,
      typeIndex: 0,
      behaviour: 'walker',
      position: Vec2(x, y),
      hpStart: hp,
      baseSpeed: speed,
      bounty: 1,
      scaleBump: 1,
      createdAtMs: born,
    );

void main() {
  const origin = Vec2(0, 0);

  group('bearing and rotation (Flash degrees: 0 = +x, clockwise)', () {
    test('bearingDeg', () {
      expect(bearingDeg(origin, const Vec2(10, 0)), 0);
      expect(bearingDeg(origin, const Vec2(0, 10)), closeTo(90, 1e-9));
      expect(bearingDeg(origin, const Vec2(0, -10)), closeTo(-90, 1e-9));
      expect(bearingDeg(origin, const Vec2(-10, 0)), closeTo(180, 1e-9));
    });

    test('normalizeRotation wraps into (-180, 180]', () {
      expect(normalizeRotation(190), -170);
      expect(normalizeRotation(-190), 170);
      expect(normalizeRotation(180), 180);
      expect(normalizeRotation(-180), 180);
      expect(normalizeRotation(720 + 45), 45);
    });

    test('rotateVec turns clockwise on screen', () {
      final v = rotateVec(const Vec2(26, 0), 90);
      expect(v.x, closeTo(0, 1e-9));
      expect(v.y, closeTo(26, 1e-9));
    });
  });

  group('bearTowards (turrets/Turret.as:turretBearTowards)', () {
    Bearing bear(double rotation, double bearing, {double dtMs = 100, double rate = 270}) =>
        bearTowards(
          rotation: rotation,
          bearing: bearing,
          rotateDegPerS: rate,
          dtMs: dtMs,
          toleranceDeg: 1,
        );

    test('snaps and reports facing within the 1 degree tolerance', () {
      final b = bear(10, 10.9, dtMs: 0);
      expect(b.faced, isTrue);
      expect(b.rotation, 10.9);
    });

    test('snaps when the remaining turn is less than one step', () {
      // 270 deg/s for 100 ms = 27 deg.
      final b = bear(0, 20);
      expect(b.faced, isTrue);
      expect(b.rotation, 20);
    });

    test('otherwise turns one step the shorter way and does not face', () {
      expect(bear(0, 90), (rotation: 27.0, faced: false));
      expect(bear(0, -90), (rotation: -27.0, faced: false));
      // 170 -> -170 is 20 deg clockwise across the seam.
      final across = bear(170, -150);
      expect(across.faced, isFalse);
      expect(across.rotation, closeTo(-163, 1e-9));
    });

    test('quirk: the raw difference is not wrapped, so it cannot snap across the seam', () {
      // 179 -> -179 is only 2 degrees apart, but the raw difference is 358.
      final b = bear(179, -179);
      expect(b.faced, isFalse);
      expect(b.rotation, closeTo(-154, 1e-9)); // 179 + 27, wrapped
    });
  });

  group('acquireTarget (OnslaughtObject.targetAcquire)', () {
    final near = _creep(1, 30, 0, hp: 50, born: 100);
    final far = _creep(2, 90, 0, hp: 200, speed: 40);
    final mid = _creep(3, 0, 60, hp: 120, speed: 80, born: 50);
    final creeps = [near, far, mid];

    Creep? pick(String mode, {List<Creep>? list, double range = 100}) =>
        acquireTarget(creeps: list ?? creeps, from: origin, range: range, mode: mode, nowMs: 1000);

    test('each mode ranks by its metric', () {
      expect(pick('near'), near);
      expect(pick('far'), far);
      expect(pick('weak'), near);
      expect(pick('strong'), far);
      expect(pick('slow'), far);
      expect(pick('fast'), mid);
      expect(pick('old'), far);
      expect(pick('young'), near);
    });

    test('unknown modes fall back to near', () => expect(pick('nonsense'), near));

    test('ties go to the earliest creep in spawn order', () {
      final a = _creep(1, 50, 0);
      final b = _creep(2, 0, 50);
      expect(pick('weak', list: [a, b]), a);
      expect(pick('strong', list: [a, b]), a);
      expect(pick('near', list: [b, a]), b);
    });

    test('acquisition needs strictly inside the circle; the box corner is out', () {
      expect(pick('near', list: [_creep(1, 100, 0)]), isNull);
      expect(pick('near', list: [_creep(1, 99.9, 0)]), isNotNull);
      expect(pick('near', list: [_creep(1, 80, 80)]), isNull);
    });

    test('maximising modes start from 0, so a value of 0 is never picked', () {
      final newborn = _creep(1, 10, 0, born: 1000);
      expect(pick('old', list: [newborn]), isNull);
      expect(pick('young', list: [newborn]), newborn);
    });

    test('dead or departed creeps are skipped', () {
      final dead = _creep(1, 10, 0)..hp = 0;
      final gone = _creep(2, 20, 0)..gone = true;
      expect(pick('near', list: [dead, gone]), isNull);
    });
  });

  group('keeping a target (OnslaughtObject.targetInRange)', () {
    test('keep-current is inclusive at the range, unlike acquisition', () {
      final edge = _creep(1, 100, 0);
      expect(targetStillInRange(target: edge, from: origin, range: 100), isTrue);
      expect(
        keepOrAcquireTarget(
          current: edge,
          creeps: [edge],
          from: origin,
          range: 100,
          mode: 'near',
          nowMs: 0,
        ),
        edge,
      );
      expect(
        keepOrAcquireTarget(
          current: null,
          creeps: [edge],
          from: origin,
          range: 100,
          mode: 'near',
          nowMs: 0,
        ),
        isNull,
      );
    });

    test('a kept target beats a nearer newcomer; out of range it is replaced', () {
      final kept = _creep(1, 90, 0);
      final newcomer = _creep(2, 10, 0);
      expect(
        keepOrAcquireTarget(
          current: kept,
          creeps: [kept, newcomer],
          from: origin,
          range: 100,
          mode: 'near',
          nowMs: 0,
        ),
        kept,
      );
      kept.position = const Vec2(101, 0);
      expect(
        keepOrAcquireTarget(
          current: kept,
          creeps: [kept, newcomer],
          from: origin,
          range: 100,
          mode: 'near',
          nowMs: 0,
        ),
        newcomer,
      );
    });
  });
}
