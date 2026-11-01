import 'package:meta/meta.dart';

import '../math/vec2.dart';
import 'json_reader.dart';
import 'params.dart';

/// Broad turret family; decides which tray section a turret appears in and
/// which rules apply (modifiers never fire, super turrets never combo).
enum TurretCategory { basic, modifier, utility, superTurret }

const _categoryIds = {
  'basic': TurretCategory.basic,
  'modifier': TurretCategory.modifier,
  'utility': TurretCategory.utility,
  'super': TurretCategory.superTurret,
};

/// One `{cost, value}` step of an upgrade track. Upgrading sets the stat to
/// [value] (absolute, not additive).
@immutable
class UpgradeStep {
  const UpgradeStep(this.cost, this.value);

  factory UpgradeStep.fromJson(JsonReader r) {
    r.expectOnlyKeys({'cost', 'value'});
    return UpgradeStep(r.number('cost', min: 0), r.number('value'));
  }

  final double cost;
  final double value;

  Map<String, Object?> toJson() => {'cost': jsonNumber(cost), 'value': jsonNumber(value)};
}

/// The three upgrade tracks of a turret. A missing track is empty.
@immutable
class UpgradeTracks {
  const UpgradeTracks({this.damage = const [], this.range = const [], this.rate = const []});

  factory UpgradeTracks.fromJson(JsonReader r) {
    if (r.isNull) return const UpgradeTracks();
    r.expectOnlyKeys({'damage', 'range', 'rate'});
    return UpgradeTracks(
      damage: r.optList('damage', UpgradeStep.fromJson),
      range: r.optList('range', UpgradeStep.fromJson),
      rate: r.optList('rate', UpgradeStep.fromJson),
    );
  }

  final List<UpgradeStep> damage;
  final List<UpgradeStep> range;
  final List<UpgradeStep> rate;

  /// Only the tracks that have steps.
  Map<String, Object?> toJson() => {
    if (damage.isNotEmpty) 'damage': [for (final s in damage) s.toJson()],
    if (range.isNotEmpty) 'range': [for (final s in range) s.toJson()],
    if (rate.isNotEmpty) 'rate': [for (final s in rate) s.toJson()],
  };

  List<UpgradeStep> track(StatKind stat) => switch (stat) {
    StatKind.damage => damage,
    StatKind.range => range,
    StatKind.rate => rate,
  };
}

/// The three upgradable stats.
enum StatKind { damage, range, rate }

/// Initial weapon stats of a turret.
@immutable
class TurretStats {
  const TurretStats({
    required this.damage,
    required this.range,
    required this.rate,
    required this.poison,
    required this.rotate,
    required this.mustFace,
  });

  factory TurretStats.fromJson(JsonReader r) {
    r.expectOnlyKeys({'damage', 'range', 'rate', 'poison', 'rotate', 'mustFace'});
    return TurretStats(
      damage: r.optNumber('damage', min: 0) ?? 0,
      range: r.number('range', min: 0),
      rate: r.optNumber('rate', min: 0) ?? 0,
      poison: r.optNumber('poison', min: 0) ?? 0,
      rotate: r.optNumber('rotate', min: 0) ?? 0,
      mustFace: r.optBoolean('mustFace', fallback: false),
    );
  }

  /// Hit points per shot.
  final double damage;

  /// Radius in world px.
  final double range;

  /// Shots per minute.
  final double rate;

  /// Slow applied per shot ("poison" means slow in this game).
  final double poison;

  /// Weapon rotation speed in degrees per second.
  final double rotate;

  /// Whether the weapon must be facing its target before it may fire.
  final bool mustFace;

  Map<String, Object?> toJson() => {
    'damage': jsonNumber(damage),
    'range': jsonNumber(range),
    'rate': jsonNumber(rate),
    'poison': jsonNumber(poison),
    'rotate': jsonNumber(rotate),
    'mustFace': mustFace,
  };

  double stat(StatKind kind) => switch (kind) {
    StatKind.damage => damage,
    StatKind.range => range,
    StatKind.rate => rate,
  };
}

/// Freakout parameters (`freak_*` in the original).
@immutable
class FreakoutSpec {
  const FreakoutSpec({
    required this.capable,
    required this.availableInitially,
    required this.lengthMs,
    required this.spacingMs,
    required this.damageMult,
    required this.rangeMult,
    required this.rateMult,
    required this.levelDamage,
    required this.levelRange,
    required this.levelRate,
  });

