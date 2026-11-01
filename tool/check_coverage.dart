// Fails when line coverage in an lcov file is below a threshold.
//
//   fvm dart run tool/check_coverage.dart <lcov.info> <min %> [<lcov.info> <min %> …]
//
// Thresholds (docs/REMASTER_PLAN.md §8.2): core ≥ 85 %, app ≥ 70 %.
// Exit codes: 0 every file passes, 1 one is below its minimum, 2 one has no
// coverage records (an empty or truncated report never passes), 64 usage.
// ignore_for_file: avoid_print

import 'dart:io';

void main(List<String> args) => exit(run(args));

/// Checks every `<lcov.info> <min %>` pair in [args], printing one line per
/// file, and returns the exit code.
int run(List<String> args) {
  if (args.isEmpty || args.length.isOdd) {
    stderr.writeln('usage: check_coverage.dart <lcov.info> <min %> [...]');
    return 64;
  }
  final results = [
    for (var i = 0; i < args.length; i += 2)
      checkCoverage(args[i], File(args[i]).readAsLinesSync(), double.parse(args[i + 1])),
  ];
  for (final r in results) {
    print(r.message);
  }
  if (results.any((r) => r.status == CoverageStatus.empty)) return 2;
  if (results.any((r) => r.status == CoverageStatus.fail)) return 1;
  return 0;
}

enum CoverageStatus { pass, fail, empty }

/// The verdict on one lcov file and the line printed for it.
typedef CoverageResult = ({CoverageStatus status, String message});

/// Checks the lcov report [lines] read from [file] against [min] percent of
/// lines hit. A report with no lines found is [CoverageStatus.empty], never
/// a pass.
CoverageResult checkCoverage(String file, List<String> lines, double min) {
  final (hit, found) = lcovTotals(lines);
  if (found == 0) {
    return (status: CoverageStatus.empty, message: 'FAIL $file: no coverage records');
  }
  final pct = hit * 100 / found;
  final pass = pct >= min;
  return (
    status: pass ? CoverageStatus.pass : CoverageStatus.fail,
    message:
        '${pass ? 'PASS' : 'FAIL'} $file: ${pct.toStringAsFixed(1)} % of $found lines (min $min %)',
  );
}

/// Sums `LH:` (lines hit) and `LF:` (lines found) over every record.
(int, int) lcovTotals(List<String> lines) {
  var hit = 0;
  var found = 0;
  for (final l in lines) {
    if (l.startsWith('LH:')) hit += int.parse(l.substring(3));
    if (l.startsWith('LF:')) found += int.parse(l.substring(3));
  }
  return (hit, found);
}
