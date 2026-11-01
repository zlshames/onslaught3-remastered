import 'dart:convert';

import 'package:hive_ce/hive.dart';

/// Key → JSON document storage. Every persisted document carries a
/// `schemaVersion` and is migrated on read (rule R9).
abstract interface class DocumentStore {
  /// The document under [key], decoded; null when there is none. Throws a
  /// [FormatException] when the stored text is not JSON.
  Future<Map<String, Object?>?> read(String key);
  Future<void> write(String key, Map<String, Object?> document);

  /// The stored text under [key] as it is, undecoded; null when there is none.
  Future<String?> readRaw(String key);

  /// Stores [text] under [key] as it is (a copy of a document that could not
  /// be read, `<key>.corrupt`).
  Future<void> writeRaw(String key, String text);
  Future<void> delete(String key);
}

/// In-memory store for tests and previews.
class MemoryDocumentStore implements DocumentStore {
  final Map<String, String> _docs = {};

  @override
  Future<Map<String, Object?>?> read(String key) async {
    final s = _docs[key];
    return s == null ? null : (jsonDecode(s) as Map).cast<String, Object?>();
  }

  @override
  Future<void> write(String key, Map<String, Object?> document) async =>
      _docs[key] = jsonEncode(document);

  @override
  Future<String?> readRaw(String key) async => _docs[key];

  @override
  Future<void> writeRaw(String key, String text) async => _docs[key] = text;

  @override
  Future<void> delete(String key) async => _docs.remove(key);
}

/// Hive-backed store (all platforms including web). Documents are stored as
/// JSON strings so no type adapters are needed and the stored form is the
/// same JSON that export/import and migrations work on.
class HiveDocumentStore implements DocumentStore {
  HiveDocumentStore(this._box);

  static const String boxName = 'documents';

  /// Opens the store. Call `Hive.initFlutter()` (app) or `Hive.init(dir)`
  /// (tests) first.
  static Future<HiveDocumentStore> open() async =>
      HiveDocumentStore(await Hive.openBox<String>(boxName));

  final Box<String> _box;

  @override
  Future<Map<String, Object?>?> read(String key) async {
    final s = _box.get(key);
    return s == null ? null : (jsonDecode(s) as Map).cast<String, Object?>();
  }

  @override
  Future<void> write(String key, Map<String, Object?> document) =>
      _box.put(key, jsonEncode(document));

  @override
  Future<String?> readRaw(String key) async => _box.get(key);

  @override
  Future<void> writeRaw(String key, String text) => _box.put(key, text);

  @override
  Future<void> delete(String key) => _box.delete(key);
}

/// One step that upgrades a document from `from` to `from + 1`.
typedef MigrationStep = Map<String, Object?> Function(Map<String, Object?> doc);

/// Chains [steps] (index i upgrades version i+1 → i+2) to bring any stored
/// version up to [currentVersion].
class Migrator {
  Migrator({required this.currentVersion, this.steps = const []}) {
    if (steps.length != currentVersion - 1) {
      throw ArgumentError('need ${currentVersion - 1} steps, got ${steps.length}');
    }
  }

  final int currentVersion;
  final List<MigrationStep> steps;

  Map<String, Object?> migrate(Map<String, Object?> doc) {
    var v = (doc['schemaVersion'] as num?)?.toInt() ?? 1;
    if (v > currentVersion) {
      throw FormatException('document schemaVersion $v is newer than $currentVersion');
    }
    var out = doc;
    while (v < currentVersion) {
      out = {...steps[v - 1](out), 'schemaVersion': v + 1};
      v++;
    }
    return out;
  }
}
