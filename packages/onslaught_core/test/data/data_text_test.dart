import 'package:onslaught_core/onslaught_core.dart';
import 'package:test/test.dart';

import '../support/repo_data.dart';

/// The data's own text (names, pickers, tutorial, mod editor) is in the
/// string tables under [DataTextKeys], with English exactly as the
/// documents have it, so a translation can override it and English reads
/// as it always did.
void main() {
  late GameData data;
  setUpAll(() => data = loadClassicData());

  test('every data text has its key, in the documents\' English', () {
    final en = data.strings['en']!.strings;
    final expected = <String, String>{
      for (final t in data.turrets.values) DataTextKeys.turret(t.id): t.name,
      for (final c in data.combos.values) DataTextKeys.combo(c.id): c.name,
      for (final m in data.maps.values) DataTextKeys.map(m.id): m.name,
      for (final c in data.challenges.presets) DataTextKeys.challenge(c.id): c.name,
      for (final corrected in [true, false])
        for (final e in data.challenges.pickersFor(corrected: corrected).entries)
          for (final o in e.value) DataTextKeys.picker(e.key, o.label): o.label,
      for (final (i, p) in data.tutorial.pages.indexed) ...{
        if (p.title.isNotEmpty) DataTextKeys.tutorialTitle(i): p.title,
        if (p.body.isNotEmpty) DataTextKeys.tutorialBody(i): p.body,
      },
      for (final item in data.modEditor.items) DataTextKeys.modItem(item.id): item.title,
      for (final e in data.descriptors.byAsset.entries) ...{
        DataTextKeys.descriptor(e.key, 'title'): e.value.title,
        if (e.value.description.isNotEmpty)
          DataTextKeys.descriptor(e.key, 'description'): e.value.description,
        if (e.value.unit != null) DataTextKeys.descriptor(e.key, 'unit'): e.value.unit!,
        for (final (part, d) in [('key', e.value.key), ('value', e.value.value)])
          if (d != null) ...{
            DataTextKeys.descriptor(e.key, 'title', part: part): d.title,
            if (d.unit != null) DataTextKeys.descriptor(e.key, 'unit', part: part): d.unit!,
          },
      },
    };
    expect(expected.length, greaterThan(400));
    final wrong = [
      for (final e in expected.entries)
        if (en[e.key] != e.value) '${e.key}: ${en[e.key]} != ${e.value}',
    ];
    expect(wrong, isEmpty);
  });

  test('lookups: the locale, then English, then the document', () {
    expect(data.turretName('blue', locale: 'de'), 'Blaue Kanone');
    expect(data.turretName('blue'), 'Blue Cannon');
    expect(data.comboName('nuke', locale: 'xx'), 'Nuke', reason: 'unknown locale: English');
    expect(data.textOr('no.such.key', 'own', locale: 'de'), 'own');
    final classic = data.maps['map1']!;
    expect(data.mapName(classic, locale: 'de'), isNot(classic.name));
    final player = MapDefinition(
      id: 'map1',
      name: 'My Road',
      base: classic.base,
      road: classic.road,
      builtIn: false,
    );
    expect(data.mapName(player, locale: 'de'), 'My Road', reason: "a player's map keeps its name");
    expect(data.tutorialPages().map((p) => p.body), data.tutorial.pages.map((p) => p.body));
    expect(
      data.tutorialPages(locale: 'de').map((p) => p.pointer),
      data.tutorial.pages.map((p) => p.pointer),
    );
  });

  test('picker slugs', () {
    expect(DataTextKeys.slug('One Meelion Dollars!'), 'one-meelion-dollars');
    expect(DataTextKeys.slug(r'$30'), '30');
    expect(DataTextKeys.slug('Slow-Med-Fast\nCycle'), 'slow-med-fast-cycle');
  });
}
