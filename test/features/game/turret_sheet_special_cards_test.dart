import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/features/game/game_view_model.dart';
import 'package:onslaught3_remastered/features/game/hud/turret_sheet.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../support/fake_game_view_model.dart';
import '../../support/test_data.dart';

/// The selected-turret sheet's special cards (freakout, charge, holding,
/// link, aura) and aura-raised stats.
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

  FakeGameViewModel sheetVm(TurretPanel panel, {double cash = 30}) => FakeGameViewModel(
    data: data,
    selection: panel,
    hud: HudState(cash: cash, lives: 10, kills: 0, wave: 1, paused: false, speed: 1),
  );

  Widget sheet(FakeGameViewModel vm) => Align(
    alignment: Alignment.bottomCenter,
    child: TurretSheet(viewModel: vm),
  );

  group('turret sheet special cards', () {
    testWidgets('freakout: countdown and a buy-now button that sends BuyFreakout', (tester) async {
      const card = FreakoutCard(
        available: true,
        stage: 'idle',
        nextSeconds: 34,
        buyCost: 8500,
        affordable: true,
      );
      final vm = sheetVm(
        turretPanel(data, 'blue', damage: 4, rate: 4, cash: 1e5, cards: const [card]),
        cash: 1e5,
      );
      await pump(tester, sheet(vm));
      expect(find.text('Next in 34s'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Freak out now for 8500'));
      expect(vm.dispatched.single, isA<BuyFreakout>());
      expect((vm.dispatched.single as BuyFreakout).uid, 1);
    });

    testWidgets('freakout: no button while warming up, when unaffordable or paused', (
      tester,
    ) async {
      for (final (card, locked) in [
        (
          const FreakoutCard(
            available: true,
            stage: 'warning',
            nextSeconds: 70,
            buyCost: 17500,
            affordable: true,
          ),
          false,
        ),
        (
          const FreakoutCard(
            available: true,
            stage: 'idle',
            nextSeconds: 70,
            buyCost: 17500,
            affordable: false,
          ),
          false,
        ),
        (
          const FreakoutCard(
            available: true,
            stage: 'idle',
            nextSeconds: 70,
            buyCost: 17500,
            affordable: true,
          ),
          true,
        ),
      ]) {
        final vm = sheetVm(turretPanel(data, 'blue', locked: locked, cards: [card]));
        await pump(tester, sheet(vm));
        final buy = find.bySemanticsLabel('Freak out now for 17500');
        if (buy.evaluate().isNotEmpty) await tester.tap(buy, warnIfMissed: false);
        expect(vm.dispatched, isEmpty, reason: '${card.stage} locked=$locked');
      }
    });

    testWidgets('freakout under classic rules: available but not scheduled', (tester) async {
      const card = FreakoutCard(
        available: true,
        stage: 'idle',
        nextSeconds: null,
        buyCost: null,
        affordable: false,
      );
      await pump(tester, sheet(sheetVm(turretPanel(data, 'yellow', cards: const [card]))));
      expect(find.text('Not scheduled'), findsOneWidget);
    });

    testWidgets('charge, holding, link and aura cards', (tester) async {
      await pump(
        tester,
        sheet(
          sheetVm(
            turretPanel(
              data,
              'yellow',
              cards: const [ChargeCard(charge: 56.7, max: 130, ratePerSecond: 14, shotPoison: 5.9)],
            ),
          ),
        ),
      );
      expect(find.text('56 / 130'), findsOneWidget);
      expect(find.text('Slow 5.9'), findsOneWidget);

      await pump(
        tester,
        sheet(
          sheetVm(
            turretPanel(
              data,
              'red',
              cards: const [
                HoldingCard(unlocked: false, held: 0, max: 4, levelRange: 3, levelRate: 3),
              ],
            ),
          ),
        ),
      );
      expect(find.text('Range 3, rate 3'), findsOneWidget);

      await pump(
        tester,
        sheet(
          sheetVm(
            turretPanel(
              data,
              'green',
              cards: const [LinkCard(links: 2, lastDamage: 95.3, mult: 1.25)],
            ),
          ),
        ),
      );
      expect(find.text('2 linked'), findsOneWidget);
      expect(find.text('Last 95'), findsOneWidget);

      final aura = auraTerms(data.turrets['damage-up-big-exchange']!.modifierAura!);
      await pump(
        tester,
        sheet(
          sheetVm(
            turretPanel(
              data,
              'damage-up-big-exchange',
              cards: [AuraCard(terms: aura, radius: 80, covered: 3)],
            ),
          ),
        ),
      );
      expect(find.text('Aura 80 px'), findsOneWidget);
      expect(find.text('dmg ×2, range ×0.7, rate ×0.7'), findsOneWidget);
      expect(find.text('3 in range'), findsOneWidget);
      // Modifiers have no weapon: no target chip, no lock.
      expect(find.text('Lock on'), findsNothing);
      expect(find.byIcon(Icons.gps_fixed), findsNothing);
    });

    testWidgets('stats raised by auras are highlighted', (tester) async {
      await pump(
        tester,
        sheet(sheetVm(turretPanel(data, 'blue', terms: const StatTerms(addRange: 100)))),
      );
      final preview = tester.widget<Text>(find.text('230 → 240'));
      expect(preview.style?.color, Colors.cyanAccent);
      expect(tester.widget<Text>(find.text('15 → 30')).style?.color, Colors.white70);
    });
  });
}
