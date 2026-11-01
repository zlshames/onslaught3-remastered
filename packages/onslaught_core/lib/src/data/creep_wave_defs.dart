import 'package:meta/meta.dart';

import 'json_reader.dart';
import 'params.dart';

/// One visual creep type from `creeps.json` (`Attacker0`…`Attacker8`).
@immutable
class CreepType {
  const CreepType({
    required this.id,
    required this.legacyId,
    required this.repoint,
    required this.hpMult,
    required this.speedMult,
    required this.sprite,
  });

  factory CreepType.fromJson(JsonReader r) {
    r.expectOnlyKeys({'id', 'legacyId', 'repoint', 'hpMult', 'speedMult', 'sprite'});
    return CreepType(
      id: r.string('id'),
      legacyId: r.string('legacyId'),
      repoint: r.boolean('repoint'),
      hpMult: r.number('hpMult', min: 0),
      speedMult: r.number('speedMult', min: 0),
      sprite: r.string('sprite'),
    );
  }

  final String id;
  final String legacyId;

  /// Whether the sprite rotates to face its direction of travel.
  final bool repoint;
  final double hpMult;
  final double speedMult;
  final String sprite;

  Map<String, Object?> toJson() => {
    'id': id,
    'legacyId': legacyId,
    'repoint': repoint,
    'hpMult': jsonNumber(hpMult),
    'speedMult': jsonNumber(speedMult),
    'sprite': sprite,
  };
}

/// `creeps.json`: the creep types (in wave rotation order) and movement rules.
@immutable
class CreepDefs {
  const CreepDefs({required this.types, required this.movement});

  factory CreepDefs.fromJson(JsonReader r) {
    r.expectOnlyKeys({'schemaVersion', 'types', 'movement'});
    return CreepDefs(
      types: r.list('types', CreepType.fromJson, minLength: 1),
      movement: Params.fromJson(r.child('movement')),
    );
  }

  static const int schemaVersion = 1;

  /// Types in rotation order: wave N uses `types[(N - 1) % types.length]`.
  final List<CreepType> types;

  /// Waypoint jitter, spawn fade-in, size bump … (`AttackerEngine`).
  final Params movement;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'types': [for (final t in types) t.toJson()],
    'movement': movement.toJson(),
  };
}

/// One `{wave, rate}` step of an HP growth schedule: from [wave] on, creep HP
/// is multiplied by [rate] each wave.
@immutable
class HpRateStep {
  const HpRateStep(this.wave, this.rate);

  factory HpRateStep.fromJson(JsonReader r) {
    r.expectOnlyKeys({'wave', 'rate'});
    return HpRateStep(r.integer('wave', min: 1), r.number('rate', min: 0));
  }

  final int wave;
  final double rate;

  Map<String, Object?> toJson() => {'wave': wave, 'rate': jsonNumber(rate)};
}

/// A difficulty level from `difficulty.json`.
@immutable
class DifficultyDef {
  const DifficultyDef({
    required this.id,
    required this.name,
    required this.creepSpeed,
    required this.startingCash,
    required this.hpSchedule,
  });

  factory DifficultyDef.fromJson(JsonReader r) {
    r.expectOnlyKeys({'id', 'name', 'creepSpeed', 'startingCash', 'hpSchedule'});
    return DifficultyDef(
      id: r.string('id'),
      name: r.string('name'),
      creepSpeed: r.number('creepSpeed', min: 0),
      startingCash: r.number('startingCash', min: 0),
      hpSchedule: r.list('hpSchedule', HpRateStep.fromJson, minLength: 1),
    );
  }

  final String id;
  final String name;

  /// Base creep speed, px/s.
  final double creepSpeed;
  final double startingCash;
  final List<HpRateStep> hpSchedule;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'creepSpeed': jsonNumber(creepSpeed),
    'startingCash': jsonNumber(startingCash),
    'hpSchedule': [for (final s in hpSchedule) s.toJson()],
  };
}

