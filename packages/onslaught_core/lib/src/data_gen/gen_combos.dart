/// `combos.json` from the legacy table.
library;

import '../data/combo_recipe.dart';
import '../data/params.dart';
import 'legacy_table.dart';

/// `combos.json`: the projectile defaults a combo falls back to, the
/// recipes in leader-check order and the Combonly plate's options.
typedef GeneratedCombos = ({
  Params defaults,
  List<ComboRecipe> recipes,
  List<CombonlyOption> combonly,
});

/// Cluster blasts → the cluster kind a combo spawns.
const _clusterKinds = {'ClusterBlast': 'cluster-rockets', 'ClusterSpark': 'cluster-sparks'};

/// Projectiles the combo places rather than fires at its target: landmines
/// on a mine point within the leader's maximum range
/// (`Turret.as:comboFindMinepoints`), black holes on one within
/// `combo_hole_range` (`comboFindBlackHolePoints`).
const _placedAt = {'LandmineEngine': 'minePoint', 'BlackHole': 'holePoint'};

GeneratedCombos generateCombos(LegacyTable l) {
  final c = l['combos'];
  final data = obj(c['data']);
  final defaults = withoutSource(l.engine['projectileDefaults']);
  return (
    defaults: paramsOf({
      for (final e in defaults.entries)
        camel(e.key): e.key.endsWith('_type') ? projectileId(e.value! as String) : e.value,
    }),
    recipes: [for (final r in objects(c['recipes'])) _combo(l, r, obj(data[r['key']]))],
    // The Combonly plate's options, in scan order (last match per colour wins).
    combonly: [
      for (final r in objects(obj(c['combonly'])['scan']))
        CombonlyOption(
          colour: (r['colour']! as String).toLowerCase(),
          recipe: kebab(r['recipe']! as String),
          needs: _counts(r['needs']),
        ),
    ],
  );
}

ComboRecipe _combo(LegacyTable l, Map<String, Object?> r, Map<String, Object?> data) {
  final key = r['key']! as String;
  final title = l.modTitles['Combo_$key'] as String?;
  Set<String> camels(Object? v) => {for (final f in strings(v ?? const [])) camel(f)};
  return ComboRecipe(
    id: kebab(key),
    name: title == null ? key : title.substring(title.indexOf(': ') + 2),
    leader: turretIds['Turret${r['leader']}']!,
    priority: integer(r['priority']),
    requires: _counts(r['requires']),
    exact: {for (final c in listOf(r['exact'])) '$c'},
    takes: _counts(r['takes']),
    takesIfReady: r['takesIfReady'] == null
        ? const ComboRequirement({})
        : _counts(r['takesIfReady']),
    helperValue: r['helperValue'] as String?,
    helperColour: r['helperColour'] as String?,
    linkAddsTo: camels(r['linkAddsTo']),
    rawValues: camels(r['rawValues']),
    bulletFromLeader: r['bulletFromLeader'] == true,
    place: _placedAt[l.eng('projectileLinkages')[r['projectile']]],
    rechargeMs: number(data['recharge']),
    projectile: projectileId(r['projectile']! as String),
    blast: r['blast'] == null ? null : blastId(r['blast']! as String),
    cluster: _clusterKinds[r['cluster']],
    sound: r['sound'] == null ? null : eventId(r['sound']! as String),
    values: paramsOf({
      for (final e in data.entries)
        if (e.key != 'recharge') camel(e.key): e.value,
      if (r['clusterLaser'] == true) 'clusterLaser': true,
      if (r['holding'] == true) 'holdingCapable': true,
      if (r['subRockets'] == true) 'rocketCapable': true,
      if (r['laserType'] != null) 'laserType': projectileId(r['laserType']! as String),
      if (r['blastPoison'] != null) 'blastPoison': r['blastPoison'],
      if (r['blastDamageRaw'] == true) 'blastDamageRaw': true,
    }),
  );
}

ComboRequirement _counts(Object? m) =>
    ComboRequirement({for (final e in obj(m).entries) e.key: integer(e.value)});
