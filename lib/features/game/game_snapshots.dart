import 'package:flutter/foundation.dart';
import 'package:onslaught_core/onslaught_core.dart';

/// Value equality over [props] for the HUD's snapshot types, so a
/// [ValueNotifier] only notifies when something visible changed.
@immutable
abstract class _Snapshot {
  const _Snapshot();

  List<Object?> get props;

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType && listEquals((other as _Snapshot).props, props);

  @override
  int get hashCode => Object.hashAll(props);
}

/// What the top bar shows about the running game. Rebuilt only when a value
/// changes, never per frame.
class HudState extends _Snapshot {
  const HudState({
    required this.cash,
    required this.lives,
    required this.kills,
    required this.wave,
    required this.paused,
    required this.speed,
    this.nextWaveSeconds = 0,
    this.waveSpacingSeconds = 20,
    this.gameOver = false,
  });

  final double cash;
  final int lives;
  final int kills;
  final int wave;
  final bool paused;
  final double speed;

  /// Seconds until the wave clock sends the next wave, rounded up to a tenth
  /// as the original clock shows it.
  final double nextWaveSeconds;

  /// Full wave spacing in seconds (for the countdown ring).
  final double waveSpacingSeconds;
  final bool gameOver;

  @override
  List<Object?> get props => [
    cash,
    lives,
    kills,
    wave,
    paused,
    speed,
    nextWaveSeconds,
    waveSpacingSeconds,
    gameOver,
  ];
}

/// One cell of the tower tray.
class TrayItem extends _Snapshot {
  const TrayItem({
    required this.id,
    required this.name,
    required this.cost,
    required this.icon,
    required this.affordable,
    this.locked = false,
    this.unlockKills = 0,
    this.killsToUnlock = 0,
  });

  /// `turrets.json` id.
  final String id;
  final String name;
  final double cost;

  /// Logical art id of the icon.
  final String? icon;
  final bool affordable;

  /// Not available yet: unlocked at [unlockKills] total kills, which is
  /// [killsToUnlock] away.
  final bool locked;
  final int unlockKills;
  final int killsToUnlock;

  @override
  List<Object?> get props => [id, name, cost, icon, affordable, locked, unlockKills, killsToUnlock];
}

/// One upgrade row of the selected-turret sheet.
class StatRow extends _Snapshot {
  const StatRow({
    required this.stat,
    required this.level,
    required this.maxLevel,
    required this.value,
    required this.nextValue,
    required this.nextCost,
    required this.affordable,
    double? baseValue,
  }) : baseValue = baseValue ?? value;

  final StatKind stat;
  final int level;
  final int maxLevel;

  /// Current effective value (with modifier auras and freakouts).
  final double value;

  /// The upgrade level's value before modifiers.
  final double baseValue;

  /// Effective value after the next upgrade, or null when maxed.
  final double? nextValue;
  final double? nextCost;
  final bool affordable;

  bool get maxed => nextCost == null;

  /// Raised or lowered by modifiers or a freakout.
  bool get modified => value != baseValue;

  @override
  List<Object?> get props => [
    stat,
    level,
    maxLevel,
    value,
    baseValue,
    nextValue,
    nextCost,
    affordable,
  ];
}

/// A turret special's card on the selected-turret sheet.
sealed class SpecialCard extends _Snapshot {
  const SpecialCard();
}

/// Blue/Yellow freakout: idle until [available]; then the countdown to the
/// next one ([nextSeconds], null while none is scheduled) and what buying
/// one now costs ([buyCost], null when it cannot be bought).
class FreakoutCard extends SpecialCard {
  const FreakoutCard({
    required this.available,
    required this.stage,
    required this.nextSeconds,
    required this.buyCost,
    required this.affordable,
  });

  /// The [stage] while no freakout is running (the others are
  /// `FreakoutSpecial.stageWarning` and `stageActive`).
  static const String stageIdle = 'idle';

  final bool available;

  /// [stageIdle], `warning` or `active` (the latest running freakout).
  final String stage;
  final int? nextSeconds;
  final double? buyCost;
  final bool affordable;

  @override
  List<Object?> get props => [available, stage, nextSeconds, buyCost, affordable];
}

/// Yellow charge: stored [charge] of [max], gained at [ratePerSecond], and
/// the poison (slow) its next shot carries.
class ChargeCard extends SpecialCard {
  const ChargeCard({
    required this.charge,
    required this.max,
    required this.ratePerSecond,
    required this.shotPoison,
  });

  final double charge;
  final double max;
  final double ratePerSecond;
  final double shotPoison;

