import '../data/game_data.dart';
import '../rules/rules_profile.dart';
import '../rules/rules_registry.dart';
import '../sim/game_command.dart';
import '../sim/game_config.dart';
import '../sim/game_event.dart';
import '../sim/game_session.dart';

/// A scripted, seeded scenario: what a scenario test runs and what a
/// regression fixture records.
class Scenario {
  const Scenario({
    required this.id,
    required this.description,
    required this.mapId,
    required this.ticks,
    this.mode = 'normal',
    this.difficulty = 'easy',
    this.profile = RulesProfile.classic,
    this.seed = 1,
    this.hashEvery = 60,
    this.commands = const [],
    this.challenge,
  });

  factory Scenario.fromJson(Map<String, Object?> j) => Scenario(
    id: j['id']! as String,
    description: j['description']! as String,
    mapId: j['map']! as String,
    mode: j['mode']! as String,
    difficulty: j['difficulty']! as String,
    profile: RulesProfile.byId(j['profile']! as String),
    seed: (j['seed']! as num).toInt(),
    ticks: (j['ticks']! as num).toInt(),
    hashEvery: (j['hashEvery']! as num).toInt(),
    challenge: j['challenge'] as String?,
    commands: [
      for (final c in j['commands']! as List<Object?>)
        ScheduledCommand.fromJson((c! as Map).cast<String, Object?>()),
    ],
  );

  final String id;
  final String description;
  final String mapId;
  final String mode;
  final String difficulty;
  final RulesProfile profile;
  final int seed;

  /// Steps to run.
  final int ticks;

  /// Record a state hash every this many steps (and after the last).
  final int hashEvery;
  final List<ScheduledCommand> commands;

  /// A `challenges.json` preset id the game plays (mode `challenge`), or null.
  final String? challenge;

  GameConfig get config =>
      GameConfig(mapId: mapId, mode: mode, difficulty: difficulty, profile: profile, seed: seed);

  /// [config] for [data]: with [challenge] resolved to its preset.
  GameConfig configFor(GameData data) {
    final id = challenge;
    if (id == null) return config;
    final preset = data.challenges.presets.where((p) => p.id == id).firstOrNull;
    if (preset == null) throw ArgumentError.value(id, 'challenge', 'unknown preset');
    return GameConfig(
      mapId: mapId,
      mode: mode,
      difficulty: preset.difficulty,
      profile: profile,
      seed: seed,
      challenge: preset,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'description': description,
    'map': mapId,
    'mode': mode,
    'difficulty': difficulty,
    'profile': profile.id,
    'seed': seed,
    'ticks': ticks,
    'hashEvery': hashEvery,
    'challenge': ?challenge,
    'commands': [for (final c in commands) c.toJson()],
  };
}

/// Builds sessions from data + seed, feeds scheduled commands and collects
/// events, so scenario tests read as "given this, after N ticks, expect that".
class SimTestHarness {
  SimTestHarness(this.data, {RulesRegistry? registry, this.systems})
    : registry = registry ?? RulesRegistry.classic();

  final GameData data;
  final RulesRegistry registry;

  /// Systems every session runs; null = the classic systems.
  final List<SimSystem>? systems;

  /// A fresh session for [config].
  GameSession session(GameConfig config) =>
      GameSession(data: data, config: config, registry: registry, systems: systems);

  /// Runs [scenario]; [onTick] sees the session after every step.
  ScenarioRun run(
    Scenario scenario, {
    void Function(GameSession s, List<GameEvent> stepEvents)? onTick,
  }) {
    final s = session(scenario.configFor(data));
    final byTick = <int, List<GameCommand>>{};
    for (final c in scenario.commands) {
      byTick.putIfAbsent(c.tick, () => []).add(c.command);
    }
    final events = <GameEvent>[];
    final hashes = <StateHash>[];
    for (var t = 0; t < scenario.ticks; t++) {
      byTick[t]?.forEach(s.enqueue);
      final stepEvents = s.step();
      events.addAll(stepEvents);
      onTick?.call(s, stepEvents);
      final done = t + 1;
      if (done % scenario.hashEvery == 0 || done == scenario.ticks) {
        hashes.add(StateHash(done, s.stateHash()));
      }
    }
    return ScenarioRun(s, events, hashes);
  }
}

/// A state hash after [tick] steps.
class StateHash {
  const StateHash(this.tick, this.hash);

  factory StateHash.fromJson(Map<String, Object?> j) =>
      StateHash((j['tick']! as num).toInt(), (j['hash']! as num).toInt());

  final int tick;
  final int hash;

  Map<String, Object?> toJson() => {'tick': tick, 'hash': hash};

  @override
  bool operator ==(Object other) => other is StateHash && other.tick == tick && other.hash == hash;

  @override
  int get hashCode => Object.hash(tick, hash);
}

/// The outcome of running a scenario.
class ScenarioRun {
  const ScenarioRun(this.session, this.events, this.hashes);
  final GameSession session;
  final List<GameEvent> events;
  final List<StateHash> hashes;

  Iterable<T> eventsOf<T extends GameEvent>() => events.whereType<T>();
}
