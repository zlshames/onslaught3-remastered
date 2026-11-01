/// `turrets.json` from the legacy table.
library;

import '../data/params.dart';
import '../data/turret_def.dart';
import 'legacy_table.dart';

/// Turrets with a special behaviour of their own, by its id.
const _ownSpecial = {
  'TurretTargeter': 'targeter',
  'TurretSniper': 'sniper',
  'TurretFusion': 'fusion',
  'TurretRailgun': 'railgun',
  'TurretCombonly': 'combonly',
};

/// Legs drawn between a turret's body and weapon
/// (`docs/legacy/ENGINE_NOTES.md` §8.1).
const _legsArt = {
  'TurretBlue': 'turret.legs.cannon',
  'TurretSniper': 'turret.legs.cannon',
  'TurretTargeter': 'turret.legs.cannon',
  'TurretYellow': 'turret.legs.electric',
  'TurretFusion': 'turret.legs.electric',
};

/// The glow a Combonly plate shows while it offers each colour
/// (`TurretCombonly.update`, `docs/legacy/ENGINE_NOTES.md` §4.8).
const _tint = {
  'TurretRed': '#FF0000',
  'TurretGreen': '#01BA01',
  'TurretBlue': '#0000FF',
  'TurretYellow': '#FFCC00',
};

/// Cosmetic timings and factors of a turret's own drawn effects. The
/// Combonly plate's colour glow (`TurretCombonly.update`, `TheColour`): a
/// 14 px circle blurred 6 px, tweened to 75 % in 500 ms and cancelled in
/// 250 ms.
final Map<String, Map<String, Object?>> _artFx = {
  'TurretCombonly': {
    'glowAlpha': 75,
    'glowInMs': 500,
    'glowOutMs': 250,
    'glowRadius': 14,
    'glowBlur': 6,
  },
};

/// Each colour's colour-blind badge shape (a remaster addition,
/// `docs/REMASTER_PLAN.md` §7 Phase 8): distinct in outline alone.
const _badgeShape = {
  'TurretBlue': 'circle',
  'TurretGreen': 'triangle',
  'TurretRed': 'square',
  'TurretYellow': 'diamond',
};

/// Turrets drawn with a turning weapon (`docs/legacy/ENGINE_NOTES.md` §8.1).
const _weaponArt = {
  'TurretBlue',
  'TurretGreen',
  'TurretRed',
  'TurretYellow',
  'TurretSniper',
  'TurretFusion',
  'TurretRailgun',
  'TurretTargeter',
};

/// Every turret, in tray order.
List<TurretDef> generateTurrets(LegacyTable l) => [
  for (final e in l.turrets.entries) _turret(l, e.key, obj(e.value)),
];

