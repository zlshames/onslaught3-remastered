import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/app/ui_skin.dart';
import 'package:onslaught_core/onslaught_core.dart';

void main() {
  test('both classic profiles draw the Classic skin', () {
    for (final p in RulesProfile.all) {
      expect(p.enhancedSkin, isFalse, reason: p.id);
      expect(UiSkin.forProfile(p), UiSkin.classic, reason: p.id);
    }
  });

  test('a profile with enhancedSkin draws the Enhanced skin, whatever its id', () {
    const c = RulesProfile.classicFixed;
    final enhanced = RulesProfile(
      id: 'anything',
      napalmUsesComboDamage: c.napalmUsesComboDamage,
      poisonRocketModified: c.poisonRocketModified,
      laserRocketLaserBlast: c.laserRocketLaserBlast,
      landmineBulletDamage: c.landmineBulletDamage,
      blackHoleDirtyKills: c.blackHoleDirtyKills,
      shockwaveCredit: c.shockwaveCredit,
      holdingRocketLifetime: c.holdingRocketLifetime,
      blackHoleGameClock: c.blackHoleGameClock,
      tutorialWaveLimit: c.tutorialWaveLimit,
      challengePickerData: c.challengePickerData,
      inGameSpeedButton: c.inGameSpeedButton,
      tapEmptyDeselects: c.tapEmptyDeselects,
      freakoutAutoStart: c.freakoutAutoStart,
      shockwaveBothWalkers: c.shockwaveBothWalkers,
      continueAfterWin: c.continueAfterWin,
      customGamesSeparate: c.customGamesSeparate,
      enhancedSkin: true,
    );
    expect(UiSkin.forProfile(enhanced), UiSkin.enhanced);
    expect(enhanced.toggles, c.toggles, reason: 'the skin is presentation, not a rule toggle');
  });
}
