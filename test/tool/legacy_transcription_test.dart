import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/legacy_extract/transcribed_sections.dart';

/// `docs/legacy/legacy_values.json` is extracted from `.legacy/`, which CI
/// does not have, plus the hand-transcribed
/// `tool/legacy_extract/engine_constants.dart`, which it does. The
/// transcribed sections of the committed table must equal what the
/// transcription produces now (key order and number spelling included), so
/// an edit to either one alone fails here. Fix: edit `engine_constants.dart`
/// and run `fvm dart run tool/legacy_extract.dart --transcribed`.
void main() {
  final table = (jsonDecode(File('docs/legacy/legacy_values.json').readAsStringSync()) as Map)
      .cast<String, Object?>();
  String encode(Object? v) => const JsonEncoder.withIndent('  ').convert(v);
  const fix = 'run `fvm dart run tool/legacy_extract.dart --transcribed`';

  test('engine is the transcription', () {
    expect(encode(table['engine']), encode(engineSection()), reason: fix);
  });

  test('the combo recipe structure is the transcription', () {
    final combos = (table['combos']! as Map).cast<String, Object?>();
    comboStructure().forEach((key, value) {
      expect(encode(combos[key]), encode(value), reason: 'combos.$key: $fix');
    });
  });

  test('the sandbox racks are the transcription', () {
    final gm = (table['gameManager']! as Map).cast<String, Object?>();
    expect(encode(gm['modeRacks']), encode(modeRacksSection()), reason: fix);
  });

  test('refreshing the transcribed sections changes nothing', () {
    final copy = (jsonDecode(jsonEncode(table)) as Map).cast<String, Object?>();
    expect(encode(withTranscribedSections(copy)), encode(table), reason: fix);
  });
}
