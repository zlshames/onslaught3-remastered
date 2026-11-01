import 'dart:convert';
import 'dart:io';

import 'package:onslaught_core/data_generator.dart';
import 'package:onslaught_core/onslaught_core.dart';
import 'package:test/test.dart';

import '../support/repo_data.dart';

/// Every data record writes back exactly what it reads (`toJson` is the
/// inverse of `fromJson`), so the generator, which builds the records from
/// the legacy table and serialises them, and the data layer, which reads
/// them, share one schema. For every committed document: reading it and
/// writing it back gives the committed file byte for byte (key order and
/// number spelling included), and reading that output again gives the same
/// records (compared through their JSON, since records have no `==`).
void main() {
  const encoder = JsonEncoder.withIndent('  ');
  String encode(Object? doc) => '${encoder.convert(doc)}\n';

  late Map<String, Object?> written;
  setUpAll(() => written = gameDocuments(loadClassicData()));

  test('the documents written back are the documents read', () {
    final manifest = loadDataDocuments()['manifest.json']! as Map;
    expect(written.keys.toList(), ['manifest.json', ...(manifest['files'] as List)]);
  });

  for (final path in loadDataDocuments().keys) {
    test('$path: toJson(fromJson(file)) is the committed file', () {
      final committed = File(repoPath('assets/data/$path')).readAsStringSync();
      expect(encode(written[path]), committed);
    });
  }

  test('fromJson(toJson(x)) is x for every record', () {
    final again = gameDocuments(
      GameData.fromDocuments(written, behaviours: RulesRegistry.classic()),
    );
    for (final path in written.keys) {
      expect(encode(again[path]), encode(written[path]), reason: path);
    }
  });
}
