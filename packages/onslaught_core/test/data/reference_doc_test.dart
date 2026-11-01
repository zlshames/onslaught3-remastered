import 'dart:io';

import 'package:onslaught_core/onslaught_core.dart';
import 'package:test/test.dart';

import '../support/repo_data.dart';

/// Cross-checks the data against the tables in
/// `docs/ONSLAUGHT2_GAME_REFERENCE.md`, so the human-readable spec and the
/// shipped numbers cannot drift apart silently.
void main() {
  late GameData data;
  late String doc;
  setUpAll(() {
    data = loadClassicData();
    doc = File(repoPath('docs/ONSLAUGHT2_GAME_REFERENCE.md')).readAsStringSync();
  });

  List<List<String>> tableRows(String headerStart) {
    final lines = doc.split('\n');
    final start = lines.indexWhere((l) => l.startsWith(headerStart));
    expect(start, isNot(-1), reason: 'table "$headerStart" not found');
    return [
      for (final l in lines.skip(start + 2).takeWhile((l) => l.startsWith('|')))
        l.split('|').map((c) => c.trim()).toList().sublist(1, l.split('|').length - 1),
    ];
  }

  test('§11 built-in maps: names, bases and roads', () {
    final rows = tableRows('| key | name | base | road |');
    expect(rows.length, data.maps.length);
    for (final r in rows) {
      final m = data.maps[r[0]]!;
      expect(m.name, r[1]);
      final base = r[2].split(',').map(double.parse).toList();
      expect(m.base, Vec2(base[0], base[1]), reason: r[0]);
      final road = RegExp(r'\(([-\d.]+),([-\d.]+)\)')
          .allMatches(r[3])
          .map((p) => Vec2(double.parse(p[1]!), double.parse(p[2]!)))
          .toList();
      expect(m.road, road, reason: r[0]);
    }
  });

  test('§5 basic turret stats', () {
    final rows = tableRows('| | Blue "Cannon" |');
    String cell(String label, int col) => rows.firstWhere((r) => r[0] == label)[col];
    final ids = ['blue', 'green', 'red', 'yellow'];
    for (var i = 0; i < 4; i++) {
      final t = data.turrets[ids[i]]!;
      expect(t.cost, double.parse(cell('Cost', i + 1)), reason: t.id);
      expect(t.stats.damage, double.parse(cell('Damage', i + 1)), reason: t.id);
      expect(t.stats.range, double.parse(cell('Range', i + 1)), reason: t.id);
      expect(t.stats.rate, double.parse(cell('Rate (/min)', i + 1)), reason: t.id);
      expect(t.stats.rotate, double.parse(cell('Rotate °/s', i + 1)), reason: t.id);
    }
  });

  test('§5 upgrade tracks', () {
    for (final (label, id) in [
      ('Blue', 'blue'),
      ('Green', 'green'),
      ('Red', 'red'),
      ('Yellow', 'yellow'),
    ]) {
      final line = doc.split('\n').firstWhere((l) => l.startsWith('- **$label** damage:'));
      for (final stat in StatKind.values) {
        final m = RegExp('${stat.name}: ([^.]+)\\.').firstMatch(line)!;
        final steps = m[1]!
            .split(', ')
            .map((s) => s.split('→').map(double.parse).toList())
            .toList();
        final track = data.turrets[id]!.upgrades.track(stat);
        expect(
          [
            for (final s in track) [s.cost, s.value],
          ],
          steps,
          reason: '$id ${stat.name}',
        );
      }
    }
  });

  test('§6 modifier costs and unlocks', () {
    final rows = tableRows('| Type | Unlock kills | Cost | Effect |');
    final byLegacy = {for (final t in data.turrets.values) t.legacyId: t};
    for (final r in rows) {
      final t = byLegacy['Turret${r[0].split(' ').first}']!;
      expect(t.unlockKills, int.parse(r[1]), reason: r[0]);
      expect(t.cost, double.parse(r[2]), reason: r[0]);
    }
  });

  test('§3 HP schedules', () {
    for (final level in data.difficulty.levels) {
      final line = doc.split('\n').firstWhere((l) => l.startsWith('| ${level.id} |'));
      final steps = RegExp(r'(\d+)→([\d.]+)')
          .allMatches(line)
          .map((m) => (int.parse(m[1]!), double.parse(m[2]!)))
          .toList();
      expect([for (final s in level.hpSchedule) (s.wave, s.rate)], steps, reason: level.id);
    }
  });

  test('§13 blast table', () {
    final rows = tableRows('| Blast | grow ms | diameter |');
    final byLegacy = {for (final b in data.blasts.values) b.legacyId: b};
    for (final r in rows) {
      final key = r[0].startsWith('tiny') ? 'tiny' : r[0].split(' ').first;
      if (r[1] == '–') continue; // the napalm spawner has no size of its own
      final b = byLegacy[key]!;
      expect(b.params.number('growMs'), double.parse(r[1]), reason: key);
      expect(b.params.number('diameter'), double.parse(r[2]), reason: key);
      expect(b.params.number('fadeMs'), double.parse(r[4]), reason: key);
    }
  });
}
