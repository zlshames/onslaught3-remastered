import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/features/game/game_view_model.dart';
import 'package:onslaught3_remastered/features/game/turret_panel_builder.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../support/test_data.dart';

/// `buildTurretPanel`: the selected-turret sheet as a pure function of the
/// session, the selected uid, the locale and the joiner.
void main() {
  late GameData data;
  setUpAll(() => data = loadTestGameData());

  /// Lyne (map9) with every turret available and plenty of cash.
  GameSession lyne() {
    final s = GameSession(
      data: data,
      config: const GameConfig(mapId: 'map9', seed: 3),
    )..debugCash = 1e7;
    for (final id in data.turrets.keys) {
      s.debugMakeAvailable(id);
    }
    return s;
  }

  Turret build(GameSession s, String id, Vec2 at) {
    s.enqueue(BuildTurret(id, at.x, at.y));
    s.step();
    return s.turrets.last;
  }

  test('null without a selection or for an unknown uid', () {
    final s = lyne();
    expect(buildTurretPanel(s, null, locale: 'en'), isNull);
    expect(buildTurretPanel(s, 999, locale: 'en'), isNull);
  });

  test('describes the turret and changes nothing in the session', () {
    final s = lyne();
    final blue = build(s, 'blue', const Vec2(300, 150));
    final before = s.stateHash();
    final p = buildTurretPanel(s, blue.uid, locale: 'en')!;
    expect(s.stateHash(), before);
    expect((p.uid, p.turretId, p.typeName), (blue.uid, 'blue', data.turretName('blue')));
    expect(p.icon, blue.def.art.icon);
    expect(
      [for (final r in p.stats) r.stat],
      [
        for (final k in StatKind.values)
          if (blue.def.upgrades.track(k).isNotEmpty) k,
      ],
    );
    final damage = p.stats.firstWhere((r) => r.stat == StatKind.damage);
    expect(damage.nextCost, blue.def.upgrades.damage.first.cost);
    expect(damage.affordable, isTrue);
    expect(p.refund, sellRefund(blue.cashValue, data.rules.sellRefund));
    expect(p.locked, isFalse);
    // Same inputs, same panel.
    expect(buildTurretPanel(s, blue.uid, locale: 'en'), p);
  });

  test('reads special state without creating it: the hash a replay rebuilds is kept', () {
    // The rules create a special's state on the turret's first tick, and
    // the state is hashed; the panel must not create it on selection.
    final s = lyne();
    final red = build(s, 'red', const Vec2(300, 150));
    expect(red.specialState, isEmpty, reason: 'built, not yet ticked');
    final before = s.stateHash();
    final p = buildTurretPanel(s, red.uid, locale: 'en')!;
    expect(red.specialState, isEmpty);
    expect(s.stateHash(), before);
    // Without state the card shows the state's initial values.
    final holding = p.cards.whereType<HoldingCard>().single;
    expect(holding.unlocked, isFalse);
    expect(holding.held, 0);
    final combo = p.cards.whereType<ComboCard>().single;
    expect((combo.led, combo.assisted), (0, 0));
    // Every other special's card too.
    for (final id in ['blue', 'yellow', 'green', 'targeter', 'fusion', 'combonly']) {
      final t = build(s, id, Vec2(300, 150 + 40.0 * s.turrets.length));
      final entries = t.specialState.length;
      final hash = s.stateHash();
      final cards = buildTurretPanel(s, t.uid, locale: 'en')!.cards;
      expect(cards, isNotEmpty, reason: id);
      expect(t.specialState.length, entries, reason: id);
      expect(s.stateHash(), hash, reason: id);
    }
  });

  test('a freakout turret starts with the idle card', () {
    final s = lyne();
    final blue = build(s, 'blue', const Vec2(300, 150));
    final cards = buildTurretPanel(s, blue.uid, locale: 'en')!.cards;
    final freak = cards.whereType<FreakoutCard>().single;
    expect(freak.stage, FreakoutCard.stageIdle);
    expect(FreakoutCard.stageIdle, 'idle');
  });

  test('the joiner flag follows the joining uid', () {
    final s = lyne();
    final t = build(s, 'targeter', const Vec2(300, 150));
    TargeterCard card(int? joining) => buildTurretPanel(
      s,
      t.uid,
      locale: 'en',
      joining: joining,
    )!.cards.whereType<TargeterCard>().single;
    expect(card(null).joining, isFalse);
    expect(card(t.uid).joining, isTrue);
    expect(card(t.uid + 1).joining, isFalse);
  });

  test('matches what the view model shows for its selection', () {
    final s = lyne();
    final vm = SessionGameViewModel(s);
    addTearDown(vm.dispose);
    vm.dispatch(const BuildTurret('red', 300, 150));
    vm.advance(1 / data.rules.tickHz);
    final uid = s.turrets.single.uid;
    vm.select(uid);
    expect(vm.selection.value, buildTurretPanel(s, uid, locale: 'en'));
  });
}
