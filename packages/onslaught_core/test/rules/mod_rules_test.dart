import 'dart:convert';
import 'dart:io';

import 'package:onslaught_core/onslaught_core.dart';
import 'package:onslaught_core/testing.dart';
import 'package:test/test.dart';

import '../support/repo_data.dart';

void main() {
  late GameData data;
  late ModRules rules;
  late Map<String, Object?> legacy;
  setUpAll(() {
    data = loadClassicData();
    rules = ModRules(data, behaviours: RulesRegistry.classic());
    legacy = (loadLegacyTable()['modEditor']! as Map).cast<String, Object?>();
  });

  ModField field(String id) => rules.field(id) ?? (throw StateError('no field $id'));
  ModField blueDamage() => field('TurretBlue.weapon_damage');

  group('what the editor offers (ModDefaults.initItemLibrary, initModAssets)', () {
    test('items in the original order; Combonly, Targeter and recipe-less combos are not', () {
      final titles = (legacy['itemTitles']! as Map).cast<String, String>();
      final recipes = {for (final c in data.combos.values) c.name};
      final expected = [
        for (final e in titles.entries)
          if (!e.key.startsWith('Combo_') || recipes.contains(e.value.split(': ').last)) e.key,
      ];
      expect([for (final i in rules.items) i.id], expected);
      expect(rules.items.map((i) => i.title), [for (final id in expected) titles[id]]);
      expect(expected, isNot(contains('Combo_big_sparky_clusterbomb')), reason: 'no recipe');
      expect(rules.items.map((i) => i.id), isNot(contains('TurretCombonly')));
    });

    test('each turret and the settings offer exactly the original assets, typed alike', () {
      final assets = (legacy['assets']! as Map).cast<String, Object?>();
      for (final item in rules.items.where((i) => !i.id.startsWith('Combo_'))) {
        final original = (assets[item.id]! as Map).cast<String, String>();
        expect({for (final f in item.fields) f.asset: f.type.name}, original, reason: item.id);
      }
    });

    test('a combo offers every field of its data (typeof), recharge included', () {
      final raw = ((loadLegacyTable()['combos']! as Map)['data']! as Map).cast<String, Object?>();
      final nuke = rules.fieldsOf('Combo_nuke');
      expect({for (final f in nuke) f.def.asset}, (raw['nuke']! as Map).keys.toSet());
      expect(field('Combo_nuke.recharge').defaultValue, data.combos['nuke']!.rechargeMs);
      expect(field('Combo_blackhole.blackhole_eject').type, ModValueType.boolean);
    });

    test('defaults are what games use, not the original editor table', () {
      expect(blueDamage().defaultValue, 15);
      // TurretFusion runs with 1 000 000; the editor table said 4 000 000
      // (docs/DEVIATIONS.md, the (data) fusionBaseDamage row).
      expect(field('TurretFusion.weapon_damage').defaultValue, 1000000);
      expect(field('TurretBlue.upgrade_damage').defaultValue, [
        for (final s in data.turrets['blue']!.upgrades.damage)
          {'cost': s.cost.toInt(), 'value': s.value.toInt()},
      ]);
      expect(field('GameSettings.starting_cash_sandbox2').defaultValue, 1000000);
      expect(field('GameSettings.wave_spacing').defaultValue, 20000);
    });

    test('every field has its descriptor', () {
      for (final f in rules.fields) {
        expect(data.descriptors.byAsset.containsKey(f.def.asset), isTrue, reason: f.id);
      }
      expect(blueDamage().descriptor.title, 'Initial Damage');
    });

    test('a field pointing nowhere or at the wrong type fails validation', () {
      final docs = loadDataDocuments();
      final ed = jsonDecode(jsonEncode(docs['mod_editor.json'])) as Map<String, Object?>;
      final fields = ((ed['items']! as List).first as Map)['fields']! as List;
      (fields[0] as Map)['path'] = ['nothing'];
      (fields[1] as Map)['type'] = 'boolean';
      expect(
        () => GameData.fromDocuments({...docs, 'mod_editor.json': ed}),
        throwsA(
          isA<DataValidationException>().having(
            (e) => e.issues.map((i) => i.reason),
            'reasons',
            containsAll([
              'no value at difficulty.json:/nothing',
              'difficulty.json:/defaultHpRate is not a boolean',
            ]),
          ),
        ),
      );
    });
  });

  group('delta set / clear (assetDeltaSet, assetDeltaClear, itemDeltaClear, modClear)', () {
    test('a set value is read back and stored sparsely by path', () {
      final d = rules.withValue(ModDelta.none, blueDamage(), 99);
      expect(rules.isSet(blueDamage(), d), isTrue);
      expect(rules.valueOf(blueDamage(), d), 99);
      expect(d.files, {
        'turrets.json': {
          'turrets': {
            'blue': {
              'stats': {'damage': 99},
            },
          },
        },
      });
      expect(rules.valueOf(field('TurretBlue.weapon_range'), d), 130, reason: 'default');
      expect(rules.changeCount(d), 1);
    });

    test('whole doubles are stored as ints; setting the default clears the change', () {
      var d = rules.withValue(ModDelta.none, blueDamage(), 99.0);
      expect(rules.valueOf(blueDamage(), d), isA<int>());
      d = rules.withValue(d, blueDamage(), 15);
      expect(d.isEmpty, isTrue);
    });

    test('reset asset leaves the rest of the item; reset item leaves other items', () {
      var d = rules.withValue(ModDelta.none, blueDamage(), 99);
      d = rules.withValue(d, field('TurretBlue.weapon_must_face'), false);
      d = rules.withValue(d, field('TurretRed.turret_cost'), 25);
      d = rules.withValue(d, field('GameSettings.wave_size'), 12);

      final asset = rules.withoutValue(d, blueDamage());
      expect(rules.isSet(blueDamage(), asset), isFalse);
      expect(rules.valueOf(field('TurretBlue.weapon_must_face'), asset), false);
      expect(rules.itemIsSet('TurretBlue', asset), isTrue);

      final item = rules.withoutItem(d, 'TurretBlue');
      expect(rules.itemIsSet('TurretBlue', item), isFalse);
      expect(rules.itemIsSet('TurretRed', item), isTrue);
      expect(rules.itemIsSet('GameSettings', item), isTrue);
      expect((item.files['turrets.json']! as Map)['turrets'], {
        'red': {'cost': 25},
      }, reason: 'emptied objects are pruned');

      final all = rules.cleared(d.copyWithName('Mine'));
      expect([all.isEmpty, all.name], [true, 'Mine']);
    });

    test('applying a delta to an id-record list changes only that record', () {
      final d = rules.withValue(ModDelta.none, field('GameSettings.starting_cash_hard'), 500);
      final modded = rules.apply(d);
      expect(modded.difficulty.level('hard').startingCash, 500);
      expect(modded.difficulty.level('easy').startingCash, 30);
      expect(data.difficulty.level('hard').startingCash, 30, reason: 'base untouched');
    });
  });

  group('min/max per descriptor (ModLibraryItem; NumericStepper bounds)', () {
    test('every number value accepts its bounds and refuses one step beyond', () {
      for (final f in rules.fields.where((f) => f.type == ModValueType.number)) {
        final d = f.descriptor;
        final step = d.step ?? 1;
        if (d.min != null) {
          expect(rules.check(f, d.min), isEmpty, reason: '${f.id} at min');
          final below = d.min! - step;
          if (below != f.defaultValue) {
            expect(rules.check(f, below).single.kind, ModProblemKind.belowMin, reason: f.id);
            expect(rules.check(f, below).single.limit, d.min);
          }
        }
        if (d.max != null) {
          expect(rules.check(f, d.max), isEmpty, reason: '${f.id} at max');
          final above = d.max! + step;
          if (above != f.defaultValue) {
            expect(rules.check(f, above).single.kind, ModProblemKind.aboveMax, reason: f.id);
          }
        }
      }
    });

    test('weapon range: 10 to 800 px', () {
      final range = field('TurretGreen.weapon_range');
      expect(rules.check(range, 9).single.kind, ModProblemKind.belowMin);
      expect(rules.check(range, 801).single.kind, ModProblemKind.aboveMax);
      expect(rules.check(range, 800), isEmpty);
    });

    test('a default outside its descriptor stays acceptable (Blue freak range x 0, min 1)', () {
      final f = field('TurretBlue.freak_range_mult');
      expect(f.defaultValue, 0);
      expect(rules.check(f, 0), isEmpty);
      expect(rules.check(f, 0.5).single.kind, ModProblemKind.belowMin);
    });

    test('types: a word, NaN and infinity are not numbers; booleans must be booleans', () {
      for (final bad in <Object?>['20', double.nan, double.infinity, null, true]) {
        expect(rules.check(blueDamage(), bad).single.kind, ModProblemKind.wrongType);
      }
      final face = field('TurretBlue.weapon_must_face');
      expect(rules.check(face, false), isEmpty);
      expect(rules.check(face, 1).single.kind, ModProblemKind.wrongType);
    });

    test('indexed values: entry count, entry bounds, malformed entries', () {
      final f = field('TurretBlue.upgrade_rate');
      final track = [...(f.defaultValue! as List).cast<Map<String, Object?>>()];
      expect(rules.check(f, track), isEmpty);
      expect(rules.check(f, <Object?>[]).single.kind, ModProblemKind.fewerEntries);
      final slow = [
        ...track,
        {'cost': 2000, 'value': 59},
      ];
      final p = rules.check(f, slow).single;
      expect(
        [p.kind, p.entry, p.part, p.limit],
        [ModProblemKind.belowMin, track.length, 'value', 60],
      );
      final free = [
        {'cost': 0, 'value': 120},
        ...track.skip(1),
      ];
      expect(rules.check(f, free).single.part, 'key');
      expect(
        rules
            .check(f, [
              {'cost': 1},
            ])
            .single
            .kind,
        ModProblemKind.wrongType,
      );
      expect(rules.check(f, {'cost': 1}).single.kind, ModProblemKind.wrongType);
    });

    test('an unchanged entry outside the bounds is kept (Sniper rate 45 < 60)', () {
      final f = field('TurretSniper.upgrade_rate');
      final track = [...(f.defaultValue! as List).cast<Map<String, Object?>>()];
      expect(track.first['value'], 45);
      final cheaper = [
        {...track.first},
        {...track.last, 'cost': 7000},
      ];
      expect(rules.check(f, cheaper), isEmpty);
    });

    test('the modded data must still validate: an upgrade path may not go down', () {
      final f = field('TurretBlue.upgrade_damage');
      final track = [...(f.defaultValue! as List).cast<Map<String, Object?>>()];
      final down = [
        ...track,
        {'cost': 2000, 'value': 1},
      ];
      expect(rules.check(f, down), isEmpty, reason: 'inside the descriptor');
      final problems = rules.validate(rules.withValue(ModDelta.none, f, down));
      expect(problems.single.kind, ModProblemKind.invalidData);
      expect(problems.single.field?.id, 'TurretBlue.upgrade_damage');
      expect(problems.single.detail, 'upgrade values must not decrease');
      expect(rules.validate(ModDelta.none), isEmpty);
    });
  });

  group('import replaces the whole mod (modFromObject)', () {
    test('every valid offered value comes in; nothing of the current mod survives', () {
      final shared = rules.withValue(
        rules.withValue(ModDelta.none, blueDamage(), 99),
        field('GameSettings.wave_size'),
        12,
      );
      final round = ModDelta.fromJson(jsonDecode(jsonEncode(shared.toJson())));
      final read = rules.importDelta(round);
      expect(read.problems, isEmpty);
      expect(read.usable, isTrue);
      expect(read.delta.files, shared.files);
      expect(rules.isSet(field('TurretRed.turret_cost'), read.delta), isFalse);
    });

    test('out-of-range and unknown values are left out and reported', () {
      const incoming = ModDelta({
        'turrets.json': {
          'turrets': {
            'blue': {
              'stats': {'damage': 99, 'range': 5000},
              'tickMs': 1,
            },
          },
        },
        'rules.json': {
          'economy': {'lives': 100},
        },
      }, name: 'Cheat');
      final read = rules.importDelta(incoming);
      expect(rules.valueOf(blueDamage(), read.delta), 99);
      expect(rules.isSet(field('TurretBlue.weapon_range'), read.delta), isFalse);
      expect(read.delta.name, 'Cheat');
      expect(read.problems.map((p) => p.toString()), [
        'aboveMax TurretBlue.weapon_range 800.0',
        'unknownValue turrets.json:/turrets/blue/tickMs',
        'unknownValue rules.json:/economy/lives',
      ]);
      expect(read.usable, isTrue);
    });

    test('a mod whose data does not validate cannot be used', () {
      final f = field('TurretBlue.upgrade_damage');
      final track = [...(f.defaultValue! as List).cast<Map<String, Object?>>()];
      final read = rules.importDelta(
        rules.withValue(ModDelta.none, f, [
          ...track,
          {'cost': 2000, 'value': 1},
        ]),
      );
      expect(read.usable, isFalse);
    });

    test('a mod saved by the original game ("Create Mod Save") converts', () {
      final read = rules.importLegacy({
        'TurretBlue': {
          'weapon_damage': '20',
          'weapon_must_face': 0,
          'upgrade_damage': {
            'cost': [20, 50],
            'amount': [30, 60, 150],
          },
          'upgrade_damage_cost': [20, 50],
          'upgrade_damage_amount': [30, 60, 150],
        },
        'GameSettings': {
          'attacker_hp_rate_extreme': {
            'wave': [1, 50],
            'rate': [1.125, 1.2],
          },
        },
        'Test': {'test_int': 1},
      });
      expect(read.problems.map((p) => p.toString()), ['unknownValue Test.test_int']);
      expect(rules.valueOf(blueDamage(), read.delta), 20);
      expect(rules.valueOf(field('TurretBlue.weapon_must_face'), read.delta), false);
      expect(rules.valueOf(field('TurretBlue.upgrade_damage'), read.delta), [
        {'cost': 20, 'value': 30},
        {'cost': 50, 'value': 60},
      ], reason: 'the shorter of the two arrays');
      expect(rules.apply(read.delta).difficulty.level('extreme').hpSchedule.length, 2);
      expect(rules.importLegacy([1]).problems.single.kind, ModProblemKind.wrongType);
    });
  });

  group('signature (ModManager.modSignature)', () {
    test('stable: key order, 20 vs 20.0 and the name do not change it', () {
      const a = ModDelta({
        'turrets.json': {
          'turrets': {
            'blue': {
              'stats': {'damage': 20, 'range': 140},
            },
          },
        },
        'waves.json': {'waveSize': 12},
      }, name: 'A');
      const b = ModDelta({
        'waves.json': {'waveSize': 12.0},
        'turrets.json': {
          'turrets': {
            'blue': {
              'stats': {'range': 140.0, 'damage': 20},
            },
          },
        },
      }, name: 'B');
      expect(modSignature(a), modSignature(b));
      expect(modSignature(a), matches(RegExp(r'^[0-9a-f]{8}$')));
    });

    test('pinned: the same mod has the same signature in every build', () {
      final d = rules.withValue(ModDelta.none, blueDamage(), 99);
      expect(modSignature(d), '0420522f');
      expect(modSignature(ModDelta.none), '5465b825');
      expect(modSignature(rules.withValue(d, blueDamage(), 98)), isNot(modSignature(d)));
    });
  });

  group('the mod plays (GameManager.resetGame with mod_active)', () {
    test('Blue damage set in the editor is the damage of the next game\'s shells', () {
      final d = rules.withValue(ModDelta.none, blueDamage(), 99);
      final modded = SimTestHarness(rules.apply(d));
      final s = modded.session(const GameConfig(mapId: 'map9', seed: 3))
        ..enqueue(const BuildTurret('blue', 300, 150))
        ..enqueue(const SendNextWave());
      while (s.projectiles.isEmpty) {
        s.step();
      }
      expect(s.projectiles.single.damage, 99);

      final plain = SimTestHarness(data).session(const GameConfig(mapId: 'map9', seed: 3))
        ..enqueue(const BuildTurret('blue', 300, 150))
        ..enqueue(const SendNextWave());
      while (plain.projectiles.isEmpty) {
        plain.step();
      }
      expect(plain.projectiles.single.damage, 15, reason: 'unmodded data is untouched');
    });

    test('the v1 mod fixture still reads and applies', () {
      final json = jsonDecode(
        File(repoPath('packages/onslaught_core/test/fixtures/mods/mod.v1.json')).readAsStringSync(),
      );
      final read = rules.importDelta(ModDelta.fromJson(json));
      expect(read.problems, isEmpty);
      expect(read.delta.name, 'Fixture mod');
      final modded = rules.apply(read.delta);
      expect(modded.turrets['blue']!.stats.damage, 99);
      expect(modded.turrets['blue']!.upgrades.damage.first.value, 40);
      expect(modded.waves.waveSize, 12);
      expect(modded.difficulty.level('extreme').hpSchedule.single.rate, 1.2);
      expect(modded.combos['nuke']!.rechargeMs, 9000);
      expect(modSignature(read.delta), modSignature(ModDelta.fromJson(json)));
    });
  });
}

extension on ModDelta {
  ModDelta copyWithName(String name) => ModDelta(files, name: name);
}

extension on DifficultyDefs {
  DifficultyDef level(String id) => levels.firstWhere((l) => l.id == id);
}
