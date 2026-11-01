import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:onslaught3_remastered/app/app.dart';
import 'package:onslaught3_remastered/features/game/flame/onslaught_flame_game.dart';
import 'package:onslaught3_remastered/features/game/game_view_model.dart';
import 'package:onslaught3_remastered/services/persistence/document_store.dart';
import 'package:onslaught3_remastered/services/persistence/mod_library.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../support/pump.dart';
import '../../support/test_data.dart';

/// Phase 7: the mod editor end to end in the app — edit, refuse, reset,
/// switch on, export, import, and the next game plays the mod (the plan's
/// "changing Blue damage in the editor changes the next game and exports
/// as a share string").
void main() {
  late GameData data;
  late ModRules rules;
  setUpAll(() {
    data = loadTestGameData();
    rules = ModRules(data, behaviours: RulesRegistry.classic());
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<MemoryDocumentStore> app(
    WidgetTester tester, {
    Size size = const Size(923, 411),
    String initial = '/mods',
    ModLibrary mods = const ModLibrary(),
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemoryDocumentStore();
    await store.write(ModLibrary.key, mods.toJson());
    await tester.pumpWidget(
      ProviderScope(
        overrides: appOverrides(data: data, store: store),
        child: OnslaughtApp(initialLocation: initial),
      ),
    );
    await settle(tester);
    return store;
  }

  Future<ModLibrary> stored(MemoryDocumentStore store) async =>
      ModLibrary.fromJson((await store.read(ModLibrary.key))!);

  ModField field(String id) => rules.field(id)!;

  Future<void> open(WidgetTester tester, String fieldId) async {
    final item = fieldId.split('.').first;
    await tester.tap(find.byKey(Key('modItem:$item')));
    await tester.pump();
    final row = find.byKey(Key('modField:$fieldId'));
    await tester.scrollUntilVisible(
      row,
      100,
      scrollable: find.descendant(
        of: find.byKey(const Key('modFields')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.ensureVisible(row);
    await tester.pump();
    await tester.tap(row);
    await tester.pump();
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('modNumber')), text);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
  }

  GameSession session(WidgetTester tester) =>
      (tester
                  .widget<GameWidget<OnslaughtFlameGame>>(
                    find.byType(GameWidget<OnslaughtFlameGame>),
                  )
                  .game!
                  .viewModel
              as SessionGameViewModel)
          .session;

  testWidgets('change Blue damage, switch the mod on: the next game uses it', (tester) async {
    final store = await app(tester);
    expect(find.text('Moddable Stuff'), findsOneWidget);
    expect(find.text('No changes yet'), findsOneWidget);
    expect(find.text('Export'), findsOneWidget);
    expect(
      tester.widget<TextButton>(find.widgetWithText(TextButton, 'Export')).onPressed,
      isNull,
      reason: 'nothing to export yet',
    );

    await open(tester, 'TurretBlue.weapon_damage');
    expect(find.text('Initial Damage'), findsWidgets);
    expect(find.textContaining('Min: 1'), findsOneWidget);
    await type(tester, '99');
    expect(find.text('1 change · signature 0420522f'), findsOneWidget);
    expect(find.text('Default: 15 hit points'), findsOneWidget);
    var mods = await stored(store);
    expect(rules.valueOf(field('TurretBlue.weapon_damage'), mods.mod), 99);
    expect(mods.active, isFalse);

    await tester.tap(find.byKey(const Key('modActive')));
    await settle(tester);
    mods = await stored(store);
    expect(mods.applies, isTrue);

    // The next game: Blue shells carry 99, and the watermark names the mod
    // and marks the game custom (it records no progress).
    GoRouter.of(tester.element(find.text('Moddable Stuff'))).go('/game/map1');
    await settle(tester);
    expect(session(tester).data.turrets['blue']!.stats.damage, 99);
    expect(find.text('Custom game · Mod: My mod, signature: 0420522f'), findsOneWidget);
  });

  testWidgets('a game with the mod switched off plays the classic values', (tester) async {
    final mod = rules.withValue(ModDelta.none, field('TurretBlue.weapon_damage'), 99);
    await app(
      tester,
      initial: '/game/map1',
      mods: ModLibrary(mod: mod),
    );
    expect(session(tester).data.turrets['blue']!.stats.damage, 15);
    expect(find.textContaining('signature'), findsNothing);
  });

  testWidgets('a value outside its descriptor is refused with the reason', (tester) async {
    final store = await app(tester);
    await open(tester, 'TurretBlue.weapon_range');
    await type(tester, '5');
    expect(find.text('Must be at least 10'), findsOneWidget);
    await type(tester, '801');
    expect(find.text('Must be at most 800'), findsOneWidget);
    await type(tester, 'far');
    expect(find.text('That is not a valid value'), findsOneWidget);
    expect((await stored(store)).mod.isEmpty, isTrue);

    // The stepper moves by the step and stops at the bound.
    await type(tester, '799');
    expect(find.text('Must be at most 800'), findsNothing);
    await tester.tap(find.byTooltip('Increase'));
    await settle(tester);
    expect(rules.valueOf(field('TurretBlue.weapon_range'), (await stored(store)).mod), 800);
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add)).onPressed, isNull);
  });

  testWidgets('reset value, reset item, reset all', (tester) async {
    var mod = rules.withValue(ModDelta.none, field('TurretBlue.weapon_damage'), 99);
    mod = rules.withValue(mod, field('TurretBlue.turret_cost'), 12);
    mod = rules.withValue(mod, field('TurretRed.turret_cost'), 25);
    final store = await app(tester, mods: ModLibrary(mod: mod, active: true));
    expect(find.text('3 changes · signature ${modSignature(mod)}'), findsOneWidget);

    await open(tester, 'TurretBlue.weapon_damage');
    await tester.tap(find.byKey(const Key('modResetValue')));
    await settle(tester);
    var now = (await stored(store)).mod;
    expect(rules.isSet(field('TurretBlue.weapon_damage'), now), isFalse);
    expect(rules.isSet(field('TurretBlue.turret_cost'), now), isTrue);

    await tester.drag(find.byKey(const Key('modFields')), const Offset(0, 600));
    await settle(tester);
    await tester.tap(find.byKey(const Key('modResetItem')));
    await settle(tester);
    now = (await stored(store)).mod;
    expect([rules.itemIsSet('TurretBlue', now), rules.itemIsSet('TurretRed', now)], [false, true]);

    await tester.tap(find.byTooltip('Reset all'));
    await settle(tester);
    expect(find.text('Reset the whole mod?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Reset to Defaults'));
    await settle(tester);
    final after = await stored(store);
    expect([after.mod.isEmpty, after.active], [true, true]);
    expect(find.text('No changes yet'), findsOneWidget);
  });

  testWidgets('an upgrade path: insert a row between two, remove it again', (tester) async {
    final store = await app(tester);
    final f = field('TurretBlue.upgrade_damage');
    final track = (f.defaultValue! as List).cast<Map<String, Object?>>();
    await open(tester, f.id);
    expect(find.text('Cost (\$)'), findsOneWidget);
    await tester.tap(find.byTooltip('Entry #1'));
    await settle(tester);
    await tester.tap(find.text('Insert below'));
    await settle(tester);
    final inserted = rules.valueOf(f, (await stored(store)).mod)! as List;
    expect(inserted.length, track.length + 1);
    expect(inserted[1], {'cost': 35, 'value': 45}, reason: 'the midpoint of #1 and #2');

    await tester.tap(find.byTooltip('Entry #2'));
    await settle(tester);
    await tester.tap(find.text('Remove'));
    await settle(tester);
    expect((await stored(store)).mod.isEmpty, isTrue, reason: 'back to the default');
  });

  testWidgets('a value that breaks the data is refused (an upgrade that goes down)', (
    tester,
  ) async {
    final store = await app(tester);
    await open(tester, 'TurretBlue.upgrade_damage');
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('modEntry1:value')),
        matching: find.byType(TextField),
      ),
      '10',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(find.text('The game cannot use this: upgrade values must not decrease'), findsOneWidget);
    expect((await stored(store)).mod.isEmpty, isTrue);
  });

  testWidgets('export a code; import it on another profile: it replaces the mod', (tester) async {
    final shared = rules.withValue(
      const ModDelta({}, name: 'Big Blue'),
      field('TurretBlue.weapon_damage'),
      99,
    );
    final code = const ModSharing().encode(shared);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
      call,
    ) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    // Someone else's mod is replaced, values the code does not set included.
    final mine = rules.withValue(ModDelta.none, field('TurretRed.turret_cost'), 25);
    final store = await app(tester, mods: ModLibrary(mod: mine));
    await tester.tap(find.text('Import'));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('modImportCode')), code);
    await settle(tester);
    expect(find.textContaining('Big Blue · 1 changed values'), findsOneWidget);
    expect(find.text('Replaces your current mod (1 changed values)'), findsOneWidget);
    await tester.tap(find.text('Load mod'));
    await settle(tester);
    expect(find.text('Your mod was successfully loaded!'), findsOneWidget);
    final now = await stored(store);
    expect(now.name, 'Big Blue');
    expect(now.mod.files, shared.files);

    await tester.tap(find.text('Export'));
    await settle(tester);
    expect(tester.widget<SelectableText>(find.byKey(const Key('shareCode'))).data, code);
    await tester.tap(find.text('Copy'));
    await settle(tester);
    expect(copied, code);
  });

  testWidgets('an import with bad values says what is left out; a broken one cannot load', (
    tester,
  ) async {
    await app(tester);
    await tester.tap(find.text('Import'));
    await settle(tester);
    await tester.enterText(
      find.byKey(const Key('modImportCode')),
      '{"TurretBlue":{"weapon_range":5000,"weapon_damage":20}}',
    );
    await settle(tester);
    expect(find.text('Left out:'), findsOneWidget);
    expect(find.text('• Turret: Blue Cannon › Initial Range: Must be at most 800'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Load mod')).onPressed,
      isNotNull,
    );

    await tester.enterText(find.byKey(const Key('modImportCode')), 'ons3:map:abc');
    await settle(tester);
    expect(find.textContaining('this is a map code'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Load mod')).onPressed,
      isNull,
    );
  });

  testWidgets('rename the mod', (tester) async {
    final store = await app(tester);
    await tester.tap(find.byKey(const Key('modName')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('modNameField')), '  Glass Cannon ');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await settle(tester);
    expect((await stored(store)).name, 'Glass Cannon');
    expect(find.text('Glass Cannon'), findsOneWidget);
  });

  testWidgets('portrait: one pane at a time, and back steps out a level', (tester) async {
    await app(tester, size: const Size(402, 874));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('modItems')), findsOneWidget);
    expect(find.byKey(const Key('modFields')), findsNothing);
    final first = rules.items.first;
    await tester.tap(find.byKey(Key('modItem:${first.id}')));
    await tester.pump();
    expect(find.byKey(const Key('modItems')), findsNothing);
    expect(find.byKey(const Key('modFields')), findsOneWidget);
    final f = rules.fieldsOf(first.id).first;
    await tester.tap(find.byKey(Key('modField:${f.id}')));
    await tester.pump();
    expect(find.byKey(const Key('modFields')), findsNothing);
    expect(find.byKey(Key('modValue:${f.id}')), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    expect(find.byKey(const Key('modFields')), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    expect(find.byKey(const Key('modItems')), findsOneWidget);
    // Import and share are icon buttons on a narrow screen.
    expect(find.byTooltip('Import'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
