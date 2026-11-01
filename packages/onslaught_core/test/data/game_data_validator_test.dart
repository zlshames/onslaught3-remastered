import 'package:onslaught_core/onslaught_core.dart';
import 'package:test/test.dart';

import '../support/repo_data.dart';

/// Cross-file checks for the ids, colours and values the rules dereference
/// with `!`: each mutates a fresh copy of the classic documents and expects
/// the issue at its path.
void main() {
  test('the classic data passes every check', () {
    final data = loadClassicData();
    expect(validateGameData(data, behaviours: RulesRegistry.classic()), isEmpty);
  });

  /// The issues loading the classic documents after [mutate] reports.
  List<DataIssue> issuesAfter(void Function(Map<String, Object?> docs) mutate) {
    final docs = loadDataDocuments();
    mutate(docs);
    try {
      GameData.fromDocuments(docs, behaviours: RulesRegistry.classic());
    } on DataValidationException catch (e) {
      return e.issues;
    }
    return const [];
  }

  Map<String, Object?> doc(Map<String, Object?> docs, String path) =>
      docs[path]! as Map<String, Object?>;

  List<Map<String, Object?>> combos(Map<String, Object?> docs) =>
      (doc(docs, 'combos.json')['combos']! as List).cast<Map<String, Object?>>();

  int comboIndex(String id) => combos(loadDataDocuments()).indexWhere((c) => c['id'] == id);

  Map<String, Object?> combo(Map<String, Object?> docs, String id) =>
      combos(docs).singleWhere((c) => c['id'] == id);

  group('combo recipes', () {
    test('cluster names a blast', () {
      final i = comboIndex('clusterbomb');
      expect(issuesAfter((d) => combo(d, 'clusterbomb')['cluster'] = 'no-such-cluster'), [
        DataIssue('combos.json:/combos/$i/cluster', 'unknown blast "no-such-cluster"'),
      ]);
    });

    test('values.laserType names a projectile', () {
      final i = comboIndex('laser-rocket');
      expect(
        issuesAfter(
          (d) => (combo(d, 'laser-rocket')['values']! as Map)['laserType'] = 'no-such-laser',
        ),
        [
          DataIssue(
            'combos.json:/combos/$i/values/laserType',
            'unknown projectile "no-such-laser"',
          ),
        ],
      );
    });

    test('helperColour is a basic colour the recipe requires', () {
      final i = comboIndex('laser-rocket');
      expect(issuesAfter((d) => combo(d, 'laser-rocket')['helperColour'] = 'yellow'), [
        DataIssue(
          'combos.json:/combos/$i/helperColour',
          'must be a basic colour turret the recipe requires (was "yellow")',
        ),
      ]);
      expect(issuesAfter((d) => combo(d, 'laser-rocket')['helperColour'] = 'sniper'), [
        DataIssue(
          'combos.json:/combos/$i/helperColour',
          'must be a basic colour turret the recipe requires (was "sniper")',
        ),
      ]);
    });

    test('each exact entry is a basic colour the recipe requires', () {
      final i = comboIndex('shockwave');
      expect(issuesAfter((d) => combo(d, 'shockwave')['exact'] = ['blue', 'red']), [
        DataIssue(
          'combos.json:/combos/$i/exact/1',
          'must be a basic colour turret the recipe requires (was "red")',
        ),
      ]);
    });

    test('linkAddsTo and rawValues name keys of values', () {
      final i = comboIndex('laser-rocket');
      expect(
        issuesAfter(
          (d) => combo(d, 'laser-rocket')
            ..['linkAddsTo'] = ['bulletDamage', 'noSuchDamage']
            ..['rawValues'] = ['otherDamage'],
        ),
        [
          DataIssue('combos.json:/combos/$i/linkAddsTo/1', 'not a key of values ("noSuchDamage")'),
          DataIssue('combos.json:/combos/$i/rawValues/0', 'not a key of values ("otherDamage")'),
        ],
      );
    });

    test('defaults.laserType and rocketType name projectiles', () {
      expect(
        issuesAfter(
          (d) => (doc(d, 'combos.json')['defaults']! as Map)
            ..['laserType'] = 'no-such-laser'
            ..['rocketType'] = 'no-such-rocket',
        ),
        [
          const DataIssue('combos.json:/defaults/laserType', 'unknown projectile "no-such-laser"'),
          const DataIssue(
            'combos.json:/defaults/rocketType',
            'unknown projectile "no-such-rocket"',
          ),
        ],
      );
    });
  });

  group('audio events held in parameters', () {
    test('Fusion tier sounds and a blast sound are referenced', () {
      final data = loadClassicData();
      expect(
        data.referencedAudioEvents,
        containsAll(['fusion-low', 'fusion-med', 'fusion-high', 'fusion-max', 'tazer']),
      );
    });

    test('an unknown one is reported', () {
      final turrets = (doc(loadDataDocuments(), 'turrets.json')['turrets']! as List)
          .cast<Map<String, Object?>>();
      final fusion = turrets.singleWhere((t) => t['id'] == 'fusion');
      expect((fusion['specialParams']! as Map)['fusion'], containsPair('soundMax', 'fusion-max'));
      expect(
        issuesAfter((d) {
          final f = (doc(d, 'turrets.json')['turrets']! as List)
              .cast<Map<String, Object?>>()
              .singleWhere((t) => t['id'] == 'fusion');
          ((f['specialParams']! as Map)['fusion'] as Map)['soundMax'] = 'no-such-sound';
          final blasts = (doc(d, 'blasts.json')['blasts']! as List).cast<Map<String, Object?>>();
          (blasts.singleWhere((b) => b['id'] == 'cluster-sparks')['params']! as Map)['sound'] =
              'no-blast-sound';
        }),
        unorderedEquals([
          const DataIssue('audio.json:/events', 'missing event "no-such-sound" referenced by data'),
          const DataIssue(
            'audio.json:/events',
            'missing event "no-blast-sound" referenced by data',
          ),
        ]),
      );
    });
  });

  test('attract creepTypes is at most the number of creep types', () {
    final types = loadClassicData().creeps.types.length;
    expect(issuesAfter((d) => doc(d, 'attract.json')['creepTypes'] = types + 1), [
      DataIssue(
        'attract.json:/creepTypes',
        'must be at most the $types creep types (was ${types + 1})',
      ),
    ]);
    expect(issuesAfter((d) => doc(d, 'attract.json')['creepTypes'] = types), isEmpty);
  });

  test('a completeAll unlock lists difficulties', () {
    final unlocks = (doc(loadDataDocuments(), 'progression.json')['unlocks']! as List)
        .cast<Map<String, Object?>>();
    final i = unlocks.indexWhere((u) => u['rule'] == 'completeAll');
    expect(i, isNonNegative);
    expect(
      issuesAfter(
        (d) => ((doc(d, 'progression.json')['unlocks']! as List)[i] as Map).remove('difficulties'),
      ),
      [DataIssue('progression.json:/unlocks/$i/difficulties', 'is required for rule completeAll')],
    );
  });
}
