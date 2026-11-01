import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/features/game/game_view_model.dart';
import 'package:onslaught3_remastered/features/game/hud/stats_bar.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../support/fake_game_view_model.dart';
import '../../support/test_data.dart';

void main() {
  late GameData data;
  setUpAll(() => data = loadTestGameData());

  Future<FakeGameViewModel> pump(WidgetTester tester, {VoidCallback? onExit}) async {
    final vm = FakeGameViewModel(data: data);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatsBar(viewModel: vm, onExit: onExit ?? () {}),
        ),
      ),
    );
    return vm;
  }

  testWidgets('shows lives, cash, wave and map name from the view model', (tester) async {
    final vm = await pump(tester);
    expect(find.text('10'), findsOneWidget);
    expect(find.text(r'$30'), findsOneWidget);
    expect(find.text('Wave 0'), findsOneWidget);
    expect(find.text('Classic'), findsOneWidget);

    vm.hudValue = const HudState(cash: 1234, lives: 7, kills: 3, wave: 5, paused: true, speed: 1);
    await tester.pump();
    expect(find.text(r'$1234'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('Wave 5'), findsOneWidget);
    expect(find.byTooltip('Resume'), findsOneWidget);
  });

  testWidgets('pause button dispatches SetPaused', (tester) async {
    final vm = await pump(tester);
    await tester.tap(find.byTooltip('Pause'));
    expect(vm.dispatched.single, isA<SetPaused>().having((c) => c.paused, 'paused', isTrue));
  });

  testWidgets('back button calls onExit', (tester) async {
    var exited = false;
    await pump(tester, onExit: () => exited = true);
    await tester.tap(find.byTooltip('Back to menu'));
    expect(exited, isTrue);
  });

  testWidgets('controls carry semantics labels and 44 pt targets', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);
    expect(find.bySemanticsLabel('Lives 10'), findsOneWidget);
    expect(find.bySemanticsLabel(r'Cash 30'), findsOneWidget);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('the wave clock sends the next wave; refused while paused', (tester) async {
    final vm = await pump(tester);
    await tester.tap(find.byTooltip('Send next wave'));
    expect(vm.dispatched.single, isA<SendNextWave>());
    vm.hudValue = const HudState(cash: 30, lives: 10, kills: 0, wave: 0, paused: true, speed: 1);
    await tester.pump();
    await tester.tap(find.byTooltip('Send next wave'));
    expect(vm.dispatched, hasLength(1));
  });

  testWidgets('speed button cycles up to the data maximum, then back to 1x', (tester) async {
    final vm = await pump(tester);
    await tester.tap(find.byTooltip('Game speed'));
    expect((vm.dispatched.single as SetSpeed).speed, 2);
    vm.hudValue = const HudState(cash: 30, lives: 10, kills: 0, wave: 0, paused: false, speed: 2);
    await tester.pump();
    await tester.tap(find.byTooltip('Game speed'));
    expect((vm.dispatched.last as SetSpeed).speed, 1);
  });

  testWidgets('the classic profile has no speed button (settings only)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatsBar(
            viewModel: FakeGameViewModel(data: data, profile: RulesProfile.classic),
            onExit: () {},
          ),
        ),
      ),
    );
    expect(find.byTooltip('Game speed'), findsNothing);
  });
}
