import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_coverage.dart' as checker;

/// `tool/check_coverage.dart` (the CI coverage gate): lcov totals, the
/// threshold, an empty report and the exit codes.
void main() {
  /// Two records: 3 of 4 lines and 1 of 4 lines, so 50 %.
  const report = [
    'SF:lib/a.dart',
    'DA:1,1',
    'LF:4',
    'LH:3',
    'end_of_record',
    'SF:lib/b.dart',
    'LF:4',
    'LH:1',
    'end_of_record',
  ];

  test('lcovTotals sums LH and LF over every record', () {
    expect(checker.lcovTotals(report), (4, 8));
    expect(checker.lcovTotals(const []), (0, 0));
  });

  test('a report at or above the minimum passes, below it fails', () {
    final at = checker.checkCoverage('a.info', report, 50);
    expect(at.status, checker.CoverageStatus.pass);
    expect(at.message, 'PASS a.info: 50.0 % of 8 lines (min 50.0 %)');
    final below = checker.checkCoverage('a.info', report, 50.1);
    expect(below.status, checker.CoverageStatus.fail);
    expect(below.message, 'FAIL a.info: 50.0 % of 8 lines (min 50.1 %)');
  });

  test('a report with no coverage records never passes', () {
    for (final lines in [
      const <String>[],
      const ['SF:lib/a.dart', 'end_of_record'],
      const ['LF:0', 'LH:0'],
    ]) {
      final r = checker.checkCoverage('empty.info', lines, 0);
      expect(r.status, checker.CoverageStatus.empty, reason: '$lines');
      expect(r.message, 'FAIL empty.info: no coverage records');
    }
  });

  group('exit codes', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('check_coverage_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    String write(String name, List<String> lines) {
      final f = File('${dir.path}/$name')..writeAsStringSync(lines.join('\n'));
      return f.path;
    }

    ({int code, List<String> lines}) run(List<String> args) {
      final lines = <String>[];
      final code = runZoned(
        () => checker.run(args),
        zoneSpecification: ZoneSpecification(print: (_, _, _, line) => lines.add(line)),
      );
      return (code: code, lines: lines);
    }

    test('usage: no arguments or an odd number is 64', () {
      expect(run(const []).code, 64);
      expect(run([write('a.info', report)]).code, 64);
    });

    test('every file passing is 0, any failing is 1, any empty is 2', () {
      final good = write('good.info', report);
      final empty = write('empty.info', const []);
      expect(run([good, '50']).code, 0);
      expect(run([good, '50', good, '60']).code, 1);
      final r = run([good, '50', empty, '0']);
      expect(r.code, 2);
      expect(r.lines, hasLength(2));
      expect(r.lines.last, 'FAIL $empty: no coverage records');
      expect(run([good, '60', empty, '0']).code, 2);
    });
  });
}