  factory FreakoutSpec.fromJson(JsonReader r) {
    r.expectOnlyKeys({
      'capable',
      'availableInitially',
      'lengthMs',
      'spacingMs',
      'damageMult',
      'rangeMult',
      'rateMult',
      'levelDamage',
      'levelRange',
      'levelRate',
    });
    return FreakoutSpec(
      capable: r.boolean('capable'),
      availableInitially: r.boolean('availableInitially'),
      lengthMs: r.number('lengthMs', min: 0),
      spacingMs: r.number('spacingMs', min: 0),
      damageMult: r.number('damageMult'),
      rangeMult: r.number('rangeMult'),
      rateMult: r.number('rateMult'),
      levelDamage: r.integer('levelDamage', min: 0),
      levelRange: r.integer('levelRange', min: 0),
      levelRate: r.integer('levelRate', min: 0),
    );
  }

  final bool capable;
  final bool availableInitially;
  final double lengthMs;
  final double spacingMs;

  /// Added to the damage multiplier during a freakout (×(1 + this)).
  final double damageMult;
  final double rangeMult;
  final double rateMult;

  /// Upgrade levels required on each track before freakouts start.
  final int levelDamage;
  final int levelRange;
  final int levelRate;

  Map<String, Object?> toJson() => {
    'capable': capable,
    'availableInitially': availableInitially,
    'lengthMs': jsonNumber(lengthMs),
    'spacingMs': jsonNumber(spacingMs),
    'damageMult': jsonNumber(damageMult),
    'rangeMult': jsonNumber(rangeMult),
    'rateMult': jsonNumber(rateMult),
    'levelDamage': levelDamage,
    'levelRange': levelRange,
    'levelRate': levelRate,
  };
}

/// What a modifier turret adds to every modifiable turret inside its aura.
@immutable
class ModifierAura {
  const ModifierAura({
    required this.addDamage,
    required this.addRange,
    required this.addRate,
    required this.multDamage,
    required this.multRange,
    required this.multRate,
  });

  factory ModifierAura.fromJson(JsonReader r) {
    r.expectOnlyKeys({'addDamage', 'addRange', 'addRate', 'multDamage', 'multRange', 'multRate'});
    return ModifierAura(
      addDamage: r.number('addDamage'),
      addRange: r.number('addRange'),
      addRate: r.number('addRate'),
      multDamage: r.number('multDamage'),
      multRange: r.number('multRange'),
      multRate: r.number('multRate'),
    );
  }

  final double addDamage;
  final double addRange;
  final double addRate;
  final double multDamage;
  final double multRange;
  final double multRate;

  Map<String, Object?> toJson() => {
    'addDamage': jsonNumber(addDamage),
    'addRange': jsonNumber(addRange),
    'addRate': jsonNumber(addRate),
    'multDamage': jsonNumber(multDamage),
    'multRange': jsonNumber(multRange),
    'multRate': jsonNumber(multRate),
  };
}

/// Logical asset ids used to draw a turret (resolved through the AssetPack
/// chain). Layers are drawn bottom to top: [base], [body], [legs] (turned
/// at random), then [weapon] (turned toward the target). A colour turret
/// also names its [tint] and [badgeShape].
@immutable
class TurretArt {
  const TurretArt({
    required this.base,
    this.body,
    this.legs,
    this.weapon,
    this.icon,
    this.tint,
    this.badgeShape,
    this.fx = Params.empty,
  });

  factory TurretArt.fromJson(JsonReader r) {
    r.expectOnlyKeys({'base', 'body', 'legs', 'weapon', 'icon', 'tint', 'badgeShape', 'fx'});
    return TurretArt(
      base: r.string('base'),
      body: r.optString('body'),
      legs: r.optString('legs'),
      weapon: r.optString('weapon'),
      icon: r.optString('icon'),
      tint: r.optRgb('tint'),
      badgeShape: r.has('badgeShape') ? r.oneOf('badgeShape', badgeShapes, fallback: '') : null,
      fx: r.has('fx') ? Params.fromJson(r.child('fx')) : Params.empty,
    );
  }

  /// The colour-blind badge shapes ([badgeShape]).
  static const Set<String> badgeShapes = {'circle', 'triangle', 'square', 'diamond'};

