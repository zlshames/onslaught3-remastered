import 'package:meta/meta.dart';

/// A named set of rule toggles. Every deliberate departure from the original
/// game is one toggle here and one row in `docs/DEVIATIONS.md` (rule R10).
///
/// [classic] keeps every original quirk bit-for-bit and is what the
/// regression fixtures freeze; [classicFixed] is the v1 default and applies
/// the fixes. New gameplay goes in a new profile, never into [classic].
@immutable
class RulesProfile {
  const RulesProfile({
    required this.id,
    required this.napalmUsesComboDamage,
    required this.poisonRocketModified,
    required this.laserRocketLaserBlast,
    required this.landmineBulletDamage,
    required this.blackHoleDirtyKills,
    required this.shockwaveCredit,
    required this.holdingRocketLifetime,
    required this.blackHoleGameClock,
    required this.tutorialWaveLimit,
    required this.challengePickerData,
    required this.inGameSpeedButton,
    required this.tapEmptyDeselects,
    required this.freakoutAutoStart,
    required this.shockwaveBothWalkers,
    required this.continueAfterWin,
    required this.customGamesSeparate,
    required this.enhancedSkin,
  });

  /// The original game, quirks included.
  static const RulesProfile classic = RulesProfile(
    id: 'classic',
    napalmUsesComboDamage: false,
    poisonRocketModified: false,
    laserRocketLaserBlast: false,
    landmineBulletDamage: false,
    blackHoleDirtyKills: true,
    shockwaveCredit: false,
    holdingRocketLifetime: false,
    blackHoleGameClock: false,
    tutorialWaveLimit: false,
    challengePickerData: false,
    inGameSpeedButton: false,
    tapEmptyDeselects: false,
    freakoutAutoStart: false,
    shockwaveBothWalkers: false,
    continueAfterWin: false,
    customGamesSeparate: false,
    enhancedSkin: false,
  );

  /// v1 default: the original with the fixes listed in `docs/DEVIATIONS.md`.
  static const RulesProfile classicFixed = RulesProfile(
    id: 'classicFixed',
    napalmUsesComboDamage: true,
    poisonRocketModified: true,
    laserRocketLaserBlast: true,
    landmineBulletDamage: false,
    blackHoleDirtyKills: true,
    shockwaveCredit: true,
    holdingRocketLifetime: false,
    blackHoleGameClock: true,
    tutorialWaveLimit: true,
    challengePickerData: true,
    inGameSpeedButton: true,
    tapEmptyDeselects: true,
    freakoutAutoStart: true,
    shockwaveBothWalkers: true,
    continueAfterWin: true,
    customGamesSeparate: true,
    enhancedSkin: false,
  );

  static const List<RulesProfile> all = [classic, classicFixed];

  static RulesProfile byId(String id) => all.firstWhere(
    (p) => p.id == id,
    orElse: () => throw ArgumentError.value(id, 'id', 'unknown rules profile'),
  );

  final String id;

  /// Napalm drops use the recipe's blast damage instead of the 1 000 000 default.
  final bool napalmUsesComboDamage;

  /// Poison-rocket blast damage goes through the leader's modifiers.
  final bool poisonRocketModified;

  /// Laser rocket fires its data-defined laser blast (6 beams) on impact.
  final bool laserRocketLaserBlast;

  /// Landmines also apply `bullet_damage` (original: blast only; kept off).
  final bool landmineBulletDamage;

  /// Black-hole kills pay no cash, score or credit (original; kept on).
  final bool blackHoleDirtyKills;

  /// Shockwave-walker kills are credited to the leader turret (stat only).
  final bool shockwaveCredit;

  /// Holding rockets with no target expire after a lifetime.
  final bool holdingRocketLifetime;

  /// Black-hole suction runs on the game clock (honours pause and speed).
  final bool blackHoleGameClock;

  /// The tutorial ends at its wave limit and is ticked off. (Challenge
  /// unlocks as the tutorial starts under either profile, as in 2350-gaby.)
  final bool tutorialWaveLimit;

  /// Challenge pickers use corrected option data.
  final bool challengePickerData;

  /// The HUD offers a 1×/2×/3× speed button on top of the base factor.
  final bool inGameSpeedButton;

  /// Tapping empty ground deselects the selected turret.
  final bool tapEmptyDeselects;

  /// Freakouts start on their own: the first one is scheduled `firstDelayMs`
  /// after the turret becomes freak-available. The original guards that
  /// schedule with an uninitialised `freak_next == false` test, which is
  /// false under SWF 8 rules, so none is ever scheduled; and the info-panel
  /// "buy now" cost, `floor((freak_next − now) / 1000) × 250`, is then NaN,
  /// which no cash amount satisfies, so in the classic rules no freakout
  /// ever happens (`turrets/Turret.as:freakoutActivate`,
  /// `turretinfo/TurretInfoBlue.as`, `CashManager.cashAvailable`).
  final bool freakoutAutoStart;

  /// Both shockwave walkers travel. In the original the spawn-ward walker
  /// removes itself during construction (`AttackerEngine` ctor calls
  /// `update()` with the waypoint index at 1, stepping it to 0), so only the
  /// base-ward walker runs (`Shockwave.as`, `blasts/BlastShockwave.as`).
  final bool shockwaveBothWalkers;

  /// A won game can go on in freeplay (`ContinuePlaying`): the waves resume
  /// with the same growth, the time limit no longer applies and the game
  /// ends when the lives run out. The original has no such choice: a won
  /// game sits on its cleared field with no more waves.
  final bool continueAfterWin;

  /// Custom games ([customGameReasons]: a mod is on, or the map is a
  /// player's) record nothing in the profile: no unlocks, completions or
  /// challenge best games, so changed data or an easy home-made road cannot
  /// earn the standard game's progress. The original records them like any
  /// other (`GameManager.modeUpdate` checks only `game_type`, never
  /// `mod_active` or `game_map_custom`).
  final bool customGamesSeparate;

  /// The game is drawn with the Enhanced presentation (the app's
  /// `UiSkin.enhanced`: side rails, the far-side panel, ground beyond the
  /// play area, …) rather than Classic's. Presentation only: it changes no
  /// rule, so it is not a toggle in [toggles] and has no `docs/DEVIATIONS.md`
  /// row. Off for both classic profiles; an Enhanced profile
  /// (`docs/ENHANCED_PLAN.md` E0) turns it on.
  final bool enhancedSkin;

  /// Toggle name → value, for fixtures, debug menus and docs checks.
  /// Presentation fields ([enhancedSkin]) are not toggles and stay out.
  Map<String, bool> get toggles => {
    'napalmUsesComboDamage': napalmUsesComboDamage,
    'poisonRocketModified': poisonRocketModified,
    'laserRocketLaserBlast': laserRocketLaserBlast,
    'landmineBulletDamage': landmineBulletDamage,
    'blackHoleDirtyKills': blackHoleDirtyKills,
    'shockwaveCredit': shockwaveCredit,
    'holdingRocketLifetime': holdingRocketLifetime,
    'blackHoleGameClock': blackHoleGameClock,
    'tutorialWaveLimit': tutorialWaveLimit,
    'challengePickerData': challengePickerData,
    'inGameSpeedButton': inGameSpeedButton,
    'tapEmptyDeselects': tapEmptyDeselects,
    'freakoutAutoStart': freakoutAutoStart,
    'shockwaveBothWalkers': shockwaveBothWalkers,
    'continueAfterWin': continueAfterWin,
    'customGamesSeparate': customGamesSeparate,
  };
}
