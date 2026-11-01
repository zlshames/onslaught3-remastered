import '../data/game_data.dart';
import '../data/turret_def.dart';
import '../math/vec2.dart';
import '../rules/rules_profile.dart';
import '../rules/rules_registry.dart';
import '../sim/game_command.dart';
import '../sim/game_config.dart';
import '../sim/game_event.dart';
import '../sim/game_session.dart';
import 'sim_test_harness.dart';

/// A balance-bot strategy (`test/balance/strategies/*.json`): which turret
/// to build where, how to spend cash and when to send waves. Strategies are
/// data so adding one needs no Dart (balance-bot skill).
class BotStrategy {
  const BotStrategy({
    required this.id,
    required this.description,
    required this.mapId,
    required this.turret,
    this.difficulty = 'easy',
    this.mode = 'normal',
    this.profile = RulesProfile.classic,
    this.seed = 1,
    this.maxTurrets = 10,
    this.upgradeOrder = const ['damage', 'rate', 'range'],
    this.sendEarly = false,
    this.decideEvery = 30,
    this.gridStep = 6,
  });

  factory BotStrategy.fromJson(Map<String, Object?> j) => BotStrategy(
    id: j['id']! as String,
    description: j['description']! as String,
    mapId: j['map']! as String,
    turret: j['turret']! as String,
    difficulty: j['difficulty'] as String? ?? 'easy',
    mode: j['mode'] as String? ?? 'normal',
    profile: RulesProfile.byId(j['profile'] as String? ?? 'classic'),
    seed: (j['seed'] as num?)?.toInt() ?? 1,
    maxTurrets: (j['maxTurrets'] as num?)?.toInt() ?? 10,
    upgradeOrder: (j['upgradeOrder'] as List?)?.cast<String>() ?? const ['damage', 'rate', 'range'],
    sendEarly: j['sendEarly'] as bool? ?? false,
    decideEvery: (j['decideEvery'] as num?)?.toInt() ?? 30,
    gridStep: (j['gridStep'] as num?)?.toDouble() ?? 6,
  );

  final String id;
  final String description;
  final String mapId;

  /// Turret id built at every spot.
  final String turret;
  final String difficulty;
  final String mode;
  final RulesProfile profile;
  final int seed;

  /// Turrets to build; cash goes to new turrets first, until this many
  /// stand, then to upgrades.
  final int maxTurrets;

  /// Upgrade policy: the first stat in this order that some turret has not
  /// maxed is upgraded on the turret where its next step is cheapest, once
  /// that step is affordable (cash is saved for it meanwhile).
  final List<String> upgradeOrder;

  /// Send the next wave as soon as the field is clear.
  final bool sendEarly;

  /// Ticks between decisions.
  final int decideEvery;

  /// Spacing of the candidate grid for build spots, px.
  final double gridStep;

  GameConfig get config =>
      GameConfig(mapId: mapId, mode: mode, difficulty: difficulty, profile: profile, seed: seed);
}

/// What a bot run produced.
class BotResult {
  const BotResult({
    required this.strategy,
    required this.wavesSent,
    required this.wavesCleared,
    required this.livesLeft,
    required this.kills,
    required this.cash,
    required this.spent,
    required this.ticks,
    required this.gameOver,
    required this.commands,
    required this.cashAtWave,
  });

  final BotStrategy strategy;

  /// Highest wave sent.
  final int wavesSent;

  /// Waves whose every creep has left the road (killed or through).
  final int wavesCleared;
  final int livesLeft;
  final int kills;
  final double cash;
  final double spent;
  final int ticks;
  final bool gameOver;

  /// Every command the bot sent, with the tick it was applied on.
  final List<ScheduledCommand> commands;

  /// Cash right after each wave was sent (index = wave − 1).
  final List<double> cashAtWave;

  Map<String, Object?> toJson() => {
    'bot': strategy.id,
    'wavesSent': wavesSent,
    'wavesCleared': wavesCleared,
    'livesLeft': livesLeft,
    'kills': kills,
    'cash': cash,
    'spent': spent,
    'ticks': ticks,
    'gameOver': gameOver,
  };

  /// The run as a replayable scenario (for regression fixtures).
  Scenario toScenario({required String id, required String description, int hashEvery = 600}) =>
      Scenario(
        id: id,
        description: description,
        mapId: strategy.mapId,
        mode: strategy.mode,
        difficulty: strategy.difficulty,
        profile: strategy.profile,
        seed: strategy.seed,
        ticks: ticks,
        hashEvery: hashEvery,
        commands: commands,
      );
}

/// Plays a [BotStrategy] headless through the sim, deterministically.
class BotRunner {
  BotRunner(this.data, {RulesRegistry? registry})
    : harness = SimTestHarness(data, registry: registry);

