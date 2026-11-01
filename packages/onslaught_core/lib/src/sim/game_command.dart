import 'package:meta/meta.dart';

/// The only way into the simulation. The UI, input bindings, bots, tests and
/// replays all drive a session by sending these. Every command serialises to
/// JSON so scenarios and replays can be stored.
@immutable
sealed class GameCommand {
  const GameCommand();

  /// Command type id used in JSON.
  String get type;

  Map<String, Object?> toJson();

  static GameCommand fromJson(Map<String, Object?> j) {
    String str(String k) => j[k]! as String;
    double num_(String k) => (j[k]! as num).toDouble();
    int int_(String k) => (j[k]! as num).toInt();
    return switch (j['type']) {
      'build' => BuildTurret(str('turret'), num_('x'), num_('y')),
      'upgrade' => UpgradeTurret(int_('uid'), str('stat')),
      'upgradeMax' => UpgradeTurretMax(int_('uid'), str('stat')),
      'sell' => SellTurret(int_('uid')),
      'move' => MoveTurret(int_('uid'), num_('x'), num_('y')),
      'targetMode' => SetTargetMode(int_('uid'), str('mode')),
      'targetLock' => SetTargetLock(int_('uid'), lockOff: j['lockOff']! as bool),
      'sendWave' => const SendNextWave(),
      'pause' => SetPaused(j['paused']! as bool),
      'speed' => SetSpeed(num_('speed')),
      'buyFreakout' => BuyFreakout(int_('uid')),
      'join' => JoinTurret(int_('uid'), int_('target')),
      'chooseCombonly' => ChooseCombonly(int_('uid')),
      'waveSettings' => SetWaveSettings(spacingMs: num_('spacingMs'), follow: j['follow']! as bool),
      'tutorialShow' => TutorialShow(int_('page')),
      'continuePlaying' => const ContinuePlaying(),
      final t => throw ArgumentError.value(t, 'type', 'unknown command'),
    };
  }

  @override
  String toString() => toJson().toString();
}

/// Build turret [turret] (a `turrets.json` id) centred at ([x], [y]).
final class BuildTurret extends GameCommand {
  const BuildTurret(this.turret, this.x, this.y);
  final String turret;
  final double x;
  final double y;
  @override
  String get type => 'build';
  @override
  Map<String, Object?> toJson() => {'type': type, 'turret': turret, 'x': x, 'y': y};
}

/// Buy the next step of [stat] (`damage`, `range`, `rate`) on turret [uid].
final class UpgradeTurret extends GameCommand {
  const UpgradeTurret(this.uid, this.stat);
  final int uid;
  final String stat;
  @override
  String get type => 'upgrade';
  @override
  Map<String, Object?> toJson() => {'type': type, 'uid': uid, 'stat': stat};
}

/// Buy as many steps of [stat] on turret [uid] as the cash allows, one
/// after another (`Turret.upgradeDamageMax`/`upgradeRangeMax`/`upgradeRateMax`,
/// Shift-click in the original). Each step bought is its own
/// `TurretUpgraded`; rejected only when not even one step can be bought.
final class UpgradeTurretMax extends GameCommand {
  const UpgradeTurretMax(this.uid, this.stat);
  final int uid;
  final String stat;
  @override
  String get type => 'upgradeMax';
  @override
  Map<String, Object?> toJson() => {'type': type, 'uid': uid, 'stat': stat};
}

/// Sell turret [uid] for its refund.
final class SellTurret extends GameCommand {
  const SellTurret(this.uid);
  final int uid;
  @override
  String get type => 'sell';
  @override
  Map<String, Object?> toJson() => {'type': type, 'uid': uid};
}

/// Move turret [uid] to ([x], [y]) for the move cost; it keeps its upgrades.
final class MoveTurret extends GameCommand {
  const MoveTurret(this.uid, this.x, this.y);
  final int uid;
  final double x;
  final double y;
  @override
  String get type => 'move';
  @override
  Map<String, Object?> toJson() => {'type': type, 'uid': uid, 'x': x, 'y': y};
}

/// Set turret [uid]'s target mode to [mode] (a `targeting.json` mode id).
final class SetTargetMode extends GameCommand {
  const SetTargetMode(this.uid, this.mode);
  final int uid;
  final String mode;
  @override
  String get type => 'targetMode';
  @override
  Map<String, Object?> toJson() => {'type': type, 'uid': uid, 'mode': mode};
}

