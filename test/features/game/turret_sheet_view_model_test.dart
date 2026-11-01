import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/features/game/game_view_model.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../support/test_data.dart';

/// Phase 2 "done when": every stat in the selected-turret sheet matches the
/// reference formulas (`docs/ONSLAUGHT2_GAME_REFERENCE.md` §4–§6).
void main() {
  late GameData data;
  setUpAll(() => data = loadTestGameData());

  /// Lyne (map9): road (0, 0) → (590, 410); these spots are clear of it.
  const spot = Vec2(300, 150);

  SessionGameViewModel vmFor({
    RulesProfile profile = RulesProfile.classicFixed,
    bool unlockAll = true,
    String locale = 'en',
  }) {
    final s = GameSession(
      data: data,
      config: GameConfig(mapId: 'map9', seed: 3, profile: profile),
    )..debugCash = 1e7;
    if (unlockAll) {
      for (final id in data.turrets.keys) {
        s.debugMakeAvailable(id);
      }
    }
    return SessionGameViewModel(s, locale: locale);
  }

  void step(SessionGameViewModel vm, [int n = 1]) {
    for (var i = 0; i < n; i++) {
      vm.advance(1 / data.rules.tickHz);
    }
  }

  Turret build(SessionGameViewModel vm, String id, Vec2 at) {
    vm.dispatch(BuildTurret(id, at.x, at.y));
    step(vm);
    return vm.session.turrets.last;
  }

  void upgrade(SessionGameViewModel vm, Turret t, StatKind stat, int n) {
    for (var i = 0; i < n; i++) {
      vm.dispatch(UpgradeTurret(t.uid, stat.name));
    }
    step(vm);
  }

  double formula(double base, StatTerms t, StatKind k) =>
      math.max(0, (base + t.added(k)) * math.max(t.mult(k), data.rules.modifierMultFloor));

  for (final colour in ['blue', 'green', 'red', 'yellow']) {
    test('$colour: sheet values are (base + added) × max(mult, 0.2), next values too', () {
      final vm = vmFor();
      final t = build(vm, colour, spot);
      upgrade(vm, t, StatKind.damage, 2);
      upgrade(vm, t, StatKind.range, 1);
      // An exchanger (dmg ×−0.4, range ×−0.1, rate ×+0.6) and a range +100.
      build(vm, 'rate-up-exchange', const Vec2(360, 150));
      build(vm, 'range-up', const Vec2(300, 90));
      vm.select(t.uid);
      final panel = vm.selection.value!;
      final terms = t.terms;
      expect(terms.multDamage, closeTo(-0.4, 1e-12));
      expect(terms.addRange, 100);
      for (final row in panel.stats) {
        final track = t.def.upgrades.track(row.stat);
        final base = statAtLevel(t.def.stats.stat(row.stat), track, row.level);
        expect(row.baseValue, base, reason: '${row.stat}');
        expect(row.value, closeTo(formula(base, terms, row.stat), 1e-9), reason: '${row.stat}');
        expect(row.modified, row.value != base);
        if (!row.maxed) {
          expect(row.nextCost, track[row.level].cost);
          expect(
            row.nextValue,
            closeTo(formula(track[row.level].value, terms, row.stat), 1e-9),
            reason: '${row.stat} next',
          );
        }
      }
      expect(panel.refund, sellRefund(t.cashValue, data.rules.sellRefund));
      vm.dispose();
    });
  }

  test('freakout card: countdown and buy-now cost floor(s) × 250 (classicFixed)', () {
    final vm = vmFor();
    final t = build(vm, 'blue', spot);
    vm.select(t.uid);
    var card = vm.selection.value!.cards.whereType<FreakoutCard>().single;
    expect(card.available, isFalse);
    expect(card.buyCost, isNull);
    upgrade(vm, t, StatKind.damage, 4);
    upgrade(vm, t, StatKind.rate, 4);
    step(vm, 60 * 10);
    card = vm.selection.value!.cards.whereType<FreakoutCard>().single;
    final next = FreakoutSpecial.msUntilNext(vm.session, t)!;
    expect(card.available, isTrue);
    expect(card.stage, 'idle');
    expect(card.nextSeconds, (next / 1000).floor());
    expect(card.buyCost, (next / 1000).floor() * 250);
    expect(card.affordable, isTrue);
    vm.dispatch(BuyFreakout(t.uid));
    step(vm);
    expect(vm.selection.value!.cards.whereType<FreakoutCard>().single.stage, 'warning');
    vm.dispose();
  });

  test('freakout card under classic rules: available but never scheduled, not buyable', () {
    final vm = vmFor(profile: RulesProfile.classic);
    final t = build(vm, 'yellow', spot);
    upgrade(vm, t, StatKind.damage, 4);
    upgrade(vm, t, StatKind.rate, 4);
    vm.select(t.uid);
    final card = vm.selection.value!.cards.whereType<FreakoutCard>().single;
    expect(card.available, isTrue);
    expect(card.nextSeconds, isNull);
    expect(card.buyCost, isNull);
    vm.dispose();
  });

  test('charge card: charge, max 100 + 10 × dmg lvl, rate 10 + 2 × rate lvl, shot poison', () {
    final vm = vmFor();
    final t = build(vm, 'yellow', spot);
    upgrade(vm, t, StatKind.damage, 3);
    upgrade(vm, t, StatKind.rate, 2);
    step(vm, 60 * 3);
    vm.select(t.uid);
    final card = vm.selection.value!.cards.whereType<ChargeCard>().single;
    final charge = t.stateOrNull<ChargeState>(ChargeSpecial.specialId)!.charge;
    expect(card.charge, charge);
    expect(card.max, 130);
    expect(card.ratePerSecond, 14);
    // Base poison at damage 3/7: 10 × floor(42.86) / 100 = 4.2; + 3 × charge/100.
    expect(t.poison, closeTo(4.2, 1e-9));
    expect(card.shotPoison, closeTo(4.2 + 3 * charge / 100, 1e-9));
    vm.dispose();
  });

  test('holding card: locked until range 3 / rate 3, then held of 4', () {
    final vm = vmFor();
    final t = build(vm, 'red', const Vec2(550, 330));
    vm.select(t.uid);
    var card = vm.selection.value!.cards.whereType<HoldingCard>().single;
    expect((card.unlocked, card.levelRange, card.levelRate, card.max), (false, 3, 3, 4));
    upgrade(vm, t, StatKind.range, 3);
    upgrade(vm, t, StatKind.rate, 3);
    step(vm, 60 * 4);
    card = vm.selection.value!.cards.whereType<HoldingCard>().single;
    expect(card.unlocked, isTrue);
    expect(card.held, 4);
    vm.dispose();
  });

  test('link card counts link turrets within its own effective range', () {
    final vm = vmFor();
    final a = build(vm, 'green', const Vec2(205, 82));
    build(vm, 'green', const Vec2(254.3, 116.2));
    build(vm, 'green', const Vec2(303.6, 150.4));
    vm.select(a.uid);
    final card = vm.selection.value!.cards.whereType<LinkCard>().single;
    expect(card.links, 1);
    expect(card.mult, 1.25);
    vm.dispose();
  });

  test('aura card and ring: radius 80 (130 after its upgrade), covered turrets', () {
    final vm = vmFor();
    build(vm, 'blue', spot);
    build(vm, 'green', const Vec2(300, 90));
    final m = build(vm, 'damage-up-big-exchange', const Vec2(360, 150));
    vm.select(m.uid);
    var panel = vm.selection.value!;
    expect(panel.targetMode, isNull);
    expect(panel.auraRadius, 80);
    var card = panel.cards.whereType<AuraCard>().single;
    expect(card.covered, 1, reason: '(300, 90) is 84.9 px away');
    expect(card.terms, auraTerms(data.turrets['damage-up-big-exchange']!.modifierAura!));
    upgrade(vm, m, StatKind.range, 1);
    panel = vm.selection.value!;
    card = panel.cards.whereType<AuraCard>().single;
    expect(panel.auraRadius, 130);
    expect(card.covered, 2);
    vm.dispose();
  });

  test('the placement ghost shows the range the turret would have at that spot', () {
    final vm = vmFor();
    build(vm, 'range-up', const Vec2(360, 150));
    vm.previewPlacement('blue', spot);
    expect(vm.placement.value!.range, 230);
    vm.previewPlacement('blue', const Vec2(150, 40));
    expect(vm.placement.value!.range, 130);
    vm.previewPlacement('blue', null);
    expect(vm.placement.value!.range, 130);
    vm.dispose();
  });

  test('messages: the welcome lines, then one per unlocked weapon', () {
    final vm = vmFor(profile: RulesProfile.classic, unlockAll: false);
    expect(vm.messages.value.map((m) => m.text), [
      'Welcome to Onslaught 3 Remastered!',
      'The attackers are on their way, you may want to build some defences!',
    ]);
    expect(vm.messages.value.every((m) => !m.alert), isTrue);
    // The 300th kill unlocks the Range Enhancer.
    vm.session.debugKills = 299;
    build(vm, 'blue', spot);
    vm.dispatch(const SendNextWave());
    for (var i = 0; i < 60 * 20 && vm.messages.value.length < 3; i++) {
      step(vm);
    }
    final unlock = vm.messages.value.last;
    expect(unlock.text, 'New weapon available: Range Enhancer');
    expect(unlock.alert, isTrue);
    expect(vm.tray.value.firstWhere((t) => t.id == 'range-up').locked, isFalse);
    vm.dispose();
  });

  test('messages and names are in the interface language', () {
    final vm = vmFor(profile: RulesProfile.classic, unlockAll: false, locale: 'de');
    expect(vm.messages.value.map((m) => m.text), [
      data.text('message.welcome', locale: 'de'),
      data.text('message.attackersComing', locale: 'de'),
    ]);
    expect(vm.tray.value.first.name, 'Blaue Kanone');
    vm.session.debugKills = 299;
    build(vm, 'blue', spot);
    vm.dispatch(const SendNextWave());
    for (var i = 0; i < 60 * 20 && vm.messages.value.length < 3; i++) {
      step(vm);
    }
    expect(vm.messages.value.last.text, 'Neue Waffe verfügbar: Reichweitenverstärker');
    // Switching language renames what the HUD shows next.
    vm.locale = 'en';
    expect(vm.tray.value.first.name, 'Blue Cannon');
    vm.dispose();
  });
}
