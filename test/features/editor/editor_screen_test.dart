import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/app/app.dart';
import 'package:onslaught3_remastered/features/editor/editor_canvas.dart';
import 'package:onslaught3_remastered/features/game/flame/onslaught_flame_game.dart';
import 'package:onslaught3_remastered/features/game/game_view_model.dart';
import 'package:onslaught3_remastered/services/persistence/document_store.dart';
import 'package:onslaught3_remastered/services/persistence/map_library.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../support/pump.dart';
import '../../support/test_data.dart';

/// Phase 6: Map Tools end to end in the app — library, editor, save, share
/// code, import and play (the plan's "a user-made map round-trips through a
/// share string and plays").
void main() {
  late GameData data;
  setUpAll(() => data = loadTestGameData());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<MemoryDocumentStore> app(
    WidgetTester tester, {
    Size size = const Size(923, 411),
    String initial = '/maps',
    MapLibrary library = const MapLibrary(),
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemoryDocumentStore();
    await store.write(MapLibrary.key, library.toJson());
    await tester.pumpWidget(
      ProviderScope(
        overrides: appOverrides(data: data, store: store),
        child: OnslaughtApp(initialLocation: initial),
      ),
    );
    await settle(tester);
    return store;
  }

  /// Taps world point [p] on the editor canvas.
  Future<void> tapWorld(WidgetTester tester, Vec2 p) async {
    final canvas = find.byType(EditorCanvas);
    final rig = tester.state<EditorCanvasState>(canvas).rig;
    final local = rig.worldToScreen(Offset(p.x, p.y));
    await tester.tapAt(tester.getTopLeft(canvas) + local);
    await tester.pump();
  }

  Future<void> dragWorld(WidgetTester tester, Vec2 from, Vec2 to) async {
    final canvas = find.byType(EditorCanvas);
    final rig = tester.state<EditorCanvasState>(canvas).rig;
    final origin = tester.getTopLeft(canvas);
    final a = origin + rig.worldToScreen(Offset(from.x, from.y));
    final b = origin + rig.worldToScreen(Offset(to.x, to.y));
    final g = await tester.startGesture(a);
    for (var i = 1; i <= 5; i++) {
      await g.moveTo(Offset.lerp(a, b, i / 5)!);
      await tester.pump();
    }
    await g.up();
    await tester.pump();
  }

  Future<void> buildMap(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Close tips'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel(RegExp('^Start')));
    await tester.pump();
    expect(find.text('Tap the map to place the start'), findsOneWidget);
    await tapWorld(tester, const Vec2(0, 100));
    await tester.tap(find.bySemanticsLabel(RegExp('^Base')));
    await tester.pump();
    await tapWorld(tester, const Vec2(550, 347));
    await tapWorld(tester, const Vec2(200, 100));
    await tapWorld(tester, const Vec2(200, 300));
  }

  testWidgets('make a map, save it, share it, import it elsewhere and play it', (tester) async {
    final store = await app(tester);
    expect(find.textContaining('No maps yet'), findsOneWidget);
    await tester.tap(find.text('New map'));
    await settle(tester);
    expect(find.text('New map'), findsOneWidget, reason: 'the editor title');
    expect(find.text(data.text('editor.noStart')), findsOneWidget);

    await buildMap(tester);
    expect(find.text('New map •'), findsOneWidget, reason: 'unsaved changes');
    expect(find.text(data.text('editor.noStart')), findsNothing);

    // Drag the second waypoint, then undo and redo it.
    await dragWorld(tester, const Vec2(200, 300), const Vec2(400, 300));
    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    await tester.tap(find.byTooltip('Redo'));
    await tester.pump();

    await tester.tap(find.byTooltip('Save'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), '  Test Map ');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await settle(tester);
    expect(find.text('Test Map'), findsOneWidget);
    final saved = MapLibrary.fromJson((await store.read(MapLibrary.key))!);
    final map = saved.byId('custom-test-map')!;
    expect(map.name, 'Test Map');
    expect(map.road.first.x, closeTo(0, 0.001));
    expect(map.road.first.y, closeTo(100, 0.001));
    expect(map.road[1].x, closeTo(200, 0.001));
    expect(map.road[2].x, closeTo(400, 0.001), reason: 'the redone drag');
    expect(validateMap(map, data.world), isEmpty);

    await tester.tap(find.byTooltip('Share'));
    await settle(tester);
    final code = tester.widget<SelectableText>(find.byKey(const Key('shareCode'))).data!;
    expect(code, startsWith('ons3:map:'));
    await tester.tap(find.text('Close'));
    await settle(tester);

    // Another player's library: import the code there and play it.
    await tester.pumpWidget(const SizedBox());
    final other = await app(tester);
    await tester.tap(find.text('Import'));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('importCode')), '$code\n');
    await tester.pump();
    expect(find.text('Test Map'), findsOneWidget, reason: 'preview');
    await tester.tap(find.text('Add to my maps'));
    await settle(tester);
    final imported = MapLibrary.fromJson((await other.read(MapLibrary.key))!).byName('Test Map')!;
    expect(imported.road, map.road);
    expect(imported.base, map.base);

    await tester.tap(find.bySemanticsLabel('My map Test Map'));
    await settle(tester);
    await tester.tap(find.text('Play'));
    await settle(tester);
    await tester.tap(find.text(data.text('difficulty.medium')));
    await settle(tester);
    final game = tester
        .widget<GameWidget<OnslaughtFlameGame>>(find.byType(GameWidget<OnslaughtFlameGame>))
        .game!;
    final s = (game.viewModel as SessionGameViewModel).session;
    expect(s.map.id, imported.id);
    expect(s.map.road, map.road);
    expect([s.config.mode, s.difficulty.id], ['normal', 'medium']);
    // A player's map is a custom game: labelled, and its progress not kept.
    expect(find.text(data.text('ui.game.custom')), findsOneWidget);
    expect(
      (game.viewModel as SessionGameViewModel).messages.value.map((m) => m.text),
      contains(data.text('message.customGame')),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an unreadable code says why and adds nothing', (tester) async {
    await app(tester);
    await tester.tap(find.text('Import'));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('importCode')), 'ons3:mod:abc');
    await tester.pump();
    expect(find.textContaining('this is a mod code'), findsOneWidget);
    final add = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Add to my maps'));
    expect(add.onPressed, isNull);
  });

  testWidgets('a map cannot be saved until it is valid', (tester) async {
    await app(tester, initial: '/editor');
    await tester.tap(find.byTooltip('Save'));
    await settle(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text(data.text('editor.noStart')), findsWidgets);
  });

  testWidgets('leaving with unsaved changes asks first', (tester) async {
    await app(tester, initial: '/editor');
    await buildMap(tester);
    await tester.tap(find.byTooltip('Back'));
    await settle(tester);
    expect(find.text('Leave without saving?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await settle(tester);
    expect(find.text('New map •'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await settle(tester);
    await tester.tap(find.text('Leave'));
    await settle(tester);
    expect(find.text('Map Tools'), findsOneWidget);
  });

  testWidgets('a library map opens in the editor and can be deleted', (tester) async {
    const map = MapDefinition(
      id: 'custom-loop',
      name: 'Loop',
      base: Vec2(500, 300),
      road: [Vec2(0, 100), Vec2(300, 100), Vec2(505, 327)],
      builtIn: false,
    );
    final store = await app(tester, library: const MapLibrary().saving(map));
    await tester.tap(find.bySemanticsLabel('My map Loop'));
    await settle(tester);
    await tester.tap(find.text('Edit'));
    await settle(tester);
    expect(find.text('Loop'), findsOneWidget);
    expect(find.byType(EditorCanvas), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('My map Loop'));
    await settle(tester);
    await tester.tap(find.text('Delete'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await settle(tester);
    expect(find.textContaining('No maps yet'), findsOneWidget);
    expect(MapLibrary.fromJson((await store.read(MapLibrary.key))!).maps, isEmpty);
  });

  testWidgets('portrait: the palette runs along the bottom; the map fills upright', (tester) async {
    await app(tester, size: const Size(402, 874), initial: '/editor');
    expect(tester.takeException(), isNull);
    final rig = tester.state<EditorCanvasState>(find.byType(EditorCanvas)).rig;
    expect(rig.fill, isTrue);
    expect(rig.isAtHome, isTrue);
    final start = tester.getRect(find.bySemanticsLabel(RegExp('^Start')).first);
    expect(start.top, greaterThan(874 - 100.0));
    // Fit, Help and Share fold into More; Fit shows the whole map.
    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Fit the whole map'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(rig.isAtFit, isTrue);
    // Building a map works the same.
    await buildMap(tester);
    expect(tester.takeException(), isNull);
  });
}
