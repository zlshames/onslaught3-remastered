import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../services/assets/asset_pack.dart';
import '../services/assets/classic_asset_pack.dart';
import '../services/assets/enhanced_asset_pack.dart';
import '../services/audio/audio_service.dart';
import '../services/data/asset_bundle_data_source.dart';
import '../services/haptics/haptics.dart';
import '../services/logging/app_logging.dart';
import '../services/logging/log_service.dart';
import '../services/logging/log_share.dart';
import '../services/logging/log_store.dart';
import '../services/logging/pii.dart';
import '../services/logging/rotating_log_writer.dart';
import '../services/persistence/document_store.dart';
import '../services/persistence/game_in_progress.dart';
import '../services/persistence/map_library.dart';
import '../services/persistence/mod_library.dart';
import '../services/persistence/profile.dart';
import '../services/persistence/settings.dart';
import 'feature_flags.dart';
import 'ui_skin.dart';

/// App-level dependency graph. Features read services through these
/// providers (rule R3); tests override them.

final featureFlagsProvider = Provider<FeatureFlags>((ref) => FeatureFlags.fromEnvironment());

/// The rules registry every session uses.
final rulesRegistryProvider = Provider<RulesRegistry>((ref) => RulesRegistry.classic());

/// Where data documents are read from.
final dataSourceProvider = Provider<DataSource>((ref) => AssetBundleDataSource());

/// The validated game data without any mod: menus, the attract demo, the
/// editors and the mod editor's defaults use it; games use [activeModProvider].
final gameDataProvider = FutureProvider<GameData>((ref) async {
  final watch = Stopwatch()..start();
  try {
    final data = await GameData.load(
      ref.watch(dataSourceProvider),
      behaviours: ref.watch(rulesRegistryProvider),
    );
    _dataLog.debug('game data loaded', fields: {'ms': watch.elapsedMilliseconds});
    return data;
  } on Object catch (e, st) {
    _dataLog.fatal('the game data cannot be loaded', error: e, stackTrace: st);
    rethrow;
  }
});

const Logger _dataLog = Logger('data');

/// The original art and sound, loaded once and shared by every chain.
final classicAssetPackProvider = FutureProvider<ClassicAssetPack>((ref) async {
  final pack = ClassicAssetPack();
  await pack.load();
  return pack;
});

/// Art and sound for Classic games, the menus and the editors: the original
/// pack alone (`[user?, hd?, classic]` in REMASTER_PLAN §5.2).
final assetPackProvider = FutureProvider<AssetPack>((ref) async {
  return AssetPackChain([await ref.watch(classicAssetPackProvider.future)]);
});

/// Art and sound for Enhanced games (docs/ENHANCED_PLAN.md): the Enhanced
/// pack's redrawn creeps over the original pack. Nothing uses it until E0
/// starts Enhanced games; Classic keeps the original creeps.
final enhancedAssetPackProvider = FutureProvider<AssetPack>((ref) async {
  final enhanced = EnhancedAssetPack();
  await enhanced.load();
  return AssetPackChain([enhanced, await ref.watch(classicAssetPackProvider.future)]);
});

/// Persisted documents. Overridden in `main` with the Hive store.
final documentStoreProvider = Provider<DocumentStore>((ref) => MemoryDocumentStore());

final persistenceProvider = Provider<PersistenceService>(
  (ref) => PersistenceService(ref.watch(documentStoreProvider)),
);

/// The keys of the persisted documents that could not be read this run and
/// were reset to their defaults ([PersistenceService.recoveredKeys]), once
/// every document has loaded; the main menu says so once when not empty.
final recoveredDocumentsProvider = FutureProvider<List<String>>((ref) async {
  await Future.wait<Object?>([
    ref.watch(settingsProvider.future),
    ref.watch(profileProvider.future),
    ref.watch(mapLibraryProvider.future),
    ref.watch(modsProvider.future),
    ref.watch(gameInProgressProvider.future),
  ]);
  return ref.watch(persistenceProvider).recoveredKeys;
});

