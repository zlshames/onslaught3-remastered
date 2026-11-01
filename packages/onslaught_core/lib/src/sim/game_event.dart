import 'package:meta/meta.dart';

/// The only way out of the simulation. Rendering, audio, the HUD, stats and
/// regression fixtures consume these. Every event records the [tick] it was
/// emitted on (the 0-based index of the step) and serialises to JSON for
/// fixture logs.
@immutable
sealed class GameEvent {
  const GameEvent(this.tick);

  final int tick;

  /// Event type id used in JSON.
  String get type;

  Map<String, Object?> get fields;

  Map<String, Object?> toJson() => {'tick': tick, 'type': type, ...fields};

  @override
  String toString() => toJson().toString();
}

/// Emitted once on the first step of a session.
final class SessionStarted extends GameEvent {
  const SessionStarted(
    super.tick, {
    required this.map,
    required this.mode,
    required this.difficulty,
    required this.profile,
    required this.seed,
    required this.cash,
    required this.lives,
  });
  final String map;
  final String mode;
  final String difficulty;
  final String profile;
  final int seed;
  final double cash;
  final int lives;
  @override
  String get type => 'sessionStarted';
  @override
  Map<String, Object?> get fields => {
    'map': map,
    'mode': mode,
    'difficulty': difficulty,
    'profile': profile,
    'seed': seed,
    'cash': cash,
    'lives': lives,
  };
}

final class PausedChanged extends GameEvent {
  const PausedChanged(super.tick, {required this.paused});
  final bool paused;
  @override
  String get type => 'pausedChanged';
  @override
  Map<String, Object?> get fields => {'paused': paused};
}

final class SpeedChanged extends GameEvent {
  const SpeedChanged(super.tick, {required this.speed});
  final double speed;
  @override
  String get type => 'speedChanged';
  @override
  Map<String, Object?> get fields => {'speed': speed};
}

/// A command the session could not apply, with a machine-readable [reason]
/// (`notImplemented`, `paused`, `cannotAfford`, …).
final class CommandRejected extends GameEvent {
  const CommandRejected(super.tick, {required this.command, required this.reason});
  final String command;
  final String reason;
  @override
  String get type => 'commandRejected';
  @override
  Map<String, Object?> get fields => {'command': command, 'reason': reason};
}

/// Wave [wave] was sent: [size] creeps of type [creepType] with [hp] HP,
/// [bounty] cash each and [speed] px/s.
final class WaveStarted extends GameEvent {
  const WaveStarted(
    super.tick, {
    required this.wave,
    required this.size,
    required this.creepType,
    required this.hp,
    required this.bounty,
    required this.speed,
    required this.early,
  });
  final int wave;
  final int size;
  final int creepType;
  final double hp;
  final int bounty;
  final double speed;

  /// Sent by the player before the wave clock ran out.
  final bool early;
  @override
  String get type => 'waveStarted';
  @override
  Map<String, Object?> get fields => {
    'wave': wave,
    'size': size,
    'creepType': creepType,
    'hp': hp,
    'bounty': bounty,
    'speed': speed,
    'early': early,
  };
}

/// A creep entered the road.
final class CreepSpawned extends GameEvent {
  const CreepSpawned(
    super.tick, {
    required this.uid,
    required this.wave,
    required this.x,
    required this.y,
  });
  final int uid;
  final int wave;
  final double x;
  final double y;
  @override
  String get type => 'creepSpawned';
  @override
  Map<String, Object?> get fields => {'uid': uid, 'wave': wave, 'x': x, 'y': y};
}

/// A creep was killed; [turret] (if still standing) gets the credit and the
/// player the [bounty].
final class CreepKilled extends GameEvent {
  const CreepKilled(
    super.tick, {
    required this.uid,
    required this.turret,
    required this.bounty,
    required this.cash,
    required this.kills,
    required this.x,
    required this.y,
  });
  final int uid;
  final int? turret;
  final int bounty;
  final double cash;
  final int kills;
  final double x;
  final double y;
  @override
  String get type => 'creepKilled';
  @override
  Map<String, Object?> get fields => {
    'uid': uid,
    'turret': turret,
    'bounty': bounty,
    'cash': cash,
    'kills': kills,
    'x': x,
    'y': y,
  };
}