  final String base;
  final String? body;
  final String? legs;
  final String? weapon;

  /// Tray and sheet icon (the whole turret).
  final String? icon;

  /// A colour's glow, 0xRRGGBB (`"#RRGGBB"` in JSON): what a Combonly plate
  /// shows while it offers this colour (`TurretCombonly.update`).
  final int? tint;

  /// The shape of a colour's colour-blind badge, one of [badgeShapes].
  final String? badgeShape;

  /// Cosmetic timings and factors of the turret's own drawn effects (the
  /// Combonly plate's glow), as its view requires. Never read by the sim.
  final Params fx;

  Iterable<String> get ids => [base, ?body, ?legs, ?weapon, ?icon];

  Map<String, Object?> toJson() => {
    'base': base,
    'body': ?body,
    'legs': ?legs,
    'weapon': ?weapon,
    'icon': ?icon,
    if (tint != null) 'tint': rgbToJson(tint!),
    'badgeShape': ?badgeShape,
    if (!fx.isEmpty) 'fx': fx.toJson(),
  };
}

/// A turret definition from `turrets.json`.
@immutable
class TurretDef {
  const TurretDef({
    required this.id,
    required this.legacyId,
    required this.name,
    required this.category,
    required this.cost,
    required this.unlockKills,
    required this.availableInitially,
    required this.stats,
    required this.upgrades,
    required this.modifiable,
    required this.comboCapableInitially,
    required this.comboNever,
    required this.joinable,
    required this.fusionFeeder,
    required this.directional,
    required this.freakout,
    required this.modifierAura,
    required this.specials,
    required this.specialParams,
    required this.projectiles,
    this.firePoints = const [],
    this.weaponRotation = 0,
    this.tickMs = 0,
    required this.defaultTargetMode,
    required this.lockOff,
    required this.art,
    required this.fireSound,
    required this.displayNames,
  });

  factory TurretDef.fromJson(JsonReader r) {
    r.expectOnlyKeys({
      'id',
      'legacyId',
      'name',
      'category',
      'cost',
      'unlockKills',
      'availableInitially',
      'stats',
      'upgrades',
      'flags',
      'freakout',
      'modifierAura',
      'specials',
      'specialParams',
      'projectiles',
      'firePoints',
      'weaponRotation',
      'tickMs',
      'targeting',
      'art',
      'sounds',
      'displayNames',
    });
    final flags = r.child('flags')
      ..expectOnlyKeys({
        'modifiable',
        'comboCapable',
        'comboNever',
        'joinable',
        'fusionFeeder',
        'directional',
      });
    final targeting = r.child('targeting')..expectOnlyKeys({'defaultMode', 'lockOff'});
    final sounds = r.child('sounds');
    if (r.has('sounds')) sounds.expectOnlyKeys({'fire'});
    final categoryId = r.oneOf('category', _categoryIds.keys.toSet(), fallback: 'basic');
    final specialParams = r.has('specialParams')
        ? r.mapOf('specialParams', Params.fromJson)
        : const <String, Params>{};
    return TurretDef(
      id: r.string('id'),
      legacyId: r.string('legacyId'),
      name: r.string('name'),
      category: _categoryIds[categoryId]!,
      cost: r.number('cost', min: 0),
      unlockKills: r.integer('unlockKills', min: 0),
      availableInitially: r.boolean('availableInitially'),
      stats: TurretStats.fromJson(r.child('stats')),
      upgrades: UpgradeTracks.fromJson(r.child('upgrades')),
      modifiable: flags.boolean('modifiable'),
      comboCapableInitially: flags.boolean('comboCapable'),
      comboNever: flags.boolean('comboNever'),
      joinable: flags.boolean('joinable'),
      fusionFeeder: flags.optBoolean('fusionFeeder', fallback: false),
      directional: flags.optBoolean('directional', fallback: true),
      freakout: r.optChild('freakout', FreakoutSpec.fromJson),
      modifierAura: r.optChild('modifierAura', ModifierAura.fromJson),
      specials: r.optList('specials', (c) => c.asString()),
      specialParams: Map.unmodifiable(specialParams),
      projectiles: r.optList('projectiles', (c) => c.asString()),
      firePoints: r.optList('firePoints', (c) => c.asPoint()),
      weaponRotation: r.optNumber('weaponRotation', min: -360, max: 360) ?? 0,
      tickMs: r.optNumber('tickMs', min: 0) ?? 0,
      defaultTargetMode: targeting.optString('defaultMode'),
      lockOff: targeting.optBoolean('lockOff', fallback: false),
      art: TurretArt.fromJson(r.child('art')),
      fireSound: r.has('sounds') ? sounds.optString('fire') : null,
      displayNames: r.optList('displayNames', (c) => c.asString()),
    );
  }

