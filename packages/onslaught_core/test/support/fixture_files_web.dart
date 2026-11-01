// Browser side of `fixtures.dart`. A browser test cannot read files, so
// `tool/web_regression.dart` bundles the regression inputs into one JSON file
// inside the package (which the test runner serves) before it starts the
// browser run, and this fetches it.
import 'dart:convert';
import 'dart:js_interop';

import 'fixtures.dart' show webInputsPath;

@JS('fetch')
external JSPromise<_Response> _fetch(JSString url);

extension type _Response(JSObject _) implements JSObject {
  external bool get ok;
  external int get status;
  external JSPromise<JSString> text();
}

Future<Map<String, Map<String, String>>> readRegressionTexts() async {
  // The runner serves the package directory at the path above `test/`.
  final page = Uri.base.path;
  final root = page.substring(0, page.lastIndexOf('/test/') + 1);
  final url = Uri.base.replace(path: '$root$webInputsPath', query: '').toString();
  final response = await _fetch(url.toJS).toDart;
  if (!response.ok) {
    throw StateError(
      'GET $url: ${response.status}. Start browser runs with '
      '`fvm dart run tool/web_regression.dart`, which writes $webInputsPath first.',
    );
  }
  final decoded = (jsonDecode((await response.text().toDart).toDart) as Map)
      .cast<String, Object?>();
  return {for (final e in decoded.entries) e.key: (e.value! as Map).cast<String, String>()};
}
