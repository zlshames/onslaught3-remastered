import 'package:onslaught_core/onslaught_core.dart';
import 'package:test/test.dart';

void main() {
  test('collects every issue with its path instead of stopping at the first', () {
    final sink = IssueSink();
    final r = JsonReader.root(
      {
        'schemaVersion': 1,
        'stats': {'range': 900, 'rate': 'fast'},
        'rnage': 1,
      },
      'turrets.json',
      sink,
    );
    r.expectOnlyKeys({'schemaVersion', 'stats'});
    final stats = r.child('stats');
    expect(stats.number('range', min: 10, max: 800), 900);
    expect(stats.number('rate'), 0);
    expect(stats.number('damage'), 0);
    expect(sink.issues.map((i) => i.toString()), [
      'turrets.json:/rnage: unknown key',
      'turrets.json:/stats/range: must be between 10 and 800 (was 900.0)',
      'turrets.json:/stats/rate: expected a number',
      'turrets.json:/stats/damage: is required',
    ]);
    expect(sink.throwIfAny, throwsA(isA<DataValidationException>()));
  });

  test('schema version mismatch is reported', () {
    final sink = IssueSink();
    readSchemaVersion(JsonReader.root({'schemaVersion': 3}, 'x.json', sink), supported: 1);
    expect(sink.issues.single.reason, contains('unsupported schema version 3'));
  });

  test('integers reject fractions; lists and maps read in order', () {
    final sink = IssueSink();
    final r = JsonReader.root(
      {
        'n': 1.5,
        'l': [1, 2],
        'm': {'b': 2, 'a': 1},
      },
      'f',
      sink,
    );
    r.integer('n');
    expect(r.list('l', (c) => c.asInt()), [1, 2]);
    expect(r.mapOf('m', (c) => c.asInt()).keys, ['b', 'a']);
    expect(sink.issues.single.path, 'f:/n');
  });

  test('lists and maps it reads are unmodifiable', () {
    final r = JsonReader.root(
      {
        'l': [1, 2],
        'm': {'a': 1},
        'nested': {
          'a': [1],
        },
      },
      'f',
      IssueSink(),
    );
    expect(() => r.list('l', (c) => c.asInt()).add(3), throwsUnsupportedError);
    expect(() => r.optList('l', (c) => c.asInt()).add(3), throwsUnsupportedError);
    expect(() => r.mapOf('m', (c) => c.asInt())['b'] = 2, throwsUnsupportedError);
    expect(() => r.child('m').asMapOf((c) => c.asInt())['b'] = 2, throwsUnsupportedError);
    final nested = r.mapOf('nested', (c) => c.asList((e) => e.asInt()));
    expect(() => nested['a']!.add(2), throwsUnsupportedError);
  });

  test('point and asPoint read {x, y} and report extra or missing keys', () {
    final sink = IssueSink();
    final r = JsonReader.root(
      {
        'p': {'x': 1, 'y': 2.5},
        'bad': {'x': 1, 'z': 0},
        'road': [
          {'x': 0, 'y': 0},
          {'x': 3, 'y': 4},
        ],
      },
      'f',
      sink,
    );
    expect(r.point('p'), const Vec2(1, 2.5));
    expect(r.list('road', (c) => c.asPoint()), const [Vec2(0, 0), Vec2(3, 4)]);
    expect(sink.isEmpty, isTrue);
    expect(r.point('bad'), const Vec2(1, 0));
    expect(sink.issues.map((i) => i.toString()), [
      'f:/bad/z: unknown key',
      'f:/bad/y: is required',
    ]);
  });

  test('optChild reads a present object and gives null for an absent or null one', () {
    final sink = IssueSink();
    final r = JsonReader.root(
      {
        'a': {'n': 3},
        'nil': null,
      },
      'f',
      sink,
    );
    double n(JsonReader c) => c.number('n');
    expect(r.optChild('a', n), 3);
    expect(r.optChild('nil', n), isNull);
    expect(r.optChild('missing', n), isNull);
    expect(sink.isEmpty, isTrue);
  });

  test('projectile and blast specs read the same record', () {
    Map<String, Object?> entry(String kind) => {
      'id': 'x',
      'legacyId': 'L',
      'kind': kind,
      'sprite': 's',
      'params': {'speed': 2},
    };
    final sink = IssueSink();
    final p = ProjectileSpec.fromJson(JsonReader.root(entry('shell'), 'projectiles.json', sink));
    final b = BlastSpec.fromJson(JsonReader.root(entry('blast'), 'blasts.json', sink));
    expect(sink.isEmpty, isTrue);
    for (final (spec, kind) in [(p, 'shell'), (b, 'blast')]) {
      expect(spec.id, 'x');
      expect(spec.legacyId, 'L');
      expect(spec.kind, kind);
      expect(spec.sprite, 's');
      expect(spec.params.number('speed'), 2);
    }
    final bad = IssueSink();
    BlastSpec.fromJson(JsonReader.root({'id': 'y', 'kind': 'blast', 'oops': 1}, 'b', bad));
    expect(bad.issues.map((i) => i.toString()), ['b:/oops: unknown key']);
  });
}
