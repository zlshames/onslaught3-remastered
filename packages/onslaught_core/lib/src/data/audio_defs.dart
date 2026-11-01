import 'package:meta/meta.dart';

import 'json_reader.dart';

/// `audio.json`: audio event id → clip asset ids, plus mix rules.
@immutable
class AudioDefs {
  const AudioDefs({required this.events, required this.volume, required this.panSpread});

  factory AudioDefs.fromJson(JsonReader r) {
    r.expectOnlyKeys({'schemaVersion', 'events', 'volume', 'panSpread'});
    return AudioDefs(
      events: r.mapOf('events', (c) => c.asList((e) => e.asString())),
      volume: r.number('volume', min: 0, max: 100),
      panSpread: r.number('panSpread', min: 0),
    );
  }

  static const int schemaVersion = 1;

  /// Event id → clip asset ids (one is picked at random per play).
  final Map<String, List<String>> events;

  /// Default volume, 0–100.
  final double volume;

  /// Pan = (panSpread · x / playWidth − panSpread / 2).
  final double panSpread;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'volume': jsonNumber(volume),
    'panSpread': jsonNumber(panSpread),
    'events': events,
  };
}
