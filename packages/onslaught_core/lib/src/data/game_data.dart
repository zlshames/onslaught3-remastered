import 'dart:convert';

import 'package:meta/meta.dart';

import 'attract_defs.dart';
import 'audio_defs.dart';
import 'challenge_defs.dart';
import 'combo_recipe.dart';
import 'creep_wave_defs.dart';
import 'descriptor_defs.dart';
import 'game_data_validator.dart';
import 'json_reader.dart';
import 'map_definition.dart';
import 'mod_delta.dart';
import 'mod_editor_defs.dart';
import 'ordnance_defs.dart';
import 'params.dart';
import 'progression_defs.dart';
import 'rules_constants.dart';
import 'string_table.dart';
import 'targeting_defs.dart';
import 'turret_def.dart';
import 'tutorial_defs.dart';
import 'world_def.dart';

/// Where data documents come from. The app reads the Flutter asset bundle,
/// tests read the file system, mods/content packs read memory. Core never
/// touches files itself (tenet 3).
abstract interface class DataSource {
  /// The text of the document at [path] (relative to the data root, e.g.
  /// `turrets.json`, `maps/map1.json`).
  Future<String> read(String path);
}

/// A [DataSource] over in-memory documents (tests, mods, share strings).
class MemoryDataSource implements DataSource {
  MemoryDataSource(this.documents);

  /// Path → JSON text.
  final Map<String, String> documents;

  @override
  Future<String> read(String path) async {
    final doc = documents[path];
    if (doc == null) throw ArgumentError.value(path, 'path', 'no such document');
    return doc;
  }
}

/// The manifest at the data root lists every document to load.
const String dataManifestPath = 'manifest.json';

/// Behaviour ids known to the rules layer. Validation checks that every id the
/// data refers to is registered. Implemented by `RulesRegistry`.
abstract interface class KnownBehaviours {
  Set<String> get turretSpecialIds;
  Set<String> get projectileKindIds;
  Set<String> get blastKindIds;
  Set<String> get creepBehaviourIds;
}

/// The immutable, validated union of every data file plus an applied
/// [ModDelta]. Sessions, rules and the UI read balance only through this.
@immutable
class GameData {
  const GameData({
    required this.world,
    required this.rules,
    required this.turrets,
    required this.combos,
    required this.comboDefaults,
    this.combonly = const [],
    required this.projectiles,
    required this.blasts,
    required this.creeps,
    required this.difficulty,
    required this.waves,
    required this.maps,
    required this.challenges,
    required this.progression,
    required this.targeting,
    required this.tutorial,
    this.attract,
    required this.audio,
    required this.strings,
    required this.descriptors,
    this.modEditor = ModEditorDefs.empty,
    required this.documents,
  });

  final WorldDef world;
  final RulesConstants rules;

  /// Turret id → definition, in tray order.
  final Map<String, TurretDef> turrets;

  /// Combo id → recipe.
  final Map<String, ComboRecipe> combos;

  /// Values a combo falls back to when its recipe does not set them
  /// (`Projectile.as` class vars).
  final Params comboDefaults;

  /// The Combonly plate's scan rules in order; for each colour the last one
  /// whose needs are met is the option offered.
  final List<CombonlyOption> combonly;
  final Map<String, ProjectileSpec> projectiles;
  final Map<String, BlastSpec> blasts;
  final CreepDefs creeps;
  final DifficultyDefs difficulty;
  final WaveDefs waves;

  /// Map id → map, in picker order.
  final Map<String, MapDefinition> maps;
  final ChallengeDefs challenges;
  final ProgressionDefs progression;
  final TargetingDefs targeting;
  final TutorialDefs tutorial;

  /// The main menu's demo game, when the data has one.
  final AttractDef? attract;
  final AudioDefs audio;

  /// Locale → string table.
  final Map<String, StringTable> strings;
  final DescriptorDefs descriptors;

