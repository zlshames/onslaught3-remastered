/// The committed legacy reference table (`docs/legacy/legacy_values.json`)
/// as the generator reads it, the remaster's naming of legacy ids (turret,
/// projectile, blast and sound ids), and the remaster's own constants that
/// the generated documents carry beside the legacy values.
library;

import '../data/params.dart';
import '../math/vec2.dart';

// ------------------------------------------------------- remaster choices

/// Remaster choice, not a legacy value: the simulation runs at 60 Hz
/// (`docs/REMASTER_PLAN.md` §2.1 and open decision 4).
const int simulationTickHz = 60;

/// Remaster choice for `RulesProfile.holdingRocketLifetime` (`docs/DEVIATIONS.md`):
/// a rocket orbiting with no target is removed after this long. The original
/// has no lifetime, and no shipped profile turns the toggle on.
const int holdingRocketLifetimeMs = 20000;

/// Remaster choice for the map editor's validation (`docs/REMASTER_PLAN.md`
/// Phase 6: start, base and a minimum length; `docs/DEVIATIONS.md`): the
/// shortest road, in px, a map may be saved with. The original only checks
/// that the start and the base are on the map.
const int mapMinRoadLength = 100;

/// Remaster choice: the longest map name the editor accepts (the original's
/// text field has no limit).
const int mapMaxNameLength = 32;

/// The stage a rocket is removed outside of (`RocketEngine.update`: `x < −width`,
/// `x > game_screen_x + width`, …): `GameStatus.game_screen_x/y` 720 × 535 and
/// the rocket clip's width (sprite 712 + body, about 20 px; the original uses
/// the rotated clip's bounds, here the unrotated width).
const Map<String, int> rocketOffscreen = {
  'screenWidth': 720,
  'screenHeight': 535,
  'offscreenMargin': 20,
};

// ------------------------------------------------------------ the table

/// The legacy table's sections the generators read.
class LegacyTable {
  LegacyTable(this.root)
    : engine = obj(root['engine']),
      turrets = obj(root['turrets']),
      modTitles = obj(obj(root['modEditor'])['itemTitles']);

  /// The whole decoded table.
  final Map<String, Object?> root;

  /// `engine`: the hand-transcribed engine constants
  /// (`tool/legacy_extract/engine_constants.dart`).
  final Map<String, Object?> engine;

  /// `turrets`: turret class → `{values, cost, unlockKills, …}`.
  final Map<String, Object?> turrets;

  /// The original mod editor's item titles (`Turret: Blue Cannon`), by item.
  final Map<String, Object?> modTitles;

  /// The top-level section [name].
  Map<String, Object?> operator [](String name) => obj(root[name]);

  /// The section [name] of `engine`.
  Map<String, Object?> eng(String name) => obj(engine[name]);
}

// ------------------------------------------------------ reading values

/// [v] as a JSON object (throws when it is not one).
Map<String, Object?> obj(Object? v) => (v! as Map).cast<String, Object?>();

/// [v] as a list, or empty when it is not one.
List<Object?> listOf(Object? v) => v is List ? v : const [];

/// [v] as a list of JSON objects.
List<Map<String, Object?>> objects(Object? v) => (v! as List<Object?>).cast<Map<String, Object?>>();

/// [v] as a list of strings.
List<String> strings(Object? v) => (v! as List<Object?>).cast<String>();

/// [v], a JSON number, as a double.
double number(Object? v) => (v! as num).toDouble();

/// [v] as a double, or null.
double? optNumber(Object? v) => v == null ? null : number(v);

/// [v], a whole JSON number, as an int.
int integer(Object? v) => (v! as num).toInt();

/// [v] as an int, or null.
int? optInteger(Object? v) => v == null ? null : integer(v);

/// `"#B2885B"` → 0xB2885B.
int rgb(Object? v) => int.parse((v! as String).substring(1), radix: 16);

/// `[x, y]` → a point.
Vec2 pointFromList(Object? v) {
  final a = listOf(v);
  return Vec2(number(a[0]), number(a[1]));
}

/// `{x, y}` → a point.
Vec2 pointFromObject(Object? v) {
  final m = obj(v);
  return Vec2(number(m['x']), number(m['y']));
}

