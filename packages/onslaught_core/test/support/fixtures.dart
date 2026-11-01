import 'dart:convert';

import 'package:onslaught_core/onslaught_core.dart';
import 'package:onslaught_core/testing.dart';

import 'fixture_files_web.dart' if (dart.library.io) 'fixture_files_io.dart' as files;

const scenariosDir = 'test/fixtures/scenarios';
const regressionDir = 'test/fixtures/regression';

/// The bundle of regression inputs `tool/web_regression.dart` writes for
/// browser runs, relative to the package (git-ignored).
const webInputsPath = 'build/web_test/regression_inputs.json';

/// What the regression and determinism suites run on: the committed fixtures
/// and scenarios by id (`area/name`) and the classic game data.
class RegressionInputs {
  RegressionInputs._(this.fixtures, this.scenarios, this.data);

  /// Decodes the raw texts of [files.readRegressionTexts]: `fixtures` and
  /// `scenarios` keyed by id, `data` keyed by path under `assets/data`.
  factory RegressionInputs.fromTexts(Map<String, Map<String, String>> texts) {
    Map<String, Object?> decode(String text) => (jsonDecode(text) as Map).cast<String, Object?>();
    return RegressionInputs._(
      {for (final e in texts['fixtures']!.entries) e.key: Fixture.fromJson(decode(e.value))},
      {for (final e in texts['scenarios']!.entries) e.key: Scenario.fromJson(decode(e.value))},
      GameData.fromDocuments({
        for (final e in texts['data']!.entries) e.key: jsonDecode(e.value),
      }, behaviours: RulesRegistry.classic()),
    );
  }

  final Map<String, Fixture> fixtures;
  final Map<String, Scenario> scenarios;
  final GameData data;
}

/// Loads [RegressionInputs] on any platform: from disk on the VM, and on the
/// web through a VM-side helper (`fixture_files_hybrid.dart`), since a
/// browser test cannot read files. Await it in `main` before declaring tests.
Future<RegressionInputs> loadRegressionInputs() async =>
    RegressionInputs.fromTexts(await files.readRegressionTexts());