  /// What the mod editor offers and where each value lives (empty when the
  /// data has no `mod_editor.json`).
  final ModEditorDefs modEditor;

  /// The decoded documents this was built from (after the mod delta), by path.
  final Map<String, Object?> documents;

  /// Reads the manifest and every document it lists from [source].
  static Future<Map<String, Object?>> readDocuments(DataSource source) async {
    final manifest = jsonDecode(await source.read(dataManifestPath));
    final sink = IssueSink();
    final paths = readManifest(JsonReader.root(manifest, dataManifestPath, sink));
    sink.throwIfAny();
    final docs = <String, Object?>{dataManifestPath: manifest};
    for (final p in paths) {
      docs[p] = jsonDecode(await source.read(p));
    }
    return docs;
  }

  /// Loads, applies [delta] and validates. Throws [DataValidationException]
  /// listing every problem.
  static Future<GameData> load(
    DataSource source, {
    ModDelta delta = ModDelta.none,
    KnownBehaviours? behaviours,
  }) async => fromDocuments(await readDocuments(source), delta: delta, behaviours: behaviours);

  /// Builds from decoded [documents] (path → JSON value).
  static GameData fromDocuments(
    Map<String, Object?> documents, {
    ModDelta delta = ModDelta.none,
    KnownBehaviours? behaviours,
  }) {
    final docs = delta.applyTo(documents);
    final sink = IssueSink();

    JsonReader doc(String path, int version) {
      if (!docs.containsKey(path)) sink.add(path, 'missing document');
      final r = JsonReader.root(docs[path], path, sink);
      if (docs.containsKey(path)) readSchemaVersion(r, supported: version);
      return r;
    }

    final manifestPaths = readManifest(
      JsonReader.root(docs[dataManifestPath], dataManifestPath, sink),
    );

    Map<String, T> records<T>(
      String path,
      String key,
      T Function(JsonReader) read,
      String Function(T) idOf, {
      Set<String> extraKeys = const {},
    }) {
      final r = doc(path, 1)..expectOnlyKeys({'schemaVersion', key, ...extraKeys});
      final list = r.list(key, read);
      final out = <String, T>{};
      for (var i = 0; i < list.length; i++) {
        final id = idOf(list[i]);
        if (out.containsKey(id)) sink.add('$path:/$key/$i/id', 'duplicate id "$id"');
        out[id] = list[i];
      }
      return Map.unmodifiable(out);
    }

    final maps = <String, MapDefinition>{};
    final strings = <String, StringTable>{};
    for (final p in manifestPaths) {
      if (p.startsWith('maps/')) {
        final m = MapDefinition.fromJson(doc(p, MapDefinition.schemaVersion));
        if (maps.containsKey(m.id)) sink.add('$p:/id', 'duplicate map id "${m.id}"');
        maps[m.id] = m;
      } else if (p.startsWith('strings/')) {
        final t = StringTable.fromJson(doc(p, StringTable.schemaVersion));
        strings[t.locale] = t;
      }
    }
    final sortedMaps = maps.values.toList()..sort((a, b) => a.order.compareTo(b.order));

    final data = GameData(
      world: WorldDef.fromJson(doc('world.json', WorldDef.schemaVersion)),
      rules: RulesConstants.fromJson(doc('rules.json', RulesConstants.schemaVersion)),
      turrets: records('turrets.json', 'turrets', TurretDef.fromJson, (t) => t.id),
      combos: records(
        'combos.json',
        'combos',
        ComboRecipe.fromJson,
        (c) => c.id,
        extraKeys: {'defaults', 'combonly'},
      ),
      comboDefaults: Params.fromJson(
        JsonReader.root(docs['combos.json'], 'combos.json', sink).child('defaults'),
      ),
      combonly: List.unmodifiable(
        JsonReader.root(
          docs['combos.json'],
          'combos.json',
          sink,
        ).optList('combonly', CombonlyOption.fromJson),
      ),
      projectiles: records('projectiles.json', 'projectiles', ProjectileSpec.fromJson, (p) => p.id),
      blasts: records('blasts.json', 'blasts', BlastSpec.fromJson, (b) => b.id),
      creeps: CreepDefs.fromJson(doc('creeps.json', CreepDefs.schemaVersion)),
      difficulty: DifficultyDefs.fromJson(doc('difficulty.json', DifficultyDefs.schemaVersion)),
      waves: WaveDefs.fromJson(doc('waves.json', WaveDefs.schemaVersion)),
      maps: Map.unmodifiable({for (final m in sortedMaps) m.id: m}),
      challenges: ChallengeDefs.fromJson(doc('challenges.json', ChallengeDefs.schemaVersion)),
      progression: ProgressionDefs.fromJson(doc('progression.json', ProgressionDefs.schemaVersion)),
      targeting: TargetingDefs.fromJson(doc('targeting.json', TargetingDefs.schemaVersion)),
      tutorial: TutorialDefs.fromJson(doc('tutorial.json', TutorialDefs.schemaVersion)),
      attract: manifestPaths.contains('attract.json')
          ? AttractDef.fromJson(doc('attract.json', AttractDef.schemaVersion))
          : null,
      audio: AudioDefs.fromJson(doc('audio.json', AudioDefs.schemaVersion)),
      strings: Map.unmodifiable(strings),
      descriptors: DescriptorDefs.fromJson(doc('descriptors.json', DescriptorDefs.schemaVersion)),
      modEditor: manifestPaths.contains('mod_editor.json')
          ? ModEditorDefs.fromJson(doc('mod_editor.json', ModEditorDefs.schemaVersion))
          : ModEditorDefs.empty,
      documents: Map.unmodifiable(docs),
    );
    sink.throwIfAny();

    final issues = validateGameData(data, behaviours: behaviours);
    if (issues.isNotEmpty) throw DataValidationException(issues);
    return data;
  }