TurretDef _turret(LegacyTable l, String cls, Map<String, Object?> rec) {
  final v = obj(rec['values']);
  final id = turretIds[cls]!;
  final isModifier = v['turret_subtype'] == 'modifier';
  final specials = <String>[];
  final params = <String, Params>{};
  final sp = l.eng('turretSpecials');
  if (v['freak_capable'] == true) {
    specials.add('freakout');
    params['freakout'] = paramsOf(withoutSource(sp['freakout']));
  }
  if (v['link_capable'] == true) {
    specials.add('link');
    params['link'] = paramsOf({'mult': v['link_mult']});
  }
  if (v.containsKey('upgrade_holding_range')) {
    specials.add('holding');
    params['holding'] = paramsOf({
      'maxRockets': v['holding_max'],
      'levelDamage': v['upgrade_holding_damage'],
      'levelRange': v['upgrade_holding_range'],
      'levelRate': v['upgrade_holding_rate'],
      ...withoutSource(sp['holding']),
    });
  }
  if (v.containsKey('charge_base')) {
    specials.add('charge');
    params['charge'] = paramsOf({
      'base': v['charge_base'],
      'rateBase': v['charge_rate_base'],
      'cost': v['charge_use'],
      'poisonMax': v['weapon_poison_max'],
      ...withoutSource(sp['charge']),
    });
  }
  if (isModifier) specials.add('modifier');
  final own = _ownSpecial[cls];
  if (own != null) {
    specials.add(own);
    final p = <String, Object?>{...withoutSource(sp[own])};
    if (own == 'targeter') {
      p['joinMax'] = v['join_max'];
      p['idleRotate'] = v['weapon_rotate_idle'];
    }
    if (own == 'fusion') {
      for (final k in ['soundLow', 'soundMed', 'soundHigh', 'soundMax']) {
        p[k] = eventId(p[k]! as String);
      }
      p['storeTimeMs'] = v['store_time'];
      p['absorbDamage'] = v['fusion_mult_damage'];
      p['absorbPoison'] = v['fusion_mult_poison'];
      p['tickMs'] = v['frame_space'];
    }
    if (p.isNotEmpty) params[own] = paramsOf(p);
  }
  // Combos come first: each colour's `turretTryFiring` tries `comboFire`
  // before its own link, charge or plain shot.
  if (basicColours.contains(cls) && v['combo_never'] != true) {
    specials.insert(0, 'combo');
    final bears = strings(obj(sp['combo'])['bearToLeader']).contains(cls);
    params['combo'] = paramsOf({'bearToLeader': bears});
  }

  final bullets = v['upgrade_bullet'] is List
      ? [for (final b in strings(v['upgrade_bullet'])) projectileId(b)]
      : [if (v['weapon_type'] != null && !isModifier) projectileId(v['weapon_type']! as String)];

  final weapons = l.eng('weapons');
  final fire = obj(weapons['firePoints'])[cls] as List<Object?>?;
  final rest = obj(weapons['restRotation'])[cls];
  final names = strings(rec['displayNames']);
  final sound = v['sound_fire'] as String?;
  final tint = _tint[cls];
  final fx = paramsOf(_artFx[cls] ?? const {});
  List<UpgradeStep> track(String stat) {
    final costs = listOf(v['upgrade_${stat}_cost']);
    final amounts = listOf(v['upgrade_${stat}_amount']);
    return [
      for (var i = 0; i < costs.length; i++) UpgradeStep(number(costs[i]), number(amounts[i])),
    ];
  }

  return TurretDef(
    id: id,
    legacyId: cls,
    name: _turretName(l, cls, v),
    category: basicColours.contains(cls)
        ? TurretCategory.basic
        : isModifier
        ? TurretCategory.modifier
        : superTurrets.contains(cls)
        ? TurretCategory.superTurret
        : TurretCategory.utility,
    cost: number(rec['cost']),
    unlockKills: integer(rec['unlockKills']),
    availableInitially: rec['availableInitially']! as bool,
    stats: TurretStats(
      damage: number(v['weapon_damage']),
      range: number(v['weapon_range']),
      rate: number(v['weapon_rate']),
      poison: number(v['weapon_poison']),
      rotate: number(v['weapon_rotate']),
      mustFace: v['weapon_must_face']! as bool,
    ),
    upgrades: UpgradeTracks(damage: track('damage'), range: track('range'), rate: track('rate')),
    modifiable: v['modify_possible']! as bool,
    comboCapableInitially: v['combo_capable']! as bool,
    comboNever: v['combo_never']! as bool,
    joinable: v['join_possible']! as bool,
    fusionFeeder: v['fusion_capable']! as bool,
    directional: v['target_angle_available'] as bool? ?? true,
    freakout: FreakoutSpec(
      capable: v['freak_capable']! as bool,
      availableInitially: v['freak_available']! as bool,
      lengthMs: number(v['freak_length']),
      spacingMs: number(v['freak_space']),
      damageMult: number(v['freak_damage_mult']),
      rangeMult: number(v['freak_range_mult']),
      rateMult: number(v['freak_rate_mult']),
      levelDamage: integer(v['freak_level_damage']),
      levelRange: integer(v['freak_level_range']),
      levelRate: integer(v['freak_level_rate']),
    ),
    modifierAura: isModifier
        ? ModifierAura(
            addDamage: number(v['modify_up_damage']),
            addRange: number(v['modify_up_range']),
            addRate: number(v['modify_up_rate']),
            multDamage: number(v['modify_up_damage_mult']),
            multRange: number(v['modify_up_range_mult']),
            multRate: number(v['modify_up_rate_mult']),
          )
        : null,
    specials: specials,
    specialParams: params,
    projectiles: bullets,
    weaponRotation: optNumber(rest) ?? 0,
    tickMs: number(v['frame_space']),
    firePoints: [for (final p in fire ?? const []) pointFromList(p)],
    defaultTargetMode: isModifier ? null : v['target_type']! as String,
    lockOff: v['target_reacquire']! as bool,
    // Turrets with a turning weapon are drawn in layers like the clip:
    // shared base, body, legs, weapon. Others draw their whole clip.
    art: _weaponArt.contains(cls)
        ? TurretArt(
            base: 'turret.base',
            body: 'turret.$id.body',
            legs: _legsArt[cls],
            weapon: 'turret.$id.weapon',
            icon: 'turret.$id',
            tint: tint == null ? null : rgb(tint),
            badgeShape: _badgeShape[cls],
            fx: fx,
          )
        : TurretArt(base: 'turret.$id', icon: 'turret.$id', fx: fx),
    fireSound: sound == null ? null : eventId(sound),
    displayNames: names.isNotEmpty ? names : [v['display_name']! as String],
  );
}

/// The turret's name: its mod editor title without the `Turret: ` group, or
/// its `display_name`.
String _turretName(LegacyTable l, String cls, Map<String, Object?> v) {
  final title = l.modTitles[cls] as String?;
  if (title == null) return v['display_name']! as String;
  final i = title.indexOf(': ');
  return i < 0 ? title : title.substring(i + 2);
}
