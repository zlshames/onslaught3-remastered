import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../logging/log_level.dart';
import '../logging/log_service.dart';

import 'document_store.dart';
import 'game_in_progress.dart';
import 'map_library.dart';
import 'mod_library.dart';
import 'profile.dart';

/// How a turret from the tray (or a move) is put down.
enum PlacementMode {
  /// The ghost follows the finger and letting go places it (the original's
  /// mouse behaviour, made touch).
  dragAndDrop('drag'),

  /// Letting go (or a tap on the map) drops the ghost and locks it there:
  /// a drag anywhere on the map then nudges it without the finger covering
  /// it, and Place builds it.
  dropAndLock('lock');

  const PlacementMode(this.id);

  /// The stored value.
  final String id;

  /// The mode stored as [id]; drag and drop for an unknown value.
  static PlacementMode fromId(String? id) =>
      values.where((m) => m.id == id).firstOrNull ?? dragAndDrop;

  /// The mode stored as [id], or null when none (or an unknown one) is stored.
  static PlacementMode? tryFromId(String? id) => values.where((m) => m.id == id).firstOrNull;

  /// The mode a player who has not chosen gets (docs/DEVIATIONS.md
  /// `placementDefault`): drop and lock in the Android and iOS apps, where the
  /// finger covers the spot it drops on; drag and drop on the web and desktop,
  /// where a mouse pointer does not.
  static PlacementMode get platformDefault {
    if (kIsWeb) return dragAndDrop;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => dropAndLock,
      _ => dragAndDrop,
    };
  }
}

/// Player settings (`settings` document; the original's `Pref*` values).
/// Balance-related values are nullable overrides: null means "use the game
/// data's default".
@immutable
class Settings {
  const Settings({
    this.soundOn = true,
    this.volume,
    this.waveSpacingS,
    this.waveFollow = false,
    this.waveRemember = false,
    this.timeScale = 1,
    this.showRanges = false,
    this.showComboRanges = false,
    this.haptics = true,
    this.leftHanded = false,
    this.rocketSmoke,
    this.smokeMax,
    this.colourBadges = false,
    this.locale,
    this.sharpGround = false,
    this.placementChoice,
    this.logLevelChoice,
  });

  /// Reads a stored document; throws a [DataValidationException] naming
  /// every field of the wrong type.
  factory Settings.fromJson(Map<String, Object?> j) {
    final sink = IssueSink();
    final r = JsonReader.root(j, key, sink);
    final s = Settings(
      soundOn: r.optBoolean('soundOn', fallback: true),
      volume: r.optNumber('volume'),
      waveSpacingS: r.optNumber('waveSpacingS'),
      waveFollow: r.optBoolean('waveFollow', fallback: false),
      waveRemember: r.optBoolean('waveRemember', fallback: false),
      timeScale: r.optNumber('timeScale') ?? 1,
      showRanges: r.optBoolean('showRanges', fallback: false),
      showComboRanges: r.optBoolean('showComboRanges', fallback: false),
      haptics: r.optBoolean('haptics', fallback: true),
      leftHanded: r.optBoolean('leftHanded', fallback: false),
      rocketSmoke: r.has('rocketSmoke') ? r.boolean('rocketSmoke') : null,
      smokeMax: r.optInteger('smokeMax'),
      colourBadges: r.optBoolean('colourBadges', fallback: false),
      locale: r.optString('locale'),
      sharpGround: r.optBoolean('sharpGround', fallback: false),
      placementChoice: PlacementMode.tryFromId(r.optString('placement')),
      logLevelChoice: LogLevel.tryFromId(r.optString('logLevel')),
    );
    sink.throwIfAny();
    return s;
  }

  /// v2 added [waveRemember]; v3 added [rocketSmoke], [smokeMax],
  /// [colourBadges] and [locale]; v4 added [sharpGround]; v5 added
  /// [placement]; v6 stores only a player's own choice ([placementChoice]);
  /// v7 added [logLevelChoice].
  static const int schemaVersion = 7;
  static const String key = 'settings';
  static final Migrator migrator = Migrator(
    currentVersion: schemaVersion,
    steps: [
      // v1 → v2: wave settings were not remembered between games.
      (doc) => {...doc, 'waveRemember': false},
      // v2 → v3: smoke follows the data, no colour badges, the device's
      // language.
      (doc) => {
        ...doc,
        'rocketSmoke': null,
        'smokeMax': null,
        'colourBadges': false,
        'locale': null,
      },
      // v3 → v4: the original ground.
      (doc) => {...doc, 'sharpGround': false},
      // v4 → v5: drag and drop, as before.
      (doc) => {...doc, 'placement': PlacementMode.dragAndDrop.id},
      // v5 → v6: a stored "drag" was v5's default, not a choice, so it gives
      // way to the platform default; a stored "lock" was chosen and stays.
      (doc) => {...doc, 'placement': doc['placement'] == 'lock' ? 'lock' : null},
      // v6 → v7: the log keeps the build's default level.
      (doc) => {...doc, 'logLevel': null},
    ],
  );

