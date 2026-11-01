import 'as2_literal.dart';

/// Turns AS2 values into plain JSON values (Map/List/num/String/bool/null).
Object? toJsonValue(Object? v) => switch (v) {
  As2Undefined() => null,
  As2Ref(:final name) => name,
  Map() => {for (final e in v.entries) e.key as String: toJsonValue(e.value)},
  List() => [for (final e in v) toJsonValue(e)],
  _ => v,
};

/// Values from `mods/ModDefaults.as`: per mod item (`TurretBlue`,
/// `GameSettings` …) the default of every asset, plus the editor descriptors
/// and item titles.
class ModDefaultsData {
  ModDefaultsData({required this.items, required this.descriptors, required this.itemTitles});

  /// Item → asset → value (JSON values).
  final Map<String, Map<String, Object?>> items;

  /// Asset name → descriptor fields (title, desc, min, max, step, unit,
  /// key_field, val_field, key_data, val_data).
  final Map<String, Map<String, Object?>> descriptors;

  /// Item → title shown in the original mod editor.
  final Map<String, String> itemTitles;
}

ModDefaultsData readModDefaults(String source) {
  final items = <String, Map<String, Object?>>{};
  for (final fn in ['initTurretsStandard', 'initTurretsModifiers', 'initTurretsSuper']) {
    for (final a in scanAssignments(functionBody(source, fn))) {
      final parts = a.target.split('.');
      if (parts.length != 3 || parts[0] != 'this') continue;
      items.putIfAbsent(parts[1], () => {})[parts[2]] = toJsonValue(a.value);
    }
  }
  items.remove('Test');

  final settings = <String, Object?>{};
  for (final a in scanAssignments(functionBody(source, 'initManagers'))) {
    final parts = a.target.split('.');
    if (parts.length == 2 && parts[0] == '_loc2_') {
      settings[parts[1]] = toJsonValue(a.value);
    }
  }
  items['GameSettings'] = settings;

  // Descriptors: ModLibraryItems built in locals, then stored by asset name.
  final descriptors = <String, Map<String, Object?>>{};
  final locals = <String, Map<String, Object?>>{};
  for (final a in scanAssignments(functionBody(source, 'initAssetLibrary'))) {
    final parts = a.target.split('.');
    if (parts.length == 1) {
      if (a.valueSource.trim() == 'new mods.ModLibraryItem()') {
        locals[parts[0]] = {};
      } else if (locals.containsKey(a.valueSource.trim())) {
        locals[parts[0]] = locals[a.valueSource.trim()]!;
      }
    } else if (parts.length == 2 && locals.containsKey(parts[0])) {
      final rhs = a.valueSource.trim();
      locals[parts[0]]![parts[1]] = locals.containsKey(rhs) ? locals[rhs] : toJsonValue(a.value);
    } else if (parts.length == 3 && parts[0] == 'this' && parts[1] == 'asset_library') {
      final rhs = a.valueSource.trim();
      final d = locals[rhs];
      if (d != null && !parts[2].startsWith('test_')) descriptors[parts[2]] = d;
    }
  }

  final titles = <String, String>{};
  for (final a in scanAssignments(functionBody(source, 'initItemLibrary'))) {
    if (a.target == 'this.item_library') {
      final v = toJsonValue(a.value)! as Map<String, Object?>;
      v.forEach((k, t) => titles[k] = t! as String);
    }
  }
  return ModDefaultsData(items: items, descriptors: descriptors, itemTitles: titles);
}

/// `ModDefaults.initModAssets`: which assets the original mod editor offers
/// for each item, and each asset's type (`number`, `boolean`,
/// `arrayIndexed`, …; the `MOD_*` constants of `ModManager.as`, given as
/// [typeNames]). Combo items are built at run time from the combo data
/// (`typeof` of each field) and are not listed here; nor is the `Test` item.
Map<String, Map<String, String>> readModAssets(String source, Map<String, String> typeNames) {
  // The object literals wrap across lines (`mods\n      .ModDefaults.MOD_NUMBER`).
  final body = functionBody(source, 'initModAssets').replaceAll(RegExp(r'\s*\n\s*'), '');
  final lists = <String, Map<String, String>>{};
  for (final m in RegExp(r'var (_loc\d+_) = new Object\((\{[^}]*\})\);').allMatches(body)) {
    final literal = parseAs2Literal(m.group(2)!)! as Map<String, Object?>;
    lists[m.group(1)!] = {
      for (final e in literal.entries)
        e.key:
            typeNames[(e.value! as As2Ref).name.split('.').last] ??
            (throw StateError('unknown mod type ${e.value}')),
    };
  }
  final out = <String, Map<String, String>>{};
  for (final m in RegExp(r'this\.mod_assets\.(\w+) = (_loc\d+_);').allMatches(body)) {
    if (m.group(1) == 'Test') continue;
    out[m.group(1)!] = lists[m.group(2)!]!;
  }
  return out;
}

