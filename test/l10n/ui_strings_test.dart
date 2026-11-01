import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/app/app.dart';
import 'package:onslaught3_remastered/app/strings.dart';
import 'package:onslaught3_remastered/services/persistence/document_store.dart';
import 'package:onslaught3_remastered/services/persistence/mod_library.dart';
import 'package:onslaught3_remastered/services/persistence/settings.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../support/pump.dart';
import '../support/test_data.dart';

/// Phase 8 localisation guard rails: every string key the app looks up
/// exists in the English table. The ratchet against hard-coded user-facing
/// English (R25) lives in test/architecture_test.dart.
void main() {
  late GameData data;
  setUpAll(() => data = loadTestGameData());

  /// Every Dart file under `lib/`, with its source (comment lines dropped).
  Map<String, String> libSources() => {
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>())
      if (f.path.endsWith('.dart'))
        f.path.replaceAll(r'\', '/'): f
            .readAsLinesSync()
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n'),
  };

  test('every string key the app looks up is in the English table', () {
    final english = data.strings['en']!.strings;
    final lookups = [
      // `data.tr(context, 'key'`, `ref.tr(context, 'key'`, `data.text('key'`.
      RegExp(r"""\.tr\(\s*context,\s*'([A-Za-z0-9_.]+)'"""),
      RegExp(r"""\.text\(\s*'([A-Za-z0-9_.]+)'"""),
      // Any `ui.*` key literal (keys held in tables or passed to helpers).
      RegExp(r"""'(ui\.[A-Za-z0-9_.]+)'"""),
    ];
    final missing = <String>[];
    var found = 0;
    libSources().forEach((path, source) {
      for (final pattern in lookups) {
        for (final m in pattern.allMatches(source)) {
          found++;
          if (!english.containsKey(m[1])) missing.add('$path: ${m[1]}');
        }
      }
    });
    expect(found, greaterThan(100), reason: 'the scan finds the lookups');
    expect(
      missing,
      isEmpty,
      reason: 'keys used in lib/ but missing from strings/en.json: add them to l10n/en.json and regenerate',
    );
  });

  testWidgets('the interface follows the chosen language, English where untranslated', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(923, 411)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // The real data plus a French table that translates only Play.
    final docs = loadTestDocuments();
    final manifest = Map<String, Object?>.of(docs['manifest.json']! as Map<String, Object?>);
    manifest['files'] = [...(manifest['files']! as List), 'strings/fr.json'];
    final french = GameData.fromDocuments({
      ...docs,
      'manifest.json': manifest,
      'strings/fr.json': {
        'schemaVersion': 1,
        'locale': 'fr',
        'strings': {'language.name': 'Français', 'ui.menu.play': 'Jouer'},
      },
    }, behaviours: RulesRegistry.classic());
    final store = MemoryDocumentStore();
    await store.write(Settings.key, const Settings(locale: 'fr').toJson());
    await tester.pumpWidget(
      ProviderScope(
        overrides: appOverrides(data: french, store: store, noHaptics: true),
        child: const OnslaughtApp(),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Jouer'), findsOneWidget, reason: 'translated');
    expect(find.text('Play'), findsNothing);
    expect(find.text('Settings'), findsOneWidget, reason: 'untranslated: English');
    // Leave the menu so the attract demo is disposed inside the test.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("a new mod's stored default name shows in the interface language", (tester) async {
    final names = <String>[];
    await tester.pumpWidget(
      Localizations(
        locale: const Locale('de'),
        delegates: const [DefaultWidgetsLocalizations.delegate],
        child: Builder(
          builder: (context) {
            names
              ..add(data.modName(context, ModLibrary.defaultName))
              ..add(data.modName(context, 'Turbo'));
            return const SizedBox();
          },
        ),
      ),
    );
    expect(names, ['Mein Mod', 'Turbo']);
  });
}
