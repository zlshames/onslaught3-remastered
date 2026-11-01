import 'package:meta/meta.dart';

import 'json_reader.dart';

/// `rules.json`: global rule constants that are not owned by one turret, creep
/// or combo (lives, refund, combo neighbourhood, modifier floor, slow rules).
@immutable
class RulesConstants {
  const RulesConstants({
    required this.tickHz,
    required this.lives,
    required this.sellRefund,
    required this.modifierMultFloor,
    required this.comboRange,
    required this.blackHolePointRange,
    required this.slowFloor,
    required this.slowRecoverAmount,
    required this.slowRecoverIntervalMs,
    required this.speedFactorMin,
    required this.speedFactorMax,
    required this.winCheckIntervalMs,
  });

  factory RulesConstants.fromJson(JsonReader r) {
    r.expectOnlyKeys({
      'schemaVersion',
      'simulation',
      'economy',
      'modifiers',
      'combos',
      'slow',
      'objectives',
    });
    final sim = r.child('simulation')
      ..expectOnlyKeys({'tickHz', 'speedFactorMin', 'speedFactorMax'});
    final eco = r.child('economy')..expectOnlyKeys({'lives', 'sellRefund'});
    final mod = r.child('modifiers')..expectOnlyKeys({'multFloor'});
    final combo = r.child('combos')..expectOnlyKeys({'range', 'blackHolePointRange'});
    final slow = r.child('slow')..expectOnlyKeys({'floor', 'recoverAmount', 'recoverIntervalMs'});
    final objectives = r.child('objectives')..expectOnlyKeys({'winCheckIntervalMs'});
    return RulesConstants(
      tickHz: sim.integer('tickHz', min: 1, max: 1000),
      speedFactorMin: sim.number('speedFactorMin', min: 0),
      speedFactorMax: sim.number('speedFactorMax', min: 0),
      lives: eco.integer('lives', min: 1),
      sellRefund: eco.number('sellRefund', min: 0, max: 1),
      modifierMultFloor: mod.number('multFloor', min: 0),
      comboRange: combo.number('range', min: 0),
      blackHolePointRange: combo.number('blackHolePointRange', min: 0),
      slowFloor: slow.number('floor', min: 0),
      slowRecoverAmount: slow.number('recoverAmount', min: 0),
      slowRecoverIntervalMs: slow.number('recoverIntervalMs', min: 1),
      winCheckIntervalMs: objectives.number('winCheckIntervalMs', min: 1),
    );
  }

  static const int schemaVersion = 1;

  /// Fixed simulation step rate.
  final int tickHz;

  /// Lowest and highest game-speed factor (original pref `PrefTimeScale`
  /// 50–200 %).
  final double speedFactorMin;
  final double speedFactorMax;

  /// Lives at the start of a game.
  final int lives;

  /// Fraction of a turret's total value refunded on sale (rounded up).
  final double sellRefund;

  /// Lower bound on a turret's accumulated multiplier (`max(mult, floor)`).
  final double modifierMultFloor;

  /// Radius within which combo-capable turrets can help each other.
  final double comboRange;

  /// Black holes open on a mine point within this distance of the leader
  /// (`combo_hole_range`). The original also declares `combo_rate = 7` but
  /// never reads it, so it is not data.
  final double blackHolePointRange;

  /// Slowest a creep can be slowed to, px/s.
  final double slowFloor;

  /// Speed regained per recovery interval, px/s.
  final double slowRecoverAmount;
  final double slowRecoverIntervalMs;

  /// Real ms between checks whether a game with objectives is won, once an
  /// objective has ended the waves (`GameManager.gameWinCheck`).
  final double winCheckIntervalMs;

  /// The `rules.json` document. The speed factors are fractions (a percent
  /// over 100), written as doubles even when whole (`2.0`).
  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'simulation': {
      'tickHz': tickHz,
      'speedFactorMin': speedFactorMin,
      'speedFactorMax': speedFactorMax,
    },
    'economy': {'lives': lives, 'sellRefund': jsonNumber(sellRefund)},
    'modifiers': {'multFloor': jsonNumber(modifierMultFloor)},
    'combos': {
      'range': jsonNumber(comboRange),
      'blackHolePointRange': jsonNumber(blackHolePointRange),
    },
    'slow': {
      'floor': jsonNumber(slowFloor),
      'recoverAmount': jsonNumber(slowRecoverAmount),
      'recoverIntervalMs': jsonNumber(slowRecoverIntervalMs),
    },
    'objectives': {'winCheckIntervalMs': jsonNumber(winCheckIntervalMs)},
  };
}
