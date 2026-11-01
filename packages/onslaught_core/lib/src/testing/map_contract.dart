import '../data/game_data.dart';
import '../data/map_definition.dart';
import '../rules/map_rules.dart';
import '../rules/rules_registry.dart';
import '../sim/game_command.dart';
import '../sim/game_config.dart';
import '../sim/game_event.dart';
import '../sim/game_session.dart';

/// The contract every map must meet, whoever made it (a built-in, the
/// editor, an import or a `MapGenerator`): it validates ([validateMap]) and
/// a game on it runs, with the first creep walking the road to the base.
/// Returns the reasons it fails; empty = it passes.
List<String> checkMapContract(
  GameData data,
  MapDefinition map, {
  RulesRegistry? registry,
  int maxSteps = 60 * 600,
}) {
  final problems = [for (final p in validateMap(map, data.world)) 'invalid: ${p.name}'];
  if (problems.isNotEmpty) return problems;
  final GameSession session;
  try {
    session = GameSession(
      data: data,
      config: GameConfig.custom(map: map),
      registry: registry,
    );
  } on Object catch (e) {
    return ['session: $e'];
  }
  session.enqueue(const SendNextWave());
  for (var i = 0; i < maxSteps; i++) {
    if (session.step().any((e) => e is BaseHit)) return const [];
  }
  return ['no creep reached the base in $maxSteps steps'];
}