/// A legacy parameter object as [Params], read the way `Params.fromJson`
/// reads it (numbers as doubles, number lists as `List<double>`), so a
/// generated record equals the one read back from its JSON.
Params paramsOf(Map<String, Object?> m) => Params(
  Map.unmodifiable({
    for (final e in m.entries)
      e.key: switch (e.value) {
        final num n => n.toDouble(),
        final List<Object?> l => List<double>.unmodifiable([for (final n in l) number(n)]),
        final Object v => v,
        null => throw StateError('parameter ${e.key} is null'),
      },
  }),
);

/// [v] without its `source` citation (an empty object when null).
Map<String, Object?> withoutSource(Object? v) {
  if (v == null) return const {};
  return {...obj(v)}..remove('source');
}

// ------------------------------------------------------------- naming

/// `big_laser_clusterbomb` → `bigLaserClusterbomb`.
String camel(String s) {
  final parts = s.split('_');
  return parts.first +
      parts.skip(1).map((p) => p.isEmpty ? '' : p[0].toUpperCase() + p.substring(1)).join();
}

/// `big_laser_clusterbomb` → `big-laser-clusterbomb`; `LandmineBig` →
/// `landmine-big`; `BaseWarn3` → `base-warn-3`; `Problem3` → `problem-3`.
String kebab(String s) => s
    .replaceAll('_', '-')
    .replaceAllMapped(RegExp(r'([a-z])([A-Z0-9])'), (m) => '${m[1]}-${m[2]}')
    .replaceAllMapped(RegExp(r'([A-Z])([A-Z][a-z])'), (m) => '${m[1]}-${m[2]}')
    .toLowerCase();

/// Turret class → turret id.
const turretIds = {
  'TurretBlue': 'blue',
  'TurretGreen': 'green',
  'TurretRed': 'red',
  'TurretYellow': 'yellow',
  'TurretRangeUp': 'range-up',
  'TurretDamageUp': 'damage-up',
  'TurretRateUpExchange': 'rate-up-exchange',
  'TurretRangeUpExchange': 'range-up-exchange',
  'TurretRateUp': 'rate-up',
  'TurretDamageUpBig': 'damage-up-big',
  'TurretDamageUpBigExchange': 'damage-up-big-exchange',
  'TurretTargeter': 'targeter',
  'TurretSniper': 'sniper',
  'TurretFusion': 'fusion',
  'TurretRailgun': 'railgun',
  'TurretCombonly': 'combonly',
};

/// The four colour turrets, in colour order.
const basicColours = {'TurretBlue', 'TurretGreen', 'TurretRed', 'TurretYellow'};

/// The colour turrets' ids.
final basicColourIds = [for (final c in basicColours) turretIds[c]!];

/// The super turrets.
const superTurrets = {'TurretSniper', 'TurretFusion', 'TurretRailgun'};

/// Difficulty id → its English name.
const difficultyNames = {'easy': 'Easy', 'medium': 'Medium', 'hard': 'Hard', 'extreme': 'Extreme'};

/// `Bullet` → `shell-1`, `Rocket3` → `rocket-3`, `BulletSniper` →
/// `sniper-shot`, other linkages in kebab-case.
String projectileId(String linkage) {
  if (linkage == 'BulletSniper') return 'sniper-shot';
  final shell = RegExp(r'^Bullet(\d?)$').firstMatch(linkage);
  if (shell != null) return 'shell-${shell.group(1)!.isEmpty ? 1 : shell.group(1)}';
  final rocket = RegExp(r'^Rocket(\d?)$').firstMatch(linkage);
  if (rocket != null) return 'rocket-${rocket.group(1)!.isEmpty ? 1 : rocket.group(1)}';
  return kebab(linkage);
}

/// A legacy blast name → blast id.
String blastId(String legacy) => switch (legacy) {
  'tiny' => 'blast-tiny',
  'ClusterBlast' => 'cluster-rockets',
  'ClusterSpark' => 'cluster-sparks',
  _ => kebab(legacy),
};

/// `FreakoutWarn` → `freakout-warn`, `BaseWarn3` → `base-warn-3`.
String eventId(String name) => kebab(name);

/// The audio clip id for an exported legacy sound file:
/// `976_ONS2_cannon_2shrt.aif.mp3` → `sfx.ons2-cannon-2shrt`. Shared with the
/// asset export so the data and the asset pack agree.
String legacyClipId(String file) {
  final stem = file
      .replaceFirst(RegExp(r'^\d+_'), '')
      .replaceFirst(RegExp(r'\.aif\.mp3$'), '')
      .toLowerCase()
      .replaceAll('_', '-');
  return 'sfx.$stem';
}
