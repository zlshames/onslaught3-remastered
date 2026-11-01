import 'package:collection/collection.dart';
import 'package:onslaught_core/data_generator.dart';
import 'package:onslaught_core/onslaught_core.dart';
import 'package:test/test.dart';

import '../support/repo_data.dart';

/// `assets/data` must be exactly what `tool/gen_data_from_legacy.dart`
/// produces from `docs/legacy/legacy_values.json` and the `l10n/`
/// translations. A failure means someone
/// edited generated data by hand (fix the table instead and regenerate) or
/// changed the generator without regenerating.
void main() {
  test('assets/data matches the generator output', () {
    final expected = generateGameDocuments(loadLegacyTable(), translations: loadTranslations());
    final actual = loadDataDocuments();
    expect(actual.keys.toSet(), expected.keys.toSet(), reason: 'document set differs');
    for (final path in expected.keys) {
      final same = const DeepCollectionEquality().equals(
        canonicalJson(expected[path]),
        canonicalJson(actual[path]),
      );
      expect(
        same,
        isTrue,
        reason: '$path differs; run `fvm dart run tool/gen_data_from_legacy.dart`',
      );
    }
  });

  test('generation is deterministic', () {
    final table = loadLegacyTable();
    expect(
      canonicalJson(generateGameDocuments(table)),
      canonicalJson(generateGameDocuments(table)),
    );
  });
}
