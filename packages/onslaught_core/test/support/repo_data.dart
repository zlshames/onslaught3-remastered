// Test-only file access (tests may read files; library code may not, R1).
import 'dart:convert';
import 'dart:io';

import 'package:onslaught_core/onslaught_core.dart';

/// Repository root, found from the package directory tests run in.
final Directory repoRoot = () {
  var d = Directory.current.absolute;
  while (!File('${d.path}/AGENTS.md').existsSync()) {
    final parent = d.parent;
    if (parent.path == d.path) throw StateError('repo root not found');
    d = parent;
  }
  return d;
}();

String repoPath(String relative) => '${repoRoot.path}/$relative';

/// The raw `assets/data` documents (the manifest and every file it lists),
/// keyed by path.
Map<String, String> readDataTexts() {
  final root = repoPath('assets/data');
  final manifest = File('$root/manifest.json').readAsStringSync();
  final files = ((jsonDecode(manifest) as Map)['files'] as List).cast<String>();
  return {'manifest.json': manifest, for (final f in files) f: File('$root/$f').readAsStringSync()};
}

/// The decoded `assets/data` documents, keyed by path.
Map<String, Object?> loadDataDocuments() => {
  for (final e in readDataTexts().entries) e.key: jsonDecode(e.value),
};

/// The classic game data, validated against the classic rules registry.
GameData loadClassicData() =>
    GameData.fromDocuments(loadDataDocuments(), behaviours: RulesRegistry.classic());

/// The committed legacy reference table.
Map<String, Object?> loadLegacyTable() =>
    (jsonDecode(File(repoPath('docs/legacy/legacy_values.json')).readAsStringSync()) as Map)
        .cast<String, Object?>();

/// The committed translations (`l10n/<locale>.json`), keyed by locale.
Map<String, Map<String, Object?>> loadTranslations() {
  final dir = Directory(repoPath('l10n'));
  if (!dir.existsSync()) return const {};
  return {
    for (final f in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')))
      f.uri.pathSegments.last.replaceAll('.json', ''): (jsonDecode(f.readAsStringSync()) as Map)
          .cast<String, Object?>(),
  };
}
