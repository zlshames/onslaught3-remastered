import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/app/app.dart';
import 'package:onslaught3_remastered/app/feature_flags.dart';
import 'package:onslaught3_remastered/features/game/flame/onslaught_flame_game.dart';
import 'package:onslaught3_remastered/features/game/game_view_model.dart';
import 'package:onslaught3_remastered/features/menu/home_screen.dart';
import 'package:onslaught3_remastered/services/persistence/document_store.dart';
import 'package:onslaught3_remastered/services/persistence/profile.dart';
import 'package:onslaught3_remastered/services/persistence/settings.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../support/pump.dart';
import '../../support/test_data.dart';

/// Phase 5 menus: home → mode → map → game; locks, ticks and the debug
/// unlock; the sandbox options; challenges with presets, pickers and best
/// games; settings.
void main() {
  late GameData data;
  setUpAll(() => data = loadTestGameData());

  Future<MemoryDocumentStore> app(
    WidgetTester tester, {
    Size size = const Size(900, 420),
    Profile profile = const Profile(),
    String initial = '/',
    FeatureFlags flags = const FeatureFlags(),
    Map<String, String> raw = const {},
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemoryDocumentStore();
    await store.write(Profile.key, profile.toJson());
    for (final MapEntry(:key, :value) in raw.entries) {
      await store.writeRaw(key, value);
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: appOverrides(data: data, store: store, flags: flags),
        child: OnslaughtApp(initialLocation: initial),
      ),
    );
    await settle(tester);
    return store;
  }

  // The real app boots with the real art and sound (no fakes), at the test
  // view's default size, to the main menu.
  testWidgets('app boots to the main menu', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: appOverrides(data: data, fakes: false),
        child: const OnslaughtApp(),
      ),
    );
    await tester.pump();
    expect(find.text('ONSLAUGHT 3'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  group('credit line', () {
    test('landscape: on the demo road\'s lower straight, mapped to the screen', () {
      const screen = Size(923, 411);
      final zoom = screen.height / data.attract!.stageHeight;
      final road = creditRoad(data.attract!, data.world.road.innerWidth, screen)!;
      expect(road.left, closeTo(screen.width / 2 + (110.3 - 360) * zoom, 1e-6));
      expect(road.right, closeTo(screen.width / 2 + (610.5 - 360) * zoom, 1e-6));
      expect(road.center.dy, closeTo((435.15 + 435.3) / 2 * zoom, 1e-6));
      expect(road.height, closeTo(data.world.road.innerWidth * zoom, 1e-6));
    });

    test('portrait: none, the demo covers the screen', () {
      expect(creditRoad(data.attract!, data.world.road.innerWidth, const Size(411, 923)), isNull);
    });

    testWidgets('sits inside the road on a landscape phone, clear of the menu', (tester) async {
      await app(tester, size: const Size(923, 411));
      final road = creditRoad(data.attract!, data.world.road.innerWidth, const Size(923, 411))!;
      final credits = tester.getRect(find.textContaining('Gaby Vanhegan'));
      expect(credits.left, greaterThanOrEqualTo(road.left));
      expect(credits.right, lessThanOrEqualTo(road.right));
      expect(credits.top, greaterThanOrEqualTo(road.top));
      expect(credits.bottom, lessThanOrEqualTo(road.bottom));
      expect(tester.getRect(find.text('Records')).bottom, lessThan(road.top));
    });
  });

  testWidgets('home → Play → Easy → Classic starts an easy normal game', (tester) async {
    await app(tester);
    expect(find.text('ONSLAUGHT 3'), findsOneWidget);
    expect(find.textContaining('Gaby Vanhegan'), findsOneWidget);
    // The attract demo runs behind the menu.
    expect(find.byType(GameWidget<OnslaughtFlameGame>), findsOneWidget);
    await tester.tap(find.text('Play'));
    await settle(tester);
    expect(find.text('Choose a Game'), findsOneWidget);
    await tester.tap(find.text('Easy Mode'));
    await settle(tester);
    // The display name, not the original's raw id (DEVIATIONS `difficultyNames`).
    expect(find.text('Difficulty: Easy'), findsOneWidget);
    expect(find.text('Classic'), findsOneWidget);
    expect(find.text('Quick Tutorial'), findsNothing, reason: 'the tutorial map is not listed');
    await tester.tap(find.bySemanticsLabel('Map Classic'));
    await settle(tester);
    final game = tester
        .widget<GameWidget<OnslaughtFlameGame>>(find.byType(GameWidget<OnslaughtFlameGame>))
        .game!;
    final s = (game.viewModel as SessionGameViewModel).session;
    expect([s.map.id, s.config.mode, s.difficulty.id], ['map1', 'normal', 'easy']);
    expect(s.config.profile, RulesProfile.classicFixed);
  });

  testWidgets('an unreadable save is reset with one notice on the main menu', (tester) async {
    const notice = 'Some saved data could not be read and was reset';
    final store = await app(tester, raw: {Profile.key: '{"available": ["extreme"', 'mods': '[]'});
    expect(find.text(notice), findsOneWidget);
    expect(await store.readRaw('profile.corrupt'), '{"available": ["extreme"');
    expect(await store.readRaw('mods.corrupt'), '[]');
    // The menus work with the defaults: a new player's modes.
    await tester.tap(find.text('Play'));
    await settle(tester);
    expect(find.text('Choose a Game'), findsOneWidget);
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text(notice), findsNothing);
    await tester.tap(find.byTooltip('Back'));
    await settle(tester);
    expect(find.text('ONSLAUGHT 3'), findsOneWidget);
    expect(find.text(notice), findsNothing, reason: 'once per run');
  });

  testWidgets('readable saves show no notice', (tester) async {
    await app(tester);
    await settle(tester);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a new profile: locked modes say how to unlock them', (tester) async {
    await app(tester, initial: '/mode');
    expect(find.text('Make 2000 kills on any difficulty to unlock'), findsOneWidget);
    expect(find.text('Score 4000 kills on medium to unlock'), findsOneWidget);
    expect(find.text('Play the tutorial to unlock the challenges'), findsOneWidget);
    // Map Tools is open to everyone (Phase 6); Mods unlock by play (Phase 7).
    expect(find.text('Coming in a later update', skipOffstage: false), findsNothing);
    expect(
      find.text('Complete easy, medium and hard modes to enable modding', skipOffstage: false),
      findsOneWidget,
    );
    await tester.tap(find.text('Challenge Games'));
    await settle(tester);
    expect(find.text('Choose a Game'), findsOneWidget, reason: 'locked: no navigation');
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('finished modes are ticked; the debug toggle opens everything', (tester) async {
    await app(
      tester,
      initial: '/mode',
      profile: const Profile(complete: {'easy', 'tutorial'}, unlockAll: true),
    );
    expect(find.bySemanticsLabel(RegExp('^Easy Mode, complete')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Quick Tutorial, complete')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('locked')), findsNothing);
    await tester.tap(find.text('Challenge Games'));
    await settle(tester);
    expect(find.text('Warmup'), findsOneWidget);
  });

  testWidgets('sandbox: the super sandbox is offered once unlocked', (tester) async {
    await app(
      tester,
      initial: '/mode',
      profile: const Profile(available: {'sandbox', 'sandbox2'}),
    );
    await tester.tap(find.text('Sandbox Mode'));
    await settle(tester);
    expect(find.text(r'$1,000,000 · every turret'), findsOneWidget);
    await tester.tap(find.text('Super Sandbox'));
    await settle(tester);
    expect(find.text('Super Sandbox Mode'), findsOneWidget);
  });

  testWidgets('sandbox only: straight to the maps, with the super sandbox hint', (tester) async {
    await app(
      tester,
      initial: '/mode',
      profile: const Profile(available: {'sandbox'}),
    );
    expect(find.text('Score 4000 kills on hard to unlock the super sandbox!'), findsOneWidget);
    await tester.tap(find.text('Sandbox Mode'));
    await settle(tester);
    expect(find.text('Sandbox Mode'), findsOneWidget);
    expect(find.text('Classic'), findsOneWidget);
  });

  testWidgets('challenges: presets, best game, custom, play and back', (tester) async {
    final warmup = data.challenges.presets.firstWhere((p) => p.id == 'warmup');
    await app(
      tester,
      initial: '/challenge',
      profile: Profile(
        available: const {'challenge'},
        complete: {challengeKey(warmup)},
        challengeBest: {
          challengeKey(warmup): ChallengeBest(
            kills: 20,
            spent: 30,
            score: 600,
            dateMs: DateTime(2026, 10, 18, 9, 5).millisecondsSinceEpoch,
          ),
        },
      ),
    );
    expect(find.text('Warmup'), findsOneWidget);
    expect(find.text(r'Kills: 20, $30'), findsOneWidget);
    expect(find.text('Score: 600'), findsOneWidget);
    expect(find.text('18/10/2026, 09:05'), findsOneWidget);
    expect(find.text('Passed'), findsOneWidget);
    await tester.tap(find.byTooltip('Next preset'));
    await settle(tester);
    expect(find.text('Threetown'), findsOneWidget);
    expect(find.text("You haven't played this challenge yet."), findsOneWidget);
    expect(find.text('Beat 300 Waves'), findsOneWidget);
    // Back past the first preset wraps to the last.
    await tester.tap(find.byTooltip('Previous preset'));
    await tester.tap(find.byTooltip('Previous preset'));
    await settle(tester);
    expect(find.text('Smollocks'), findsOneWidget);
    // Changing a picker makes it a custom challenge.
    await tester.tap(find.text('15 Turrets'));
    await settle(tester);
    await tester.tap(find.text('Unlimited').last);
    await settle(tester);
    expect(find.text('Custom challenge'), findsOneWidget);
    // Extreme and the big cash options stay hidden until unlocked.
    await tester.tap(find.text('Hard as Nails'));
    await settle(tester);
    expect(find.text('Extreme!'), findsNothing);
    await tester.tap(find.text('Easy Peasy').last);
    await settle(tester);
    await tester.tap(find.text('Play'));
    await settle(tester);
    expect(find.text('Challenge: Custom challenge'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await settle(tester);
    expect(find.text('Custom challenge'), findsOneWidget);
    expect(find.text('Easy Peasy'), findsOneWidget);
  });

  testWidgets('a preset plays at its difficulty with its cash', (tester) async {
    final spiffles = data.challenges.presets.firstWhere((p) => p.id == 'spiffles');
    await app(
      tester,
      initial: Uri(
        path: '/game/map3',
        queryParameters: {'mode': 'challenge', 'challenge': challengeKey(spiffles)},
      ).toString(),
    );
    final game = tester
        .widget<GameWidget<OnslaughtFlameGame>>(find.byType(GameWidget<OnslaughtFlameGame>))
        .game!;
    final s = (game.viewModel as SessionGameViewModel).session;
    expect(s.config.challenge, same(spiffles));
    expect(s.difficulty.id, 'hard');
    expect(s.cash, 30);
    // The badges: time left and waves.
    expect(find.textContaining(RegExp(r'^(20:00|19:5\d)$')), findsOneWidget);
    expect(find.text('0/100'), findsOneWidget);
  });

  testWidgets('the tutorial starts paused with its window', (tester) async {
    await app(tester, initial: '/tutorial');
    final game = tester
        .widget<GameWidget<OnslaughtFlameGame>>(find.byType(GameWidget<OnslaughtFlameGame>))
        .game!;
    final s = (game.viewModel as SessionGameViewModel).session;
    expect([s.map.id, s.config.mode], ['tutorial', 'tutorial']);
    expect(s.clock.paused, isTrue);
    expect(find.text('Welcome to Onslaught'), findsOneWidget);
    await tester.tap(find.byTooltip('Close the tutorial'));
    await settle(tester);
    expect(find.text('ONSLAUGHT 3'), findsOneWidget);
  });

  testWidgets('settings are saved as they change; debug unlock behind its flag', (tester) async {
    final store = await app(tester, initial: '/settings');
    expect(find.text('Debug: unlock every mode'), findsNothing);
    await tester.tap(find.text('Sound'));
    await settle(tester);
    await tester.tap(find.text('Remember wave settings for the next game'));
    await settle(tester);
    final saved = Settings.fromJson((await store.read(Settings.key))!);
    expect(saved.soundOn, isFalse);
    expect(saved.waveRemember, isTrue);
  });

  testWidgets('Tower placement offers drop and lock and saves it', (tester) async {
    final store = await app(tester, initial: '/settings');
    final choice = find.byType(DropdownButton<PlacementMode>);
    await tester.scrollUntilVisible(choice, 100);
    await tester.ensureVisible(choice);
    await settle(tester);
    expect(find.text('Tower placement'), findsOneWidget);
    await tester.tap(choice);
    await settle(tester);
    await tester.tap(find.text('Drop and lock').last);
    await settle(tester);
    final saved = Settings.fromJson((await store.read(Settings.key))!);
    expect(saved.placement, PlacementMode.dropAndLock);
  });

  testWidgets('the debug unlock toggle writes the profile', (tester) async {
    final store = await app(
      tester,
      initial: '/settings',
      flags: const FeatureFlags(debugMenu: true),
    );
    await tester.scrollUntilVisible(find.text('Debug: unlock every mode'), 100);
    await tester.tap(find.text('Debug: unlock every mode'));
    await settle(tester);
    expect(Profile.fromJson((await store.read(Profile.key))!).unlockAll, isTrue);
  });

  testWidgets('remembered wave settings start the game with them', (tester) async {
    final store = MemoryDocumentStore();
    await store.write(
      Settings.key,
      const Settings(
        waveSpacingS: 12,
        waveFollow: true,
        waveRemember: true,
        timeScale: 1.5,
      ).toJson(),
    );
    tester.view
      ..physicalSize = const Size(900, 420)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: appOverrides(data: data, store: store),
        child: const OnslaughtApp(initialLocation: '/game/map1'),
      ),
    );
    await settle(tester);
    final game = tester
        .widget<GameWidget<OnslaughtFlameGame>>(find.byType(GameWidget<OnslaughtFlameGame>))
        .game!;
    final s = (game.viewModel as SessionGameViewModel).session;
    expect(s.waveSpacingMs, 12000);
    expect(s.waveFollow, isTrue);
  });

  /// Android's Back button (or gesture), as the platform sends it.
  Future<bool> systemBack(WidgetTester tester) async {
    final handled = await tester.binding.handlePopRoute();
    await settle(tester);
    return handled;
  }

  testWidgets('the system back follows the back button, then the main menu exits', (tester) async {
    await app(tester, initial: '/mods');
    expect(find.text(data.text('flow.modeModding')), findsOneWidget);
    expect(await systemBack(tester), isTrue, reason: 'the app must not close');
    expect(find.text('Choose a Game'), findsOneWidget);
    expect(await systemBack(tester), isTrue);
    expect(find.text('ONSLAUGHT 3'), findsOneWidget);
    // Nothing behind the main menu: the pop goes to the platform (the app exits).
    expect(await systemBack(tester), isFalse);
  });

  testWidgets('the system back: maps → mode, settings → home', (tester) async {
    await app(tester, initial: '/maps');
    expect(find.text(data.text('flow.modeMapping')), findsOneWidget);
    expect(await systemBack(tester), isTrue);
    expect(find.text('Choose a Game'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await app(tester, initial: '/settings');
    expect(await systemBack(tester), isTrue);
    expect(find.text('ONSLAUGHT 3'), findsOneWidget);
  });

  testWidgets('the system back leaves a game for the main menu', (tester) async {
    await app(tester, initial: '/game/map1');
    expect(find.byType(GameWidget<OnslaughtFlameGame>), findsOneWidget);
    expect(find.text('ONSLAUGHT 3'), findsNothing);
    expect(await systemBack(tester), isTrue);
    expect(find.text('ONSLAUGHT 3'), findsOneWidget);
  });

  testWidgets('the system back closes a dialog before leaving the screen', (tester) async {
    await app(tester, initial: '/mode');
    final context = tester.element(find.text('Choose a Game'));
    unawaited(showDialog<void>(context: context, builder: (_) => const Text('a dialog')));
    await settle(tester);
    expect(find.text('a dialog'), findsOneWidget);
    expect(await systemBack(tester), isTrue);
    expect(find.text('a dialog'), findsNothing);
    expect(find.text('Choose a Game'), findsOneWidget);
  });
  // ------------------------------------------------------------ portrait

  testWidgets('portrait: the modes run one per row without overflowing', (tester) async {
    await app(tester, size: const Size(375, 667), initial: '/mode');
    expect(tester.takeException(), isNull);
    final easy = tester.getRect(find.text('Easy Mode'));
    final medium = tester.getRect(find.text('Medium Mode'));
    expect(medium.left, easy.left);
    expect(medium.top, greaterThan(easy.bottom));
  });

  testWidgets('portrait: the map page shows two maps a row', (tester) async {
    await app(tester, size: const Size(402, 874), initial: '/map?mode=normal&difficulty=easy');
    expect(tester.takeException(), isNull);
    final first = tester.getRect(find.text('Classic'));
    expect(first.right, lessThan(402 / 2 + 1));
  });

  testWidgets('portrait: the challenge page puts Play above the pickers', (tester) async {
    await app(
      tester,
      size: const Size(402, 874),
      profile: const Profile(unlockAll: true),
      initial: '/challenge',
    );
    expect(tester.takeException(), isNull);
    final play = tester.getRect(find.text('Play'));
    final difficulty = tester.getRect(find.text('Difficulty'));
    expect(play.bottom, lessThan(difficulty.top));
  });
}

/// Pumps a few frames (the Flame games never settle).
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
