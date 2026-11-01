import 'dart:convert';
import 'dart:io';

import 'package:onslaught_core/onslaught_core.dart';

/// The real classic data, read from `assets/data` on disk (host tests only).
GameData loadTestGameData() =>
    GameData.fromDocuments(loadTestDocuments(), behaviours: RulesRegistry.classic());

/// The raw data documents in `assets/data`, keyed by path (the manifest
/// included), for tests that add or change a document before loading.
Map<String, Object?> loadTestDocuments() {
  const root = 'assets/data';
  final manifest = jsonDecode(File('$root/manifest.json').readAsStringSync()) as Map;
  return {
    'manifest.json': manifest,
    for (final f in (manifest['files'] as List).cast<String>())
      f: jsonDecode(File('$root/$f').readAsStringSync()),
  };
}

/// [DataSource] over the files in `assets/data`.
class FileDataSource implements DataSource {
  @override
  Future<String> read(String path) => File('assets/data/$path').readAsString();
}
