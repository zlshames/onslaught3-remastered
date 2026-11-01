import 'package:onslaught_core/onslaught_core.dart';
import 'package:test/test.dart';

class _Targeter extends TurretSpecial {
  @override
  String get id => 'targeter';
  @override
  Set<String>? get paramKeys => {'joinMax'};
}

void main() {
  test('classic registry knows every classic mechanic', () {
    final r = RulesRegistry.classic();
    expect(
      r.turretSpecialIds,
      containsAll(['freakout', 'link', 'holding', 'charge', 'targeter', 'fusion', 'combonly']),
    );
    expect(
      r.projectileKindIds,
      containsAll(['shell', 'rocket', 'beam', 'spark', 'landmine', 'rail']),
    );
    expect(
      r.blastKindIds,
      containsAll(['blast', 'napalm', 'shockwave', 'cluster-rockets', 'cluster-sparks']),
    );
    expect(r.creepBehaviourIds, contains('walker'));
  });

  test('Phase 2 mechanics have real rules', () {
    final r = RulesRegistry.classic();
    for (final id in ['freakout', 'link', 'holding', 'charge', 'modifier']) {
      expect(r.allowsTurretSpecial(id), isTrue, reason: id);
    }
    for (final id in ['shell', 'beam', 'spark', 'rocket']) {
      expect(r.implementsProjectileKind(id), isTrue, reason: id);
    }
  });

  test('Phase 3 mechanics have real rules', () {
    final r = RulesRegistry.classic();
    expect(r.turretSpecial('combo'), isA<ComboSpecial>());
    expect(r.allowsTurretSpecial('combo'), isTrue);
    for (final id in ['cluster-bomb', 'landmine', 'black-hole']) {
      expect(r.implementsProjectileKind(id), isTrue, reason: id);
    }
    for (final id in ['blast', 'napalm', 'shockwave', 'cluster-rockets', 'cluster-sparks']) {
      expect(r.blastKind(id).id, id, reason: id);
    }
    expect(r.projectileKind('black-hole'), isA<RealTimeProjectileKind>());
  });

  test('Phase 4 mechanics have real rules', () {
    final r = RulesRegistry.classic();
    expect(r.turretSpecial('targeter'), isA<TargeterSpecial>());
    expect(r.turretSpecial('fusion'), isA<FusionSpecial>());
    expect(r.turretSpecial('combonly'), isA<CombonlySpecial>());
    for (final id in ['targeter', 'sniper', 'railgun', 'fusion', 'combonly']) {
      expect(r.allowsTurretSpecial(id), isTrue, reason: id);
    }
    expect(r.projectileKind('rail'), isA<RealTimeProjectileKind>());
    for (final id in ['sniper-shot', 'rail']) {
      expect(r.implementsProjectileKind(id), isTrue, reason: id);
    }
    expect(r.allowsTurretSpecial('nope'), isFalse);
  });

  test('registering a behaviour replaces the one with the same id', () {
    final r = RulesRegistry.classic()..registerTurretSpecial(_Targeter());
    expect(r.turretSpecial('targeter'), isA<_Targeter>());
    expect(r.allowsTurretSpecial('targeter'), isTrue);
  });

  test('unknown ids throw', () {
    expect(() => RulesRegistry().blastKind('nope'), throwsArgumentError);
  });
}
