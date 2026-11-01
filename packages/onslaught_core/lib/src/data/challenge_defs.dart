import 'package:meta/meta.dart';

import 'json_reader.dart';

/// A challenge objective: survive [target] waves or reach [target] kills.
@immutable
class ChallengeObjective {
  const ChallengeObjective(this.type, this.target);

  factory ChallengeObjective.fromJson(JsonReader r) {
    r.expectOnlyKeys({'type', 'target'});
    return ChallengeObjective(
      r.oneOf('type', {'waves', 'kills'}, fallback: 'waves'),
      r.integer('target', min: 1),
    );
  }

  /// [waves] or [kills].
  final String type;
  final int target;

  static const String waves = 'waves';
  static const String kills = 'kills';

  /// The time limit, as an objective kind in events.
  static const String time = 'time';

  Map<String, Object?> toJson() => {'type': type, 'target': target};
}

/// A challenge rule set: a preset from `challenges.json` or a custom one.
@immutable
class ChallengeDef {
  const ChallengeDef({
    required this.id,
    required this.name,
    required this.difficulty,
    required this.objective,
    required this.cash,
    required this.timeLimitS,
    required this.turretLimit,
    required this.waveSizes,
    required this.waveSpeeds,
    required this.debugOnly,
  });

  factory ChallengeDef.fromJson(JsonReader r) {
    r.expectOnlyKeys({
      'id',
      'name',
      'difficulty',
      'objective',
      'cash',
      'timeLimitS',
      'turretLimit',
      'waveSizes',
      'waveSpeeds',
      'debugOnly',
    });
    return ChallengeDef(
      id: r.string('id'),
      name: r.string('name'),
      difficulty: r.string('difficulty'),
      objective: r.optChild('objective', ChallengeObjective.fromJson),
      cash: r.number('cash', min: 0),
      timeLimitS: r.optNumber('timeLimitS', min: 1),
      turretLimit: r.optInteger('turretLimit', min: 1),
      waveSizes: r.list('waveSizes', (c) => c.asInt(min: 1), minLength: 1),
      waveSpeeds: r.list('waveSpeeds', (c) => c.asNumber(min: 1), minLength: 1),
      debugOnly: r.optBoolean('debugOnly', fallback: false),
    );
  }

  final String id;
  final String name;
  final String difficulty;

  /// Null = last as long as you can.
  final ChallengeObjective? objective;
  final double cash;
  final double? timeLimitS;
  final int? turretLimit;

  /// Creeps per wave, cycled.
  final List<int> waveSizes;

  /// Creep speed per wave, px/s, cycled.
  final List<double> waveSpeeds;
  final bool debugOnly;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'difficulty': difficulty,
    'objective': ?objective?.toJson(),
    'cash': jsonNumber(cash),
    'timeLimitS': ?optJsonNumber(timeLimitS),
    'turretLimit': ?turretLimit,
    'waveSizes': waveSizes,
    'waveSpeeds': [for (final s in waveSpeeds) jsonNumber(s)],
    if (debugOnly) 'debugOnly': true,
  };
}

/// One option in a challenge picker. [value] is null for "unlimited"/"none".
@immutable
class PickerOption {
  const PickerOption(this.label, this.value, {this.requiresMode});

  factory PickerOption.fromJson(JsonReader r) {
    r.expectOnlyKeys({'label', 'value', 'requiresMode'});
    final v = r.child('value').raw;
    if (v != null && v is! num && v is! String) {
      r.child('value').issue('expected a number, string or null');
    }
    return PickerOption(
      r.string('label'),
      v is num || v is String ? v : null,
      requiresMode: r.optString('requiresMode'),
    );
  }

  final String label;
  final Object? value;

  /// Mode that must be unlocked before this option is offered.
  final String? requiresMode;

  /// [value] is always written, null included ("unlimited").
  Map<String, Object?> toJson() => {
    'label': label,
    'value': switch (value) {
      final num n => jsonNumber(n),
      final v => v,
    },
    'requiresMode': ?requiresMode,
  };
}

/// `challenges.json`: presets and the custom-challenge pickers.
@immutable
class ChallengeDefs {
  const ChallengeDefs({
    required this.presets,
    required this.pickers,
    this.classicPickers = const {},
  });

  factory ChallengeDefs.fromJson(JsonReader r) {
    r.expectOnlyKeys({'schemaVersion', 'presets', 'pickers', 'classicPickers'});
    Map<String, List<PickerOption>> pickerMap(String key) =>
        r.mapOf(key, (c) => c.asList(PickerOption.fromJson));
    return ChallengeDefs(
      presets: r.list('presets', ChallengeDef.fromJson),
      pickers: pickerMap('pickers'),
      classicPickers: r.has('classicPickers') ? pickerMap('classicPickers') : const {},
    );
  }

  static const int schemaVersion = 1;
  final List<ChallengeDef> presets;

  /// Picker id (difficulty, objective, cash, timeLimit, turretLimit,
  /// waveSize, waveSpeed) → options in display order, with the original's
  /// data bugs corrected (`RulesProfile.challengePickerData`).
  final Map<String, List<PickerOption>> pickers;

  /// The original options of the pickers [pickers] corrects.
  final Map<String, List<PickerOption>> classicPickers;

  /// The pickers to offer: corrected when [corrected], else the original's.
  Map<String, List<PickerOption>> pickersFor({required bool corrected}) =>
      corrected ? pickers : {...pickers, ...classicPickers};

  Map<String, Object?> toJson() {
    Map<String, Object?> pickerMap(Map<String, List<PickerOption>> m) => {
      for (final e in m.entries) e.key: [for (final o in e.value) o.toJson()],
    };
    return {
      'schemaVersion': schemaVersion,
      'presets': [for (final p in presets) p.toJson()],
      'pickers': pickerMap(pickers),
      'classicPickers': pickerMap(classicPickers),
    };
  }
}
