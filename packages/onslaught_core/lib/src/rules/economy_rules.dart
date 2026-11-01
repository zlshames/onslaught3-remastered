import '../data/creep_wave_defs.dart';

/// Cash returned when selling a turret worth [cashValue] (purchase price plus
/// every upgrade bought): `ceil(cashValue × refund)` (`TurretManager.turretSell`).
int sellRefund(double cashValue, double refund) => (cashValue * refund).ceil();

/// Final score: total kills × total cash spent (`GameManager`).
double score({required int kills, required double spent}) => kills * spent;

/// Creep HP during wave [wave] for a [difficulty]
/// (`AttackerManager._waveNext`): starting from `baseHp`, every wave first
/// switches the growth rate when the schedule has an entry for that wave,
/// then multiplies HP by the current rate. Wave-size scaling is separate
/// ([waveSizeScale]).
double creepHpForWave(DifficultyDefs defs, DifficultyDef difficulty, int wave) {
  final steps = {for (final s in difficulty.hpSchedule) s.wave: s.rate};
  var rate = defs.defaultHpRate;
  var hp = defs.baseHp;
  for (var w = 1; w <= wave; w++) {
    rate = steps[w] ?? rate;
    hp *= rate;
  }
  return hp;
}

/// Scale applied to HP, bounty and sprite size when a wave has [waveSize]
/// creeps instead of the normal [normalSize] (`AttackerManager.waveSend`):
/// fewer, bigger creeps carry the whole wave's HP and bounty.
double waveSizeScale(int waveSize, int normalSize) => normalSize / waveSize;

/// Cash paid per kill in wave [wave]: the wave number scaled by
/// [waveSizeScale] and rounded (`AttackerManager.waveSend`).
int creepBounty(int wave, int waveSize, int normalSize) =>
    (wave * waveSizeScale(waveSize, normalSize)).round();

/// Index of the creep type used by wave [wave] (`(wave − 1) % types`).
int creepTypeIndex(int wave, int typeCount) => (wave - 1) % typeCount;
