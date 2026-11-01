import 'package:onslaught_core/testing.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

/// Same seed + commands ⇒ identical events and hashes, run twice in one
/// process. CI runs this on the VM (macOS and Linux) and in Chrome.
Future<void> main() async {
  final inputs = await loadRegressionInputs();
  final recorder = FixtureRecorder(inputs.data);
  for (final s in inputs.scenarios.entries) {
    test('deterministic: ${s.key}', () {
      final a = recorder.record(s.value);
      final b = recorder.record(s.value);
      expect(FixtureRecorder.diff(a, b), isNull);
    });
  }
}