  /// Every logical asset id (art) the data refers to.
  Set<String> get referencedArtIds => {
    ...world.art.values,
    for (final g in world.groundArt) g.art,
    for (final g in attract?.groundArt ?? const <GroundArt>[]) g.art,
    for (final t in turrets.values) ...t.art.ids,
    for (final p in projectiles.values) ?p.sprite,
    for (final b in blasts.values) ?b.sprite,
    for (final c in creeps.types) c.sprite,
  };

  /// Every audio clip id the data refers to.
  Set<String> get referencedClipIds => {for (final clips in audio.events.values) ...clips};

  /// Every audio event id the data refers to: fire and combo sounds, the
  /// sounds a special's parameters name (every `sound…` key, e.g. Fusion's
  /// `soundLow`), and a blast's own `sound` parameter.
  Set<String> get referencedAudioEvents => {
    for (final t in turrets.values) ?t.fireSound,
    for (final c in combos.values) ?c.sound,
    for (final t in turrets.values)
      for (final p in t.specialParams.values)
        for (final e in p.toJson().entries)
          if (e.key.startsWith('sound') && e.value is String) e.value as String,
    for (final b in blasts.values)
      if (b.params.toJson()['sound'] case final String sound) sound,
  };

  /// Looks up a string in [locale], falling back to English, then the key.
  String text(String key, {String locale = 'en'}) =>
      strings[locale]?.strings[key] ?? strings['en']?.strings[key] ?? key;
}

/// Reads `manifest.json` → list of document paths.
List<String> readManifest(JsonReader r) {
  r.expectOnlyKeys({'schemaVersion', 'files'});
  readSchemaVersion(r, supported: 1);
  final paths = r.list('files', (c) => c.asString(), minLength: 1);
  final seen = <String>{};
  for (var i = 0; i < paths.length; i++) {
    if (!seen.add(paths[i])) r.child('files').child('$i').issue('duplicate path');
  }
  return paths;
}