/// `difficulty.json`.
@immutable
class DifficultyDefs {
  const DifficultyDefs({
    required this.levels,
    required this.baseHp,
    required this.defaultHpRate,
    required this.modeCash,
    this.modeRacks = const {},
  });

  factory DifficultyDefs.fromJson(JsonReader r) {
    r.expectOnlyKeys({
      'schemaVersion',
      'levels',
      'baseHp',
      'defaultHpRate',
      'modeCash',
      'modeRacks',
    });
    return DifficultyDefs(
      levels: r.list('levels', DifficultyDef.fromJson, minLength: 1),
      baseHp: r.number('baseHp', min: 0),
      defaultHpRate: r.number('defaultHpRate', min: 0),
      modeCash: r.mapOf('modeCash', (c) => c.asNumber(min: 0)),
      modeRacks: r.has('modeRacks')
          ? r.mapOf('modeRacks', (c) => c.asList((e) => e.asString()))
          : const {},
    );
  }

  static const int schemaVersion = 1;
  final List<DifficultyDef> levels;

  /// Creep HP before the first wave's multiplier (`attacker_energy`).
  final double baseHp;

  /// Per-wave multiplier used until a schedule step applies
  /// (`attacker_upgrade_rate`).
  final double defaultHpRate;

  /// Starting cash of the non-difficulty modes (sandbox, sandbox2, debug).
  final Map<String, double> modeCash;

  /// Turrets a mode adds to the rack at the start (sandbox, sandbox2), by
  /// turret id.
  final Map<String, List<String>> modeRacks;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'levels': [for (final l in levels) l.toJson()],
    'baseHp': jsonNumber(baseHp),
    'defaultHpRate': jsonNumber(defaultHpRate),
    'modeCash': {for (final e in modeCash.entries) e.key: jsonNumber(e.value)},
    'modeRacks': modeRacks,
  };
}

/// `waves.json`: wave size and timing.
@immutable
class WaveDefs {
  const WaveDefs({
    required this.waveSize,
    required this.waveSpacingMs,
    required this.creepSpacingMs,
    required this.managerTickMs,
    required this.sizeChange,
    required this.spacingPrefMinS,
    required this.spacingPrefMaxS,
  });

  factory WaveDefs.fromJson(JsonReader r) {
    r.expectOnlyKeys({
      'schemaVersion',
      'waveSize',
      'waveSpacingMs',
      'creepSpacingMs',
      'managerTickMs',
      'sizeChange',
      'spacingPref',
    });
    final pref = r.child('spacingPref')..expectOnlyKeys({'minS', 'maxS'});
    return WaveDefs(
      waveSize: r.integer('waveSize', min: 1),
      waveSpacingMs: r.number('waveSpacingMs', min: 0),
      creepSpacingMs: r.number('creepSpacingMs', min: 0),
      managerTickMs: r.number('managerTickMs', min: 1),
      sizeChange: r.boolean('sizeChange'),
      spacingPrefMinS: pref.number('minS', min: 0),
      spacingPrefMaxS: pref.number('maxS', min: 0),
    );
  }

  static const int schemaVersion = 1;

  /// Creeps per wave in normal play.
  final int waveSize;
  final double waveSpacingMs;
  final double creepSpacingMs;

  /// Interval on which the wave manager and each wave's spawner check their
  /// timers. A creep spawns on the first check after [creepSpacingMs], so
  /// the real spacing rounds up to a multiple of this.
  final double managerTickMs;

  /// Whether smaller waves get bigger, tougher creeps
  /// (`attacker_size_change`).
  final bool sizeChange;

  /// Bounds of the wave-spacing setting, seconds.
  final double spacingPrefMinS;
  final double spacingPrefMaxS;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'waveSize': waveSize,
    'waveSpacingMs': jsonNumber(waveSpacingMs),
    'creepSpacingMs': jsonNumber(creepSpacingMs),
    'managerTickMs': jsonNumber(managerTickMs),
    'sizeChange': sizeChange,
    'spacingPref': {'minS': jsonNumber(spacingPrefMinS), 'maxS': jsonNumber(spacingPrefMaxS)},
  };
}
