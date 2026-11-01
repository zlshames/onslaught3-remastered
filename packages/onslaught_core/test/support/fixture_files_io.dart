// VM side of `fixtures.dart`: reads the regression inputs from disk.
import 'dart:io';

import 'fixtures.dart' show regressionDir, scenariosDir;
import 'repo_data.dart';

/// The raw texts `RegressionInputs.fromTexts` decodes.
Map<String, Map<String, String>> readRegressionTextsSync() => {
  'fixtures': _jsonTree(regressionDir),
  'scenarios': _jsonTree(scenariosDir),
  'data': readDataTexts(),
};

Future<Map<String, Map<String, String>>> readRegressionTexts() async => readRegressionTextsSync();

/// Every `.json` file under [root] (relative to the package), by its path
/// below [root] without the extension, in path order.
Map<String, String> _jsonTree(String root) {
  final dir = Directory(root);
  if (!dir.existsSync()) return const {};
  final files =
      dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return {
    for (final f in files)
      f.path.substring(root.length + 1, f.path.length - '.json'.length): f.readAsStringSync(),
  };
}
