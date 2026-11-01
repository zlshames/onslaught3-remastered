/// `projectiles.json` and `blasts.json` from the legacy table.
library;

import '../data/art_defs.dart';
import '../data/ordnance_defs.dart';
import 'legacy_table.dart';

/// Projectile engine class → projectile kind.
const _projectileKinds = {
  'ShellEngine': 'shell',
  'RocketEngine': 'rocket',
  'BFG': 'rocket',
  'BulletSniper': 'sniper-shot',
  'LaserEngine': 'beam',
  'RailLaser': 'rail',
  'SparkEngine': 'spark',
  'ClusterBombEngine': 'cluster-bomb',
  'LandmineEngine': 'landmine',
  'BlackHole': 'black-hole',
};

/// Legacy blast → blast kind (the rest are plain `blast`).
const _blastKinds = {
  'BlastShockwave': 'shockwave',
  'BlastNapalm': 'napalm',
  'ClusterBlast': 'cluster-rockets',
  'ClusterSpark': 'cluster-sparks',
};

/// `LaserEngine.laserGetType`: the beam's line and glow colour, width and
/// glow size by damage; each band includes its upper bound (the original's
/// `<=` tests), and above the last bound it is white with a red glow.
const _laserBands = [
  DamageBand(upTo: 49.999, core: 0x00FF00, glow: 0x00FF00, width: 1, glowSize: 5),
  DamageBand(upTo: 120, core: 0x00FF00, glow: 0xFF0000, width: 1, glowSize: 5),
  DamageBand(upTo: 400, core: 0x00FF00, glow: 0x0000FF, width: 1, glowSize: 5),
  DamageBand(upTo: 1500, core: 0xFFFF00, glow: 0x00FF00, width: 3, glowSize: 5),
  DamageBand(upTo: 3900, core: 0xFFFF00, glow: 0xFF0000, width: 3, glowSize: 5),
  DamageBand(upTo: 9300, core: 0xFFFF00, glow: 0x0000FF, width: 3, glowSize: 5),
  DamageBand(upTo: 19500, core: 0xFF0000, glow: 0x00FF00, width: 5, glowSize: 5),
  DamageBand(upTo: 35000, core: 0xFF0000, glow: 0xFF0000, width: 5, glowSize: 5),
  DamageBand(upTo: 60000, core: 0xFF0000, glow: 0x0000FF, width: 5, glowSize: 5),
  DamageBand(upTo: 100000, core: 0x660198, glow: 0x00FF00, width: 6, glowSize: 5),
  DamageBand(upTo: 200000, core: 0x660198, glow: 0xFF0000, width: 6, glowSize: 5),
  DamageBand(upTo: 400000, core: 0x660198, glow: 0x0000FF, width: 6, glowSize: 5),
  DamageBand(upTo: 750000, core: 0xFF007F, glow: 0x00FF00, width: 7, glowSize: 5),
  DamageBand(upTo: 900000, core: 0xFF007F, glow: 0xFF0000, width: 7, glowSize: 5),
  DamageBand(upTo: 1000000, core: 0xFF007F, glow: 0x0000FF, width: 7, glowSize: 5),
  DamageBand(upTo: 2000000, core: 0x42C0FB, glow: 0x00FF00, width: 8, glowSize: 5),
  DamageBand(upTo: 3000000, core: 0x42C0FB, glow: 0xFF0000, width: 8, glowSize: 5),
  DamageBand(upTo: 4000000, core: 0x42C0FB, glow: 0x0000FF, width: 8, glowSize: 5),
  DamageBand(upTo: 5000000, core: 0x0000EE, glow: 0x00FF00, width: 9, glowSize: 5),
  DamageBand(upTo: 6000000, core: 0x0000EE, glow: 0xFF0000, width: 9, glowSize: 5),
  DamageBand(upTo: 7000000, core: 0x0000EE, glow: 0x0000FF, width: 9, glowSize: 5),
  DamageBand(upTo: 8000000, core: 0x333333, glow: 0x00FF00, width: 10, glowSize: 5),
  DamageBand(core: 0xFFFFFF, glow: 0xAA0000, width: 10, glowSize: 8),
];