/// A creep reached the base and cost a life.
final class BaseHit extends GameEvent {
  const BaseHit(super.tick, {required this.uid, required this.lives});
  final int uid;
  final int lives;
  @override
  String get type => 'baseHit';
  @override
  Map<String, Object?> get fields => {'uid': uid, 'lives': lives};
}

/// The game is lost and the clock stops: the last life went
/// ([reason] `lives`), or a challenge's time ran out before its objective
/// was reached (`timeLimit`, `GameManager.timeLimitHit`).
final class GameOver extends GameEvent {
  const GameOver(
    super.tick, {
    required this.wave,
    required this.kills,
    required this.shots,
    required this.spent,
    required this.score,
    this.reason = livesReason,
  });

  static const String livesReason = 'lives';
  static const String timeLimitReason = 'timeLimit';

  final int wave;
  final int kills;
  final int shots;
  final double spent;
  final double score;
  final String reason;
  @override
  String get type => 'gameOver';
  @override
  Map<String, Object?> get fields => {
    'wave': wave,
    'kills': kills,
    'shots': shots,
    'spent': spent,
    'score': score,
    if (reason != livesReason) 'reason': reason,
  };
}

/// The game's objectives are met and the field is clear
/// (`GameManager.gameWin`, from the once-a-second `gameWinCheck`): a
/// challenge is passed, the tutorial is complete. The clock stops.
final class GameWon extends GameEvent {
  const GameWon(
    super.tick, {
    required this.wave,
    required this.kills,
    required this.shots,
    required this.spent,
    required this.score,
  });
  final int wave;
  final int kills;
  final int shots;
  final double spent;
  final double score;
  @override
  String get type => 'gameWon';
  @override
  Map<String, Object?> get fields => {
    'wave': wave,
    'kills': kills,
    'shots': shots,
    'spent': spent,
    'score': score,
  };
}

/// A won game goes on in freeplay (`ContinuePlaying`): the clock runs again
/// and the next wave is [nextWaveMs] game ms away.
final class FreeplayStarted extends GameEvent {
  const FreeplayStarted(super.tick, {required this.wave, required this.nextWaveMs});
  final int wave;
  final double nextWaveMs;
  @override
  String get type => 'freeplayStarted';
  @override
  Map<String, Object?> get fields => {'wave': wave, 'nextWaveMs': nextWaveMs};
}

/// An objective was reached ([kind] `waves`, `kills` or `time`;
/// `GameManager.targetHit`): for waves and kills no more waves come.
final class ObjectiveReached extends GameEvent {
  const ObjectiveReached(super.tick, {required this.kind});
  final String kind;
  @override
  String get type => 'objectiveReached';
  @override
  Map<String, Object?> get fields => {'kind': kind};
}

/// The time limit ran out before objective [kind] was reached (or the time
/// objective itself failed: `GameManager.targetMissed`).
final class ObjectiveMissed extends GameEvent {
  const ObjectiveMissed(super.tick, {required this.kind});
  final String kind;
  @override
  String get type => 'objectiveMissed';
  @override
  Map<String, Object?> get fields => {'kind': kind};
}

/// The tutorial's "Show me" set the cash (`GameTutorial` page `onShow`).
final class TutorialCashSet extends GameEvent {
  const TutorialCashSet(super.tick, {required this.page, required this.cash});
  final int page;
  final double cash;
  @override
  String get type => 'tutorialCashSet';
  @override
  Map<String, Object?> get fields => {'page': page, 'cash': cash};
}

/// The player's wave settings changed (`GameManager.settingsApply`).
final class WaveSettingsChanged extends GameEvent {
  const WaveSettingsChanged(super.tick, {required this.spacingMs, required this.follow});
  final double spacingMs;
  final bool follow;
  @override
  String get type => 'waveSettingsChanged';
  @override
  Map<String, Object?> get fields => {'spacingMs': spacingMs, 'follow': follow};
}

final class TurretBuilt extends GameEvent {
  const TurretBuilt(
    super.tick, {
    required this.uid,
    required this.turret,
    required this.x,
    required this.y,
    required this.cost,
    required this.cash,
  });
  final int uid;
  final String turret;
  final double x;
  final double y;
  final double cost;
  final double cash;
  @override
  String get type => 'turretBuilt';
  @override
  Map<String, Object?> get fields => {
    'uid': uid,
    'turret': turret,
    'x': x,
    'y': y,
    'cost': cost,
    'cash': cash,
  };
}

