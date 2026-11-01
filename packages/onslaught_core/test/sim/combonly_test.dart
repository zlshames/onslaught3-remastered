import 'dart:math' as math;

import 'package:onslaught_core/onslaught_core.dart';
import 'package:onslaught_core/testing.dart';
import 'package:test/test.dart';

import '../support/combo_bench.dart';
import '../support/repo_data.dart';
import '../support/sim_helpers.dart';

/// The Combonly plate (`turrets/TurretCombonly.as`, `CombonlyPlate.as`;
/// `docs/legacy/ENGINE_NOTES.md` §4.8).
void main() {
  late GameData data;
  late SimTestHarness harness;
  setUpAll(() {
    data = loadClassicData();
    harness = SimTestHarness(data);
  });

  GameSession lyne() {
    final s = harness.session(const GameConfig(mapId: 'map9', mode: 'sandbox2', seed: 4))
      ..debugCash = 1e12;
    unlockAll(s);
    return s;
  }

  /// 132 px from Lyne's road; its ring of five spots lies within the 70 px
  /// scan and at least 36 px apart.
  const plateAt = Vec2(200, 300);
  final ring = [
    for (var i = 0; i < 5; i++)
      plateAt + Vec2(math.cos(i * 2 * math.pi / 5), math.sin(i * 2 * math.pi / 5)) * 55,
  ];

  /// Builds a plate and, around it, damage-maxed colour turrets as [counts].
  (Turret, List<Turret>) layout(GameSession s, Map<String, int> counts) {
    final plate = build(s, 'combonly', plateAt);
    final turrets = <Turret>[];
    for (final e in counts.entries) {
      for (var i = 0; i < e.value; i++) {
        turrets.add(maxed(s, e.key, ring[turrets.length]));
      }
    }
    return (plate, turrets);
  }

  Map<String, String> optionsOf(Turret plate) => {
    for (final o in CombonlySpecial.stateOf(plate).options) o.colour: o.recipe,
  };

  Creep onlyCreep(GameSession s) {
    final c = firstCreep(s)..hp = 1e12;
    s.waves.spawners.clear();
    return c;
  }

  test('the scan table has the 20 options of the original, one per recipe', () {
    expect(data.combonly, hasLength(20));
    expect(data.combonly.map((o) => o.recipe).toSet(), data.combos.keys.toSet());
    for (final o in data.combonly) {
      expect(data.combos[o.recipe]!.leader, o.colour, reason: o.recipe);
    }
  });

  group('each option is offered when exactly its turrets stand around the plate', () {
    for (final o in loadClassicData().combonly) {
      test('${o.colour}: ${o.recipe} ${o.needs.counts}', () {
        final s = lyne();
        final (plate, _) = layout(s, o.needs.counts);
        s.run(61);
        expect(optionsOf(plate)[o.colour], o.recipe);
        expect(CombonlySpecial.stateOf(plate).mode, CombonlyMode.cycle);
      });
    }
  });

  test('per colour the last matching rule wins; colours cycle newest-first', () {
    final s = lyne();
    final (plate, _) = layout(s, {'blue': 2, 'red': 1});
    s.run(61);
    final st = CombonlySpecial.stateOf(plate);
    expect([for (final o in st.options) o.recipe], ['nuke', 'big-landmine']);
  });

  test('turrets that are not combo-capable, or beyond 70 px, do not count', () {
    final s = lyne();
    final plate = build(s, 'combonly', plateAt);
    build(s, 'blue', ring[0]);
    maxed(s, 'blue', ring[1]);
    maxed(s, 'blue', plateAt + const Vec2(0, -75));
    s.run(61);
    final st = CombonlySpecial.stateOf(plate);
    expect(st.options, isEmpty);
    expect(st.mode, CombonlyMode.choose);
  });

  test('it shows one colour per second, the second option first, paused or not', () {
    final s = lyne();
    final (plate, _) = layout(s, {'blue': 2, 'red': 1});
    final st = CombonlySpecial.stateOf(plate);
    final shown = <String?>[];
    var last = st.index;
    for (var i = 0; i < 60 * 4 + 5; i++) {
      if (i == 150) s.enqueue(const SetPaused(true));
      s.step();
      if (st.glow && (st.index != last || shown.isEmpty)) shown.add(st.shown);
      last = st.index;
    }
    expect(s.clock.paused, isTrue);
    expect(shown.take(4), ['blue', 'red', 'blue', 'red']);
  });

  test('building nearby sends it back to choose and rescans', () {
    final s = lyne();
    final (plate, _) = layout(s, {'blue': 2});
    s.run(130);
    final st = CombonlySpecial.stateOf(plate);
    expect(st.glow, isTrue);
    final red = build(s, 'red', ring[2]);
    expect(st.glow, isFalse);
    expect(st.mode, CombonlyMode.cycle);
    expect(optionsOf(plate), {'blue': 'landmine'});
    // An upgrade does not notify it; its next cycle rescans.
    upgrade(s, red, StatKind.damage, red.def.upgrades.damage.length);
    s.run(61);
    expect(optionsOf(plate), {'red': 'nuke', 'blue': 'big-landmine'});
  });

  test('a click with nothing showing does nothing', () {
    final s = lyne();
    final plate = build(s, 'combonly', plateAt);
    s.enqueue(ChooseCombonly(plate.uid));
    expect(s.step().whereType<CommandRejected>().single.reason, 'nothingShown');
  });

  test('a click on a colour that is no longer an option is refused', () {
    final s = lyne();
    final (plate, turrets) = layout(s, {'blue': 2, 'red': 1});
    final st = CombonlySpecial.stateOf(plate);
    while (st.shown != 'red') {
      s.step();
    }
    s.enqueue(SellTurret(turrets.first.uid));
    s.step();
    expect(st.shown, 'red', reason: 'kept, unseen');
    s.enqueue(ChooseCombonly(plate.uid));
    expect(s.step().whereType<CommandRejected>().single.reason, 'unavailable');
    expect(st.chosen, isNull);
  });

  test('choosing consumes its turrets into its value, then it arms and fires silently', () {
    final s = lyne();
    final (plate, turrets) = layout(s, {'blue': 2, 'red': 1});
    final st = CombonlySpecial.stateOf(plate);
    while (st.shown != 'red') {
      s.step();
    }
    final cash = s.cash;
    final spent = s.totalSpent;
    final value = plate.cashValue + turrets.fold<double>(0, (a, t) => a + t.cashValue);
    s.enqueue(ChooseCombonly(plate.uid));
    final chosen = s.step().whereType<CombonlyChanged>().single;
    expect(chosen.stage, 'chosen');
    expect(chosen.recipe, 'nuke');
    expect(chosen.consumed.toSet(), {for (final t in turrets) t.uid});
    expect(plate.cashValue, value);
    expect(chosen.cashValue, value);
    expect(turrets.every((t) => !t.active), isTrue);
    expect(plate.active, isFalse, reason: 'taking on its weapon');
    s.enqueue(SellTurret(turrets.first.uid));
    expect(s.step().whereType<CommandRejected>().single.reason, 'inactive');

    final events = <GameEvent>[];
    for (var i = 0; i < 125; i++) {
      events.addAll(s.step());
    }
    final armed = events.whereType<CombonlyChanged>().single;
    expect(armed.stage, 'armed');
    expect(armed.tick - chosen.tick, inInclusiveRange(89, 91), reason: '1.5 s');
    final consumed = events.whereType<TurretConsumed>().toList();
    expect(consumed.map((e) => e.uid).toSet(), chosen.consumed.toSet());
    expect(consumed.first.tick - chosen.tick, inInclusiveRange(119, 121), reason: '2 s');
    expect(s.turrets, [plate]);
    expect(s.cash, cash, reason: 'no refund');
    expect(s.totalSpent, spent);
    expect(plate.active, isTrue);

    final creep = onlyCreep(s);
    final fired = stepUntil<ComboFired>(s, test: (e) => e.uid == plate.uid);
    expect(fired!.combo, 'nuke');
    expect(fired.helpers, isEmpty, reason: 'combo_silent');
    final rocket = s.projectiles.singleWhere((p) => p.specId == 'rocket-nuke');
    final red = data.turrets['red']!;
    final from = plate.position + rotateVec(red.firePoints.first, plate.rotation);
    expect(rocket.position.distanceTo(from), lessThan(1e-9), reason: "the red weapon's fire point");
    expect(rocket.targetUid, creep.uid);
    final next = stepUntil<ComboFired>(s, test: (e) => e.uid == plate.uid);
    expect((next!.tick - fired.tick) / 60 * 1000, greaterThanOrEqualTo(7400), reason: 'recharge');

    s.enqueue(SellTurret(plate.uid));
    final sold = s.step().whereType<TurretSold>().single;
    expect(sold.refund, (value * 0.7).ceil());
  });

  test('as a BFG it pools its own link turrets; with none its pooled shot is empty', () {
    final s = lyne();
    final (plate, _) = layout(s, {'red': 1, 'green': 1, 'blue': 1});
    final st = CombonlySpecial.stateOf(plate);
    while (st.shown != 'green') {
      s.step();
    }
    s.enqueue(ChooseCombonly(plate.uid));
    s.run(130);
    onlyCreep(s);
    final fired = stepUntil<ComboFired>(s, test: (e) => e.uid == plate.uid);
    expect(fired!.combo, 'bfg');
    expect(plate.shots, 1, reason: '`linkFire(self, 0)` with no link turret: an empty shot');
  });

  test('a sandbox2 game opens every turret; a normal one only the colours', () {
    final s2 = harness.session(const GameConfig(mapId: 'map9', mode: 'sandbox2'));
    final normal = harness.session(const GameConfig(mapId: 'map9'));
    for (final def in data.turrets.values) {
      expect(s2.isAvailable(def), isTrue, reason: def.id);
      expect(normal.isAvailable(def), def.availableInitially, reason: def.id);
    }
    final s1 = harness.session(const GameConfig(mapId: 'map9', mode: 'sandbox'));
    expect(s1.isAvailable(data.turrets['targeter']!), isTrue);
    expect(s1.isAvailable(data.turrets['sniper']!), isFalse);
    expect(s2.cash, 1000000);
  });
}