/// A persisted document as an [AsyncNotifier]: loaded with [load], and
/// changed with [change] (or replaced with [put]), which stores it with
/// [store] unless it is unchanged. Changes are applied in call order even
/// while an earlier save is in flight: the state moves on at once and the
/// write follows; a write that fails is logged (`persistence`) and, when no
/// later change has moved the state on, rolled back to the document the
/// store still holds ([lastSaveError] keeps the error).
abstract class PersistedNotifier<T> extends AsyncNotifier<T> {
  /// Reads the document.
  Future<T> load(PersistenceService persistence);

  /// Writes [value].
  Future<void> store(PersistenceService persistence, T value);

  @override
  Future<T> build() => load(ref.watch(persistenceProvider));

  /// Applies [edit] to the current document and saves the result.
  Future<void> change(T Function(T current) edit) async => put(edit(state.value ?? await future));

  /// The error of the last write that failed, null once a write succeeds.
  Object? get lastSaveError => _lastSaveError;
  Object? _lastSaveError;

  /// Makes [next] the document and saves it; nothing happens when it equals
  /// the current one. A failed write does not throw: it is logged, kept in
  /// [lastSaveError] and the state rolled back unless a later change (whose
  /// own write carries the whole document) has already moved it on.
  @protected
  Future<void> put(T next) async {
    if (next == state.value) return;
    final previous = state;
    state = AsyncData(next);
    try {
      await store(ref.read(persistenceProvider), next);
      _lastSaveError = null;
    } catch (e, st) {
      _lastSaveError = e;
      _persistenceLog.error(
        'saving a document failed; the stored one is kept',
        error: e,
        stackTrace: st,
        fields: {'notifier': '$runtimeType'},
      );
      if (previous.hasValue && identical(state.value, next)) state = previous;
    }
  }
}

const Logger _persistenceLog = Logger('persistence');

/// The player's settings; [SettingsNotifier.save] stores a change.
final settingsProvider = AsyncNotifierProvider<SettingsNotifier, Settings>(SettingsNotifier.new);

class SettingsNotifier extends PersistedNotifier<Settings> {
  @override
  Future<Settings> load(PersistenceService persistence) => persistence.loadSettings();

  @override
  Future<void> store(PersistenceService persistence, Settings value) =>
      persistence.saveSettings(value);

  /// Makes [settings] the player's settings and saves them.
  Future<void> save(Settings settings) => put(settings);
}

/// The player's progress; [ProfileNotifier.change] stores a change.
final profileProvider = AsyncNotifierProvider<ProfileNotifier, Profile>(ProfileNotifier.new);

class ProfileNotifier extends PersistedNotifier<Profile> {
  @override
  Future<Profile> load(PersistenceService persistence) => persistence.loadProfile();

  @override
  Future<void> store(PersistenceService persistence, Profile value) =>
      persistence.saveProfile(value);
}

/// The game the player left unfinished (one at a time): the main menu's Play
/// offers to resume it. [GameInProgressNotifier.save] replaces it and
/// [GameInProgressNotifier.clear] forgets it.
final gameInProgressProvider = AsyncNotifierProvider<GameInProgressNotifier, GameInProgress?>(
  GameInProgressNotifier.new,
);

class GameInProgressNotifier extends PersistedNotifier<GameInProgress?> {
  @override
  Future<GameInProgress?> load(PersistenceService persistence) => persistence.loadGameInProgress();

  @override
  Future<void> store(PersistenceService persistence, GameInProgress? value) =>
      persistence.saveGameInProgress(value);

  /// Makes [game] the game in progress and saves it. Waits for the stored
  /// one to have loaded first, so that load cannot land after this and undo
  /// it (a game screen opened straight from a link may be the first reader).
  Future<void> save(GameInProgress game) async {
    await future;
    await put(game);
  }

  /// Forgets the game in progress (after the stored one has loaded, as
  /// [save]).
  Future<void> clear() async {
    await future;
    await put(null);
  }
}

/// The player's maps; [MapLibraryNotifier] stores changes.
final mapLibraryProvider = AsyncNotifierProvider<MapLibraryNotifier, MapLibrary>(
  MapLibraryNotifier.new,
);

class MapLibraryNotifier extends PersistedNotifier<MapLibrary> {
  @override
  Future<MapLibrary> load(PersistenceService persistence) => persistence.loadMaps();