/// The `static var MOD_X = "…";` type constants of `ModManager.as`.
Map<String, String> readModTypeNames(String source) => {
  for (final m in RegExp(r'static var (MOD_\w+) = "(\w+)";').allMatches(source))
    m.group(1)!: m.group(2)!,
};

/// The decompiler's name for a local (`_loc2_`, `_loc3_`, …) changes between
/// builds of the SWF, so readers find each local by how it is created.
final _local = RegExp(r'^_loc\d+_$');

/// Combo key → numeric data from `Combos.as` (`Combos.init`), in source order.
Map<String, Map<String, Object?>> readCombos(String source) {
  final out = <String, Map<String, Object?>>{};
  var current = <String, Object?>{};
  String? local;
  for (final a in scanAssignments(functionBody(source, 'init'))) {
    if (_local.hasMatch(a.target) && a.valueSource.trim() == 'new ComboData()') {
      local = a.target;
      current = {};
    } else if (local != null && a.target.startsWith('$local.')) {
      current[a.target.substring(local.length + 1)] = toJsonValue(a.value);
    } else if (a.target.startsWith('Combos.combo_data.')) {
      out[a.target.substring('Combos.combo_data.'.length)] = current;
    }
  }
  return out;
}

/// A map as declared in `RoadManager.as`.
class LegacyMap {
  LegacyMap(this.key, this.name, this.base, this.road);
  final String key;
  final String name;
  final Map<String, Object?> base;
  final List<Map<String, Object?>> road;
}

/// Built-in maps from `RoadManager.as`, in declaration order.
List<LegacyMap> readMaps(String source) {
  final bases = <String, Map<String, Object?>>{};
  final names = <String, String>{};
  final layouts = <String, List<Map<String, Object?>>>{};
  final order = <String>[];
  for (final a in scanAssignments(source)) {
    final parts = a.target.split('.');
    if (parts.length != 3 || parts[0] != 'this') continue;
    final key = parts[2];
    final rhs = a.valueSource.trim();
    if (rhs.startsWith('this.')) continue; // aliases such as `standard`
    switch (parts[1]) {
      case 'map_bases':
        bases[key] = toJsonValue(a.value)! as Map<String, Object?>;
      case 'map_names':
        names[key] = toJsonValue(a.value)! as String;
        if (!order.contains(key)) order.add(key);
      case 'map_layouts':
        layouts[key] = [
          for (final p in toJsonValue(a.value)! as List<Object?>) p! as Map<String, Object?>,
        ];
    }
  }
  return [
    for (final k in order)
      if (bases.containsKey(k) && layouts.containsKey(k))
        LegacyMap(k, names[k]!, bases[k]!, layouts[k]!),
  ];
}

/// Challenge presets and picker option lists from `GameSelectChallenge.as`.
class LegacyChallenges {
  LegacyChallenges(this.presets, this.pickers);

  /// Each preset's fields, plus `debugOnly` for the debug-mode test preset.
  final List<Map<String, Object?>> presets;

  /// Picker id → options `{label, data, requiresMode?, debugOnly?}`.
  final Map<String, List<Map<String, Object?>>> pickers;
}