  @override
  List<Object?> get props => [charge, max, ratePerSecond, shotPoison];
}

/// Red holding pattern: locked until the [levelRange]/[levelRate] upgrade
/// levels, then [held] of [max] rockets circling.
class HoldingCard extends SpecialCard {
  const HoldingCard({
    required this.unlocked,
    required this.held,
    required this.max,
    required this.levelRange,
    required this.levelRate,
  });

  final bool unlocked;
  final int held;
  final int max;
  final int levelRange;
  final int levelRate;

  @override
  List<Object?> get props => [unlocked, held, max, levelRange, levelRate];
}

/// Green link: link turrets in its range and its last pooled shot.
class LinkCard extends SpecialCard {
  const LinkCard({required this.links, required this.lastDamage, required this.mult});

  final int links;
  final double lastDamage;
  final double mult;

  @override
  List<Object?> get props => [links, lastDamage, mult];
}

/// Combos (`turretinfo/TurretInfoCombos`): locked until the damage track
/// is fully bought ([damageLevelsToGo] left); then whether it may combo now
/// or in [nextSeconds], the combo-capable turrets within the combo range by
/// turret id ([partners]), the recipe those partners make ([recipe], the
/// name of the first match when all are ready; null for none) and the
/// combos it [led] and [assisted].
class ComboCard extends SpecialCard {
  const ComboCard({
    required this.capable,
    required this.damageLevelsToGo,
    required this.nextSeconds,
    required this.partners,
    required this.recipe,
    required this.led,
    required this.assisted,
  });

  final bool capable;
  final int damageLevelsToGo;

  /// Whole seconds until it may combo again; null when it may now.
  final int? nextSeconds;
  final Map<String, int> partners;
  final String? recipe;
  final int led;
  final int assisted;

  @override
  List<Object?> get props => [
    capable,
    damageLevelsToGo,
    nextSeconds,
    for (final e in partners.entries) '${e.key}:${e.value}',
    recipe,
    led,
    assisted,
  ];
}

/// A modifier's aura: what it adds, its radius and how many turrets it
/// covers.
class AuraCard extends SpecialCard {
  const AuraCard({required this.terms, required this.radius, required this.covered});

  final StatTerms terms;
  final double radius;
  final int covered;

  @override
  List<Object?> get props => [terms, radius, covered];
}

/// Targeter: turrets joined ([joins] of [max]) and whether the player is
/// picking turrets to join or let go ([joining], the joiner).
class TargeterCard extends SpecialCard {
  const TargeterCard({required this.joins, required this.max, required this.joining});

  final int joins;
  final int max;
  final bool joining;

  @override
  List<Object?> get props => [joins, max, joining];
}

/// Fusion cannon: stored damage and poison, its glow [tier] (`none`,
/// `low` … `max`) and the turrets feeding it.
class FusionCard extends SpecialCard {
  const FusionCard({
    required this.storeDamage,
    required this.storePoison,
    required this.tier,
    required this.feeders,
  });

  final double storeDamage;
  final double storePoison;
  final String tier;
  final int feeders;

  @override
  List<Object?> get props => [storeDamage, storePoison, tier, feeders];
}

/// One option a Combonly plate offers: the colour it would become and the
/// combo it would fire.
typedef CombonlyChoice = ({String colour, String recipe, String name});

/// Combonly plate: its [options], the one [shown] now (tap "Lock in" while
/// one shows), or the one [chosen] and whether its weapon is [armed].
class CombonlyCard extends SpecialCard {
  const CombonlyCard({
    required this.options,
    required this.shown,
    required this.chosen,
    required this.armed,
  });

  final List<CombonlyChoice> options;
  final CombonlyChoice? shown;
  final CombonlyChoice? chosen;
  final bool armed;

  @override
  List<Object?> get props => [...options, shown, chosen, armed];
}

/// One in-game message (`GameManager.messageNew`), shown as a toast and kept
/// in the log. [seq] orders them.
class GameMessage extends _Snapshot {
  const GameMessage({required this.seq, required this.text, this.alert = true});

  final int seq;
  final String text;

  /// Whether it draws attention (the original's message sound and flash).
  final bool alert;

  @override
  List<Object?> get props => [seq, text, alert];
}