final class TurretUpgraded extends GameEvent {
  const TurretUpgraded(
    super.tick, {
    required this.uid,
    required this.stat,
    required this.level,
    required this.cost,
    required this.cash,
  });
  final int uid;
  final String stat;
  final int level;
  final double cost;
  final double cash;
  @override
  String get type => 'turretUpgraded';
  @override
  Map<String, Object?> get fields => {
    'uid': uid,
    'stat': stat,
    'level': level,
    'cost': cost,
    'cash': cash,
  };
}

final class TurretSold extends GameEvent {
  const TurretSold(super.tick, {required this.uid, required this.refund, required this.cash});
  final int uid;
  final int refund;
  final double cash;
  @override
  String get type => 'turretSold';
  @override
  Map<String, Object?> get fields => {'uid': uid, 'refund': refund, 'cash': cash};
}

final class TurretMoved extends GameEvent {
  const TurretMoved(
    super.tick, {
    required this.uid,
    required this.x,
    required this.y,
    required this.cost,
    required this.cash,
  });
  final int uid;
  final double x;
  final double y;
  final double cost;
  final double cash;
  @override
  String get type => 'turretMoved';
  @override
  Map<String, Object?> get fields => {'uid': uid, 'x': x, 'y': y, 'cost': cost, 'cash': cash};
}

/// A turret's target mode or lock changed.
final class TargetModeChanged extends GameEvent {
  const TargetModeChanged(
    super.tick, {
    required this.uid,
    required this.mode,
    required this.lockOff,
  });
  final int uid;
  final String mode;
  final bool lockOff;
  @override
  String get type => 'targetModeChanged';
  @override
  Map<String, Object?> get fields => {'uid': uid, 'mode': mode, 'lockOff': lockOff};
}

/// A turret fired [projectile] (a `projectiles.json` id) at creep [target]
/// (null for a shot at no creep: a held rocket, a link helper shooting its
/// leader). Drives the fire sound and the weapon's firing frames.
final class TurretFired extends GameEvent {
  const TurretFired(
    super.tick, {
    required this.uid,
    required this.projectile,
    required this.target,
    this.silent = false,
    this.assist = false,
    this.into,
    this.sound,
  });
  final int uid;
  final String projectile;
  final int? target;

  /// The turret the shot was fired into (a Fusion cannon being fed).
  final int? into;

  /// The fire sound when it is not the turret's usual one (a Fusion
  /// cannon's discharge sounds by its stored energy).
  final String? sound;

  /// No fire sound (`turretFire(…, no_sound)`: link helpers that pool).
  final bool silent;

  /// A link helper's shot into its leader.
  final bool assist;
  @override
  String get type => 'turretFired';
  @override
  Map<String, Object?> get fields => {
    'uid': uid,
    'projectile': projectile,
    'target': target,
    if (silent) 'silent': true,
    if (assist) 'assist': true,
    'into': ?into,
    'sound': ?sound,
  };
}

/// Targeter [uid] joined ([joined]) or let go of turret [target]; [joins]
/// is its join list afterwards, oldest first.
final class TurretJoined extends GameEvent {
  const TurretJoined(
    super.tick, {
    required this.uid,
    required this.target,
    required this.joined,
    required this.joins,
  });
  final int uid;
  final int target;
  final bool joined;
  final List<int> joins;
  @override
  String get type => 'turretJoined';
  @override
  Map<String, Object?> get fields => {
    'uid': uid,
    'target': target,
    'joined': joined,
    'joins': joins,
  };
}

/// Combonly plate [uid] moved to [stage]: `chosen` (it locked in [recipe]
/// as a [colour] weapon and is consuming the turrets [consumed]) or `armed`
/// (its weapon is in place and it fires).
final class CombonlyChanged extends GameEvent {
  const CombonlyChanged(
    super.tick, {
    required this.uid,
    required this.stage,
    required this.colour,
    required this.recipe,
    this.consumed = const [],
    this.cashValue,
  });
  final int uid;
  final String stage;
  final String colour;
  final String recipe;
  final List<int> consumed;