  final bool soundOn;

  /// 0–100; null = `audio.json` default.
  final double? volume;

  /// Seconds between waves; null = `waves.json` default.
  final double? waveSpacingS;

  /// Send the next wave as soon as the field is clear.
  final bool waveFollow;

  /// Start every game with [waveSpacingS] and [waveFollow]
  /// (`PrefWaveRemember`); otherwise each game starts at the defaults and
  /// the wave settings apply to the game they are changed in.
  final bool waveRemember;

  /// Base game-speed factor (original 50–200 % setting).
  final double timeScale;
  final bool showRanges;
  final bool showComboRanges;

  /// Vibrate on build, sell, upgrade and weapon unlocks.
  final bool haptics;

  /// Put the tower tray on the left.
  final bool leftHanded;

  /// Rocket smoke trails (`PrefSmoke`); null = `world.json` default.
  final bool? rocketSmoke;

  /// How many smoke clips are kept (`PrefSmokeMax`); null = `world.json`
  /// default.
  final int? smokeMax;

  /// Shape-and-letter badges on the colour turrets, so they can be told
  /// apart without colour.
  final bool colourBadges;

  /// The language of the interface (a `strings/<locale>.json`); null = the
  /// device's language when the data has it, else English.
  final String? locale;

  /// Ground: Sharp (the shader-drawn ground) instead of the original image;
  /// offered with the Enhanced skin only, applied from the next game.
  final bool sharpGround;

  /// How the player chose to put turrets down; null = [PlacementMode.platformDefault].
  final PlacementMode? placementChoice;

  /// How much the log keeps (Settings → Diagnostics); null = the build's
  /// default (`AppLogging.defaultLevel`).
  final LogLevel? logLevelChoice;

  /// How turrets are put down: the player's choice, else the platform's default.
  PlacementMode get placement => placementChoice ?? PlacementMode.platformDefault;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'soundOn': soundOn,
    'volume': volume,
    'waveSpacingS': waveSpacingS,
    'waveFollow': waveFollow,
    'waveRemember': waveRemember,
    'timeScale': timeScale,
    'showRanges': showRanges,
    'showComboRanges': showComboRanges,
    'haptics': haptics,
    'leftHanded': leftHanded,
    'rocketSmoke': rocketSmoke,
    'smokeMax': smokeMax,
    'colourBadges': colourBadges,
    'locale': locale,
    'sharpGround': sharpGround,
    'placement': placementChoice?.id,
    'logLevel': logLevelChoice?.id,
  };

  Settings copyWith({
    bool? soundOn,
    double? volume,
    double? waveSpacingS,
    bool? waveFollow,
    bool? waveRemember,
    double? timeScale,
    bool? haptics,
    bool? leftHanded,
    bool? rocketSmoke,
    int? smokeMax,
    bool? colourBadges,
    String? locale,
    bool? sharpGround,
    PlacementMode? placement,
    LogLevel? logLevel,
  }) => Settings(
    soundOn: soundOn ?? this.soundOn,
    volume: volume ?? this.volume,
    waveSpacingS: waveSpacingS ?? this.waveSpacingS,
    waveFollow: waveFollow ?? this.waveFollow,
    waveRemember: waveRemember ?? this.waveRemember,
    timeScale: timeScale ?? this.timeScale,
    showRanges: showRanges,
    showComboRanges: showComboRanges,
    haptics: haptics ?? this.haptics,
    leftHanded: leftHanded ?? this.leftHanded,
    rocketSmoke: rocketSmoke ?? this.rocketSmoke,
    smokeMax: smokeMax ?? this.smokeMax,
    colourBadges: colourBadges ?? this.colourBadges,
    locale: locale ?? this.locale,
    sharpGround: sharpGround ?? this.sharpGround,
    placementChoice: placement ?? placementChoice,
    logLevelChoice: logLevel ?? logLevelChoice,
  );

  /// These settings with the interface language set to [locale] (null =
  /// the device's language), which [copyWith] cannot clear.
  Settings withLocale(String? locale) => Settings.fromJson({...toJson(), 'locale': locale});

  /// Whether rockets leave smoke, given the data's default.
  bool smokeOn(GameData data) => rocketSmoke ?? data.world.effects.rocketSmoke.enabled;

  /// The smoke ring size, given the data's default and bounds.
  int smokeLimit(GameData data) {
    final r = data.world.effects.rocketSmoke;
    return (smokeMax ?? r.max).clamp(r.maxPrefMin, r.maxPrefMax);
  }

  @override
  bool operator ==(Object other) => other is Settings && mapEquals(other.toJson(), toJson());

  @override
  int get hashCode => Object.hashAll(toJson().values);
}

