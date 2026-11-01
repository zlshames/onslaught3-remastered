import 'package:meta/meta.dart';

import 'json_reader.dart';

/// `strings/<locale>.json`.
@immutable
class StringTable {
  const StringTable({required this.locale, required this.strings});

  factory StringTable.fromJson(JsonReader r) {
    r.expectOnlyKeys({'schemaVersion', 'locale', 'strings'});
    return StringTable(
      locale: r.string('locale'),
      strings: r.mapOf('strings', (c) => c.asString()),
    );
  }

  static const int schemaVersion = 1;
  final String locale;
  final Map<String, String> strings;

  /// The string for [key], or the key itself so a missing string is visible.
  String operator [](String key) => strings[key] ?? key;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'locale': locale,
    'strings': strings,
  };
}