/// `SparkEngine.sparkGetType`: line colour, glow colour, width (`beam_size`)
/// and glow size by damage; each band excludes its upper bound. The
/// original's 2M–4M band is shadowed by its 2M–3M one, so it applies from 3M.
const _sparkBands = [
  DamageBand(below: 50, core: 0x00FF00, glow: 0x99FF99, width: 1, glowSize: 5),
  DamageBand(below: 75, core: 0x9999FF, glow: 0xFFFFFF, width: 6, glowSize: 3),
  DamageBand(below: 125, core: 0xFF3333, glow: 0xFFFFFF, width: 6, glowSize: 3),
  DamageBand(below: 200, core: 0xFF0000, glow: 0xFFFFFF, width: 6, glowSize: 3),
  DamageBand(below: 800, core: 0x33FF33, glow: 0xFFFFFF, width: 6, glowSize: 3),
  DamageBand(below: 3500, core: 0x33FF33, glow: 0xFFFFFF, width: 6, glowSize: 4),
  DamageBand(below: 11000, core: 0xFF33FF, glow: 0xFFFFFF, width: 6, glowSize: 4),
  DamageBand(below: 30000, core: 0x3333FF, glow: 0xFFFFFF, width: 6, glowSize: 4),
  DamageBand(below: 60000, core: 0x000000, glow: 0xFFFF33, width: 2, glowSize: 10),
  DamageBand(below: 100000, core: 0xFFFF00, glow: 0xFFFFFF, width: 3, glowSize: 6),
  DamageBand(below: 1000000, core: 0xFF0000, glow: 0xFF00FF, width: 3, glowSize: 7),
  DamageBand(below: 2000000, core: 0xFF00FF, glow: 0xFFFF00, width: 4, glowSize: 7),
  DamageBand(below: 3000000, core: 0x666666, glow: 0x9999FF, width: 4, glowSize: 7),
  DamageBand(below: 4000000, core: 0x666666, glow: 0xFF99FF, width: 4, glowSize: 7),
  DamageBand(below: 5000000, core: 0x666666, glow: 0xFFFFFF, width: 4, glowSize: 7),
  DamageBand(below: 7500000, core: 0xCC6666, glow: 0xFFFF33, width: 4, glowSize: 8),
  DamageBand(below: 10000000, core: 0xFF3333, glow: 0x33FF33, width: 4, glowSize: 8),
  DamageBand(below: 25000000, core: 0xFF3333, glow: 0xFFFFFF, width: 5, glowSize: 8),
  DamageBand(below: 30000000, core: 0x333333, glow: 0xFFFFFF, width: 7, glowSize: 8),
  DamageBand(below: 40000000, core: 0x3333CC, glow: 0xFFFFFF, width: 8, glowSize: 8),
  DamageBand(below: 50000000, core: 0x333333, glow: 0x33CC33, width: 9, glowSize: 8),
  DamageBand(below: 60000000, core: 0xAAAAAA, glow: 0x33CC33, width: 10, glowSize: 8),
  DamageBand(below: 70000000, core: 0xAAAAAA, glow: 0x33CC33, width: 12, glowSize: 10),
  DamageBand(below: 80000000, core: 0xAAAAAA, glow: 0x33CC33, width: 14, glowSize: 12),
  DamageBand(below: 90000000, core: 0xAAAAAA, glow: 0x33CC33, width: 16, glowSize: 14),
  DamageBand(below: 100000000, core: 0xAAAAAA, glow: 0x33CC33, width: 20, glowSize: 16),
  DamageBand(below: 110000000, core: 0xAAAAAA, glow: 0x33CC33, width: 20, glowSize: 20),
  DamageBand(below: 120000000, core: 0xAAAAAA, glow: 0x33CC33, width: 24, glowSize: 24),
  DamageBand(below: 130000000, core: 0xAAAAAA, glow: 0x33CC33, width: 28, glowSize: 28),
  DamageBand(core: 0xAAAAAA, glow: 0x33CC33, width: 32, glowSize: 32),
];

