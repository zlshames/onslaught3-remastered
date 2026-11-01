import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../logging/logging.dart';
import '../share/share_codec.dart';
import 'document_store.dart' show Migrator;

const Logger _log = Logger('mods');

/// The player's mod (`mods` document): one sparse [ModDelta] and the switch
/// that applies it to new games. The original kept one mod
/// (`mods["default"]`, `GameStatus.mod_name`) and the `ModActive` pref.
@immutable
class ModLibrary {
  const ModLibrary({this.mod = const ModDelta({}, name: defaultName), this.active = false});

  /// Reads a stored document. A mod that no longer parses is dropped (the
  /// switch with it) rather than failing to load, and passed to [onDropped]
  /// ([PersistenceService.loadMods] keeps the stored text and says so); a
  /// switch of the wrong type throws a [DataValidationException].
  factory ModLibrary.fromJson(Map<String, Object?> j, {void Function(Object? entry)? onDropped}) {
    final sink = IssueSink();
    final r = JsonReader.root(j, key, sink);
    final active = r.optBoolean('active', fallback: false);
    sink.throwIfAny();
    final raw = r.child('mod').raw;
    try {
      return ModLibrary(mod: ModDelta.fromJson(raw), active: active);
    } on DataValidationException catch (e, st) {
      _log.warning('the stored mod cannot be read and is reset', error: e, stackTrace: st);
      onDropped?.call(raw);
      return const ModLibrary();
    }
  }

  static const int schemaVersion = 1;
  static const String key = 'mods';
  static final Migrator migrator = Migrator(currentVersion: schemaVersion);

  /// What a new mod is called, as stored; shown in the interface language
  /// (`GameText.modName`, `ui.mods.defaultName`).
  static const String defaultName = 'My mod';

  final ModDelta mod;

  /// Whether new games use [mod] (`GameStatus.mod_active`).
  final bool active;

  /// The mod's name, or [defaultName].
  String get name => mod.name ?? defaultName;

  /// Whether new games play with a mod: it is switched on and changes
  /// something.
  bool get applies => active && !mod.isEmpty;

  ModLibrary copyWith({ModDelta? mod, bool? active}) =>
      ModLibrary(mod: mod ?? this.mod, active: active ?? this.active);

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'active': active,
    'mod': mod.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is ModLibrary &&
      other.active == active &&
      jsonEncode(other.mod.toJson()) == jsonEncode(mod.toJson());

  @override
  int get hashCode => Object.hash(active, jsonEncode(mod.toJson()));
}

/// Shares mods as `ons3:mod:…` strings, and reads those or a mod saved by
/// the original game (its "Create Mod Save" JSON).
class ModSharing {
  const ModSharing({this.codec = const ShareCodec()});

  final ShareCodec codec;

  String encode(ModDelta mod) {
    final code = codec.encode(ShareCodec.modKind, mod.toJson());
    _log.debug('mod code made', fields: {'files': mod.files.length, 'length': code.length});
    return code;
  }

  /// Reads [text] for [rules]. Throws [ShareCodecException] when it is
  /// neither a mod code nor an original mod save. The import dialog reads on
  /// every change, so a code that cannot be read is logged at `trace` only.
  ModImport decode(String text, ModRules rules) {
    try {
      return _decode(text, rules);
    } on ShareCodecException catch (e) {
      _log.trace('mod code not readable', fields: {'reason': e.key, 'length': text.length});
      rethrow;
    }
  }

  ModImport _decode(String text, ModRules rules) {
    final trimmed = text.trim();
    if (trimmed.startsWith('{')) {
      final Object? json;
      try {
        json = jsonDecode(trimmed);
      } on FormatException {
        throw const ShareCodecException('ui.share.modSaveNotJson');
      }
      // A share payload pasted as JSON, or the original's item → asset map.
      if (json is Map && json.containsKey('files') && json.containsKey('schemaVersion')) {
        return rules.importDelta(_delta(json));
      }
      return rules.importLegacy(json);
    }
    return rules.importDelta(_delta(codec.decode(ShareCodec.modKind, text)));
  }

  static ModDelta _delta(Object? json) {
    try {
      return ModDelta.fromJson(json);
    } on DataValidationException catch (e) {
      throw ShareCodecException('ui.share.modMalformed', {'issue': e.issues.first.path});
    }
  }
}
