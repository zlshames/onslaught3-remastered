import 'package:meta/meta.dart';

import 'json_reader.dart';

/// One page of the tutorial.
@immutable
class TutorialPage {
  const TutorialPage({
    required this.title,
    required this.body,
    this.pointer,
    this.setCash,
    this.showNow = false,
  });

  factory TutorialPage.fromJson(JsonReader r) {
    r.expectOnlyKeys({'title', 'body', 'pointer', 'setCash', 'showNow'});
    return TutorialPage(
      title: r.string('title'),
      body: r.string('body'),
      pointer: r.optString('pointer'),
      setCash: r.optNumber('setCash', min: 0),
      showNow: r.optBoolean('showNow', fallback: false),
    );
  }

  final String title;
  final String body;

  /// Logical UI target the "Show me" arrow points at.
  final String? pointer;

  /// Cash is set to this (once per tutorial) when the page's "Show me" is used.
  final double? setCash;

  /// The arrow is shown as soon as the page opens (`show_now`).
  final bool showNow;

  Map<String, Object?> toJson() => {
    'title': title,
    'body': body,
    'pointer': ?pointer,
    'setCash': ?optJsonNumber(setCash),
    if (showNow) 'showNow': true,
  };
}

/// `tutorial.json`.
@immutable
class TutorialDefs {
  const TutorialDefs({required this.pages, required this.waveLimit, required this.map});

  factory TutorialDefs.fromJson(JsonReader r) {
    r.expectOnlyKeys({'schemaVersion', 'pages', 'waveLimit', 'map'});
    return TutorialDefs(
      pages: r.list('pages', TutorialPage.fromJson, minLength: 1),
      waveLimit: r.integer('waveLimit', min: 1),
      map: r.string('map'),
    );
  }

  static const int schemaVersion = 1;
  final List<TutorialPage> pages;
  final int waveLimit;
  final String map;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'map': map,
    'waveLimit': waveLimit,
    'pages': [for (final p in pages) p.toJson()],
  };
}