/// Everything the selected-turret sheet shows.
class TurretPanel extends _Snapshot {
  const TurretPanel({
    required this.uid,
    required this.turretId,
    required this.typeName,
    required this.displayName,
    required this.icon,
    required this.kills,
    required this.shots,
    required this.stats,
    required this.refund,
    required this.moveCost,
    required this.canAffordMove,
    required this.targetMode,
    required this.targetModeIndex,
    required this.targetModes,
    required this.lockOff,
    required this.locked,
    this.cards = const [],
    this.auraRadius,
  });

  final int uid;
  final String turretId;
  final String typeName;
  final String displayName;
  final String? icon;
  final int kills;
  final int shots;
  final List<StatRow> stats;
  final int refund;
  final double moveCost;
  final bool canAffordMove;

  /// Current target mode id (null for turrets without a weapon).
  final String? targetMode;

  /// The turret's cycle position. It starts at 0 for every turret, even one
  /// whose default mode is not the first (`target_type_num`), so cycling
  /// from Yellow's "fast" goes to "far".
  final int targetModeIndex;

  /// Every mode id, in cycle order.
  final List<String> targetModes;

  /// The mode the target chip cycles to next.
  String get nextTargetMode => targetModes[(targetModeIndex + 1) % targetModes.length];
  final bool lockOff;

  /// Paused or over, or the turret is inactive (a Combonly plate taking on
  /// its weapon): the original refuses every turret command then.
  final bool locked;

  /// Cards for the turret's specials, in data order.
  final List<SpecialCard> cards;

  /// For modifiers: the aura radius drawn instead of a weapon range.
  final double? auraRadius;

  @override
  List<Object?> get props => [
    ...cards,
    auraRadius,
    uid,
    turretId,
    typeName,
    displayName,
    icon,
    kills,
    shots,
    ...stats,
    refund,
    moveCost,
    canAffordMove,
    targetMode,
    targetModeIndex,
    ...targetModes,
    lockOff,
    locked,
  ];
}

/// The ghost turret shown while placing (building or moving).
class PlacementPreview extends _Snapshot {
  const PlacementPreview({
    required this.turretId,
    required this.at,
    required this.valid,
    required this.range,
    this.moving,
    this.locked = false,
  });

  final String turretId;

  /// World position, or null while the finger is off the map.
  final Vec2? at;

  /// Placeable here and affordable.
  final bool valid;

  /// Range circle radius in world px.
  final double range;

  /// Uid of the turret being moved, or null when building.
  final int? moving;

  /// Dropped and locked at [at] (drop and lock): a drag on the map nudges
  /// it and only Place builds it.
  final bool locked;

  @override
  List<Object?> get props => [turretId, at, valid, range, moving, locked];
}

/// How a game ended, for the end dialog.
enum GameEnd {
  /// The lives ran out (`TurretInfoGameOver`).
  gameOver,

  /// A challenge was passed or failed (`TurretInfoChallengeOver`).
  challengePassed,
  challengeFailed,

  /// The tutorial's 50 waves were beaten (`GameManager.gameWin`).
  tutorialComplete;

  /// A win: the dialog offers to continue playing.
  bool get won => this == challengePassed || this == tutorialComplete;
}

/// The numbers on the end dialog (`TurretInfoGameOver`,
/// `TurretInfoChallengeOver`).
class GameOverSummary extends _Snapshot {
  const GameOverSummary({
    required this.wave,
    required this.kills,
    required this.shots,
    required this.spent,
    required this.score,
    this.end = GameEnd.gameOver,
    this.seconds = 0,
    this.canContinue = false,
  });

  final int wave;
  final int kills;
  final int shots;
  final double spent;
  final double score;
  final GameEnd end;

  /// Game seconds played (the challenge dialog's Time, which the original
  /// never fills in).
  final int seconds;

  /// A win the player may play on from in freeplay
  /// (`RulesProfile.continueAfterWin`).
  final bool canContinue;

  @override
  List<Object?> get props => [wave, kills, shots, spent, score, end, seconds, canContinue];
}

/// The state of a challenge target badge.
enum BadgeState { pending, reached, missed }

/// One challenge target badge under the top bar (`TheTimeLimit`,
/// `TheWaveLimit`, `TheKillTarget`): [kind] `time`, `waves` or `kills`,
/// its readout ("mm:ss" or "n/target"), its state, and a [milestone] count
/// that steps every 50 waves or 100 kills (the original flashes the badge).
class ObjectiveBadge extends _Snapshot {
  const ObjectiveBadge({
    required this.kind,
    required this.text,
    this.state = BadgeState.pending,
    this.milestone = 0,
  });

  final String kind;
  final String text;
  final BadgeState state;
  final int milestone;

  @override
  List<Object?> get props => [kind, text, state, milestone];
}
