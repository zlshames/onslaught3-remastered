import 'package:collection/collection.dart';

import 'game_data.dart';
import 'json_reader.dart';
import 'mod_editor_defs.dart';
import 'params.dart';
import 'turret_def.dart';

/// Cross-file checks that single-document parsing cannot do: every id that is
/// referred to exists, maps lie inside the play area, upgrade tracks are
/// monotonic, combo recipes are well-formed (and name the blasts,
/// projectiles, colours and values the rules look up with `!`), and (when
/// [behaviours] is given) every behaviour id is registered in the rules
/// layer.
List<DataIssue> validateGameData(GameData d, {KnownBehaviours? behaviours}) {
  final sink = IssueSink();

  final colours = {
    for (final t in d.turrets.values)
      if (t.category == TurretCategory.basic) t.id,
  };
  final modes = d.targeting.modes.toSet();
  final difficulties = {for (final l in d.difficulty.levels) l.id};

  // Turrets.
  var i = 0;
  for (final t in d.turrets.values) {
    final at = 'turrets.json:/turrets/$i';
    for (final p in t.projectiles) {
      if (!d.projectiles.containsKey(p)) {
        sink.add('$at/projectiles', 'unknown projectile "$p"');
      }
    }
    final mode = t.defaultTargetMode;
    if (mode != null && !modes.contains(mode)) {
      sink.add('$at/targeting/defaultMode', 'unknown target mode "$mode"');
    }
    if (t.category == TurretCategory.modifier && t.modifierAura == null) {
      sink.add(at, 'modifier turrets need a modifierAura');
    }
    for (final s in StatKind.values) {
      _checkTrack(sink, '$at/upgrades/${s.name}', t.upgrades.track(s));
    }
    for (final s in t.specialParams.keys) {
      if (!t.specials.contains(s)) {
        sink.add('$at/specialParams/$s', 'parameters for a special the turret does not have');
      }
    }
    if (behaviours != null) {
      for (final s in t.specials) {
        if (!behaviours.turretSpecialIds.contains(s)) {
          sink.add('$at/specials', 'special "$s" is not registered in RulesRegistry');
        }
      }
    }
    if (t.art.base.isEmpty) sink.add('$at/art/base', 'must not be empty');
    i++;
  }

  // Combos.
  i = 0;
  final priorities = <String, Set<int>>{};
  for (final c in d.combos.values) {
    final at = 'combos.json:/combos/$i';
    if (!colours.contains(c.leader)) {
      sink.add('$at/leader', 'leader must be a basic colour turret (was "${c.leader}")');
    }
    if (!priorities.putIfAbsent(c.leader, () => {}).add(c.priority)) {
      sink.add('$at/priority', 'duplicate priority ${c.priority} for leader "${c.leader}"');
    }
    for (final colour in c.requires.counts.keys) {
      if (!colours.contains(colour)) {
        sink.add('$at/requires/$colour', 'not a basic colour turret');
      }
    }
    if (c.requires.total == 0) sink.add('$at/requires', 'needs at least one helper');
    final p = c.projectile;
    if (p != null && !d.projectiles.containsKey(p)) {
      sink.add('$at/projectile', 'unknown projectile "$p"');
    }
    final b = c.blast;
    if (b != null && !d.blasts.containsKey(b)) {
      sink.add('$at/blast', 'unknown blast "$b"');
    }
    // The cluster is spawned as a blast (`spawnBlast` via the ordnance).
    final cluster = c.cluster;
    if (cluster != null && !d.blasts.containsKey(cluster)) {
      sink.add('$at/cluster', 'unknown blast "$cluster"');
    }
    final laser = _paramString(c.values, 'laserType');
    if (laser != null && !d.projectiles.containsKey(laser)) {
      sink.add('$at/values/laserType', 'unknown projectile "$laser"');
    }
    // The helper a value is taken from, and the exact counts, are colours
    // the recipe requires.
    bool required(String colour) =>
        colours.contains(colour) && c.requires.counts.containsKey(colour);
    final helper = c.helperColour;
    if (helper != null && !required(helper)) {
      sink.add(
        '$at/helperColour',
        'must be a basic colour turret the recipe requires (was "$helper")',
      );
    }
    var j = 0;
    for (final colour in c.exact) {
      if (!required(colour)) {
        sink.add(
          '$at/exact/$j',
          'must be a basic colour turret the recipe requires (was "$colour")',
        );
      }
      j++;
    }
    for (final (key, fields) in [('linkAddsTo', c.linkAddsTo), ('rawValues', c.rawValues)]) {
      j = 0;
      for (final field in fields) {
        if (!c.values.has(field)) sink.add('$at/$key/$j', 'not a key of values ("$field")');
        j++;
      }
    }
    i++;
  }
  for (final key in ['laserType', 'rocketType']) {
    final id = _paramString(d.comboDefaults, key);
    if (id != null && !d.projectiles.containsKey(id)) {
      sink.add('combos.json:/defaults/$key', 'unknown projectile "$id"');
    }
  }

  // Projectiles and blasts.
  if (behaviours != null) {
    i = 0;
    for (final p in d.projectiles.values) {
      if (!behaviours.projectileKindIds.contains(p.kind)) {
        sink.add(
          'projectiles.json:/projectiles/$i/kind',
          'projectile kind "${p.kind}" is not registered in RulesRegistry',
        );
      }
      i++;
    }
    i = 0;
    for (final b in d.blasts.values) {
      if (!behaviours.blastKindIds.contains(b.kind)) {
        sink.add(
          'blasts.json:/blasts/$i/kind',
          'blast kind "${b.kind}" is not registered in RulesRegistry',
        );
      }
      i++;
    }
  }
  i = 0;
  for (final p in d.projectiles.values) {
    for (final key in ['blast', 'childProjectile']) {
      final ref = p.params.string(key);
      if (ref == null) continue;
      final table = key == 'blast' ? d.blasts : d.projectiles;
      if (!table.containsKey(ref)) {
        sink.add('projectiles.json:/projectiles/$i/params/$key', 'unknown id "$ref"');
      }
    }
    i++;
  }
  i = 0;
  for (final b in d.blasts.values) {
    final drop = b.params.string('dropBlast');
    if (drop != null && !d.blasts.containsKey(drop)) {
      sink.add('blasts.json:/blasts/$i/params/dropBlast', 'unknown blast "$drop"');
    }
    i++;
  }

  // Difficulty schedules ascend and start at wave 1.
  i = 0;
  for (final l in d.difficulty.levels) {
    final at = 'difficulty.json:/levels/$i/hpSchedule';
    if (l.hpSchedule.isNotEmpty && l.hpSchedule.first.wave != 1) {
      sink.add('$at/0/wave', 'the schedule must start at wave 1');
    }
    for (var j = 1; j < l.hpSchedule.length; j++) {
      if (l.hpSchedule[j].wave <= l.hpSchedule[j - 1].wave) {
        sink.add('$at/$j/wave', 'waves must be strictly ascending');
      }
    }
    i++;
  }

  // Maps lie inside the play area and have no zero-length road.
  for (final m in d.maps.values) {
    final at = 'maps/${m.id}.json:';
    if (!d.world.contains(m.base.x, m.base.y)) {
      sink.add('$at/base', 'base ${m.base} is outside the play area');
    }
    for (var j = 0; j < m.road.length; j++) {
      final p = m.road[j];
      if (!d.world.contains(p.x, p.y)) {
        sink.add('$at/road/$j', 'point $p is outside the play area');
      }
    }
    final length = [for (var j = 1; j < m.road.length; j++) m.road[j].distanceTo(m.road[j - 1])]
        .fold<double>(0, (a, b) => a + b);
    if (length <= 0) sink.add('$at/road', 'road has zero length');
  }
  // The editor's areas lie inside the play area.
  final ed = d.world.editor;
  for (final (key, a) in [
    ('startArea', ed.startArea),
    ('baseArea', ed.baseArea),
    ('waypointArea', ed.waypointArea),
  ]) {
    if (!d.world.contains(a.x, a.y) || !d.world.contains(a.right, a.bottom)) {
      sink.add('world.json:/editor/$key', 'area is outside the play area');
    }
  }
  if (!d.maps.containsKey(d.tutorial.map)) {
    sink.add('tutorial.json:/map', 'unknown map "${d.tutorial.map}"');
  }

  // The attract demo: known difficulty, known turrets on the stage. Its road
  // may run off the stage (the original's last waypoint lies just below it,
  // so creeps walk off-screen).
  final attract = d.attract;
  if (attract != null) {
    if (!difficulties.contains(attract.difficulty)) {
      sink.add('attract.json:/difficulty', 'unknown difficulty "${attract.difficulty}"');
    }
    // `spawnCreep` picks a creep type by index below this.
    final types = d.creeps.types.length;
    if (attract.creepTypes > types) {
      sink.add(
        'attract.json:/creepTypes',
        'must be at most the $types creep types (was ${attract.creepTypes})',
      );
    }
    for (var j = 0; j < attract.turrets.length; j++) {
      final t = attract.turrets[j];
      if (!d.turrets.containsKey(t.turret)) {
        sink.add('attract.json:/turrets/$j/turret', 'unknown turret "${t.turret}"');
      }
      if (t.x < 0 || t.y < 0 || t.x > attract.stageWidth || t.y > attract.stageHeight) {
        sink.add('attract.json:/turrets/$j', 'turret (${t.x}, ${t.y}) is outside the stage');
      }
    }
  }

  // Challenges.
  i = 0;
  for (final c in d.challenges.presets) {
    if (!difficulties.contains(c.difficulty)) {
      sink.add('challenges.json:/presets/$i/difficulty', 'unknown difficulty "${c.difficulty}"');
    }
    i++;
  }
  for (final e in d.challenges.classicPickers.keys) {
    if (!d.challenges.pickers.containsKey(e)) {
      sink.add('challenges.json:/classicPickers/$e', 'no corrected picker "$e"');
    }
  }

  // Combonly options.
  i = 0;
  for (final o in d.combonly) {
    final at = 'combos.json:/combonly/$i';
    final recipe = d.combos[o.recipe];
    if (recipe == null) {
      sink.add('$at/recipe', 'unknown combo "${o.recipe}"');
    } else if (recipe.leader != o.colour) {
      sink.add('$at/colour', 'must be the leader of "${o.recipe}" (${recipe.leader})');
    }
    for (final colour in o.needs.counts.keys) {
      if (!colours.contains(colour)) sink.add('$at/needs/$colour', 'not a basic colour turret');
    }
    if ((o.needs.counts[o.colour] ?? 0) < 1) {
      sink.add('$at/needs', 'must include a turret of its own colour');
    }
    i++;
  }
  // Progression.
  final modeSet = d.progression.modes.toSet();
  i = 0;
  for (final u in d.progression.unlocks) {
    final at = 'progression.json:/unlocks/$i';
    if (!modeSet.contains(u.mode)) sink.add('$at/mode', 'unknown mode "${u.mode}"');
    for (final diff in u.difficulties) {
      if (!difficulties.contains(diff)) {
        sink.add('$at/difficulties', 'unknown difficulty "$diff"');
      }
    }
    if (u.rule == 'killsOnAnyDifficulty' && u.kills == null) {
      sink.add('$at/kills', 'is required for rule killsOnAnyDifficulty');
    }
    if (u.rule == 'completeAll' && u.difficulties.isEmpty) {
      sink.add('$at/difficulties', 'is required for rule completeAll');
    }
    i++;
  }
  for (final mode in d.difficulty.modeCash.keys) {
    if (!modeSet.contains(mode)) {
      sink.add('difficulty.json:/modeCash/$mode', 'unknown mode "$mode"');
    }
  }
  for (final e in d.difficulty.modeRacks.entries) {
    if (!modeSet.contains(e.key)) {
      sink.add('difficulty.json:/modeRacks/${e.key}', 'unknown mode "${e.key}"');
    }
    for (final id in e.value) {
      if (!d.turrets.containsKey(id)) {
        sink.add('difficulty.json:/modeRacks/${e.key}', 'unknown turret "$id"');
      }
    }
  }

  // Audio: every event referenced by turrets/combos is defined.
  for (final e in d.referencedAudioEvents) {
    if (!d.audio.events.containsKey(e)) {
      sink.add('audio.json:/events', 'missing event "$e" referenced by data');
    }
  }

  // Mod editor: every value it offers exists, has the declared type and a
  // descriptor (so the editor never shows a value the game does not use).
  for (var n = 0; n < d.modEditor.items.length; n++) {
    final item = d.modEditor.items[n];
    for (var k = 0; k < item.fields.length; k++) {
      final f = item.fields[k];
      final at = 'mod_editor.json:/items/$n/fields/$k';
      if (!d.descriptors.byAsset.containsKey(f.asset)) {
        sink.add(at, 'no descriptor for "${f.asset}"');
      }
      final r = resolveDataPath(d.documents[f.file], f.path);
      if (!r.found) {
        sink.add(at, 'no value at ${f.file}:/${f.path.join('/')}');
      } else if (!_hasModType(r.value, f)) {
        sink.add(at, '${f.file}:/${f.path.join('/')} is not a ${f.type.name}');
      }
    }
  }

  // Strings: English is required.
  if (!d.strings.containsKey('en')) sink.add('strings/en.json:', 'missing English strings');
  // Translations: only English keys, with the same `{placeholders}` (a
  // missing key falls back to English).
  final english = d.strings['en']?.strings ?? const <String, String>{};
  Set<String> slots(String s) => {for (final m in RegExp(r'\{(\w+)\}').allMatches(s)) m[1]!};
  for (final t in d.strings.values) {
    if (t.locale == 'en') continue;
    for (final e in t.strings.entries) {
      final at = 'strings/${t.locale}.json:/strings/${e.key}';
      final en = english[e.key];
      if (en == null) {
        sink.add(at, 'no English string has this key');
      } else if (!const SetEquality<String>().equals(slots(en), slots(e.value))) {
        sink.add(at, 'placeholders ${slots(e.value)} differ from English ${slots(en)}');
      }
    }
  }

  return sink.issues;
}

/// [key] of [p] when it is a string (a wrong type is reported where the
/// parameters are read), else null.
String? _paramString(Params p, String key) => switch (p.toJson()[key]) {
  final String v => v,
  _ => null,
};

void _checkTrack(IssueSink sink, String at, List<UpgradeStep> track) {
  for (var j = 0; j < track.length; j++) {
    if (track[j].cost <= 0) sink.add('$at/$j/cost', 'must be positive');
    if (j > 0 && track[j].value < track[j - 1].value) {
      sink.add('$at/$j/value', 'upgrade values must not decrease');
    }
  }
}

bool _hasModType(Object? v, ModFieldDef f) => switch (f.type) {
  ModValueType.number => v is num,
  ModValueType.integer => v is int,
  ModValueType.boolean => v is bool,
  ModValueType.string => v is String,
  ModValueType.arrayIndexed =>
    v is List && v.every((e) => e is Map && e[f.keyField] is num && e[f.valueField] is num),
};