  /// The plate's value after taking the consumed turrets' values.
  final double? cashValue;
  @override
  String get type => 'combonlyChanged';
  @override
  Map<String, Object?> get fields => {
    'uid': uid,
    'stage': stage,
    'colour': colour,
    'recipe': recipe,
    if (consumed.isNotEmpty) 'consumed': consumed,
    'cashValue': ?cashValue,
  };
}

/// Turret [uid], consumed by Combonly plate [into], is gone (no refund: its
/// value went into the plate).
final class TurretConsumed extends GameEvent {
  const TurretConsumed(super.tick, {required this.uid, required this.into});
  final int uid;
  final int into;
  @override
  String get type => 'turretConsumed';
  @override
  Map<String, Object?> get fields => {'uid': uid, 'into': into};
}

/// A turret's freakout moved to [stage]: `warning` (3 s, its sign shows),
/// `active` (the multipliers apply) or `ended`. A bought one carries its
/// [cost] and the [cash] left.
final class FreakoutChanged extends GameEvent {
  const FreakoutChanged(super.tick, {required this.uid, required this.stage, this.cost, this.cash});
  final int uid;
  final String stage;
  final double? cost;
  final double? cash;
  @override
  String get type => 'freakoutChanged';
  @override
  Map<String, Object?> get fields => {'uid': uid, 'stage': stage, 'cost': ?cost, 'cash': ?cash};
}

/// Turrets of type [turret] became available at [kills] kills
/// (`GameManager.weaponAvailable`: message, "Weapon" sound, rack entry).
final class WeaponUnlocked extends GameEvent {
  const WeaponUnlocked(super.tick, {required this.turret, required this.kills});
  final String turret;
  final int kills;
  @override
  String get type => 'weaponUnlocked';
  @override
  Map<String, Object?> get fields => {'turret': turret, 'kills': kills};
}

/// Turret [uid] fired combo [combo] (`Turret.comboFired`: the "Combo" sound,
/// the `SpecialFire` sign on the leader) with the helpers it took
/// ([helpers]: the `SpecialTake` sign on each). [projectile] is what it
/// launched; [sound] is a sound the combo plays as it fires (the black
/// hole's), besides "Combo".
final class ComboFired extends GameEvent {
  const ComboFired(
    super.tick, {
    required this.uid,
    required this.combo,
    required this.helpers,
    required this.projectile,
    this.sound,
  });
  final int uid;
  final String combo;
  final List<int> helpers;
  final String? projectile;
  final String? sound;
  @override
  String get type => 'comboFired';
  @override
  Map<String, Object?> get fields => {
    'uid': uid,
    'combo': combo,
    'helpers': helpers,
    'projectile': projectile,
    'sound': ?sound,
  };
}

/// A blast [blast] (a `blasts.json` id) went off at ([x], [y]) with
/// [damage]; [sound] is its audio event (`sound_blast`, or the cluster
/// spark's "Tazer"), null when silent.
final class BlastStarted extends GameEvent {
  const BlastStarted(
    super.tick, {
    required this.uid,
    required this.blast,
    required this.x,
    required this.y,
    required this.damage,
    this.sound,
  });
  final int uid;
  final String blast;
  final double x;
  final double y;
  final double damage;
  final String? sound;
  @override
  String get type => 'blastStarted';
  @override
  Map<String, Object?> get fields => {
    'uid': uid,
    'blast': blast,
    'x': x,
    'y': y,
    'damage': damage,
    'sound': ?sound,
  };
}

/// A black hole opened at ([x], [y]) (`BlackHole` ctor: "BlackHole" sound).
final class BlackHoleOpened extends GameEvent {
  const BlackHoleOpened(super.tick, {required this.uid, required this.x, required this.y});
  final int uid;
  final double x;
  final double y;
  @override
  String get type => 'blackHoleOpened';
  @override
  Map<String, Object?> get fields => {'uid': uid, 'x': x, 'y': y};
}

/// Creep [uid] reached the centre of black hole [hole] and was removed
/// (`attackerDead(true)`): a dirty kill, with no cash, kill or credit.
final class CreepSwallowed extends GameEvent {
  const CreepSwallowed(super.tick, {required this.uid, required this.hole});
  final int uid;
  final int hole;
  @override
  String get type => 'creepSwallowed';
  @override
  Map<String, Object?> get fields => {'uid': uid, 'hole': hole};
}
