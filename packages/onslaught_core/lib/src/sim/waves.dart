import '../data/creep_wave_defs.dart';
import '../rules/economy_rules.dart';

/// One wave being sent (`WaveManager`): spawns [size] creeps, one per check
/// once more than `creepSpacingMs` has passed since the previous one.
class WaveSpawner {
  WaveSpawner({
    required this.wave,
    required this.size,
    required this.creepType,
    required this.hp,
    required this.bounty,
    required this.speed,
    required this.scaleBump,
  });

  final int wave;
  final int size;
  final int creepType;

  /// HP of each creep (`energy_start`), already scaled by wave size.
  final double hp;
  final int bounty;
  final double speed;
  final double scaleBump;

  /// Creeps spawned so far (`wave_sent`).
  int sent = 0;

  /// Game time of the last spawn (`attacker_last`; 0 until the first, so the
  /// first check spawns unless the game is younger than the spacing).
  double lastSpawnMs = 0;

  /// Game ms since this spawner's last check (its own 200 ms interval,
  /// started when the wave was sent).
  double sinceCheckMs = 0;

  bool get done => sent >= size;

  Map<String, Object?> toJson() => {
    'wave': wave,
    'sent': sent,
    'lastSpawnMs': lastSpawnMs,
    'sinceCheckMs': sinceCheckMs,
  };
}

/// The wave scheduler's state (`AttackerManager`): the wave counter, the
/// current per-creep HP, when the last wave left and the spawners at work.
class WaveState {
  WaveState({required this.creepHp, required this.hpRate});

  /// Number of the last wave sent (0 before the first).
  int wave = 0;

  /// HP of a normal-size creep of the current wave (`attacker_energy`);
  /// multiplied by the difficulty's rate as each wave is sent.
  double creepHp;

  /// The per-wave HP multiplier in force (`attacker_upgrade_rate`); a wave
  /// with an entry in the difficulty's schedule switches it first.
  double hpRate;

  /// Game time the last wave was sent (`wave_last`; the game start before
  /// the first).
  double lastWaveMs = 0;

  /// Game ms since the manager's last check.
  double sinceCheckMs = 0;

  final List<WaveSpawner> spawners = [];

  /// Game ms until the wave clock (every [spacingMs]) sends the next wave
  /// (negative once due).
  double msUntilNextWave(double nowMs, double spacingMs) => spacingMs - (nowMs - lastWaveMs);

  /// Advances to the next wave (`AttackerManager._waveNext` + `waveSend`)
  /// and returns its spawner. [rates] is the difficulty's schedule (wave →
  /// new rate). A wave of [size] creeps (a challenge's size list; the
  /// standard size otherwise) carries the HP and bounty of a standard wave
  /// shared among them, and with [sizeChange] its creeps are drawn bigger.
  WaveSpawner next({
    required WaveDefs defs,
    required Map<int, double> rates,
    required double speed,
    required int creepTypes,
    required double nowMs,
    int? size,
    bool? sizeChange,
  }) {
    wave++;
    hpRate = rates[wave] ?? hpRate;
    creepHp *= hpRate;
    lastWaveMs = nowMs;
    final n = size ?? defs.waveSize;
    final scale = waveSizeScale(n, defs.waveSize);
    final spawner = WaveSpawner(
      wave: wave,
      size: n,
      creepType: creepTypeIndex(wave, creepTypes),
      hp: creepHp * scale,
      bounty: creepBounty(wave, n, defs.waveSize),
      speed: speed,
      scaleBump: (sizeChange ?? defs.sizeChange) ? scale : 1,
    );
    spawners.add(spawner);
    return spawner;
  }

  Map<String, Object?> toJson() => {
    'wave': wave,
    'creepHp': creepHp,
    'hpRate': hpRate,
    'lastWaveMs': lastWaveMs,
    'sinceCheckMs': sinceCheckMs,
    'spawners': [for (final s in spawners) s.toJson()],
  };
}