const Logger _log = Logger('persistence');

/// Loads and saves versioned documents (settings, profile, the map library
/// and the mod) through a [DocumentStore].
///
/// A stored document that cannot be read (damaged JSON, a newer
/// `schemaVersion` after a downgrade, a field of the wrong type) does not
/// fail the load: its text is kept under `<key>.corrupt` (replacing an older
/// copy), the default document is returned, and the key is added to
/// [recoveredKeys] so the main menu can say so once. The stored document is
/// left in place until the next save replaces it. A library with one entry
/// that cannot be read (a map, the mod) loads the rest; its whole text is
/// kept and recorded the same way ([loadEntries]).
class PersistenceService {
  PersistenceService(this.store);

  final DocumentStore store;

  final List<String> _recovered = [];

  /// The keys of the documents reset to their defaults by [load] so far, in
  /// load order, each once.
  List<String> get recoveredKeys => List.unmodifiable(_recovered);

  /// Where the text of the unreadable document [key] is kept.
  static String corruptKey(String key) => '$key.corrupt';

  /// Reads document [key], migrated by [migrator] and parsed by [fromJson];
  /// [fallback] when there is none or it cannot be read (see the class
  /// comment). Other errors (the store itself failing) propagate.
  Future<T> load<T>(
    String key,
    Migrator migrator,
    T Function(Map<String, Object?> json) fromJson,
    T fallback,
  ) async {
    final text = await store.readRaw(key);
    if (text == null) return fallback;
    try {
      final doc = jsonDecode(text);
      if (doc is! Map) throw FormatException('document $key is not a JSON object');
      return fromJson(migrator.migrate(Map<String, Object?>.from(doc)));
    } on Object catch (e, st) {
      if (!_unreadable(e)) rethrow;
      _log.warning(
        'a stored document cannot be read; using the default and keeping a copy',
        error: e,
        stackTrace: st,
        fields: {'document': key},
      );
      await _keep(key, text);
      return fallback;
    }
  }

  /// [load] for a document of several entries: [fromJson] reads what it can
  /// and calls `dropped` for each entry it leaves out. When it does, the
  /// stored text (the dropped entries with the rest) is kept under
  /// `<key>.corrupt` and [key] recorded, as for a document that cannot be
  /// read at all.
  Future<T> loadEntries<T>(
    String key,
    Migrator migrator,
    T Function(Map<String, Object?> json, void Function(Object? entry) dropped) fromJson,
    T fallback,
  ) async {
    var lost = false;
    final value = await load(key, migrator, (j) => fromJson(j, (_) => lost = true), fallback);
    if (lost) {
      final text = await store.readRaw(key);
      if (text != null) await _keep(key, text);
    }
    return value;
  }

  Future<void> _keep(String key, String text) async {
    await store.writeRaw(corruptKey(key), text);
    if (!_recovered.contains(key)) _recovered.add(key);
  }

  /// The errors a damaged or foreign document raises while it is decoded,
  /// migrated or parsed.
  static bool _unreadable(Object e) =>
      e is FormatException || e is TypeError || e is DataValidationException || e is ArgumentError;

  Future<Settings> loadSettings() =>
      load(Settings.key, Settings.migrator, Settings.fromJson, const Settings());

  Future<void> saveSettings(Settings s) => store.write(Settings.key, s.toJson());

  Future<Profile> loadProfile() =>
      load(Profile.key, Profile.migrator, Profile.fromJson, const Profile());

  Future<void> saveProfile(Profile p) => store.write(Profile.key, p.toJson());

  Future<MapLibrary> loadMaps() => loadEntries(
    MapLibrary.key,
    MapLibrary.migrator,
    (j, dropped) => MapLibrary.fromJson(j, onDropped: dropped),
    const MapLibrary(),
  );

  Future<void> saveMaps(MapLibrary library) => store.write(MapLibrary.key, library.toJson());

  Future<ModLibrary> loadMods() => loadEntries(
    ModLibrary.key,
    ModLibrary.migrator,
    (j, dropped) => ModLibrary.fromJson(j, onDropped: dropped),
    const ModLibrary(),
  );

  Future<void> saveMods(ModLibrary mods) => store.write(ModLibrary.key, mods.toJson());

  /// The game the player left unfinished, if any.
  Future<GameInProgress?> loadGameInProgress() => load<GameInProgress?>(
    GameInProgress.key,
    GameInProgress.migrator,
    GameInProgress.fromJson,
    null,
  );

  /// Stores [game] as the game in progress, or forgets it when null.
  Future<void> saveGameInProgress(GameInProgress? game) => game == null
      ? store.delete(GameInProgress.key)
      : store.write(GameInProgress.key, game.toJson());
}