  /// Stable kebab-case id (`blue`, `range-up`, `sniper`).
  final String id;

  /// The original ActionScript class (`TurretBlue`), kept for mod/legacy mapping.
  final String legacyId;
  final String name;
  final TurretCategory category;
  final double cost;

  /// Total kills needed before the turret can be bought (0 = always).
  final int unlockKills;
  final bool availableInitially;
  final TurretStats stats;
  final UpgradeTracks upgrades;

  /// Whether modifier auras affect this turret.
  final bool modifiable;
  final bool comboCapableInitially;
  final bool comboNever;

  /// Whether a Targeter may join this turret.
  final bool joinable;

  /// Whether this turret feeds a Fusion cannon in range (`fusion_capable`).
  final bool fusionFeeder;

  /// Whether the directional cone can be set (`target_angle_available`).
  final bool directional;
  final FreakoutSpec? freakout;
  final ModifierAura? modifierAura;

  /// Behaviour ids registered in `RulesRegistry.turretSpecials`.
  final List<String> specials;

  /// Parameters per special id.
  final Map<String, Params> specialParams;

  /// Projectile id fired at each damage level (index = level, last repeats).
  final List<String> projectiles;

  /// Where shots leave the weapon, in weapon-local px (x along the barrel,
  /// rotated with the weapon). Several points are used in turn. Empty = the
  /// turret centre.
  final List<Vec2> firePoints;

  /// Weapon rotation in degrees when built (before it first turns).
  final double weaponRotation;

  /// Real-time interval of its update timer (`frame_space`, a `setInterval`
  /// started when it is built); 0 = every simulation step.
  final double tickMs;

  /// Default target mode id from `targeting.json` (null = no weapon).
  final String? defaultTargetMode;

  /// Drop the target after every shot (`target_reacquire`).
  final bool lockOff;
  final TurretArt art;

  /// Audio event id played when the turret fires.
  final String? fireSound;

  /// Random display names given to new turrets of this type.
  final List<String> displayNames;

  /// The `turrets.json` record. [weaponRotation] is written for a turret
  /// with a turning weapon (`art.weapon`), where 0 is a real rest angle, and
  /// otherwise only when set.
  Map<String, Object?> toJson() => {
    'id': id,
    'legacyId': legacyId,
    'name': name,
    'category': _categoryIds.entries.firstWhere((e) => e.value == category).key,
    'cost': jsonNumber(cost),
    'unlockKills': unlockKills,
    'availableInitially': availableInitially,
    'stats': stats.toJson(),
    'upgrades': upgrades.toJson(),
    'flags': {
      'modifiable': modifiable,
      'comboCapable': comboCapableInitially,
      'comboNever': comboNever,
      'joinable': joinable,
      'fusionFeeder': fusionFeeder,
      'directional': directional,
    },
    'freakout': ?freakout?.toJson(),
    'modifierAura': ?modifierAura?.toJson(),
    'specials': specials,
    if (specialParams.isNotEmpty)
      'specialParams': {for (final e in specialParams.entries) e.key: e.value.toJson()},
    'projectiles': projectiles,
    if (art.weapon != null || weaponRotation != 0) 'weaponRotation': jsonNumber(weaponRotation),
    'tickMs': jsonNumber(tickMs),
    if (firePoints.isNotEmpty) 'firePoints': [for (final p in firePoints) pointToJson(p)],
    'targeting': {'defaultMode': ?defaultTargetMode, 'lockOff': lockOff},
    'art': art.toJson(),
    if (fireSound != null) 'sounds': {'fire': fireSound},
    'displayNames': displayNames,
  };

  /// Projectile fired at [damageLevel] (0 = not upgraded).
  String? projectileAtLevel(int damageLevel) {
    if (projectiles.isEmpty) return null;
    final i = damageLevel.clamp(0, projectiles.length - 1);
    return projectiles[i];
  }
}