/// Lock or unlock turret [uid]'s target: with [lockOff] it drops its target
/// after every shot (`target_reacquire`, "Lock Off").
final class SetTargetLock extends GameCommand {
  const SetTargetLock(this.uid, {required this.lockOff});
  final int uid;
  final bool lockOff;
  @override
  String get type => 'targetLock';
  @override
  Map<String, Object?> toJson() => {'type': type, 'uid': uid, 'lockOff': lockOff};
}

/// Send the next wave now.
final class SendNextWave extends GameCommand {
  const SendNextWave();
  @override
  String get type => 'sendWave';
  @override
  Map<String, Object?> toJson() => {'type': type};
}

final class SetPaused extends GameCommand {
  const SetPaused(this.paused);
  final bool paused;
  @override
  String get type => 'pause';
  @override
  Map<String, Object?> toJson() => {'type': type, 'paused': paused};
}

/// Set the game-speed factor (1 = 100 %), clamped to the data's bounds.
final class SetSpeed extends GameCommand {
  const SetSpeed(this.speed);
  final double speed;
  @override
  String get type => 'speed';
  @override
  Map<String, Object?> toJson() => {'type': type, 'speed': speed};
}

/// Pays to start turret [uid]'s next freakout now (the info panel's
/// "Freak out now" button, `TurretInfoBlue`).
final class BuyFreakout extends GameCommand {
  const BuyFreakout(this.uid);
  final int uid;
  @override
  String get type => 'buyFreakout';
  @override
  Map<String, Object?> toJson() => {'type': type, 'uid': uid};
}

/// Targeter [uid] joins turret [target] (or lets it go when it is already
/// joined): the joiner drag of `TurretJoiner`, as a command. A fourth join
/// drops the oldest.
final class JoinTurret extends GameCommand {
  const JoinTurret(this.uid, this.target);
  final int uid;
  final int target;
  @override
  String get type => 'join';
  @override
  Map<String, Object?> toJson() => {'type': type, 'uid': uid, 'target': target};
}

/// Locks Combonly plate [uid] into the option it is showing (a click on the
/// plate while a colour shows, `TurretCombonly.onPress`).
final class ChooseCombonly extends GameCommand {
  const ChooseCombonly(this.uid);
  final int uid;
  @override
  String get type => 'chooseCombonly';
  @override
  Map<String, Object?> toJson() => {'type': type, 'uid': uid};
}

/// The settings window was closed (`GameSettings.prefsSaveAndApply` →
/// `GameManager.settingsApply`): the wave clock now runs every [spacingMs]
/// and, with [follow], the next wave is sent as soon as the field is clear.
/// Applies while paused.
final class SetWaveSettings extends GameCommand {
  const SetWaveSettings({required this.spacingMs, required this.follow});
  final double spacingMs;
  final bool follow;
  @override
  String get type => 'waveSettings';
  @override
  Map<String, Object?> toJson() => {'type': type, 'spacingMs': spacingMs, 'follow': follow};
}

/// The tutorial's "Show me" on page [page] (0-based; `GameTutorial.tutorialShow`):
/// a page with `setCash` sets the cash, once per tutorial. Applies while
/// paused; refused outside the tutorial.
final class TutorialShow extends GameCommand {
  const TutorialShow(this.page);
  final int page;
  @override
  String get type => 'tutorialShow';
  @override
  Map<String, Object?> toJson() => {'type': type, 'page': page};
}

/// "Continue playing" on the win dialog (`RulesProfile.continueAfterWin`;
/// BTD6-style freeplay): a won game goes on with the waves resumed, no time
/// limit and no further win. Refused unless the game has just been won.
final class ContinuePlaying extends GameCommand {
  const ContinuePlaying();
  @override
  String get type => 'continuePlaying';
  @override
  Map<String, Object?> toJson() => {'type': type};
}

/// A command and the step it is applied at: a line of a scripted scenario,
/// and of a session's `GameSession.commandLog` (what a game in progress is
/// saved as and rebuilt from).
@immutable
class ScheduledCommand {
  const ScheduledCommand(this.tick, this.command);

  factory ScheduledCommand.fromJson(Map<String, Object?> j) => ScheduledCommand(
    (j['tick']! as num).toInt(),
    GameCommand.fromJson((j['command']! as Map).cast<String, Object?>()),
  );

  /// The command is applied at the start of this step (0 = first step).
  final int tick;
  final GameCommand command;

  Map<String, Object?> toJson() => {'tick': tick, 'command': command.toJson()};
}
