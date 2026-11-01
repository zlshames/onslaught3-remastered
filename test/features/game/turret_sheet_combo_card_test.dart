import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/features/game/game_view_model.dart';
import 'package:onslaught3_remastered/features/game/hud/turret_sheet.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../support/fake_game_view_model.dart';
import '../../support/test_data.dart';

/// Phase 3 HUD: the combo card on the selected-turret sheet.
void main() {
  late GameData data;
  setUpAll(() => data = loadTestGameData());

  Future<void> pumpCard(WidgetTester tester, String turretId, ComboCard card) async {
    tester.view
      ..physicalSize = const Size(1280, 720)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final vm = FakeGameViewModel(
      data: data,
      selection: turretPanel(data, turretId, cards: [card]),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: TurretSheet(viewModel: vm),
          ),
        ),
      ),
    );
  }

  testWidgets('locked: buy the damage track first', (tester) async {
    await pumpCard(
      tester,
      'blue',
      const ComboCard(
        capable: false,
        damageLevelsToGo: 3,
        nextSeconds: null,
        partners: {},
        recipe: null,
        led: 0,
        assisted: 0,
      ),
    );
    expect(find.text('Combo'), findsOneWidget);
    expect(find.text('Max damage first'), findsOneWidget);
    expect(find.text('3 to go'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Combos unlock after 3 more')), findsOneWidget);
  });

  testWidgets('ready: the recipe its partners make, partner counts', (tester) async {
    await pumpCard(
      tester,
      'blue',
      const ComboCard(
        capable: true,
        damageLevelsToGo: 0,
        nextSeconds: null,
        partners: {'red': 2, 'blue': 1},
        recipe: 'Bit Cluster Landmine',
        led: 0,
        assisted: 0,
      ),
    );
    expect(find.text('Combo ready'), findsOneWidget);
    expect(find.text('Bit Cluster Landmine (R2 B1)'), findsOneWidget);
  });

  testWidgets('recharging: countdown and the combo counts', (tester) async {
    await pumpCard(
      tester,
      'red',
      const ComboCard(
        capable: true,
        damageLevelsToGo: 0,
        nextSeconds: 6,
        partners: {'blue': 2},
        recipe: 'Nuke',
        led: 3,
        assisted: 1,
      ),
    );
    expect(find.text('Combo in 6s'), findsOneWidget);
    expect(find.text('Led 3, helped 1'), findsOneWidget);
  });

  testWidgets('capable with nobody in range', (tester) async {
    await pumpCard(
      tester,
      'green',
      const ComboCard(
        capable: true,
        damageLevelsToGo: 0,
        nextSeconds: null,
        partners: {},
        recipe: null,
        led: 0,
        assisted: 0,
      ),
    );
    expect(find.text('No partners'), findsOneWidget);
  });
}