LegacyChallenges readChallenges(String source) {
  // Presets: blocks of `_locN_.k = v;` pushed with `this.challenge_list.push`;
  // the first is only pushed in debug mode.
  final ctor = functionBody(source, 'GameSelectChallenge');
  final presets = <Map<String, Object?>>[];
  var current = <String, Object?>{};
  var debugGuard = false;
  String? preset;
  final presetNew = RegExp(r'^(?:var )?(_loc\d+_) = new Object\(\)');
  for (final line in ctor.split('\n')) {
    final t = line.trim();
    final created = presetNew.firstMatch(t);
    if (created != null) {
      preset = created.group(1);
      current = {};
      debugGuard = false;
    } else if (t.startsWith('if(GameStatus.debug_mode == true)')) {
      debugGuard = true;
    } else if (preset != null && t.startsWith('this.challenge_list.push($preset)')) {
      presets.add({...current, if (debugGuard) 'debugOnly': true});
    } else if (preset != null) {
      final a = scanAssignments(t).firstOrNull;
      if (a != null && a.target.startsWith('$preset.') && a.target != '$preset.encoded') {
        current[a.target.substring(preset.length + 1)] = toJsonValue(a.value);
      }
    }
  }

  // Pickers: `_locN_.X = new Array(...)` and guarded `_locN_.X.push(...)` on
  // the local stored as `GameSelectChallenge.ChallengeOptions`.
  // A push onto a list that does not exist yet is a no-op, as in AS2.
  final onLoad = functionBody(source, 'onLoad');
  final options = RegExp(r'GameSelectChallenge\.ChallengeOptions = (_loc\d+_);')
      .firstMatch(onLoad)!
      .group(1)!;
  final pickers = <String, List<Map<String, Object?>>>{};
  String? requiresMode;
  var debugOnly = false;
  final push = RegExp(
    '^$options'
    r'\.(\w+)\.push\((.*)\);$',
  );
  for (final line in onLoad.split('\n')) {
    final t = line.trim();
    final guard = RegExp(r'modeIsAvailable\("(\w+)"\)').firstMatch(t);
    if (t.startsWith('if(') && guard != null) {
      requiresMode = guard.group(1);
      continue;
    }
    if (t.startsWith('if(GameStatus.debug_mode == true)')) {
      debugOnly = true;
      continue;
    }
    if (t == '}') {
      requiresMode = null;
      debugOnly = false;
      continue;
    }
    final pm = push.firstMatch(t);
    if (pm != null) {
      final list = pickers[pm.group(1)!];
      if (list == null) continue;
      final opt = toJsonValue(parseAs2Literal(pm.group(2)!))! as Map<String, Object?>;
      list.add({...opt, 'requiresMode': ?requiresMode, if (debugOnly) 'debugOnly': true});
      continue;
    }
    final a = scanAssignments(t).firstOrNull;
    if (a != null &&
        RegExp(
          '^$options'
          r'\.\w+$',
        ).hasMatch(a.target)) {
      pickers[a.target.substring(options.length + 1)] = [
        for (final o in toJsonValue(a.value)! as List<Object?>) o! as Map<String, Object?>,
      ];
    }
  }
  return LegacyChallenges(presets, pickers);
}

/// Turret class → random display names (`TurretManager` constructor).
Map<String, List<String>> readTypeNames(String source) {
  final out = <String, List<String>>{};
  for (final a in scanAssignments(source)) {
    if (a.target.startsWith('this.type_names.')) {
      out[a.target.substring('this.type_names.'.length)] = [
        for (final n in toJsonValue(a.value)! as List<Object?>) n! as String,
      ];
    }
  }
  return out;
}

/// Tutorial pages from `GameTutorial.tutorialBuild`, in order.
List<Map<String, Object?>> readTutorialPages(String source) {
  final body = functionBody(source, 'tutorialBuild');
  final pages = <Map<String, Object?>>[];
  final pageLocal = RegExp(r'this\.page_list\.push\((_loc\d+_)\);').firstMatch(body)!.group(1)!;
  final blocks = body.split('this.page_list.push($pageLocal);');
  for (final block in blocks) {
    final page = <String, Object?>{};
    for (final a in scanAssignments(block)) {
      if (!a.target.startsWith('$pageLocal.')) continue;
      final key = a.target.substring(pageLocal.length + 1);
      if (key == 'title' || key == 'text') page[key] = toJsonValue(a.value);
      if (key == 'show') page['show'] = a.valueSource.trim();
      if (key == 'show_now') page['showNow'] = toJsonValue(a.value);
    }
    final cash = RegExp(r'player_cash\s*=\s*(\d+)').firstMatch(block);
    if (cash != null) page['setCash'] = int.parse(cash.group(1)!);
    if (page.containsKey('title')) pages.add(page);
  }
  return pages;
}

