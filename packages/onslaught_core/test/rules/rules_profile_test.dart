import 'dart:io';

import 'package:onslaught_core/onslaught_core.dart';
import 'package:test/test.dart';

void main() {
  test('classic keeps the original behaviour for every fix', () {
    final c = RulesProfile.classic.toggles;
    for (final t in [
      'napalmUsesComboDamage',
      'poisonRocketModified',
      'laserRocketLaserBlast',
      'shockwaveCredit',
      'blackHoleGameClock',
      'tutorialWaveLimit',
      'challengePickerData',
      'inGameSpeedButton',
      'tapEmptyDeselects',
      'freakoutAutoStart',
      'shockwaveBothWalkers',
      'continueAfterWin',
      'customGamesSeparate',
    ]) {
      expect(c[t], isFalse, reason: t);
      expect(RulesProfile.classicFixed.toggles[t], isTrue, reason: t);
    }
  });

  test('both profiles share the toggles marked "keep"', () {
    for (final t in ['landmineBulletDamage', 'blackHoleDirtyKills', 'holdingRocketLifetime']) {
      expect(RulesProfile.classic.toggles[t], RulesProfile.classicFixed.toggles[t], reason: t);
    }
  });

  test('every toggle has a row in docs/DEVIATIONS.md (R10)', () {
    final doc = File('../../docs/DEVIATIONS.md').readAsStringSync();
    for (final t in RulesProfile.classic.toggles.keys) {
      expect(doc, contains('| `$t` |'), reason: t);
    }
  });

  test('the skin flag is presentation, not a toggle: off for both classic profiles', () {
    for (final p in RulesProfile.all) {
      expect(p.enhancedSkin, isFalse, reason: p.id);
      expect(p.toggles.containsKey('enhancedSkin'), isFalse, reason: 'no DEVIATIONS row (R10)');
    }
  });

  test('byId round-trips and rejects unknown ids', () {
    for (final p in RulesProfile.all) {
      expect(RulesProfile.byId(p.id), same(p));
    }
    expect(() => RulesProfile.byId('nope'), throwsArgumentError);
  });
}
