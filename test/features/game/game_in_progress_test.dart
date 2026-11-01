import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/app/app.dart';
import 'package:onslaught3_remastered/features/game/flame/onslaught_flame_game.dart';
import 'package:onslaught3_remastered/features/game/game_view_model.dart';
import 'package:onslaught3_remastered/services/persistence/document_store.dart';
import 'package:onslaught3_remastered/services/persistence/game_in_progress.dart';
import 'package:onslaught3_remastered/services/persistence/settings.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../support/pump.dart';
import '../../support/test_data.dart';

/// Leaving a game pauses and stores it; Play offers to resume it (rebuilt
/// exactly by replaying its commands) or discard it (docs/DEVIATIONS.md
/// `gameInProgress`).
void main() {
  late GameData data;
  setUpAll(() => data = loadTestGameData());

  MemoryDocumentStore store() {
    final s = MemoryDocumentStore();
    // MemoryDocumentStore writes synchronously; drag and drop, as these
    // tests build nothing by hand.
    unawaited(
      s.write(Settings.key, const Settings(placementChoice: PlacementMode.dragAndDrop).toJson()),
    );
    return s;
  }

  Future<void> pumpApp(WidgetTester tester, DocumentStore s, String initial) async {
    tester.view
      ..physicalSize = const Size(923, 411)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: appOverrides(data: data, store: s),
        child: OnslaughtApp(initialLocation: initial),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  SessionGameViewModel vmOf(WidgetTester tester) =>
      tester
              .widget<GameWidget<OnslaughtFlameGame>>(find.byType(GameWidget<OnslaughtFlameGame>))
              .game!
              .viewModel
          as SessionGameViewModel;

  /// Plays a little: an early wave, a build, a few seconds.
  Future<SessionGameViewModel> playABit(WidgetTester tester) async {
    final vm = vmOf(tester);
    vm.dispatch(const SendNextWave());
    final spot = vm.session.map.road.first;
    vm.dispatch(BuildTurret('blue', spot.x + 40, spot.y + 40));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(vm.session.tick, greaterThan(60));
    return vm;
  }

  Future<void> leave(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Back to menu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<GameInProgress?> stored(WidgetTester tester, DocumentStore s) async {
    final doc = await tester.runAsync(() => s.read(GameInProgress.key));
    return doc == null ? null : GameInProgress.fromJson(doc);
  }

  testWidgets('leaving pauses and stores the game; Play offers it; Resume rebuilds it exactly', (
    tester,
  ) async {
    final s = store();
    await pumpApp(tester, s, '/game/map2?difficulty=medium');
    final vm = await playABit(tester);
    final wave = vm.session.waves.wave;
    await leave(tester);

    final game = (await stored(tester, s))!;
    expect(find.text('ONSLAUGHT 3'), findsOneWidget);
    expect([game.mapId, game.difficulty, game.mode], ['map2', 'medium', 'normal']);
    expect(game.wave, wave);
    expect(game.commands.map((c) => c.command.type), contains('pause'));

    await tester.tap(find.text('Play'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Game in progress'), findsOneWidget);
    expect(find.text('Wave: $wave'), findsOneWidget);
    expect(find.text('Lives: ${game.lives}'), findsOneWidget);
    expect(find.text('Difficulty: Medium'), findsOneWidget);

    await tester.tap(find.byKey(const Key('resumeGame')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final resumed = vmOf(tester).session;
    expect(resumed.tick, greaterThanOrEqualTo(game.tick));
    expect(resumed.clock.paused, isTrue, reason: 'a resumed game opens paused');
    expect(resumed.waves.wave, wave);
    expect(resumed.cash, game.cash);
    expect(resumed.turrets, hasLength(vm.session.turrets.length));
  });

  testWidgets('a rebuilt game matches the stored state hash at the stored step', (tester) async {
    final s = store();
    await pumpApp(tester, s, '/game/map2');
    await playABit(tester);
    await leave(tester);
    final game = (await stored(tester, s))!;
    final copy = GameSession(
      data: data,
      config: GameConfig(mapId: game.mapId, difficulty: game.difficulty, seed: game.seed),
    );
    SessionReplay(copy, game.commands, game.tick).runToEnd();
    expect(copy.stateHash(), game.stateHash);
  });

  testWidgets('Discard forgets the stored game and goes on to choose a new one', (tester) async {
    final s = store();
    await pumpApp(tester, s, '/game/map2');
    await playABit(tester);
    // The system back stores the game as the exit button does.
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect((await stored(tester, s))!.commands.last.command.toJson(), {
      'type': 'pause',
      'paused': true,
    });

    await tester.tap(find.text('Play'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('discardGame')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(await stored(tester, s), isNull);
    expect(find.text('Game in progress'), findsNothing);
    expect(find.text('ONSLAUGHT 3'), findsNothing, reason: 'on to the mode screen');
  });

  testWidgets('without a game in progress Play goes straight to choosing a game', (tester) async {
    final s = store();
    await pumpApp(tester, s, '/');
    await tester.tap(find.text('Play'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Game in progress'), findsNothing);
    expect(find.text('ONSLAUGHT 3'), findsNothing);
  });

  testWidgets('the tutorial is not stored, and leaves a stored game alone', (tester) async {
    final s = store();
    await pumpApp(tester, s, '/game/map2');
    await playABit(tester);
    await leave(tester);
    final before = (await stored(tester, s))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: appOverrides(data: data, store: s),
        child: const OnslaughtApp(initialLocation: '/tutorial'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // The system back (Android back, browser back) leaves the tutorial.
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('ONSLAUGHT 3'), findsOneWidget);
    expect((await stored(tester, s))!.tick, before.tick);
  });

  testWidgets('a game that ends forgets the stored one it was', (tester) async {
    final s = store();
    await pumpApp(tester, s, '/game/map2');
    await playABit(tester);
    await leave(tester);
    await tester.tap(find.text('Play'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('resumeGame')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final vm = vmOf(tester);
    final session = vm.session;
    for (final t in session.turrets.toList()) {
      vm.dispatch(SellTurret(t.uid));
    }
    session.debugLives = 1;
    vm
      ..dispatch(const SetPaused(false))
      ..dispatch(const SendNextWave());
    for (var i = 0; i < 1500 && !session.gameOver; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(session.gameOver, isTrue);
    await tester.pump();
    expect(await stored(tester, s), isNull);
  });
}
