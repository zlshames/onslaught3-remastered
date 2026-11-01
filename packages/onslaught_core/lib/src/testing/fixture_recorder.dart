import 'dart:convert';

import '../data/game_data.dart';
import '../rules/rules_registry.dart';
import '../sim/stable_hash.dart';
import 'sim_test_harness.dart';

/// A recorded run of a [Scenario]: the full event log and periodic state
/// hashes. Replays must match exactly; this is what freezes v1 behaviour.
class Fixture {
  const Fixture({
    required this.scenario,
    required this.events,
    required this.hashes,
    this.recordedWith,
  });

  factory Fixture.fromJson(Map<String, Object?> j) {
    final v = (j['schemaVersion']! as num).toInt();
    if (v != schemaVersion) {
      throw FormatException('fixture schemaVersion $v, expected $schemaVersion');
    }
    return Fixture(
      scenario: Scenario.fromJson((j['scenario']! as Map).cast<String, Object?>()),
      events: [for (final e in j['events']! as List<Object?>) (e! as Map).cast<String, Object?>()],
      hashes: [
        for (final h in j['hashes']! as List<Object?>)
          StateHash.fromJson((h! as Map).cast<String, Object?>()),
      ],
      recordedWith: j['recordedWith'] as String?,
    );
  }

  /// Version of the fixture format, event serialisation and hash algorithm.
  /// Changing any of them re-records every fixture in one dedicated commit.
  static const int schemaVersion = 1;

  final Scenario scenario;

  /// Events as JSON (`{tick, type, …}`).
  final List<Map<String, Object?>> events;
  final List<StateHash> hashes;

  /// Free-form provenance (e.g. a git sha); not compared.
  final String? recordedWith;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'scenario': scenario.toJson(),
    'recordedWith': ?recordedWith,
    'eventCount': events.length,
    'events': events,
    'hashes': [for (final h in hashes) h.toJson()],
  };

  /// Pretty JSON with a trailing newline, as committed.
  String encode() => '${const JsonEncoder.withIndent('  ').convert(toJson())}\n';
}

/// Where a replay first diverged from its fixture.
class FixtureDiff {
  const FixtureDiff(this.message, {this.eventIndex, this.tick});
  final String message;
  final int? eventIndex;
  final int? tick;

  @override
  String toString() => message;
}

/// Records and replays [Fixture]s.
class FixtureRecorder {
  FixtureRecorder(this.data, {RulesRegistry? registry})
    : harness = SimTestHarness(data, registry: registry);

  final GameData data;
  final SimTestHarness harness;

  Fixture record(Scenario scenario, {String? recordedWith}) {
    final run = harness.run(scenario);
    return Fixture(
      scenario: scenario,
      events: [for (final e in run.events) e.toJson()],
      hashes: run.hashes,
      recordedWith: recordedWith,
    );
  }

  /// Replays [fixture]'s scenario; null when it matches exactly.
  FixtureDiff? verify(Fixture fixture) => diff(fixture, record(fixture.scenario));

  /// The first difference between [expected] and [actual], or null.
  static FixtureDiff? diff(Fixture expected, Fixture actual) {
    final n = expected.events.length < actual.events.length
        ? expected.events.length
        : actual.events.length;
    for (var i = 0; i < n; i++) {
      final a = canonicalJson(expected.events[i]);
      final b = canonicalJson(actual.events[i]);
      if (a != b) {
        return FixtureDiff(
          'event $i differs:\n  expected $a\n  actual   $b',
          eventIndex: i,
          tick: (expected.events[i]['tick'] as num?)?.toInt(),
        );
      }
    }
    if (expected.events.length != actual.events.length) {
      return FixtureDiff(
        'event count differs: expected ${expected.events.length}, '
        'actual ${actual.events.length} (first extra at index $n)',
        eventIndex: n,
      );
    }
    for (var i = 0; i < expected.hashes.length && i < actual.hashes.length; i++) {
      if (expected.hashes[i] != actual.hashes[i]) {
        final e = expected.hashes[i];
        return FixtureDiff(
          'state hash differs after tick ${e.tick}: expected ${e.hash}, '
          'actual ${actual.hashes[i].hash}',
          tick: e.tick,
        );
      }
    }
    if (expected.hashes.length != actual.hashes.length) {
      return FixtureDiff(
        'hash count differs: expected ${expected.hashes.length}, '
        'actual ${actual.hashes.length}',
      );
    }
    return null;
  }
}
