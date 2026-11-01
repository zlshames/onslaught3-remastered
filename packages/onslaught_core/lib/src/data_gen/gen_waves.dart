/// `creeps.json`, `difficulty.json` and `waves.json` from the legacy table.
library;

import '../data/creep_wave_defs.dart';
import 'legacy_table.dart';

/// `creeps.json`: the creep types (`Attacker0`…) and movement rules.
CreepDefs generateCreeps(LegacyTable l) {
  final c = l.eng('creeps');
  final repoint = (c['repoint']! as List<Object?>).cast<bool>();
  return CreepDefs(
    types: [
      for (var i = 0; i < repoint.length; i++)
        CreepType(
          id: 'creep-$i',
          legacyId: 'Attacker$i',
          repoint: repoint[i],
          hpMult: 1,
          speedMult: 1,
          sprite: 'creep.$i',
        ),
    ],
    movement: paramsOf({
      'waypointJitter': c['waypointJitter'],
      'fadeInMs': c['fadeInMs'],
      'scaleBumpPercent': c['scaleBumpPercent'],
    }),
  );
}

/// `difficulty.json`: the levels with their speed, cash and HP schedule,
/// the HP base and the mode cash and racks.
DifficultyDefs generateDifficulty(LegacyTable l) {
  final am = obj(l['attackerManager']['values']);
  final gm = l['gameManager'];
  final cash = obj(gm['startingCash']);
  return DifficultyDefs(
    levels: [
      for (final d in difficultyNames.keys)
        DifficultyDef(
          id: d,
          name: difficultyNames[d]!,
          creepSpeed: number(am['attacker_speed_$d']),
          startingCash: number(cash[d]),
          hpSchedule: [
            for (final e in (obj(
              am['attacker_hp_rate_$d'],
            ).entries.toList()..sort((a, b) => int.parse(a.key).compareTo(int.parse(b.key)))))
              HpRateStep(int.parse(e.key), number(e.value)),
          ],
        ),
    ],
    baseHp: number(am['attacker_energy']),
    defaultHpRate: number(am['attacker_upgrade_rate']),
    modeCash: {'sandbox': number(cash['sandbox']), 'sandbox2': number(cash['sandbox2'])},
    modeRacks: {
      for (final e in obj(obj(gm['modeRacks'])['racks']).entries)
        e.key: [for (final cls in strings(e.value)) turretIds[cls]!],
    },
  );
}

/// `waves.json`: wave size and timing.
WaveDefs generateWaves(LegacyTable l) {
  final am = obj(l['attackerManager']['values']);
  final s = l.eng('settings');
  return WaveDefs(
    waveSize: integer(am['wave_size']),
    waveSpacingMs: number(am['wave_spacing']),
    creepSpacingMs: number(am['attacker_spacing']),
    // AttackerManager and each WaveManager run on a 200 ms interval.
    managerTickMs: number(am['frame_space']),
    sizeChange: am['attacker_size_change']! as bool,
    spacingPrefMinS: number(s['waveSpacingMinS']),
    spacingPrefMaxS: number(s['waveSpacingMaxS']),
  );
}
