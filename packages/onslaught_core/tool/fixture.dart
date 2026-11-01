// Records, diffs and shows regression fixtures (see the regression-fixtures skill).
//
//   fvm dart run tool/fixture.dart record session/clock-pause-speed.classic
//   fvm dart run tool/fixture.dart record --all
//   fvm dart run tool/fixture.dart diff   session/clock-pause-speed.classic
//   fvm dart run tool/fixture.dart show   session/clock-pause-speed.classic --from 50 --to 100
//
// Run from packages/onslaught_core. Recording overwrites the committed
// fixture: only do it for a deliberate behaviour change (rule R15).
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:onslaught_core/onslaught_core.dart';
import 'package:onslaught_core/testing.dart';

const _scenarios = 'test/fixtures/scenarios';
const _regression = 'test/fixtures/regression';

void main(List<String> args) {
  if (args.isEmpty) _usage();
  final cmd = args.first;
  final rest = args.skip(1).toList();
  final recorder = FixtureRecorder(_loadData());
  switch (cmd) {
    case 'record':
      final ids = rest.contains('--all')
          ? _scenarioIds()
          : rest.where((a) => !a.startsWith('--')).toList();
      if (ids.isEmpty) _usage();
      for (final id in ids) {
        final fixture = recorder.record(_scenario(id));
        final f = File('$_regression/$id.json')..createSync(recursive: true);
        f.writeAsStringSync(fixture.encode());
        print('recorded $id: ${fixture.events.length} events, ${fixture.hashes.length} hashes');
      }
    case 'diff':
      for (final id in rest) {
        final expected = _fixture(id);
        final diff = FixtureRecorder.diff(expected, recorder.record(expected.scenario));
        print(diff == null ? '$id: identical' : '$id: $diff');
        if (diff != null) exitCode = 1;
      }
    case 'show':
      final id = rest.first;
      int? opt(String name) {
        final i = rest.indexOf(name);
        return i < 0 ? null : int.parse(rest[i + 1]);
      }

      final from = opt('--from') ?? 0;
      final to = opt('--to') ?? 1 << 30;
      final fixture = _fixture(id);
      for (final e in fixture.events) {
        final tick = (e['tick']! as num).toInt();
        if (tick >= from && tick <= to) print(jsonEncode(e));
      }
      for (final h in fixture.hashes) {
        if (h.tick >= from && h.tick <= to) print('hash @${h.tick}: ${h.hash}');
      }
    default:
      _usage();
  }
}

Never _usage() {
  stderr.writeln(
    'usage: fixture.dart record <id…>|--all | diff <id…> | show <id> [--from N] [--to M]',
  );
  exit(64);
}

GameData _loadData() {
  final root = '../../assets/data';
  final manifest = jsonDecode(File('$root/manifest.json').readAsStringSync()) as Map;
  final docs = <String, Object?>{
    'manifest.json': manifest,
    for (final f in (manifest['files'] as List).cast<String>())
      f: jsonDecode(File('$root/$f').readAsStringSync()),
  };
  return GameData.fromDocuments(docs, behaviours: RulesRegistry.classic());
}

List<String> _scenarioIds() => [
  for (final f in Directory(_scenarios).listSync(recursive: true).whereType<File>())
    if (f.path.endsWith('.json')) f.path.substring(_scenarios.length + 1, f.path.length - 5),
]..sort();

Scenario _scenario(String id) => Scenario.fromJson(
  (jsonDecode(File('$_scenarios/$id.json').readAsStringSync()) as Map).cast<String, Object?>(),
);

Fixture _fixture(String id) => Fixture.fromJson(
  (jsonDecode(File('$_regression/$id.json').readAsStringSync()) as Map).cast<String, Object?>(),
);
