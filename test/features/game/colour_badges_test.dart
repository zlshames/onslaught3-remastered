import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/features/game/colour_badges.dart';
import 'package:onslaught3_remastered/features/game/effect_settings.dart';
import 'package:onslaught3_remastered/features/game/game_view_model.dart';
import 'package:onslaught3_remastered/features/game/hud/colour_badge_icon.dart';
import 'package:onslaught3_remastered/features/game/hud/tower_tray.dart';
import 'package:onslaught3_remastered/features/game/hud/turret_sheet.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../support/fake_game_view_model.dart';
import '../../support/test_data.dart';

class _NoInput implements PlacementInput {
  @override
  void dragTo(String turretId, Offset globalPosition, {bool touch = false, bool start = false}) {}
  @override
  void dragEnd() {}
}

/// Phase 8 colour-blind-safe badges: each colour turret gets its own shape
/// and letter; the tray and the sheet show them when the setting is on.
void main() {
  late GameData data;
  setUpAll(() => data = loadTestGameData());

  test('the four colours have four shapes and their letters; others none', () {
    final colours = [
      for (final t in data.turrets.values)
        if (t.category == TurretCategory.basic) t.id,
    ];
    expect(colours, ['blue', 'green', 'red', 'yellow']);
    final badges = [for (final id in colours) colourBadgeFor(data, id)!];
    expect({for (final b in badges) b.shape}, hasLength(4));
    expect([for (final b in badges) b.letter], ['B', 'G', 'R', 'Y']);
    for (final id in ['range-up', 'sniper', 'targeter', 'combonly', 'unknown']) {
      expect(colourBadgeFor(data, id), isNull, reason: id);
    }
  });

  test('every badge shape the data may name is drawable, and only those', () {
    expect({for (final s in BadgeShape.values) s.name}, TurretArt.badgeShapes);
    expect(
      [
        for (final id in ['blue', 'green', 'red', 'yellow']) colourBadgeFor(data, id)!.shape,
      ],
      [BadgeShape.circle, BadgeShape.triangle, BadgeShape.square, BadgeShape.diamond],
    );
  });

  test('a missing badge string falls back to the name\'s first letter', () {
    expect(colourLetter(data, 'red', locale: 'xx'), 'R', reason: 'English fallback');
    expect(data.text('badge.red'), 'R');
  });

  testWidgets('tray cells and the sheet carry badges only when switched on', (tester) async {
    final effects = ValueNotifier(EffectSettings.of(data));
    final vm = FakeGameViewModel(
      data: data,
      tray: [
        for (final id in ['blue', 'red', 'range-up'])
          TrayItem(
            id: id,
            name: data.turrets[id]!.name,
            cost: data.turrets[id]!.cost,
            icon: data.turrets[id]!.art.icon,
            affordable: true,
          ),
      ],
      selection: bluePanel(data),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: TurretSheet(viewModel: vm, effects: effects),
                ),
              ),
              TowerTray(viewModel: vm, input: _NoInput(), effects: effects),
            ],
          ),
        ),
      ),
    );
    Iterable<String> shown() =>
        tester.widgetList<ColourBadgeIcon>(find.byType(ColourBadgeIcon)).map((b) => b.turretId);
    expect(shown(), isEmpty);
    effects.value = const EffectSettings(rocketSmoke: true, smokeMax: 100, colourBadges: true);
    await tester.pump(const Duration(milliseconds: 300));
    // Blue in the sheet and the tray, Red in the tray; the modifier's cell
    // has an empty badge.
    expect(shown().toList()..sort(), ['blue', 'blue', 'range-up', 'red']);
    expect(
      find.descendant(of: find.byType(ColourBadgeIcon), matching: find.byType(CustomPaint)),
      findsNWidgets(3),
    );
  });
}
