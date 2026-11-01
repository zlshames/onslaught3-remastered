import 'package:onslaught_core/testing.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

/// Faithful-mode regression suite: every fixture's scenario must replay to
/// exactly the recorded events and state hashes. To change one on purpose,
/// re-record it with `fvm dart run tool/fixture.dart record <id>` and explain
/// the rule change in the commit (rule R15, regression-fixtures skill).
///
/// Runs on the VM and in the browser (`fvm dart test -p chrome test/regression`),
/// so a fixture recorded on the VM must replay identically on the web.
Future<void> main() async {
  final inputs = await loadRegressionInputs();
  final fixtures = inputs.fixtures;
  final scenarios = inputs.scenarios;
  final recorder = FixtureRecorder(inputs.data);

  test('every scenario has a recorded fixture and vice versa', () {
    expect(fixtures.keys.toSet(), scenarios.keys.toSet());
  });

  for (final entry in fixtures.entries) {
    test('replays ${entry.key}', () {
      final diff = recorder.verify(entry.value);
      expect(
        diff,
        isNull,
        reason: '$diff\nInspect with: fvm dart run tool/fixture.dart diff ${entry.key}',
      );
    });

    test('scenario file and fixture agree for ${entry.key}', () {
      expect(entry.value.scenario.toJson(), scenarios[entry.key]?.toJson());
    });
  }
}
