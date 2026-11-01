import 'package:onslaught_core/data_generator.dart';
import 'package:onslaught_core/onslaught_core.dart';
import 'package:test/test.dart';

import '../support/repo_data.dart';

void main() {
  late GameData data;
  setUpAll(() => data = loadClassicData());

  test('every data file parses and validates', () {
    // loadClassicData throws DataValidationException listing every issue.
    expect(data.turrets, isNotEmpty);
  });

  test('content counts match the original', () {
    expect(data.turrets.length, 16);
    expect(data.combos.length, 20, reason: 'big_sparky_clusterbomb is unreachable and excluded');
    expect(data.maps.length, 13);
    expect(data.challenges.presets.where((p) => !p.debugOnly).length, 14);
    expect(data.creeps.types.length, 9);
    expect(data.difficulty.levels.map((l) => l.id), ['easy', 'medium', 'hard', 'extreme']);
    expect(data.tutorial.pages.length, 36);
    expect(data.targeting.modes.length, 8);
  });

  test('every behaviour id in data is registered', () {
    final issues = validateGameData(data, behaviours: RulesRegistry.classic());
    expect(issues, isEmpty);
  });

  test('turret categories and tray order', () {
    expect(data.turrets.keys.take(4), ['blue', 'green', 'red', 'yellow']);
    expect(data.turrets.values.where((t) => t.category == TurretCategory.modifier).length, 7);
    for (final t in data.turrets.values.where((t) => t.category == TurretCategory.basic)) {
      expect(t.availableInitially, isTrue, reason: t.id);
      expect(t.unlockKills, 0, reason: t.id);
      expect(t.specials, contains('combo'), reason: t.id);
    }
  });

  test('unlock thresholds ascend with tray order after the basics', () {
    final unlocks = [for (final t in data.turrets.values.skip(4)) t.unlockKills];
    expect(unlocks, orderedEquals([...unlocks]..sort()));
    expect(unlocks.first, 300);
    expect(unlocks.last, 1600);
  });

  test('every combo leader has a strict priority order', () {
    for (final leader in ['blue', 'red', 'green', 'yellow']) {
      final p = [
        for (final c in data.combos.values)
          if (c.leader == leader) c.priority,
      ];
      expect(p, [for (var i = 0; i < p.length; i++) i], reason: leader);
    }
  });

  test('maps lie inside the play area and every road has length', () {
    for (final m in data.maps.values) {
      final road = Road.fromMap(m, minePointSpacing: data.world.road.minePointSpacing);
      expect(road.length, greaterThan(0), reason: m.id);
      expect(road.minePoints, isNotEmpty, reason: m.id);
    }
  });

  test('every referenced art id and audio event is well formed', () {
    for (final id in data.referencedArtIds) {
      expect(id, matches(RegExp(r'^[a-z0-9]+(\.[a-z0-9-]+)+$')), reason: id);
    }
    for (final e in data.referencedAudioEvents) {
      expect(data.audio.events, contains(e));
    }
  });

  group('original editor descriptors', () {
    // The original mod editor enforced these bounds on player input. Classic
    // data that sits outside them is an original quirk, listed here so a new
    // violation fails the test.
    const knownOutside = <String>{
      'sniper:upgrade_rate:45', // Sniper's first rate upgrade (45) is below the editor's 60 minimum.
    };

    test('turret stats sit inside the descriptor bounds', () {
      final d = data.descriptors.byAsset;
      final outside = <String>{};
      void check(String turret, String asset, double v, ValueDescriptor? desc) {
        if (desc != null && !desc.accepts(v)) outside.add('$turret:$asset:${v.toInt()}');
      }

      for (final t in data.turrets.values) {
        if (t.category == TurretCategory.modifier) continue;
        if (t.stats.range > 0) check(t.id, 'weapon_range', t.stats.range, d['weapon_range']);
        if (t.stats.rate > 0) check(t.id, 'weapon_rate', t.stats.rate, d['weapon_rate']);
        check(t.id, 'weapon_poison', t.stats.poison, d['weapon_poison']);
        check(t.id, 'weapon_rotate', t.stats.rotate, d['weapon_rotate']);
        for (final s in t.upgrades.rate) {
          check(t.id, 'upgrade_rate', s.value, d['upgrade_rate']?.value);
        }
        for (final s in t.upgrades.range) {
          check(t.id, 'upgrade_range', s.value, d['upgrade_range']?.value);
        }
      }
      expect(outside, knownOutside);
    });
  });

  test('a mod delta changes the next load and is validated', () {
    final docs = loadDataDocuments();
    final modded = GameData.fromDocuments(
      docs,
      delta: const ModDelta({
        'turrets.json': {
          'turrets': {
            'blue': {
              'stats': {'damage': 99},
            },
          },
        },
      }),
    );
    expect(modded.turrets['blue']!.stats.damage, 99);
    expect(data.turrets['blue']!.stats.damage, 15);
    expect(
      () => GameData.fromDocuments(
        docs,
        delta: const ModDelta({
          'turrets.json': {
            'turrets': {
              'blue': {
                'projectiles': ['no-such-shell'],
              },
            },
          },
        }),
      ),
      throwsA(
        isA<DataValidationException>().having(
          (e) => e.issues.single.reason,
          'reason',
          contains('unknown projectile "no-such-shell"'),
        ),
      ),
    );
  });

  test('colour turrets carry their tint and badge shape as art data', () {
    final colours = {
      for (final t in data.turrets.values)
        if (t.art.tint != null || t.art.badgeShape != null) t.id: (t.art.tint, t.art.badgeShape),
    };
    // `TurretCombonly.update` (docs/legacy/ENGINE_NOTES.md §4.8).
    expect(colours, {
      'blue': (0x0000FF, 'circle'),
      'green': (0x01BA01, 'triangle'),
      'red': (0xFF0000, 'square'),
      'yellow': (0xFFCC00, 'diamond'),
    });
    expect(
      () => GameData.fromDocuments(
        loadDataDocuments(),
        delta: const ModDelta({
          'turrets.json': {
            'turrets': {
              'blue': {
                'art': {'tint': 'blue', 'badgeShape': 'star'},
              },
            },
          },
        }),
      ),
      throwsA(
        isA<DataValidationException>().having(
          (e) => e.issues.map((i) => i.reason),
          'reasons',
          containsAll([contains('expected a colour'), contains('must be one of')]),
        ),
      ),
    );
  });

  group('effect art bands', () {
    final banded = {
      'laser-beam': ('beam', const ['core', 'glow', 'width', 'glowSize']),
      'spark': ('spark', const ['core', 'glow', 'width', 'glowSize']),
      'rail-laser': ('rail', const ['strokes']),
    };

    test('every damage-tiered effect has bands, and only those do', () {
      final withBands = [
        for (final p in [...data.projectiles.values, ...data.blasts.values])
          if (p.art?.bands.isNotEmpty ?? false) p.id,
      ];
      expect(withBands, unorderedEquals(banded.keys));
      for (final MapEntry(key: id, value: (kind, _)) in banded.entries) {
        expect(data.projectiles[id]!.kind, kind, reason: id);
      }
    });

    for (final MapEntry(key: id, value: (_, fields)) in banded.entries) {
      test('$id: bounds ascend, one kind of bound, and the last band is open', () {
        final bands = data.projectiles[id]!.art!.bands;
        expect(bands.length, greaterThan(1));
        final bounded = bands.sublist(0, bands.length - 1);
        expect(bands.last.bound, isNull, reason: 'the last band covers every higher damage');
        expect(bounded.map((b) => b.bound), everyElement(isNotNull));
        expect(
          bounded.map((b) => b.upTo != null).toSet(),
          hasLength(1),
          reason: 'a table uses <= or < throughout, as the original',
        );
        for (var i = 1; i < bounded.length; i++) {
          expect(bounded[i].bound!, greaterThan(bounded[i - 1].bound!), reason: '$id band $i');
        }
      });

      test('$id: every band is complete', () {
        final art = data.projectiles[id]!.art!;
        for (final (i, b) in art.bands.indexed) {
          final present = {
            'core': b.core != null,
            'glow': b.glow != null,
            'width': b.width != null,
            'glowSize': b.glowSize != null,
            'strokes': b.strokes.isNotEmpty,
          };
          for (final f in fields) {
            expect(present[f], isTrue, reason: '$id band $i lacks $f');
          }
          if (fields.contains('strokes')) {
            expect(b.strokes, hasLength(art.fx.numbers('strokeWidths')!.length));
            expect(b.strokes, hasLength(art.fx.numbers('strokeAlphas')!.length));
          }
        }
      });
    }

    test('a band is found by damage the way the original tests it', () {
      final laser = data.projectiles['laser-beam']!.art!;
      expect(laser.bandFor(120)!.glow, 0xFF0000, reason: '<= includes the bound');
      expect(laser.bandFor(120.001)!.glow, 0x0000FF);
      final spark = data.projectiles['spark']!.art!;
      expect(spark.bandFor(50)!.core, 0x9999FF, reason: '< excludes the bound');
      expect(spark.bandFor(49.9)!.core, 0x00FF00);
    });

    test('art is not exposed in the mod editor', () {
      final editor = loadDataDocuments()['mod_editor.json'].toString();
      for (final key in ['bands', 'fx', 'strokes', 'captureShrink', 'glowRadius']) {
        expect(editor, isNot(contains(key)), reason: key);
      }
    });
  });

  test('a broken document reports its path', () {
    final docs = loadDataDocuments();
    final world = Map<String, Object?>.of(docs['world.json']! as Map<String, Object?>);
    world['schemaVersion'] = 2;
    docs['world.json'] = world;
    expect(
      () => GameData.fromDocuments(docs),
      throwsA(
        isA<DataValidationException>().having(
          (e) => e.issues.map((i) => i.path),
          'paths',
          contains('world.json:/schemaVersion'),
        ),
      ),
    );
  });

  group('translations', () {
    Map<String, Object?> withFrench(Map<String, String> strings) {
      final docs = loadDataDocuments();
      final manifest = Map<String, Object?>.of(docs['manifest.json']! as Map<String, Object?>);
      manifest['files'] = [...(manifest['files']! as List), 'strings/fr.json'];
      return {
        ...docs,
        'manifest.json': manifest,
        'strings/fr.json': {'schemaVersion': 1, 'locale': 'fr', 'strings': strings},
      };
    }

    test('a translation is used, and what it leaves out falls back to English', () {
      final d = GameData.fromDocuments(
        withFrench({
          'language.name': 'Français',
          'message.weaponAvailable': 'Nouvelle arme disponible : {name}',
        }),
      );
      expect(d.text('message.weaponAvailable', locale: 'fr'), contains('Nouvelle arme'));
      expect(d.text('message.welcome', locale: 'fr'), d.text('message.welcome'));
      expect(d.text('language.name', locale: 'fr'), 'Français');
    });

    test('unknown keys and changed placeholders are refused', () {
      expect(
        () => GameData.fromDocuments(
          withFrench({'no.such.key': 'x', 'message.weaponAvailable': 'Nouvelle arme : {nom}'}),
        ),
        throwsA(
          isA<DataValidationException>().having(
            (e) => e.issues.map((i) => i.path),
            'paths',
            containsAll([
              'strings/fr.json:/strings/no.such.key',
              'strings/fr.json:/strings/message.weaponAvailable',
            ]),
          ),
        ),
      );
    });

    test('the generator writes translations beside English and lists them', () {
      final docs = generateGameDocuments(
        loadLegacyTable(),
        translations: {
          'fr': {
            'schemaVersion': 1,
            'locale': 'fr',
            'strings': {'language.name': 'Français'},
          },
        },
      );
      expect((docs['manifest.json']! as Map)['files'], contains('strings/fr.json'));
      expect(((docs['strings/fr.json']! as Map)['strings'] as Map)['language.name'], 'Français');
    });
  });
}
