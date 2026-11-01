/// `progression.json`, `targeting.json`, `tutorial.json`, `attract.json`
/// and `audio.json` from the legacy table.
library;

import '../data/attract_defs.dart';
import '../data/audio_defs.dart';
import '../data/progression_defs.dart';
import '../data/targeting_defs.dart';
import '../data/tutorial_defs.dart';
import 'gen_world.dart';
import 'legacy_table.dart';

/// `progression.json`: the modes in menu order and how each is unlocked.
ProgressionDefs generateProgression(LegacyTable l) {
  final ms = obj(l['gameManager']['milestones']);
  final completeKills = integer(ms['completeKills']);
  return ProgressionDefs(
    modes: const [
      'normal',
      'extreme',
      'tutorial',
      'challenge',
      'sandbox',
      'sandbox2',
      'modding',
      'mapping',
    ],
    completeKills: completeKills,
    unlocks: [
      const ModeUnlock(mode: 'normal', rule: 'always', difficulties: [], kills: null),
      const ModeUnlock(mode: 'tutorial', rule: 'always', difficulties: [], kills: null),
      const ModeUnlock(mode: 'mapping', rule: 'always', difficulties: [], kills: null),
      ModeUnlock(
        mode: 'extreme',
        rule: 'killsOnAnyDifficulty',
        difficulties: const ['easy', 'medium', 'hard', 'extreme'],
        kills: integer(ms['extremeKills']),
      ),
      ModeUnlock(
        mode: 'sandbox',
        rule: 'killsOnAnyDifficulty',
        difficulties: const ['medium'],
        kills: completeKills,
      ),
      ModeUnlock(
        mode: 'sandbox2',
        rule: 'killsOnAnyDifficulty',
        difficulties: const ['hard'],
        kills: completeKills,
      ),
      const ModeUnlock(
        mode: 'modding',
        rule: 'completeAll',
        difficulties: ['easy', 'medium', 'hard'],
        kills: null,
      ),
      const ModeUnlock(mode: 'challenge', rule: 'tutorialStart', difficulties: [], kills: null),
    ],
  );
}

/// `targeting.json`: the target modes and directional cones.
TargetingDefs generateTargeting(LegacyTable l) {
  final tg = l.eng('targeting');
  return TargetingDefs(
    modes: strings(tg['modes']),
    cones: [for (final e in obj(tg['cones']).entries) TargetCone(e.key, optNumber(e.value))],
    mustFaceToleranceDeg: number(tg['mustFaceToleranceDeg']),
  );
}

/// `tutorial.json`: the tutorial's map, wave limit and pages.
TutorialDefs generateTutorial(LegacyTable l) => TutorialDefs(
  map: 'tutorial',
  waveLimit: integer(l.eng('rules')['tutorialWaveLimit']),
  pages: [
    for (final p in objects(l['tutorial']['pages']))
      TutorialPage(
        title: p['title']! as String,
        body: p['text']! as String,
        pointer: p['show'] == null ? null : _pointer(p['show']! as String),
        setCash: optNumber(p['setCash']),
        showNow: p['showNow'] == true,
      ),
  ],
);

/// `this.CloseButton`, `_root.UpgradePanel.RangeCost` → `CloseButton`,
/// `UpgradePanel.RangeCost`: the original UI element, mapped to the new UI
/// in Phase 5.
String _pointer(String expr) =>
    expr.replaceFirst(RegExp(r'^(this|_root)\.'), '').replaceFirst(RegExp(r'^Game\.'), '');

/// `attract.json`: the attract-mode demo behind the main menu
/// (`GameManagerIntro`).
AttractDef generateAttract(LegacyTable l) {
  final a = l.eng('attractDemo');
  return AttractDef(
    difficulty: a['difficulty']! as String,
    waveSize: integer(a['waveSize']),
    waveSpacingMs: number(a['waveSpacingMs']),
    baseHp: number(a['baseHp']),
    creepTypes: integer(a['creepTypes']),
    sizeChange: a['sizeChange']! as bool,
    stageWidth: number(l.eng('world')['playWidth']),
    stageHeight: rocketOffscreen['screenHeight']!.toDouble(),
    road: [for (final p in listOf(a['road'])) pointFromList(p)],
    turrets: [
      for (final p in listOf(a['turrets']).cast<List<Object?>>())
        AttractTurret(turretIds[p[0]]!, number(p[1]), number(p[2])),
    ],
    groundArt: groundArtFrom(a['groundArt']),
  );
}

/// `audio.json`: the mix and every sound event's clips.
AudioDefs generateAudio(LegacyTable l) {
  final mix = l.eng('soundMix');
  return AudioDefs(
    volume: number(mix['volume']),
    panSpread: number(mix['panSpread']),
    events: {
      for (final e in l.eng('soundEvents').entries)
        eventId(e.key): [for (final f in strings(e.value)) legacyClipId(f)],
    },
  );
}
