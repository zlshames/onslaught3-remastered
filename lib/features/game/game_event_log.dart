import 'package:onslaught_core/onslaught_core.dart';

import '../../services/logging/logging.dart';

const Logger _log = Logger('game');

/// Writes a game's notable events to the log (`docs/LOGGING.md`): the
/// result, unlocks, objectives and freeplay at `info`; what the player did
/// (build, upgrade, sell, move, target mode, joins, combos, freakouts,
/// pause, speed, wave settings), what the game refused and each wave and
/// base hit at `debug`; tutorial cash at `trace`. Events that come many
/// times a second (shots, kills, spawns, blasts) are not logged. Each line
/// carries the game step (`tick`) it happened at.
void logGameEvent(GameEvent e, {Logger log = _log}) {
  final (level, message, fields) = switch (e) {
    GameOver(:final wave, :final kills, :final score, :final reason) => (
      LogLevel.info,
      'game over',
      {'wave': wave, 'kills': kills, 'score': score, 'reason': reason},
    ),
    GameWon(:final wave, :final kills, :final score) => (
      LogLevel.info,
      'game won',
      {'wave': wave, 'kills': kills, 'score': score},
    ),
    FreeplayStarted(:final wave) => (LogLevel.info, 'freeplay started', {'wave': wave}),
    WeaponUnlocked(:final turret, :final kills) => (
      LogLevel.info,
      'weapon unlocked',
      {'turret': turret, 'kills': kills},
    ),
    ObjectiveReached(:final kind) => (LogLevel.info, 'objective reached', {'kind': kind}),
    ObjectiveMissed(:final kind) => (LogLevel.info, 'objective missed', {'kind': kind}),
    WaveStarted(:final wave, :final size, :final creepType, :final hp) => (
      LogLevel.debug,
      'wave started',
      {'wave': wave, 'size': size, 'creepType': creepType, 'hp': hp},
    ),
    BaseHit(:final lives) => (LogLevel.debug, 'base hit', {'lives': lives}),
    TurretBuilt(:final uid, :final turret, :final x, :final y, :final cost) => (
      LogLevel.debug,
      'turret built',
      {'uid': uid, 'turret': turret, 'x': x.round(), 'y': y.round(), 'cost': cost},
    ),
    TurretUpgraded(:final uid, :final stat, :final level, :final cost, :final cash) => (
      LogLevel.debug,
      'turret upgraded',
      {'uid': uid, 'stat': stat, 'level': level, 'cost': cost, 'cash': cash},
    ),
    TurretSold(:final uid, :final refund, :final cash) => (
      LogLevel.debug,
      'turret sold',
      {'uid': uid, 'refund': refund, 'cash': cash},
    ),
    TurretMoved(:final uid, :final x, :final y, :final cost, :final cash) => (
      LogLevel.debug,
      'turret moved',
      {'uid': uid, 'x': x.round(), 'y': y.round(), 'cost': cost, 'cash': cash},
    ),
    TargetModeChanged(:final uid, :final mode, :final lockOff) => (
      LogLevel.debug,
      'target mode changed',
      {'uid': uid, 'mode': mode, 'lockOff': lockOff},
    ),
    TurretJoined(:final uid, :final target, :final joined) => (
      LogLevel.debug,
      joined ? 'turrets joined' : 'turrets parted',
      {'uid': uid, 'target': target},
    ),
    CombonlyChanged(:final uid, :final stage, :final colour, :final recipe) => (
      LogLevel.debug,
      'combo changed',
      {'uid': uid, 'stage': stage, 'colour': colour, 'recipe': recipe},
    ),
    TurretConsumed(:final uid, :final into) => (
      LogLevel.debug,
      'turret consumed',
      {'uid': uid, 'into': into},
    ),
    FreakoutChanged(:final uid, :final stage, :final cost) => (
      LogLevel.debug,
      'freakout changed',
      {'uid': uid, 'stage': stage, 'cost': cost},
    ),
    PausedChanged(:final paused) => (LogLevel.debug, 'paused changed', {'paused': paused}),
    SpeedChanged(:final speed) => (LogLevel.debug, 'speed changed', {'speed': speed}),
    WaveSettingsChanged(:final spacingMs, :final follow) => (
      LogLevel.debug,
      'wave settings changed',
      {'spacingMs': spacingMs, 'follow': follow},
    ),
    CommandRejected(:final command, :final reason) => (
      LogLevel.debug,
      'command refused',
      {'command': command, 'reason': reason},
    ),
    TutorialCashSet(:final page, :final cash) => (
      LogLevel.trace,
      'tutorial cash set',
      {'page': page, 'cash': cash},
    ),
    _ => (null, '', const <String, Object?>{}),
  };
  if (level == null || !log.isEnabled(level)) return;
  final withTick = {'tick': e.tick, ...fields};
  switch (level) {
    case LogLevel.info:
      log.info(message, fields: withTick);
    case LogLevel.debug:
      log.debug(message, fields: withTick);
    default:
      log.trace(message, fields: withTick);
  }
}
