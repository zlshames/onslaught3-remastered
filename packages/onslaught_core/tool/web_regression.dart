// Runs the regression and determinism suites in a browser, so fixtures
// recorded on the VM are proven to replay identically on the web.
//
//   fvm dart run tool/web_regression.dart                 # Chrome, dart2js
//   fvm dart run tool/web_regression.dart -c dart2wasm    # Chrome, WebAssembly
//
// Run from packages/onslaught_core. Browser tests cannot read files, so this
// first bundles the committed fixtures, scenarios and assets/data into
// build/web_test/regression_inputs.json (git-ignored), then runs
// `dart test -p chrome` on the regression and determinism suites and the
// unit tests of what they rest on (det_math, canonical JSON), plus any extra
// arguments, and exits with its exit code.
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import '../test/support/fixture_files_io.dart';
import '../test/support/fixtures.dart' show webInputsPath;

/// The suites that must pass in the browser.
const webSuites = [
  'test/regression',
  'test/math/det_math_test.dart',
  'test/sim/stable_hash_test.dart',
];

Future<void> main(List<String> args) async {
  final texts = readRegressionTextsSync();
  File(webInputsPath)
    ..createSync(recursive: true)
    ..writeAsStringSync(jsonEncode(texts));
  print(
    'bundled ${texts['fixtures']!.length} fixtures, ${texts['scenarios']!.length} scenarios '
    'and ${texts['data']!.length} data documents into $webInputsPath',
  );
  final test = await Process.start(Platform.resolvedExecutable, [
    'test',
    '-p',
    'chrome',
    ...args,
    ...webSuites,
  ], mode: ProcessStartMode.inheritStdio);
  exit(await test.exitCode);
}
