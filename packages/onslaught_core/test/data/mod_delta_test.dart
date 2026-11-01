import 'package:onslaught_core/onslaught_core.dart';
import 'package:test/test.dart';

import '../support/repo_data.dart';

void main() {
  final docs = <String, Object?>{
    'turrets.json': {
      'schemaVersion': 1,
      'turrets': [
        {
          'id': 'blue',
          'cost': 10,
          'stats': {'damage': 15, 'range': 130},
        },
        {'id': 'red', 'cost': 20},
      ],
    },
    'rules.json': {
      'economy': {'lives': 10, 'sellRefund': 0.7},
    },
  };

  test('patches a record inside an id-keyed array', () {
    final out = const ModDelta({
      'turrets.json': {
        'turrets': {
          'blue': {
            'stats': {'damage': 99},
          },
        },
      },
    }).applyTo(docs);
    final turrets = (out['turrets.json']! as Map)['turrets'] as List;
    expect(turrets[0], {
      'id': 'blue',
      'cost': 10,
      'stats': {'damage': 99, 'range': 130},
    });
    expect(turrets[1], {'id': 'red', 'cost': 20});
  });

  test('null deletes keys and records; unknown ids append', () {
    final out = const ModDelta({
      'turrets.json': {
        'turrets': {
          'red': null,
          'pink': {'cost': 5},
        },
      },
      'rules.json': {
        'economy': {'sellRefund': null},
      },
    }).applyTo(docs);
    final turrets = (out['turrets.json']! as Map)['turrets'] as List;
    expect(turrets.map((t) => (t as Map)['id']), ['blue', 'pink']);
    expect((out['rules.json']! as Map)['economy'], {'lives': 10});
  });

  test('a patch for an unknown id that is not an object is appended for the reader to report', () {
    final out = const ModDelta({
      'turrets.json': {
        'turrets': {
          'pink': 5,
          'grey': [1, 2],
        },
      },
    }).applyTo(docs);
    final turrets = (out['turrets.json']! as Map)['turrets'] as List;
    expect(turrets.skip(2), [
      5,
      [1, 2],
    ]);

    final classic = loadDataDocuments();
    final count = ((classic['turrets.json']! as Map)['turrets'] as List).length;
    expect(
      () => GameData.fromDocuments(
        classic,
        delta: const ModDelta({
          'turrets.json': {
            'turrets': {'pink': 5},
          },
        }),
      ),
      throwsA(
        isA<DataValidationException>().having(
          (e) => e.issues,
          'issues',
          contains(DataIssue('turrets.json:/turrets/$count', 'expected an object')),
        ),
      ),
    );
  });

  test('does not mutate its input', () {
    const ModDelta({
      'rules.json': {
        'economy': {'lives': 1},
      },
    }).applyTo(docs);
    expect(((docs['rules.json']! as Map)['economy'] as Map)['lives'], 10);
  });

  test('round-trips through JSON and rejects bad documents', () {
    const d = ModDelta({
      'rules.json': {
        'economy': {'lives': 3},
      },
    }, name: 'Hard mode');
    final back = ModDelta.fromJson(d.toJson());
    expect(back.name, 'Hard mode');
    expect(back.files, d.files);
    expect(
      () => ModDelta.fromJson(const {'schemaVersion': 2, 'files': <String, Object?>{}}),
      throwsA(isA<DataValidationException>()),
    );
    expect(
      () => ModDelta.fromJson(const {'schemaVersion': 1, 'files': <String, Object?>{}, 'oops': 1}),
      throwsA(isA<DataValidationException>()),
    );
  });
}