/// `RailLaser.railGetType`: the colours of the Railgun's five strokes,
/// widest first, by damage (each band includes its upper bound). The
/// strokes are 40/30/20/10/3 px wide at alphas 20/30/40/50/75 %
/// (`RailLaser.laserFire`).
const _railBands = [
  DamageBand(upTo: 4000000, strokes: [_white, _white, _white, _white, 0x33CC33]),
  DamageBand(upTo: 9000000, strokes: [_white, _white, _white, 0x33CC33, 0x33CC33]),
  DamageBand(upTo: 15000000, strokes: [_white, _white, 0x33CC33, 0x33CC33, 0x33CC33]),
  DamageBand(upTo: 25000000, strokes: [_white, _white, 0xFF3333, 0xFF3333, 0xFF3333]),
  DamageBand(strokes: [_white, _white, _white, 0xFF33FF, 0xFF33FF]),
];

const _white = 0xFFFFFF;

/// The drawn look of each projectile engine that is not only a sprite.
final Map<String, EffectArt> _projectileArt = {
  'LaserEngine': const EffectArt(bands: _laserBands),
  'SparkEngine': const EffectArt(bands: _sparkBands),
  'RailLaser': EffectArt(
    bands: _railBands,
    fx: paramsOf({
      'strokeWidths': [40, 30, 20, 10, 3],
      'strokeAlphas': [20, 30, 40, 50, 75],
    }),
  ),
  // `BlackHole`: its swirl turns 29° a frame, a piece of debris falls into
  // the core in 100 ms (`BlackHoleDebris`), and whatever it pulls in
  // shrinks by 75 % over the pull (`OnslaughtObject.as:blackHoled`).
  'BlackHole': EffectArt(
    fx: paramsOf({'swirlDegPerFrame': 29, 'debrisFallMs': 100, 'captureShrink': 75}),
  ),
};

/// The drawn look of each blast that has more than its sprite.
final Map<String, EffectArt> _blastArt = {
  // `BlastShockwave.blastSpark`: a decorative spark every 100–799 ms, each
  // fading out over 400 ms.
  'BlastShockwave': EffectArt(
    fx: paramsOf({'sparkDelayMinMs': 100, 'sparkDelayRangeMs': 700, 'sparkFadeMs': 400}),
  ),
};

/// Every projectile, one per linkage.
List<ProjectileSpec> generateProjectiles(LegacyTable l) {
  final engines = l.eng('projectileEngines');
  final art = l.eng('artSymbols');
  return [
    for (final e in l.eng('projectileLinkages').entries)
      ProjectileSpec(
        id: projectileId(e.key),
        legacyId: e.key,
        kind: _projectileKinds[e.value]!,
        sprite: art.containsKey(e.key) ? 'projectile.${projectileId(e.key)}' : null,
        params: paramsOf({
          if (e.value == 'BFG') ...withoutSource(engines['RocketEngine']),
          ...withoutSource(engines[e.value]),
          if (_projectileKinds[e.value] == 'rocket') ...{
            ...rocketOffscreen,
            'holdingLifetimeMs': holdingRocketLifetimeMs,
          },
        }),
        art: _projectileArt[e.value],
      ),
  ];
}

/// Every blast.
List<BlastSpec> generateBlasts(LegacyTable l) {
  final art = l.eng('artSymbols');
  return [
    for (final e in l.eng('blasts').entries)
      BlastSpec(
        id: blastId(e.key),
        legacyId: e.key,
        kind: _blastKinds[e.key] ?? 'blast',
        sprite: art.containsKey(e.key)
            ? 'blast.${blastId(e.key)}'
            : e.key == 'tiny'
            ? 'blast.blast-small'
            : null,
        params: paramsOf({
          for (final p in withoutSource(e.value).entries)
            p.key: switch (p.key) {
              'dropBlast' => blastId(p.value! as String),
              'childProjectile' => projectileId(p.value! as String),
              'sound' => eventId(p.value! as String),
              _ => p.value,
            },
        }),
        art: _blastArt[e.key],
      ),
  ];
}
