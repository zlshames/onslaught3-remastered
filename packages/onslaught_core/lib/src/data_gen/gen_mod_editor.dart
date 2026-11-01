/// `descriptors.json` and `mod_editor.json` from the legacy table.
library;

import '../data/descriptor_defs.dart';
import '../data/mod_editor_defs.dart';
import 'legacy_table.dart';

/// `descriptors.json`: the original mod editor's descriptor per asset.
DescriptorDefs generateDescriptors(LegacyTable l) {
  ValueDescriptor conv(Map<String, Object?> d) => ValueDescriptor(
    title: d['title']! as String,
    description: d['desc'] as String? ?? '',
    type: d['key_field'] != null ? 'arrayIndexed' : null,
    min: optNumber(d['min']),
    max: optNumber(d['max']),
    step: optNumber(d['step']),
    unit: d['unit'] as String?,
    keyField: d['key_field'] as String?,
    valueField: d['val_field'] as String?,
    key: d['key_data'] == null ? null : conv(obj(d['key_data'])),
    value: d['val_data'] == null ? null : conv(obj(d['val_data'])),
  );
  return DescriptorDefs({
    for (final e in obj(l['modEditor']['descriptors']).entries) e.key: conv(obj(e.value)),
  });
}

/// Where each original mod asset of a turret item lives in a
/// `turrets.json` record (the conversions in `generateTurrets`, reversed).
const _modTurretPaths = {
  'turret_cost': ['cost'],
  'turret_unlock': ['unlockKills'],
  'turret_available': ['availableInitially'],
  'weapon_damage': ['stats', 'damage'],
  'weapon_range': ['stats', 'range'],
  'weapon_rate': ['stats', 'rate'],
  'weapon_poison': ['stats', 'poison'],
  'weapon_rotate': ['stats', 'rotate'],
  'weapon_must_face': ['stats', 'mustFace'],
  'upgrade_damage': ['upgrades', 'damage'],
  'upgrade_range': ['upgrades', 'range'],
  'upgrade_rate': ['upgrades', 'rate'],
  'modify_possible': ['flags', 'modifiable'],
  'combo_capable': ['flags', 'comboCapable'],
  'combo_never': ['flags', 'comboNever'],
  'freak_capable': ['freakout', 'capable'],
  'freak_available': ['freakout', 'availableInitially'],
  'freak_length': ['freakout', 'lengthMs'],
  'freak_space': ['freakout', 'spacingMs'],
  'freak_damage_mult': ['freakout', 'damageMult'],
  'freak_range_mult': ['freakout', 'rangeMult'],
  'freak_rate_mult': ['freakout', 'rateMult'],
  'freak_level_damage': ['freakout', 'levelDamage'],
  'freak_level_range': ['freakout', 'levelRange'],
  'freak_level_rate': ['freakout', 'levelRate'],
  'modify_up_damage': ['modifierAura', 'addDamage'],
  'modify_up_range': ['modifierAura', 'addRange'],
  'modify_up_rate': ['modifierAura', 'addRate'],
  'modify_up_damage_mult': ['modifierAura', 'multDamage'],
  'modify_up_range_mult': ['modifierAura', 'multRange'],
  'modify_up_rate_mult': ['modifierAura', 'multRate'],
};

/// A field of [asset] stored at [path] in [file].
ModFieldDef _field(
  String asset,
  String type,
  String file,
  List<String> path, {
  String? keyField,
  String? valueField,
}) => ModFieldDef(
  asset: asset,
  type: ModValueType.values.byName(type),
  file: file,
  path: path,
  keyField: keyField,
  valueField: valueField,
);

/// Where each `GameSettings` asset lives (`difficulty.json`, `waves.json`).
ModFieldDef? _settingsField(String asset, String type) {
  final d = RegExp(r'_(easy|medium|hard|extreme)$').firstMatch(asset)?.group(1);
  final level = ['levels', ?d];
  ModFieldDef at(String file, List<String> path) => _field(asset, type, file, path);
  return switch (asset) {
    'attacker_energy' => at('difficulty.json', ['baseHp']),
    'attacker_upgrade_rate' => at('difficulty.json', ['defaultHpRate']),
    'attacker_spacing' => at('waves.json', ['creepSpacingMs']),
    'wave_spacing' => at('waves.json', ['waveSpacingMs']),
    'wave_size' => at('waves.json', ['waveSize']),
    'starting_cash_sandbox' => at('difficulty.json', ['modeCash', 'sandbox']),
    'starting_cash_sandbox2' => at('difficulty.json', ['modeCash', 'sandbox2']),
    _ when d == null => null,
    _ when asset.startsWith('attacker_hp_rate_') => _field(
      asset,
      type,
      'difficulty.json',
      [...level, 'hpSchedule'],
      keyField: 'wave',
      valueField: 'rate',
    ),
    _ when asset.startsWith('attacker_speed_') => at('difficulty.json', [...level, 'creepSpeed']),
    _ when asset.startsWith('starting_cash_') => at('difficulty.json', [...level, 'startingCash']),
    _ => null,
  };
}

/// `mod_editor.json`: the original mod editor's items (`item_library`, in
/// its order) and, per item, the assets it offered (`initModAssets`; for
/// a combo, every field of its data, typed by `typeof`), each pointing at
/// the value it edits in the data documents. Items the original lists but
/// the data has no record for (a combo with no recipe) are left out.
/// Defaults are not copied: the editor reads them from the data, so it
/// always shows what a game really uses.
ModEditorDefs generateModEditor(LegacyTable l) {
  final assets = obj(l['modEditor']['assets']);
  final combos = l['combos'];
  final comboData = obj(combos['data']);
  final recipes = {for (final r in objects(combos['recipes'])) r['key']};
  String typeOf(Object? v) => switch (v) {
    bool() => 'boolean',
    String() => 'string',
    _ => 'number',
  };
  final items = <ModItemDef>[];
  for (final e in l.modTitles.entries) {
    final item = e.key;
    final fields = <ModFieldDef>[];
    final String group;
    if (item == 'GameSettings') {
      group = 'settings';
      for (final a in obj(assets[item]).entries) {
        final field = _settingsField(a.key, a.value! as String);
        if (field == null) throw StateError('no data path for $item.${a.key}');
        fields.add(field);
      }
    } else if (item.startsWith('Combo_')) {
      final key = item.substring('Combo_'.length);
      if (!recipes.contains(key)) continue;
      group = 'combo';
      for (final f in obj(comboData[key]).entries) {
        fields.add(
          _field(f.key, typeOf(f.value), 'combos.json', [
            'combos',
            kebab(key),
            if (f.key == 'recharge') 'rechargeMs' else ...['values', camel(f.key)],
          ]),
        );
      }
    } else {
      final id = turretIds[item]!;
      group = basicColours.contains(item)
          ? 'turret'
          : superTurrets.contains(item)
          ? 'super'
          : 'modifier';
      for (final a in obj(assets[item]).entries) {
        final path = _modTurretPaths[a.key];
        if (path == null) throw StateError('no data path for $item.${a.key}');
        final indexed = a.value == 'arrayIndexed';
        fields.add(
          _field(
            a.key,
            a.value! as String,
            'turrets.json',
            ['turrets', id, ...path],
            keyField: indexed ? 'cost' : null,
            valueField: indexed ? 'value' : null,
          ),
        );
      }
    }
    items.add(ModItemDef(id: item, title: e.value! as String, group: group, fields: fields));
  }
  return ModEditorDefs(items);
}
