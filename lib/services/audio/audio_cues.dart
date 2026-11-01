import 'package:onslaught_core/onslaught_core.dart';

/// One sound to play: an `audio.json` event id and, when the sound has a
/// source on the map, its world x for the pan rule.
typedef AudioCue = ({String event, double? x});

/// What the game knows about a turret when it picks its sounds.
typedef TurretLookup = ({TurretDef def, Vec2 position})? Function(int uid);

/// The sounds the original plays for [e] (`SoundPlayer.play` call sites):
///
/// * shots play the turret's fire sound unless silent (pooling link
///   helpers), or the sound the shot names (a Fusion cannon's discharge by
///   its stored energy); kills "AttackerDead"; hits are silent (no asset);
/// * builds and moves "Build", sales "Sell", upgrades "UpgradeDamage /
///   Range / Rate", a refused upgrade (maxed or too dear) "UpgradeNo";
/// * a base hit "BaseHit", plus the lives voice at 3, 2 and 1 lives left
///   and "BaseDead" at 0 (`PlayerBase.lifeLost`);
/// * each wave "NextWave", pause / unpause, freakout warn / start / end and
///   a weapon unlock "Weapon";
/// * a combo "Combo" at its leader (`Turret.comboFired`), plus the sound the
///   combo plays as it fires (the black hole's); a blast its `sound_blast`
///   where it goes off (none for napalm), a spark cluster "Tazer"; a black
///   hole "BlackHole" again as it opens (its constructor). Swallowed creeps
///   are silent (`attackerDead(true)`);
/// * joining turrets, a Combonly plate locking in or arming and the turrets
///   it consumes are silent (`TurretJoiner`, `TurretCombonly`,
///   `TurretManager.turretSold` play nothing);
/// * winning, objectives, the tutorial's cash and new wave settings are
///   silent (`gameWin`, `targetHit`, `settingsApply` play nothing).
List<AudioCue> audioCuesFor(GameEvent e, TurretLookup turret) {
  double? xOf(int uid) => turret(uid)?.position.x;
  return switch (e) {
    TurretFired(:final uid, :final silent, :final sound) when !silent => [
      if (sound ?? turret(uid)?.def.fireSound case final event?) (event: event, x: xOf(uid)),
    ],
    TurretFired() => const [],
    CreepKilled(:final x) => [(event: 'attacker-dead', x: x)],
    TurretBuilt(:final x) => [(event: 'build', x: x)],
    TurretMoved(:final x) => [(event: 'build', x: x)],
    TurretSold() => const [(event: 'sell', x: null)],
    TurretUpgraded(:final uid, :final stat) => [(event: 'upgrade-$stat', x: xOf(uid))],
    // A refused upgrade-max (`UpgradeTurretMax`) bought nothing: the same
    // sound as a refused single upgrade.
    CommandRejected(:final command, :final reason)
        when (command == 'upgrade' || command == 'upgradeMax') &&
            (reason == 'maxed' || reason == 'cannotAfford') =>
      const [(event: 'upgrade-no', x: null)],
    CommandRejected() => const [],
    BaseHit(:final lives) => [
      if (lives == 0) (event: 'base-dead', x: null),
      if (lives >= 1 && lives <= 3) (event: 'base-warn-$lives', x: null),
      (event: 'base-hit', x: null),
    ],
    WaveStarted() => const [(event: 'next-wave', x: null)],
    PausedChanged(:final paused) => [(event: paused ? 'pause' : 'un-pause', x: null)],
    FreakoutChanged(:final uid, :final stage) => [
      (
        event: switch (stage) {
          'warning' => 'freakout-warn',
          'active' => 'freakout-start',
          _ => 'freakout-end',
        },
        x: xOf(uid),
      ),
    ],
    WeaponUnlocked() => const [(event: 'weapon', x: null)],
    ComboFired(:final uid, :final sound) => [
      (event: 'combo', x: xOf(uid)),
      if (sound != null) (event: sound, x: xOf(uid)),
    ],
    BlastStarted(:final sound, :final x) => [if (sound != null) (event: sound, x: x)],
    BlackHoleOpened(:final x) => [(event: 'black-hole', x: x)],
    CreepSwallowed() || TurretJoined() || CombonlyChanged() || TurretConsumed() => const [],
    SessionStarted() ||
    SpeedChanged() ||
    CreepSpawned() ||
    GameOver() ||
    GameWon() ||
    FreeplayStarted() ||
    ObjectiveReached() ||
    ObjectiveMissed() ||
    TutorialCashSet() ||
    WaveSettingsChanged() ||
    TargetModeChanged() => const [],
  };
}
