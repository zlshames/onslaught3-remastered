import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/features/game/game_view_model.dart';
import 'package:onslaught3_remastered/features/game/hud/game_over_panel.dart';
import 'package:onslaught3_remastered/features/game/hud/objective_badges.dart';
import 'package:onslaught3_remastered/features/game/hud/tutorial_panel.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../support/fake_game_view_model.dart';
import '../../support/pump.dart';
import '../../support/test_data.dart';

/// Phase 5 in the game: challenge badges, messages and the challenge-over
/// dialog from a live session; the tutorial window and its arrow.
void main() {
  late GameData data;
  setUpAll(() => data = loadTestGameData());

  ChallengeDef preset(String id) => data.challenges.presets.firstWhere((p) => p.id == id);

  SessionGameViewModel challengeVm(ChallengeDef c) => SessionGameViewModel(
    GameSession(
      data: data,
      config: GameConfig(
        mapId: 'map1',
        mode: 'challenge',
        difficulty: c.difficulty,
        challenge: c,
        seed: 3,
      ),
    ),
  );

  void step(SessionGameViewModel vm, [int n = 1]) {
    for (var i = 0; i < n; i++) {
      vm.advance(1 / data.rules.tickHz);
    }
  }

  void autokill(SessionGameViewModel vm) {
    for (final c in List.of(vm.session.creeps)) {
      if (c.targetable) vm.session.debugHitCreep(c, double.infinity);
    }
  }

  group('view model', () {
    test('challenge badges notify when a badge changes, not on every step', () {
      final vm = challengeVm(preset('smollocks'));
      step(vm);
      final shown = <String>[];
      vm.objectives.addListener(() => shown.add(vm.objectives.value.first.text));
      // Two seconds of game time: the time badge ticks twice; the waves
      // badge stays at 0/500.
      step(vm, data.rules.tickHz * 2);
      expect(shown, ['29:59', '29:58']);
      vm.dispose();
    });

    test('challenge badges: time, waves and kills in the original order', () {
      final vm = challengeVm(preset('smollocks'));
      step(vm);
      expect(
        [for (final b in vm.objectives.value) '${b.kind} ${b.text} ${b.state.name}'],
        ['time 30:00 pending', 'waves 0/500 pending'],
      );
      final kills = challengeVm(preset('bounce'));
      step(kills);
      expect(
        [for (final b in kills.objectives.value) '${b.kind} ${b.text}'],
        ['time 20:00', 'kills 0/4000'],
      );
    });

    test('a normal game has no badges and the original welcome lines', () {
      final vm = SessionGameViewModel(
        GameSession(
          data: data,
          config: const GameConfig(mapId: 'map1'),
        ),
      );
      step(vm);
      expect(vm.objectives.value, isEmpty);
      expect(vm.messages.value.map((m) => m.text), [
        data.text('message.welcome'),
        data.text('message.attackersComing'),
      ]);
    });

    test('the tutorial opens with its own message', () {
      final vm = SessionGameViewModel(
        GameSession(
          data: data,
          config: const GameConfig(mapId: 'tutorial', mode: 'tutorial'),
        ),
      );
      expect(vm.messages.value.map((m) => m.text), [data.text('flow.tutorialStart')]);
    });

    test('passing Warmup: time badge reached, the message and the passed dialog', () {
      final vm = challengeVm(preset('warmup'));
      while (vm.gameOver.value == null && vm.session.clock.nowMs < 70000) {
        step(vm);
        autokill(vm);
      }
      final end = vm.gameOver.value!;
      expect(end.end, GameEnd.challengePassed);
      expect(end.seconds, 60);
      expect(vm.objectives.value.single.state, BadgeState.reached);
      expect(vm.objectives.value.single.text, '00:00');
      expect(
        vm.messages.value.last.text,
        'You beat the challenge! And all within the time limit too! Consider this challenge complete.',
      );
    });

    test('continue playing after passing: the dialog goes, the waves resume', () {
      final vm = challengeVm(preset('warmup'));
      while (vm.gameOver.value == null) {
        step(vm);
        autokill(vm);
      }
      expect(vm.gameOver.value!.canContinue, isTrue);
      vm.dispatch(const ContinuePlaying());
      step(vm);
      expect(vm.gameOver.value, isNull);
      expect(vm.hud.value.gameOver, isFalse);
      final wave = vm.session.waves.wave;
      vm.dispatch(const SendNextWave());
      step(vm);
      expect(vm.session.waves.wave, wave + 1);
      // Lives running out now end it as a plain game, not a failed challenge.
      vm.session.debugLives = 1;
      while (vm.gameOver.value == null) {
        vm.dispatch(const SendNextWave());
        step(vm, 30);
      }
      expect(vm.gameOver.value!.end, GameEnd.gameOver);
    });

    test('the tutorial win shows the win dialog', () {
      final vm = SessionGameViewModel(
        GameSession(
          data: data,
          config: const GameConfig(mapId: 'tutorial', mode: 'tutorial'),
        ),
      );
      while (vm.gameOver.value == null) {
        if (!vm.session.objectives.noMoreWaves) vm.dispatch(const SendNextWave());
        step(vm);
        autokill(vm);
      }
      expect(vm.gameOver.value!.end, GameEnd.tutorialComplete);
      expect(vm.gameOver.value!.wave, 50);
    });

    test('classic rules: a win cannot be played on', () {
      final c = preset('warmup');
      final vm = SessionGameViewModel(
        GameSession(
          data: data,
          config: GameConfig(
            mapId: 'map1',
            mode: 'challenge',
            difficulty: c.difficulty,
            challenge: c,
            profile: RulesProfile.classic,
          ),
        ),
      );
      while (vm.gameOver.value == null) {
        step(vm);
        autokill(vm);
      }
      expect(vm.gameOver.value!.canContinue, isFalse);
    });

    test('failing Spiffles on time: badges missed, the failed dialog', () {
      final vm = challengeVm(preset('spiffles'));
      vm.dispatch(const SetSpeed(2));
      while (vm.gameOver.value == null && vm.session.clock.nowMs < 1300000) {
        step(vm);
        autokill(vm);
      }
      expect(vm.gameOver.value!.end, GameEnd.challengeFailed);
      expect(
        {for (final b in vm.objectives.value) b.kind: b.state},
        {'time': BadgeState.missed, 'waves': BadgeState.missed},
      );
    });

    test('a kill target announces itself', () {
      final vm = challengeVm(preset('longshine'));
      final s = vm.session
        ..debugCash = 1e9
        // Five kills short; a Blue beside the road makes them in the game.
        ..debugKills = 995;
      vm.dispatch(const BuildTurret('blue', 366, 228));
      step(vm);
      for (var i = 0; i < 60 * 120 && !s.objectives.killTargetHit; i++) {
        if (s.creeps.isEmpty) vm.dispatch(const SendNextWave());
        for (final c in s.creeps) {
          c.hp = c.hp.clamp(0, 1e-3);
        }
        step(vm);
      }
      step(vm);
      expect(vm.messages.value.map((m) => m.text), contains(data.text('flow.killTargetHit')));
      expect(vm.objectives.value.single.state, BadgeState.reached);
      expect(vm.hud.value.nextWaveSeconds, 0);
    });
  });

  group('widgets', () {
    Future<void> pump(WidgetTester tester, Widget child) async {
      tester.view
        ..physicalSize = const Size(900, 420)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: appOverrides(data: data, fakes: false),
          child: MaterialApp(home: Scaffold(body: child)),
        ),
      );
    }

    testWidgets('badges read out their state', (tester) async {
      final vm = FakeGameViewModel(data: data)
        ..objectivesValue = const [
          ObjectiveBadge(kind: 'time', text: '12:34'),
          ObjectiveBadge(kind: 'waves', text: '100/100', state: BadgeState.reached),
          ObjectiveBadge(kind: 'kills', text: '5/1000', state: BadgeState.missed),
        ];
      await pump(tester, ObjectiveBadges(viewModel: vm));
      expect(find.text('12:34'), findsOneWidget);
      expect(find.bySemanticsLabel('Waves 100/100, reached'), findsOneWidget);
      expect(find.bySemanticsLabel('Kills 5/1000, missed'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('a win offers Continue Playing, Watch Replay (not yet), Restart, Main Menu', (
      tester,
    ) async {
      var restarted = 0;
      var menu = 0;
      final vm = FakeGameViewModel(
        data: data,
        gameOver: const GameOverSummary(
          wave: 50,
          kills: 500,
          shots: 900,
          spent: 300,
          score: 150000,
          end: GameEnd.tutorialComplete,
          seconds: 1010,
          canContinue: true,
        ),
      );
      await pump(
        tester,
        GameOverPanel(viewModel: vm, onRestart: () => restarted++, onMenu: () => menu++),
      );
      expect(find.text('Tutorial Complete!'), findsOneWidget);
      expect(find.text('You beat back all 50 waves!'), findsOneWidget);
      final replay = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.textContaining('Watch Replay'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(replay.onPressed, isNull);
      await tester.tap(find.text('Continue Playing'));
      expect(vm.dispatched.single, isA<ContinuePlaying>());
      await tester.tap(find.text('Restart'));
      await tester.tap(find.text('Main Menu'));
      expect([restarted, menu], [1, 1]);
      // A failed challenge or a lost game offers only Restart and Main Menu.
      vm.gameOverValue = const GameOverSummary(
        wave: 3,
        kills: 2,
        shots: 4,
        spent: 30,
        score: 60,
        end: GameEnd.challengeFailed,
      );
      await tester.pump();
      expect(find.text('Continue Playing'), findsNothing);
      expect(find.textContaining('Watch Replay'), findsNothing);
    });

    testWidgets('the challenge-over dialog: passed and failed', (tester) async {
      final vm = FakeGameViewModel(
        data: data,
        gameOver: const GameOverSummary(
          wave: 3,
          kills: 20,
          shots: 40,
          spent: 30,
          score: 600,
          end: GameEnd.challengePassed,
          seconds: 61,
        ),
      );
      await pump(tester, GameOverPanel(viewModel: vm, onRestart: () {}, onMenu: () {}));
      expect(find.text('Challenge Passed!'), findsOneWidget);
      expect(find.text('Well done, you passed the challenge!'), findsOneWidget);
      expect(find.text('01:01'), findsOneWidget);
      expect(find.text('Shots'), findsNothing);
      vm.gameOverValue = const GameOverSummary(
        wave: 3,
        kills: 20,
        shots: 40,
        spent: 30,
        score: 600,
        end: GameEnd.challengeFailed,
      );
      await tester.pump();
      expect(find.text('Challenge Failed.'), findsOneWidget);
    });

    testWidgets('tutorial: pages, Show me, the arrow and Close', (tester) async {
      final shown = <int>[];
      var closed = false;
      final target = GlobalKey();
      await pump(
        tester,
        Stack(
          children: [
            Positioned(right: 40, top: 40, child: SizedBox(key: target, width: 40, height: 40)),
            Positioned.fill(
              child: TutorialPanel(
                pages: data.tutorial.pages,
                resolve: (p) {
                  final box = target.currentContext!.findRenderObject()! as RenderBox;
                  return p == 'GamePause' ? box.localToGlobal(Offset.zero) & box.size : null;
                },
                onShow: shown.add,
                onClose: () => closed = true,
              ),
            ),
          ],
        ),
      );
      await tester.pump();
      // Page 1 shows its arrow at once (show_now).
      expect(find.text('Welcome to Onslaught'), findsOneWidget);
      expect(find.text('Tutorial 1/36'), findsOneWidget);
      expect(shown, [0]);
      expect(find.byTooltip('Previous page'), findsOneWidget);
      await tester.tap(find.byTooltip('Next page'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Ending the Tutorial'), findsOneWidget);
      // On to "Pause and Unpause", whose arrow waits for Show me.
      await tester.tap(find.byTooltip('Next page'));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byTooltip('Next page'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Pause and Unpause'), findsOneWidget);
      expect(shown, [0, 1, 2]);
      await tester.tap(find.text('Show me'));
      await tester.pump();
      expect(shown, [0, 1, 2, 3]);
      final arrow = find.descendant(
        of: find.byType(IgnorePointer),
        matching: find.byType(CustomPaint),
      );
      expect(arrow, findsWidgets);
      // 7 toggles of 400 ms, then gone.
      await tester.pump(const Duration(milliseconds: 3300));
      await tester.tap(find.byTooltip('Close the tutorial'));
      expect(closed, isTrue);
    });

    testWidgets('tutorial: the last page has no Next, pages without a target no Show me', (
      tester,
    ) async {
      await pump(
        tester,
        TutorialPanel(
          pages: [data.tutorial.pages[7], data.tutorial.pages.last],
          resolve: (_) => null,
          onShow: (_) {},
          onClose: () {},
        ),
      );
      await tester.pump();
      expect(find.text('Buying a Turret'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
      await tester.tap(find.byTooltip('Next page'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Thanks!'), findsOneWidget);
      expect(
        tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_right)).onPressed,
        isNull,
      );
    });
  });
}
