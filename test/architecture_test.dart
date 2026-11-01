import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// App-side layering rules (docs/REMASTER_PLAN.md §5.1, rules R2, R3, R5, R6, R25).
void main() {
  List<File> dartFiles(String dir) =>
      Directory(dir)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();

  final imports = RegExp(r'''^\s*import\s+['"]([^'"]+)['"]''', multiLine: true);

  test('HUD widgets never import Flame (R2)', () {
    final offenders = [
      for (final f in Directory('lib/features').existsSync() ? dartFiles('lib/features') : <File>[])
        if (f.path.contains('/hud/') &&
            imports.allMatches(f.readAsStringSync()).any((m) => m[1]!.startsWith('package:flame')))
          f.path,
    ];
    expect(offenders, isEmpty);
  });

  test('features do not import each other (R3)', () {
    final offenders = <String>[];
    for (final f in dartFiles('lib/features')) {
      final own = f.path.split('/')[2];
      for (final m in imports.allMatches(f.readAsStringSync())) {
        final target = m[1]!;
        final other =
            RegExp(r'features/(\w+)/').firstMatch(target)?.group(1) ??
            (target.startsWith('../../') && target.contains('features/') ? 'x' : null);
        final rel = RegExp(r'^\.\./(\w+)/').firstMatch(target)?.group(1);
        final crossesRel = rel != null && rel != own && Directory('lib/features/$rel').existsSync();
        if ((other != null && other != own) || crossesRel) offenders.add('${f.path} → $target');
      }
    }
    expect(offenders, isEmpty);
  });

  test('services never import features (dependencies point down)', () {
    final offenders = [
      for (final f in dartFiles('lib/services'))
        for (final m in imports.allMatches(f.readAsStringSync()))
          if (m[1]!.contains('features/')) '${f.path} → ${m[1]}',
    ];
    expect(offenders, isEmpty);
  });

  test('under lib/app only router.dart imports features', () {
    final offenders = [
      for (final f in dartFiles('lib/app'))
        if (f.path.replaceAll(r'\', '/') != 'lib/app/router.dart')
          for (final m in imports.allMatches(f.readAsStringSync()))
            if (m[1]!.contains('features/')) '${f.path} → ${m[1]}',
    ];
    expect(offenders, isEmpty);
  });

  test('asset file paths appear only in services/ (R5)', () {
    final path = RegExp(r'''['"]assets/(images|audio|data)/''');
    final offenders = [
      for (final f in dartFiles('lib'))
        if (!f.path.startsWith('lib/services/') && path.hasMatch(f.readAsStringSync())) f.path,
    ];
    expect(offenders, isEmpty);
  });

  /// User-facing literals left in `lib/` on purpose: file → literals, each
  /// with the reason. Shrink it; never grow it without a reason.
  const uiLiteralAllowlist = <String, Set<String>>{
    // Debug builds only (`FeatureFlags.debugMenu`): the original's debug
    // mode switch is not part of the player's interface.
    'lib/features/menu/settings_screen.dart': {
      'Debug: unlock every mode',
      'Progress is kept; this only opens the locked modes.',
    },
    // The camera debug overlay (`GameOverlays.cameraDebug`, debug flag):
    // a developer readout, not shown to players.
    'lib/features/game/hud/camera_debug_overlay.dart': {r'zoom ${r.zoom.toStringAsFixed(3)} '},
  };

  test('no hard-coded user-facing text in lib/ widgets (R25, ratchet)', () {
    // Every Dart file under lib/, with comment lines dropped.
    final sources = {
      for (final f in dartFiles('lib'))
        f.path.replaceAll(r'\', '/'): f
            .readAsLinesSync()
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n'),
    };
    // A literal right after `Text(`, `tooltip:`, `label:`, `title:`,
    // `semanticsLabel:`, `labelText:` or `hintText:` (also on the next line).
    final pattern = RegExp(
      r"""(?:Text\(|(?<![A-Za-z])(?:tooltip|label|title|semanticsLabel|labelText|hintText):)\s*r?('|")((?:\\.|(?!\1).)*)\1""",
    );
    // Interpolations are code, not words.
    final interpolation = RegExp(r'\$\{[^}]*\}|\$[A-Za-z_]\w*');
    final found = <String>[];
    final stale = <String>[];
    sources.forEach((path, source) {
      for (final m in pattern.allMatches(source)) {
        final literal = m[2]!;
        if (!RegExp('[A-Za-z]').hasMatch(literal.replaceAll(interpolation, ''))) continue;
        if (uiLiteralAllowlist[path]?.contains(literal) ?? false) continue;
        found.add('$path: $literal');
      }
    });
    uiLiteralAllowlist.forEach((path, literals) {
      for (final l in literals) {
        if (!(sources[path]?.contains(l) ?? false)) stale.add('$path: $l');
      }
    });
    expect(found, isEmpty, reason: 'move these into l10n/en.json and look them up with tr');
    expect(stale, isEmpty, reason: 'allowlist entries that no longer exist: remove them');
  });

  /// Package names declared at the top level of a pubspec's sections
  /// (dependencies, dev_dependencies, and `sdk` under environment).
  Set<String> pubspecNames(String path) => RegExp(r'^  (\w+):', multiLine: true)
      .allMatches(File(path).readAsStringSync().split('flutter:\n  uses-material-design').first)
      .map((m) => m[1]!)
      .toSet();

  test('every package dependency of the app is recorded in the dependency log (R6)', () {
    final log = File('.agents/architecture.md').readAsStringSync();
    final deps = pubspecNames('pubspec.yaml').where(
      (d) => !{'flutter', 'flutter_test', 'integration_test', 'onslaught_core', 'sdk'}.contains(d),
    );
    final missing = deps.where((d) => !log.contains('`$d')).toList()..sort();
    expect(missing, isEmpty);
  });

  test('every package in the dependency log is a dependency of the app or the core (R6)', () {
    final log = File('.agents/architecture.md').readAsStringSync();
    final table = log.substring(log.indexOf('## Dependency log'));
    // The first column of each row names the packages; later columns may
    // name alternatives that were not adopted.
    final logged = {
      for (final row in table.split('\n').where((l) => l.startsWith('| ')).skip(1))
        for (final m in RegExp('`([a-z_][a-z0-9_]*)`').allMatches(row.split('|')[1])) m[1]!,
    };
    final declared = {
      ...pubspecNames('pubspec.yaml'),
      ...pubspecNames('packages/onslaught_core/pubspec.yaml'),
    };
    expect(logged, isNotEmpty);
    final stale = logged.where((d) => !declared.contains(d)).toList()..sort();
    expect(stale, isEmpty, reason: 'dependency-log rows name packages no pubspec declares');
  });
}
