import 'package:meta/meta.dart';

import 'json_reader.dart';
import 'params.dart';

/// Helper turrets a combo needs besides its leader, by colour turret id.
@immutable
class ComboRequirement {
  const ComboRequirement(this.counts);

  factory ComboRequirement.fromJson(JsonReader r) {
    final counts = r.asMapOf((c) => c.asInt(min: 0));
    return ComboRequirement(Map.unmodifiable(counts));
  }

  /// Turret id → number of helpers of that colour.
  final Map<String, int> counts;

  int get total => counts.values.fold(0, (a, b) => a + b);

  Map<String, Object?> toJson() => counts;
}

/// One option the Combonly plate can offer (`combos.json` `combonly`,
/// `TurretCombonly.as:comboScan`): when the combo-capable turrets around it
/// meet [needs], the plate can become a dedicated [recipe] weapon of
/// [colour], consuming those turrets.
@immutable
class CombonlyOption {
  const CombonlyOption({required this.colour, required this.recipe, required this.needs});

  factory CombonlyOption.fromJson(JsonReader r) {
    r.expectOnlyKeys({'colour', 'recipe', 'needs'});
    return CombonlyOption(
      colour: r.string('colour'),
      recipe: r.string('recipe'),
      needs: ComboRequirement.fromJson(r.child('needs')),
    );
  }

  /// Colour turret id the plate turns into (its weapon and glow).
  final String colour;

  /// Combo id it then fires.
  final String recipe;

  /// Turrets it consumes by colour, one of [colour] included.
  final ComboRequirement needs;

  Map<String, Object?> toJson() => {'colour': colour, 'recipe': recipe, 'needs': needs.toJson()};
}

/// A combo recipe from `combos.json`.
@immutable
class ComboRecipe {
  const ComboRecipe({
    required this.id,
    required this.name,
    required this.leader,
    required this.priority,
    required this.requires,
    required this.exact,
    required this.takes,
    required this.takesIfReady,
    required this.helperValue,
    required this.helperColour,
    required this.linkAddsTo,
    required this.rawValues,
    required this.bulletFromLeader,
    required this.place,
    required this.rechargeMs,
    required this.projectile,
    required this.blast,
    required this.cluster,
    required this.sound,
    required this.values,
  });

  factory ComboRecipe.fromJson(JsonReader r) {
    r.expectOnlyKeys({
      'id',
      'name',
      'leader',
      'priority',
      'requires',
      'exact',
      'takes',
      'takesIfReady',
      'helperValue',
      'helperColour',
      'linkAddsTo',
      'rawValues',
      'bulletFromLeader',
      'place',
      'rechargeMs',
      'projectile',
      'blast',
      'cluster',
      'sound',
      'values',
    });
    return ComboRecipe(
      id: r.string('id'),
      name: r.string('name'),
      leader: r.string('leader'),
      priority: r.integer('priority', min: 0),
      requires: ComboRequirement.fromJson(r.child('requires')),
      exact: Set.unmodifiable(r.optList('exact', (c) => c.asString())),
      takes: ComboRequirement.fromJson(r.child('takes')),
      takesIfReady: r.has('takesIfReady')
          ? ComboRequirement.fromJson(r.child('takesIfReady'))
          : const ComboRequirement({}),
      helperValue: r.has('helperValue')
          ? r.oneOf('helperValue', {'link', 'poison', 'ownLink', 'ownPoison'}, fallback: 'link')
          : null,
      helperColour: r.optString('helperColour'),
      linkAddsTo: Set.unmodifiable(r.optList('linkAddsTo', (c) => c.asString())),
      rawValues: Set.unmodifiable(r.optList('rawValues', (c) => c.asString())),
      bulletFromLeader: r.optBoolean('bulletFromLeader', fallback: false),
      place: r.has('place')
          ? r.oneOf('place', {'minePoint', 'holePoint'}, fallback: 'minePoint')
          : null,
      rechargeMs: r.number('rechargeMs', min: 0),
      projectile: r.optString('projectile'),
      blast: r.optString('blast'),
      cluster: r.optString('cluster'),
      sound: r.optString('sound'),
      values: Params.fromJson(r.child('values')),
    );
  }

  /// Stable id, the original `Combos` key in kebab-case (`big-clusterbomb`).
  final String id;
  final String name;

  /// Turret id of the leader colour whose `comboFire` checks this recipe.
  final String leader;

  /// Order in which the leader checks its recipes (0 = first).
  final int priority;

  /// Helpers needed besides the leader (at least this many of each colour).
  final ComboRequirement requires;

  /// Colours whose count must match [requires] exactly (Yellow recipes).
  final Set<String> exact;

  /// Helpers the combo takes (puts on recharge); may differ from [requires].
  final ComboRequirement takes;

  /// Helpers taken only if one happens to be ready.
  final ComboRequirement takesIfReady;

  /// How a helper adds value: `link` (a green helper's link pool is added
  /// to the damage), `poison` (a yellow helper's poison is used), `ownLink`
  /// (the leader's own link pool), `ownPoison` (the leader's poison).
  final String? helperValue;

  /// Colour turret id of the helper a `link` or `poison` value is taken
  /// from.
  final String? helperColour;

  /// `values` fields the helper value (a link pool) is added to before the
  /// leader's damage modifiers are applied.
  final Set<String> linkAddsTo;

  /// `values` damage fields used as they are, without the leader's damage
  /// modifiers.
  final Set<String> rawValues;

  /// The projectile hits with the leader's effective damage instead of
  /// `bulletDamage` (napalm).
  final bool bulletFromLeader;

  /// Where a placed projectile goes instead of being fired at the target:
  /// `minePoint` (a road mine point within the leader's maximum range) or
  /// `holePoint` (one within `rules.json` `blackHolePointRange`).
  final String? place;

  /// Time before the helpers used can combo again.
  final double rechargeMs;

  /// Projectile id spawned by the leader (null for in-place effects).
  final String? projectile;

  /// Blast id applied on impact.
  final String? blast;

  /// Cluster kind spawned on impact (`rockets`, `sparks`).
  final String? cluster;

  /// Audio event id.
  final String? sound;

  /// The original combo data fields (bullet/cluster/blast damage, poison,
  /// laser, napalm, black-hole …) in camelCase; overrides for the projectile.
  final Params values;

  /// The `combos.json` record; optional fields only when set.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'leader': leader,
    'priority': priority,
    'requires': requires.toJson(),
    if (exact.isNotEmpty) 'exact': exact.toList(),
    'takes': takes.toJson(),
    if (takesIfReady.counts.isNotEmpty) 'takesIfReady': takesIfReady.toJson(),
    'helperValue': ?helperValue,
    'helperColour': ?helperColour,
    if (linkAddsTo.isNotEmpty) 'linkAddsTo': linkAddsTo.toList(),
    if (rawValues.isNotEmpty) 'rawValues': rawValues.toList(),
    if (bulletFromLeader) 'bulletFromLeader': true,
    'place': ?place,
    'rechargeMs': jsonNumber(rechargeMs),
    'projectile': ?projectile,
    'blast': ?blast,
    'cluster': ?cluster,
    'sound': ?sound,
    'values': values.toJson(),
  };
}