/// The literal defaults of one AS2 class: class-level `var`/`static var`
/// initialisers, then every literal `this.x = v`, `this.x.k = v` and
/// `this.x[i] = v` in its constructor (in source order, so later wins).
/// Arrays filled by index become lists when the indices are 0…n−1, otherwise
/// maps keyed by the index (e.g. `attacker_hp_rate_easy[10] = 1.2`).
class ClassDefaults {
  ClassDefaults(this.className, this.superName, this.values);

  final String className;

  /// Short name of the superclass (`Turret`, `TurretModify`), or null.
  final String? superName;

  /// Property → JSON value.
  final Map<String, Object?> values;
}

final _classDecl = RegExp(r'^class\s+([\w.]+)(?:\s+extends\s+([\w.]+))?');
final _classVar = RegExp(r'^   (?:static )?var (\w+) = (.+);\s*$');
final _thisAssign = RegExp(r'^\s*this\.(\w+)((?:\.\w+|\[\d+\])*)\s*=\s*(.+);\s*$');

ClassDefaults readClassDefaults(String source) {
  final lines = source.split('\n');
  final decl = _classDecl.firstMatch(lines.first.trim());
  if (decl == null) throw StateError('not a class file');
  String short(String n) => n.split('.').last;
  final className = short(decl.group(1)!);
  final superName = decl.group(2) == null ? null : short(decl.group(2)!);

  final values = <String, Object?>{};
  for (final line in lines) {
    final m = _classVar.firstMatch(line);
    if (m == null) continue;
    final v = _tryLiteral(m.group(2)!);
    if (v != _noValue) values[m.group(1)!] = v;
  }

  String ctor;
  try {
    ctor = functionBody(source, className);
  } on StateError {
    ctor = '';
  }
  for (final line in ctor.split('\n')) {
    final m = _thisAssign.firstMatch(line);
    if (m == null) continue;
    final v = _tryLiteral(m.group(3)!);
    if (v == _noValue) continue;
    final name = m.group(1)!;
    final path = RegExp(r'\.(\w+)|\[(\d+)\]').allMatches(m.group(2)!).toList();
    if (path.isEmpty) {
      values[name] = v;
      continue;
    }
    // Nested assignment: walk/create maps keyed by property or index.
    var node = values[name];
    if (node is! Map<String, Object?>) {
      node = <String, Object?>{};
      values[name] = node;
    }
    var cur = node;
    for (var i = 0; i < path.length; i++) {
      final key = path[i].group(1) ?? path[i].group(2)!;
      if (i == path.length - 1) {
        cur[key] = v;
      } else {
        cur = (cur[key] ??= <String, Object?>{}) as Map<String, Object?>;
      }
    }
  }
  values.updateAll((k, v) => _listify(v));
  return ClassDefaults(className, superName, values);
}

/// Merges [chain] (base class first) into one map of effective defaults.
Map<String, Object?> mergeClassChain(List<ClassDefaults> chain) => {
  for (final c in chain) ...c.values,
};

const Object _noValue = Object();

Object? _tryLiteral(String src) {
  final s = src.trim();
  // Empty `new Array()`/`new Object()` start containers filled later.
  if (s == 'new Array()' || s == 'new Object()') return <String, Object?>{};
  try {
    final v = parseAs2Literal(s);
    if (v is As2Ref) return _noValue; // references to other values: not data
    return toJsonValue(v);
  } on As2ParseException {
    return _noValue;
  }
}

Object? _listify(Object? v) {
  if (v is Map<String, Object?>) {
    final m = v.map((k, e) => MapEntry(k, _listify(e)));
    final idx = m.keys.map(int.tryParse).toList();
    if (m.isNotEmpty && idx.every((i) => i != null)) {
      final sorted = idx.cast<int>()..sort();
      final contiguous = [for (var i = 0; i < sorted.length; i++) i];
      if (sorted.length == contiguous.length &&
          Iterable<int>.generate(sorted.length).every((i) => sorted[i] == i)) {
        return [for (var i = 0; i < sorted.length; i++) m['$i']];
      }
    }
    return m;
  }
  return v;
}