  final GameData data;
  final SimTestHarness harness;

  /// Plays until [untilWave] has been sent and cleared, the game is over, or
  /// [maxTicks] pass.
  BotResult run(BotStrategy strategy, {required int untilWave, int maxTicks = 1 << 22}) {
    final s = harness.session(strategy.config);
    final def = data.turrets[strategy.turret]!;
    final spots = buildSpots(s, def, strategy);
    final commands = <ScheduledCommand>[];
    final cashAtWave = <double>[];
    var nextSpot = 0;
    var cleared = 0;

    void send(GameCommand c) {
      s.enqueue(c);
      commands.add(ScheduledCommand(s.tick, c));
    }

    while (s.tick < maxTicks && !s.gameOver) {
      if (s.tick % strategy.decideEvery == 0) {
        if (s.turrets.length < strategy.maxTurrets && nextSpot < spots.length) {
          if (s.cash >= def.cost) {
            send(BuildTurret(def.id, spots[nextSpot].x, spots[nextSpot].y));
            nextSpot++;
          }
        } else {
          final upgrade = _upgrade(s, strategy);
          if (upgrade != null) send(upgrade);
        }
        if (strategy.sendEarly &&
            s.creeps.isEmpty &&
            s.waves.spawners.isEmpty &&
            s.waves.wave > 0 &&
            s.waves.wave < untilWave) {
          send(const SendNextWave());
        }
      }
      for (final e in s.step()) {
        if (e is WaveStarted) cashAtWave.add(s.cash);
      }
      cleared = _cleared(s);
      if (cleared >= untilWave) break;
    }
    return BotResult(
      strategy: strategy,
      wavesSent: s.waves.wave,
      wavesCleared: cleared,
      livesLeft: s.lives,
      kills: s.kills,
      cash: s.cash,
      spent: s.totalSpent,
      ticks: s.tick,
      gameOver: s.gameOver,
      commands: commands,
      cashAtWave: cashAtWave,
    );
  }

  /// The highest wave none of whose creeps is still to spawn or on the road.
  static int _cleared(GameSession s) {
    var lowest = s.waves.wave + 1;
    for (final c in s.creeps) {
      if (c.wave < lowest) lowest = c.wave;
    }
    for (final w in s.waves.spawners) {
      if (w.wave < lowest) lowest = w.wave;
    }
    return lowest - 1;
  }

  /// The cheapest affordable next upgrade following the strategy's order,
  /// over all turrets (oldest first on a tie).
  UpgradeTurret? _upgrade(GameSession s, BotStrategy strategy) {
    for (final name in strategy.upgradeOrder) {
      final stat = StatKind.values.byName(name);
      UpgradeTurret? best;
      var bestCost = double.infinity;
      for (final t in s.turrets) {
        final track = t.def.upgrades.track(stat);
        final level = t.level(stat);
        if (level >= track.length) continue;
        final cost = track[level].cost;
        if (cost < bestCost) {
          bestCost = cost;
          best = UpgradeTurret(t.uid, name);
        }
      }
      if (best != null) return bestCost <= s.cash ? best : null;
    }
    return null;
  }

  /// Build spots for [def] on the session's map: every valid grid point,
  /// ranked by how much road lies within the turret's base range (sampled
  /// every 4 px), picked greedily so chosen spots keep the turret spacing.
  static List<Vec2> buildSpots(GameSession s, TurretDef def, BotStrategy strategy) {
    final world = s.data.world;
    final roadSamples = <Vec2>[];
    for (var d = 0.0; d <= s.road.length; d += 4) {
      roadSamples.add(s.road.pointAt(d));
    }
    final range2 = def.stats.range * def.stats.range;
    final candidates = <(Vec2, int)>[];
    for (var y = strategy.gridStep; y < world.playHeight; y += strategy.gridStep) {
      for (var x = strategy.gridStep; x < world.playWidth; x += strategy.gridStep) {
        final p = Vec2(x, y);
        if (s.placementIssueAt(p) != null) continue;
        var cover = 0;
        for (final r in roadSamples) {
          if (r.distanceSquaredTo(p) <= range2) cover++;
        }
        candidates.add((p, cover));
      }
    }
    candidates.sort((a, b) {
      final c = b.$2.compareTo(a.$2);
      if (c != 0) return c;
      final dy = a.$1.y.compareTo(b.$1.y);
      return dy != 0 ? dy : a.$1.x.compareTo(b.$1.x);
    });
    final chosen = <Vec2>[];
    final spacing = world.placement.turretSpacing;
    for (final (p, _) in candidates) {
      if (chosen.every((q) => q.distanceTo(p) >= spacing)) chosen.add(p);
      if (chosen.length >= strategy.maxTurrets) break;
    }
    return chosen;
  }
}
