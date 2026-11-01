/// `challenges.json` from the legacy table.
library;

import '../data/challenge_defs.dart';
import 'legacy_table.dart';

/// The original's picker ids → the remaster's.
const _pickerIds = {
  'difficulty': 'difficulty',
  'objective': 'objective',
  'cash': 'cash',
  'timelimit': 'timeLimit',
  'turretlimit': 'turretLimit',
  'wavesize': 'waveSize',
  'wavespeed': 'waveSpeed',
};

/// `challenges.json`: the presets, the corrected pickers and the original
/// options of the pickers that were corrected.
ChallengeDefs generateChallenges(LegacyTable l) {
  final c = l['challenges'];
  final classic = _classicPickers(c);
  return ChallengeDefs(
    presets: [
      for (final p in objects(c['presets']))
        ChallengeDef(
          id: kebab(p['name']! as String),
          name: p['name']! as String,
          difficulty: p['difficulty']! as String,
          objective: p['objective'] == null ? null : _objective(p['objective']! as String),
          cash: number(p['cash']),
          timeLimitS: optNumber(p['timelimit']),
          turretLimit: optInteger(p['turretlimit']),
          waveSizes: _intList(p['wavesize']),
          waveSpeeds: [for (final s in _intList(p['wavespeed'])) s.toDouble()],
          debugOnly: p['debugOnly'] == true,
        ),
    ],
    pickers: {
      for (final e in classic.entries) e.key: _pickerFixes[e.key]?.call(e.value) ?? e.value,
    },
    classicPickers: {
      for (final e in classic.entries)
        if (_pickerFixes.containsKey(e.key)) e.key: e.value,
    },
  );
}

/// The original's picker options, labels and values exactly as shipped.
Map<String, List<PickerOption>> _classicPickers(Map<String, Object?> c) => {
  for (final e in obj(c['pickers']).entries)
    _pickerIds[e.key]!: [
      for (final o in objects(e.value))
        if (o['debugOnly'] != true)
          PickerOption(
            o['label']! as String,
            o['data'],
            requiresMode: o['requiresMode'] as String?,
          ),
    ],
};

/// `RulesProfile.challengePickerData` (`docs/DEVIATIONS.md`): the picker
/// data bugs of `GameSelectChallenge.as:onLoad`, corrected for v1. The
/// original pushes its "Extreme!" difficulty into the cash list before
/// that list exists, so it is never offered; "3 mins" is 280 s; and the
/// turret limits 9, 7 and 5 are all labelled "8 Turrets" next to a second
/// 5 ("5 Turrets"). v1 offers Extreme once it is unlocked, makes "3 mins"
/// 180 s and labels each limit by its value, turning the duplicate 5 into
/// the missing 6 (assumption: 9, 8, 7, 6, 5 was intended). Only the
/// pickers listed here differ; `classicPickers` keeps their originals.
final Map<String, List<PickerOption> Function(List<PickerOption>)> _pickerFixes = {
  'difficulty': (o) => [...o, const PickerOption('Extreme!', 'extreme', requiresMode: 'extreme')],
  'timeLimit': (o) => [
    for (final x in o)
      x.label == '3 mins' ? PickerOption(x.label, 180, requiresMode: x.requiresMode) : x,
  ],
  'turretLimit': (o) => [for (final x in o) _labelledLimit(x)],
};

/// A turret limit labelled by its value; the first of the two 5s sits
/// where 6 belongs (between 7 and 5).
PickerOption _labelledLimit(PickerOption x) {
  var v = x.value as num?;
  if (v == 5 && x.label != '5 Turrets') v = 6;
  return PickerOption(v == null ? x.label : '$v Turrets', v, requiresMode: x.requiresMode);
}

ChallengeObjective _objective(String s) {
  final parts = s.split(',');
  return ChallengeObjective(parts[0] == 'w' ? 'waves' : 'kills', int.parse(parts[1]));
}

List<int> _intList(Object? v) =>
    v is num ? [v.toInt()] : [for (final p in '$v'.split(',')) int.parse(p.trim())];
