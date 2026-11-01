// Regenerates assets/data/*.json from the legacy reference table.
//
//   fvm dart run tool/gen_data_from_legacy.dart
//
// Input:  docs/legacy/legacy_values.json (committed; see docs/legacy/README.md)
//         l10n/<locale>.json: en is the hand-written English (the remaster's
//         interface text), every other file a translation (see l10n/README.md)
// Output: assets/data/** (committed). The data snapshot test fails when the
// two disagree, so edit the table (with a citation), never the output.
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:onslaught_core/data_generator.dart';

const _input = 'docs/legacy/legacy_values.json';
const _outDir = 'assets/data';
const _translations = 'l10n';

void main() {
  final legacy = (jsonDecode(File(_input).readAsStringSync()) as Map).cast<String, Object?>();
  final docs = generateGameDocuments(legacy, translations: readTranslations(_translations));
  final out = Directory(_outDir);
  if (out.existsSync()) {
    // Only generated JSON lives here; remove stale documents.
    for (final f in out.listSync(recursive: true).whereType<File>()) {
      if (f.path.endsWith('.json')) f.deleteSync();
    }
  }
  const encoder = JsonEncoder.withIndent('  ');
  docs.forEach((path, doc) {
    final f = File('$_outDir/$path')..createSync(recursive: true);
    f.writeAsStringSync('${encoder.convert(doc)}\n');
  });
  print('Wrote ${docs.length} documents to $_outDir');
}

/// The `<locale>.json` translations in [dir], keyed by locale.
Map<String, Map<String, Object?>> readTranslations(String dir) {
  final d = Directory(dir);
  if (!d.existsSync()) return const {};
  return {
    for (final f in d.listSync().whereType<File>().where((f) => f.path.endsWith('.json')))
      f.uri.pathSegments.last.replaceAll('.json', ''): (jsonDecode(f.readAsStringSync()) as Map)
          .cast<String, Object?>(),
  };
}
