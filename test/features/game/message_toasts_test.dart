import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/features/game/game_view_model.dart';
import 'package:onslaught3_remastered/features/game/hud/message_toasts.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../support/fake_game_view_model.dart';
import '../../support/test_data.dart';

/// Message toasts: one at a time, each for its duration, dismissed by a tap.
void main() {
  late GameData data;
  setUpAll(() => data = loadTestGameData());

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view
      ..physicalSize = const Size(1280, 720)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  }

  group('message toasts', () {
    testWidgets('each new message shows for its duration, one at a time', (tester) async {
      final vm = FakeGameViewModel(data: data);
      await pump(tester, MessageToasts(viewModel: vm, duration: const Duration(seconds: 2)));
      expect(find.byType(Text), findsNothing);
      vm.messagesValue = const [
        GameMessage(seq: 0, text: 'one', alert: false),
        GameMessage(seq: 1, text: 'two'),
      ];
      await tester.pump();
      expect(find.text('one'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('one'), findsNothing);
      expect(find.text('two'), findsOneWidget);
      await tester.tap(find.text('two'));
      await tester.pumpAndSettle();
      expect(find.text('two'), findsNothing);
    });
  });
}