  @override
  Future<void> store(PersistenceService persistence, MapLibrary value) =>
      persistence.saveMaps(value);

  /// Stores [map] (replacing the map with its id) and saves the library.
  Future<void> save(MapDefinition map) {
    _persistenceLog.info('map saved', fields: {'map': map.id, 'mapName': Pii(map.name)});
    return change((l) => l.saving(map));
  }

  Future<void> delete(String id) {
    _persistenceLog.info('map deleted', fields: {'map': id});
    return change((l) => l.removing(id));
  }
}

/// Shares and imports maps as text codes.
final mapSharingProvider = Provider<MapSharing>((ref) => const MapSharing());

/// The player's mod and its switch; [ModsNotifier.change] stores changes
/// (the original flushed every change at once).
final modsProvider = AsyncNotifierProvider<ModsNotifier, ModLibrary>(ModsNotifier.new);

class ModsNotifier extends PersistedNotifier<ModLibrary> {
  @override
  Future<ModLibrary> load(PersistenceService persistence) => persistence.loadMods();

  @override
  Future<void> store(PersistenceService persistence, ModLibrary value) =>
      persistence.saveMods(value);
}

/// The mod editor's rules over the unmodded data.
final modRulesProvider = FutureProvider<ModRules>((ref) async {
  return ModRules(
    await ref.watch(gameDataProvider.future),
    behaviours: ref.watch(rulesRegistryProvider),
  );
});

/// Shares and imports mods as text codes.
final modSharingProvider = Provider<ModSharing>((ref) => const ModSharing());

/// The mod new games play with, applied to the data.
@immutable
class ActiveMod {
  const ActiveMod({required this.name, required this.signature, required this.data});

  final String name;

  /// [modSignature], shown in the game while the mod is on.
  final String signature;

  /// The game data with the mod applied.
  final GameData data;
}

/// The active mod, or null when the switch is off, the mod is empty, or it
/// no longer validates (data changed in an update): then games play the
/// unmodded data and the mod editor shows the problems. A change takes
/// effect from the next game (`GameManager.resetGame`).
final activeModProvider = FutureProvider<ActiveMod?>((ref) async {
  final mods = await ref.watch(modsProvider.future);
  if (!mods.applies) return null;
  final rules = await ref.watch(modRulesProvider.future);
  try {
    final active = ActiveMod(
      name: mods.name,
      signature: modSignature(mods.mod),
      data: rules.apply(mods.mod),
    );
    _dataLog.info('mod on', fields: {'modName': Pii(mods.name), 'signature': active.signature});
    return active;
  } on DataValidationException catch (e) {
    _dataLog.warning('the mod no longer validates; games play unmodded', error: e);
    return null;
  }
});

/// The rule set new games use (v1: the original with the documented fixes).
final rulesProfileProvider = Provider<RulesProfile>((ref) => RulesProfile.classicFixed);

/// The skin menus, the attract demo and settings are drawn with: Enhanced
/// when `ENHANCED_SKIN` forces it, else the one new games' rule set picks.
/// A running game takes its skin from its own config (`UiSkin.forProfile`).
final uiSkinProvider = Provider<UiSkin>(
  (ref) => ref.watch(featureFlagsProvider).enhancedSkin
      ? UiSkin.enhanced
      : UiSkin.forProfile(ref.watch(rulesProfileProvider)),
);

/// Where sounds are played. Tests override it with a silent sink.
final audioSinkProvider = Provider<AudioSink>((ref) => FlameAudioSink());

/// Where game vibrations go (tests record them).
final hapticSinkProvider = Provider<HapticSink>((ref) => const PlatformHapticSink());

/// The app's logging (level, export, clear). Overridden in `main` with the
/// logging `setUpLogging` started; by default (tests, previews) the
/// installed service over log files kept in memory, which it does not write.
final appLoggingProvider = Provider<AppLogging>(
  (ref) => AppLogging(service: LogService.instance, files: RotatingLogWriter(MemoryLogStore())),
);

/// Where exported logs go: the share sheet (tests record them).
final logSharerProvider = Provider<LogSharer>((ref) => const PlatformLogSharer());
