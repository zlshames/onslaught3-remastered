import 'dart:async';
import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:onslaught3_remastered/app/app.dart';
import 'package:onslaught3_remastered/app/feature_flags.dart';
import 'package:onslaught3_remastered/app/providers.dart';
import 'package:onslaught3_remastered/features/editor/editor_canvas.dart';
import 'package:onslaught3_remastered/features/game/flame/entity_layer.dart';
import 'package:onslaught3_remastered/features/game/flame/onslaught_flame_game.dart';
import 'package:onslaught3_remastered/features/game/flame/ordnance_views.dart';
import 'package:onslaught3_remastered/features/game/flame/super_views.dart';
import 'package:onslaught3_remastered/features/game/game_view_model.dart';
import 'package:onslaught3_remastered/services/data/asset_bundle_data_source.dart';
import 'package:onslaught3_remastered/services/persistence/document_store.dart';
import 'package:onslaught3_remastered/services/persistence/mod_library.dart';
import 'package:onslaught3_remastered/services/persistence/profile.dart';
import 'package:onslaught_core/onslaught_core.dart';

import 'quiet_sinks.dart';

/// Smoke flows on a device, each from the main menu on a fresh in-memory
/// profile (Play → Easy Mode → Classic). Phase 0: Classic → the road renders →
/// two-finger pinch zooms → one-finger drag pans → back to the menu.
/// Phase 1: drag a Blue from the tray onto the map → send the wave → the
/// Blue kills creeps → select it → upgrade → sell.
/// Phase 3: a Red leader with two idle Blues fires a nuke, the sheet shows
/// its combo countdown and the blast is drawn.
/// Phase 4: the Super Sandbox (unlocked profile) on Lyne opens all 16 turrets; a
/// Targeter joins a far Blue through the sheet's Join button and a tap on the map
/// (and the Sniper and Railgun by command, so they fire early); a Combonly
/// plate locks in through its button, consumes its turrets and fires; the
/// Sniper, Railgun and a fed Fusion cannon fire at a wave.
/// Phase 5: the attract demo runs behind the menu; challenges are locked on
/// a new profile; the tutorial starts paused and its "Show me" gives the
/// one-off cash; the Warmup challenge is passed on its time limit, played on
/// in freeplay, and its best game shows on the challenge page.
/// Phase 6: Map Tools → a new map built by dragging the start from the
/// palette and tapping the base and waypoints → pinch-zoom and fit → save →
/// share code → delete → import the code → play it; creeps walk its road.
/// Phase 7: Mods (unlocked profile) → Blue's damage set to 99 (a range of 5
/// is refused) → switched on → exported as a code that carries it → the next
/// Classic game shows the watermark and its Blue fires 99-damage shells.
///
/// Sound is not under test here (the cue mapping has unit tests): a silent
/// sink keeps audioplayers' per-frame position callbacks from outliving the
/// widget tree at teardown.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('menu → Classic road, pinch-zoom and pan', (tester) async {
    await tester.pumpWidget(_app());
    await _playClassic(tester);

    await _pumpUntil(tester, find.byTooltip('Pause'));
    final game = tester
        .widget<GameWidget<OnslaughtFlameGame>>(find.byType(GameWidget<OnslaughtFlameGame>))
        .game!;
    expect(game.viewModel.map.name, 'Classic');
    expect(game.rig.isAtFit, isTrue);

    // Two-finger pinch out around the screen centre.
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final c = size.center(Offset.zero);
    final a = await tester.startGesture(c - const Offset(40, 0), pointer: 11);
    final b = await tester.startGesture(c + const Offset(40, 0), pointer: 12);
    for (var i = 1; i <= 15; i++) {
      await a.moveTo(c - Offset(40.0 + 8 * i, 0));
      await b.moveTo(c + Offset(40.0 + 8 * i, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(game.rig.relativeZoom, greaterThan(2));

    // One-finger drag pans.
    final before = game.rig.center;
    await tester.timedDragFrom(c, const Offset(-150, -60), const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 400));
    expect(game.rig.center.dx, greaterThan(before.dx));

    await tester.tap(find.byTooltip('Back to menu'));
    await _pumpUntil(tester, find.text('ONSLAUGHT 3'));
  });
  testWidgets('drag-build a Blue, send a wave, kill, upgrade, sell', (tester) async {
    await tester.pumpWidget(_app());
    await _playClassic(tester);
    await _pumpUntil(tester, find.byTooltip('Send next wave'));
    final game = tester
        .widget<GameWidget<OnslaughtFlameGame>>(find.byType(GameWidget<OnslaughtFlameGame>))
        .game!;
    final vm = game.viewModel as SessionGameViewModel;

    // Drag from the tray cell to a spot beside the road (blue-rush's second
    // spot on Classic).
    const spot = Offset(366, 228);
    final target = game.rig.worldToScreen(spot);
    final from = tester.getCenter(find.text(r'$10'));
    final drag = await tester.startGesture(from);
    for (var i = 1; i <= 20; i++) {
      await drag.moveTo(Offset.lerp(from, target, i / 20)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await _letGoOfBuildDrag(tester, drag, vm);
    final turret = vm.session.turrets.single;
    expect(turret.position.x, closeTo(spot.dx, 1));
    expect(turret.position.y, closeTo(spot.dy, 1));

    await tester.tap(find.byTooltip('Send next wave'));
    final end = DateTime.now().add(const Duration(seconds: 30));
    while (vm.session.kills == 0 && DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(vm.session.kills, greaterThan(0));
    expect(turret.kills, greaterThan(0));

    await tester.tapAt(target);
    await _pumpUntil(tester, find.text('Damage'));
    await tester.tap(find.text('Damage'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(turret.damageLevel, 1);
    await tester.tap(find.textContaining('Sell'));
    // Past the sheet's 150 ms fade-out.
    await tester.pump(const Duration(milliseconds: 400));
    expect(vm.session.turrets, isEmpty);
    expect(find.text('Damage'), findsNothing);
    expect(vm.session.config.profile, RulesProfile.classicFixed);
  });

  testWidgets('a Red with two idle Blues fires a nuke; its blast is drawn', (tester) async {
    await tester.pumpWidget(_app());
    await _playClassic(tester);
    await _pumpUntil(tester, find.byTooltip('Send next wave'));
    final game = tester
        .widget<GameWidget<OnslaughtFlameGame>>(find.byType(GameWidget<OnslaughtFlameGame>))
        .game!;
    final vm = game.viewModel as SessionGameViewModel;
    final s = vm.session..debugCash = 1e9;

    // A leader 40–120 px from the road, and two helper spots 50–69 px from
    // it that are out of a Blue's reach of the road (130 px plus the 9 px
    // creep jitter), so they are idle and ready when the Red first engages.
    bool free(Vec2 p, List<Vec2> taken) =>
        s.placementIssueAt(p) == null && taken.every((t) => t.distanceTo(p) >= 40);
    (Vec2, List<Vec2>)? layout() {
      for (var y = 20.0; y < 460; y += 5) {
        for (var x = 20.0; x < 700; x += 5) {
          final leader = Vec2(x, y);
          final d = s.road.distanceToCentreLine(leader);
          if (d < 40 || d > 120 || !free(leader, const [])) continue;
          final helpers = <Vec2>[];
          for (var a = 0; a < 360 && helpers.length < 2; a += 10) {
            for (final r in const [69.0, 60.0, 50.0]) {
              final rad = a * math.pi / 180;
              final h = leader + Vec2(math.cos(rad), math.sin(rad)) * r;
              if (s.road.distanceToCentreLine(h) > 140 && free(h, [leader, ...helpers])) {
                helpers.add(h);
                break;
              }
            }
          }
          if (helpers.length == 2) return (leader, helpers);
        }
      }
      return null;
    }

    final (leaderAt, helperSpots) = layout()!;
    for (final (id, at) in [
      ('red', leaderAt),
      ('blue', helperSpots[0]),
      ('blue', helperSpots[1]),
    ]) {
      vm.dispatch(BuildTurret(id, at.x, at.y));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 200));
    expect(s.turrets, hasLength(3));
    for (final t in s.turrets) {
      for (var i = 0; i < t.def.upgrades.damage.length; i++) {
        vm.dispatch(UpgradeTurret(t.uid, 'damage'));
      }
    }
    for (var i = 0; i < s.turrets.first.def.upgrades.range.length; i++) {
      vm.dispatch(UpgradeTurret(s.turrets.first.uid, 'range'));
    }
    await tester.pump(const Duration(milliseconds: 100));
    vm.select(s.turrets.first.uid);

    final combos = <ComboFired>[];
    final sub = vm.events.listen((e) {
      if (e is ComboFired) combos.add(e);
    });
    await tester.tap(find.byTooltip('Send next wave'));
    final end = DateTime.now().add(const Duration(seconds: 45));
    while (combos.isEmpty && DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(combos.first.combo, 'nuke');
    expect(find.textContaining('Combo in'), findsOneWidget);
    var blastSeen = false;
    final blastEnd = DateTime.now().add(const Duration(seconds: 15));
    while (!blastSeen && DateTime.now().isBefore(blastEnd)) {
      await tester.pump(const Duration(milliseconds: 50));
      blastSeen = game.world.children
          .whereType<EntityLayer>()
          .single
          .children
          .whereType<BlastView>()
          .isNotEmpty;
    }
    expect(blastSeen, isTrue);
    // Hold a few seconds of frames for screenshots.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await sub.cancel();
  });

  testWidgets('sandbox2: all 16 turrets; join, lock in a Combonly plate, supers fire', (
    tester,
  ) async {
    await tester.pumpWidget(_app(profile: const Profile(available: {'sandbox', 'sandbox2'})));
    await _pumpUntil(tester, find.text('Play'));
    await tester.tap(find.text('Play'));
    await _pumpUntil(tester, find.text('Sandbox Mode'));
    await tester.tap(find.text('Sandbox Mode'));
    await _pumpUntil(tester, find.text('Super Sandbox'));
    await tester.tap(find.text('Super Sandbox'));
    await _pumpUntil(tester, find.text('Super Sandbox Mode'));
    await tester.scrollUntilVisible(
      find.text('Lyne'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(find.text('Lyne'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Lyne'));
    await _pumpUntil(tester, find.byTooltip('Send next wave'));
    final game = tester
        .widget<GameWidget<OnslaughtFlameGame>>(find.byType(GameWidget<OnslaughtFlameGame>))
        .game!;
    final vm = game.viewModel as SessionGameViewModel;
    final s = vm.session;
    expect(s.config.mode, 'sandbox2');
    expect(s.cash, 1000000);
    expect(vm.tray.value, hasLength(16));
    expect(vm.tray.value.where((t) => t.locked), isEmpty);

    // The layout of the sandbox2-everything regression fixture.
    const spots = [
      ('targeter', Vec2(120, 30)),
      ('sniper', Vec2(420, 200)),
      ('railgun', Vec2(560, 330)),
      ('fusion', Vec2(330, 100)),
      ('green', Vec2(380, 60)),
      ('yellow', Vec2(290, 40)),
      ('combonly', Vec2(150, 300)),
      ('red', Vec2(205, 300)),
      ('yellow', Vec2(95, 300)),
      ('blue', Vec2(480, 240)),
      ('range-up', Vec2(190, 60)),
      ('damage-up', Vec2(520, 40)),
      ('rate-up-exchange', Vec2(570, 40)),
      ('range-up-exchange', Vec2(620, 40)),
      ('rate-up', Vec2(670, 40)),
      ('damage-up-big', Vec2(545, 90)),
      ('damage-up-big-exchange', Vec2(595, 90)),
    ];
    for (final (id, at) in spots) {
      vm.dispatch(BuildTurret(id, at.x, at.y));
    }
    await tester.pump(const Duration(milliseconds: 100));
    expect(s.turrets, hasLength(spots.length));
    expect(s.turrets.map((t) => t.def.id).toSet(), hasLength(16));
    final built = List.of(s.turrets);
    // By build order: the list shrinks once the plate consumes its turrets.
    Turret at(int i) => built[i];
    for (final t in [at(7), at(8)]) {
      for (var i = 0; i < t.def.upgrades.damage.length; i++) {
        vm.dispatch(UpgradeTurret(t.uid, 'damage'));
      }
    }
    await tester.pump(const Duration(milliseconds: 100));

    // Join the far Blue: the sheet's Join, then a tap on it on the map.
    vm.select(at(0).uid);
    await _pumpUntil(tester, find.text('Join'));
    await tester.tap(find.text('Join'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(vm.joining.value, at(0).uid);
    final blue = at(9).position;
    game.tapAt(game.rig.worldToScreen(Offset(blue.x, blue.y)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(at(0).stateOrNull<TargeterState>(TargeterSpecial.specialId)?.joins, [at(9).uid]);
    await tester.tap(find.text('Done'));
    await tester.pump(const Duration(milliseconds: 50));
    // Join the Sniper and the Railgun too, as the fixture does: they
    // otherwise fire only at the creeps that leak past the rest (the
    // Railgun first at ~29 s in the fixture), which a wall-clock budget on
    // a slow device often does not reach. Joined turrets are triggered
    // newest first, so the Railgun (whose beam hurts 32 ms later) fires
    // before the Sniper's instant shot can kill the target.
    vm
      ..dispatch(JoinTurret(at(0).uid, at(1).uid))
      ..dispatch(JoinTurret(at(0).uid, at(2).uid));
    await tester.pump(const Duration(milliseconds: 100));
    expect(at(0).stateOrNull<TargeterState>(TargeterSpecial.specialId)?.joins, [
      at(9).uid,
      at(1).uid,
      at(2).uid,
    ]);

    // Lock the plate in once its colour shows.
    final plate = at(6);
    final consumed = [at(7).uid, at(8).uid];
    vm.select(plate.uid);
    await _pumpUntil(tester, find.text('Lock\nin'));
    await tester.tap(find.text('Lock\nin'));
    await _pumpUntil(tester, find.text('Ready'), timeout: const Duration(seconds: 10));
    // Armed after 1.5 s; the consumed turrets go at 2 s.
    for (var i = 0; i < 20 && s.turrets.any((t) => consumed.contains(t.uid)); i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(s.turrets.map((t) => t.uid), isNot(anyOf(contains(consumed[0]), contains(consumed[1]))));

    final fired = <int, int>{};
    final combos = <ComboFired>[];
    final sub = vm.events.listen((e) {
      if (e is TurretFired) fired[e.uid] = (fired[e.uid] ?? 0) + 1;
      if (e is ComboFired) combos.add(e);
    });
    // A beam lives 125 ms and the Flame ticker draws frames between pumps,
    // so look for its view after every drawn frame, not after each pump.
    final layer = game.world.children.whereType<EntityLayer>().single;
    var railSeen = false;
    var watching = true;
    _afterEveryFrame(() {
      railSeen |= layer.children.whereType<RailBeamView>().isNotEmpty;
      return railSeen || !watching;
    });
    var blueSent = false;
    final end = DateTime.now().add(const Duration(seconds: 40));
    for (var w = 0; DateTime.now().isBefore(end); w++) {
      if (w % 30 == 0) vm.dispatch(const SendNextWave());
      await tester.pump(const Duration(milliseconds: 100));
      blueSent |= at(9).bearCreepUid != null || (fired[at(9).uid] ?? 0) > 0;
      final done =
          railSeen &&
          combos.any((c) => c.uid == plate.uid) &&
          blueSent &&
          [1, 2, 3].every((i) => (fired[at(i).uid] ?? 0) > 0) &&
          (at(3).stateOrNull<FusionState>(FusionSpecial.specialId)?.fed ?? 0) > 0;
      if (done) break;
    }
    watching = false;
    expect(fired[at(2).uid] ?? 0, greaterThan(0), reason: 'railgun fires');
    expect(railSeen, isTrue, reason: 'rail beam drawn');
    expect(combos.where((c) => c.uid == plate.uid), isNotEmpty, reason: 'plate fires');
    expect(fired[at(1).uid] ?? 0, greaterThan(0), reason: 'sniper fires');
    expect(blueSent, isTrue, reason: 'the Targeter sends the joined Blue');
    expect(
      (at(3).stateOrNull<FusionState>(FusionSpecial.specialId)?.fed ?? 0),
      greaterThan(0),
      reason: 'fusion fed',
    );
    // Hold a few seconds of frames for screenshots.
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await sub.cancel();
  });

  testWidgets('Phase 5: attract demo, tutorial with Show me, locked challenges', (tester) async {
    await tester.pumpWidget(_app());
    await _pumpUntil(tester, find.text('ONSLAUGHT 3'));
    // The attract demo plays behind the menu: its 19 turrets, no lives lost.
    await _pumpUntil(tester, find.byType(GameWidget<OnslaughtFlameGame>));
    final attract = _viewModel(tester).session;
    final end = DateTime.now().add(const Duration(seconds: 30));
    while (attract.waves.wave == 0 && DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(attract.config.attract, isTrue);
    expect(attract.turrets, hasLength(19));
    expect(attract.waves.wave, greaterThan(0));
    expect(attract.lives, attract.data.rules.lives);

    await tester.tap(find.text('Play'));
    await _pumpUntil(tester, find.text('Challenge Games'));
    await tester.tap(find.text('Challenge Games'));
    await tester.pump(const Duration(milliseconds: 300));
    // Still on the mode page; the lock text is on the tile and in the snack bar.
    expect(find.text('Choose a Game'), findsOneWidget);
    expect(find.text('Play the tutorial to unlock the challenges'), findsNWidgets(2));

    await tester.tap(find.text('Quick Tutorial'));
    await _pumpUntil(tester, find.text('Welcome to Onslaught'));
    final s = _viewModel(tester).session;
    // The tutorial's pause is a queued command: it applies on the next step.
    final pauseBy = DateTime.now().add(const Duration(seconds: 30));
    while (!s.clock.paused && DateTime.now().isBefore(pauseBy)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect([s.map.id, s.config.mode, s.clock.paused], ['tutorial', 'tutorial', isTrue]);
    // On to "Your First Combo" (page 15): Show me gives $14 500, once.
    for (var i = 0; i < 14; i++) {
      await tester.tap(find.byTooltip('Next page'));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Your First Combo'), findsOneWidget);
    await tester.tap(find.text('Show me'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(s.cash, 14500);
    await tester.tap(find.byTooltip('Close the tutorial'));
    await _pumpUntil(tester, find.text('ONSLAUGHT 3'));
  });

  testWidgets('Phase 5: pass the Warmup challenge; its best game is kept', (tester) async {
    await tester.pumpWidget(_app(profile: const Profile(available: {'challenge'})));
    await _pumpUntil(tester, find.text('Play'));
    await tester.tap(find.text('Play'));
    await _pumpUntil(tester, find.text('Challenge Games'));
    await tester.tap(find.text('Challenge Games'));
    await _pumpUntil(tester, find.text('Warmup'));
    expect(find.text("You haven't played this challenge yet."), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Play'));
    await _pumpUntil(tester, find.text('Challenge: Warmup'));
    await tester.tap(find.text('Classic'));
    await _pumpUntil(tester, find.byTooltip('Send next wave'));
    final vm = _viewModel(tester);
    final s = vm.session;
    expect(s.config.challenge?.id, 'warmup');
    expect(find.text('01:00'), findsOneWidget);
    // Perfect defence at double speed until the 60 s are up and the field is clear.
    vm.dispatch(const SetSpeed(2));
    final end = DateTime.now().add(const Duration(seconds: 60));
    while (vm.gameOver.value == null && DateTime.now().isBefore(end)) {
      for (final c in List.of(s.creeps)) {
        if (c.targetable) s.debugHitCreep(c, double.infinity);
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Challenge Passed!'), findsOneWidget);
    // Freeplay: the dialog goes and the waves come back.
    final wave = s.waves.wave;
    await tester.tap(find.text('Continue Playing'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Challenge Passed!'), findsNothing);
    expect(s.freeplay, isTrue);
    await tester.tap(find.byTooltip('Send next wave'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(s.waves.wave, wave + 1);
    await tester.tap(find.byTooltip('Back to menu'));
    await _pumpUntil(tester, find.text('Play'));
    await tester.tap(find.text('Play'));
    // Leaving stored the freeplay game, so Play offers to resume or discard it.
    await _pumpUntil(tester, find.byKey(const Key('discardGame')));
    await tester.tap(find.byKey(const Key('discardGame')));
    await _pumpUntil(tester, find.text('Challenge Games'));
    await tester.tap(find.text('Challenge Games'));
    await _pumpUntil(tester, find.text('Passed'));
    expect(find.textContaining('Kills: '), findsOneWidget);
  });

  testWidgets('Phase 6: make a map, share it, import the code and play it', (tester) async {
    await tester.pumpWidget(_app());
    await _pumpUntil(tester, find.text('Play'));
    await tester.tap(find.text('Play'));
    await _pumpUntil(tester, find.text('Map Tools'));
    await tester.tap(find.text('Map Tools'));
    await _tapAction(tester, 'New map');
    await _pumpUntil(tester, find.byType(EditorCanvas));
    await tester.tap(find.byTooltip('Close tips'));
    await tester.pump(const Duration(milliseconds: 200));

    const settle = Duration(milliseconds: 600);
    // A compact top bar keeps these two in its More menu.
    Future<void> tapEditorAction(String label) async {
      if (find.byTooltip(label).evaluate().isNotEmpty) return tester.tap(find.byTooltip(label));
      await tester.tap(find.byTooltip('More'));
      await _pumpUntil(tester, find.text(label));
      await tester.pump(settle);
      await tester.tap(find.text(label));
    }

    // A portrait phone opens the editor zoomed in; every spot below needs the whole map.
    await tapEditorAction('Fit the whole map');
    await tester.pump(settle);

    final canvas = find.byType(EditorCanvas);
    final rig = tester.state<EditorCanvasState>(canvas).rig;
    Offset at(double x, double y) => tester.getTopLeft(canvas) + rig.worldToScreen(Offset(x, y));
    Future<void> tapAt(double x, double y) async {
      await tester.tapAt(at(x, y));
      await tester.pump(const Duration(milliseconds: 200));
    }

    // The start dragged from the palette; the base by tap-to-place.
    final chip = tester.getCenter(find.bySemanticsLabel(RegExp('^Start')));
    final drag = await tester.startGesture(chip);
    for (var i = 1; i <= 20; i++) {
      await drag.moveTo(Offset.lerp(chip, at(10, 240), i / 20)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await drag.up();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.bySemanticsLabel(RegExp('^Base')));
    await tester.pump(const Duration(milliseconds: 200));
    await tapAt(600, 120);
    await tapAt(200, 240);
    await tapAt(200, 420);
    await tapAt(420, 420);
    await tapAt(420, 120);
    expect(find.text(_noStartText), findsNothing);

    // Pinch to zoom in, then fit.
    final c = tester.getCenter(canvas);
    final a = await tester.startGesture(c - const Offset(40, 0), pointer: 21);
    final b = await tester.startGesture(c + const Offset(40, 0), pointer: 22);
    for (var i = 1; i <= 10; i++) {
      await a.moveTo(c - Offset(40.0 + 8 * i, 0));
      await b.moveTo(c + Offset(40.0 + 8 * i, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await tester.pump(const Duration(milliseconds: 200));
    expect(rig.relativeZoom, greaterThan(1.5));
    await tapEditorAction('Fit the whole map');
    await tester.pump(settle);
    expect(rig.isAtFit, isTrue);

    await tester.tap(find.byTooltip('Save'));
    await _pumpUntil(tester, find.byType(TextField));
    await tester.pump(settle);
    await tester.enterText(find.byType(TextField), 'Phone Map');
    await tester.pump(settle);
    // The keyboard's Done saves (a phone's keyboard covers the dialog's buttons).
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _pumpUntilGone(tester, find.byType(Dialog));
    expect(find.text('Phone Map'), findsOneWidget);
    await tapEditorAction('Share');
    await _pumpUntil(tester, find.byKey(const Key('shareCode')));
    await tester.pump(settle);
    final code = tester.widget<SelectableText>(find.byKey(const Key('shareCode'))).data!;
    expect(code, startsWith('ons3:map:'));
    await tester.tap(find.text('Close'));
    await _pumpUntilGone(tester, find.byType(Dialog));

    // Delete it from the library, then bring it back from the code. Sheets
    // and dialogs are let finish their animations before the next tap.
    await tester.tap(find.byTooltip('Back'));
    await _pumpUntil(tester, find.bySemanticsLabel('My map Phone Map'));
    await tester.tap(find.bySemanticsLabel('My map Phone Map'));
    await _pumpUntil(tester, find.text('Delete'));
    await tester.pump(settle);
    await tester.tap(find.text('Delete'));
    await _pumpUntil(tester, find.widgetWithText(FilledButton, 'Delete'));
    await tester.pump(settle);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await _pumpUntilGone(tester, find.byType(Dialog));
    expect(find.textContaining('No maps yet'), findsOneWidget);
    await _tapAction(tester, 'Import');
    await _pumpUntil(tester, find.byKey(const Key('importCode')));
    await tester.pump(settle);
    await tester.enterText(find.byKey(const Key('importCode')), code);
    await _pumpUntil(tester, find.text('Add to my maps'));
    await tester.tap(find.text('Add to my maps'));
    await _pumpUntilGone(tester, find.byType(Dialog));

    await tester.tap(find.bySemanticsLabel('My map Phone Map'));
    await _pumpUntil(tester, find.text('Play'));
    await tester.pump(settle);
    await tester.tap(find.text('Play'));
    await _pumpUntil(tester, find.text('Easy'));
    await tester.pump(settle);
    await tester.tap(find.text('Easy'));
    await _pumpUntil(tester, find.byTooltip('Send next wave'));
    final vm = _viewModel(tester);
    expect(vm.map.name, 'Phone Map');
    expect(vm.map.builtIn, isFalse);
    await tester.tap(find.byTooltip('Send next wave'));
    final end = DateTime.now().add(const Duration(seconds: 10));
    while (vm.world.creeps.isEmpty && DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(vm.world.creeps, isNotEmpty);
    await tester.tap(find.byTooltip('Back to menu'));
    await _pumpUntil(tester, find.text('ONSLAUGHT 3'));
  });

  testWidgets('Phase 7: mod Blue damage, switch it on, export it; the next game uses it', (
    tester,
  ) async {
    await tester.pumpWidget(_app(profile: const Profile(available: {'modding'})));
    await _pumpUntil(tester, find.text('Play'));
    await tester.tap(find.text('Play'));
    await _pumpUntil(tester, find.text('Mods'));
    await tester.tap(find.text('Mods'));
    await _pumpUntil(tester, find.text('Moddable Stuff'));

    const settle = Duration(milliseconds: 600);
    await tester.tap(find.byKey(const Key('modItem:TurretBlue')));
    await tester.pump(settle);
    await tester.tap(find.byKey(const Key('modField:TurretBlue.weapon_damage')));
    await tester.pump(settle);
    await tester.enterText(find.byKey(const Key('modNumber')), '99');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _pumpUntil(tester, find.textContaining('1 change · signature'));
    // Out of range: refused with the reason, the 99 stays. A portrait phone
    // shows one pane at a time, so it first goes back to the fields.
    final range = find.byKey(const Key('modField:TurretBlue.weapon_range'));
    if (range.evaluate().isEmpty) {
      await tester.tap(find.byTooltip('Back'));
      await tester.pump(settle);
    }
    await tester.tap(range);
    await tester.pump(settle);
    await tester.enterText(find.byKey(const Key('modNumber')), '5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _pumpUntil(tester, find.text('Must be at least 10'));
    expect(find.textContaining('1 change · signature'), findsOneWidget);

    await tester.tap(find.byKey(const Key('modActive')));
    await tester.pump(settle);
    await _tapAction(tester, 'Export');
    await _pumpUntil(tester, find.byKey(const Key('shareCode')));
    await tester.pump(settle);
    final code = tester.widget<SelectableText>(find.byKey(const Key('shareCode'))).data!;
    expect(code, startsWith('ons3:mod:'));
    final shared = const ModSharing().decode(
      code,
      ModRules(await GameData.load(AssetBundleDataSource(), behaviours: RulesRegistry.classic())),
    );
    expect(
      (((shared.delta.files['turrets.json']! as Map)['turrets'] as Map)['blue'] as Map)['stats'],
      {'damage': 99},
    );
    await tester.tap(find.text('Close'));
    await _pumpUntilGone(tester, find.byType(Dialog));

    // Back through a portrait phone's panes, or straight out of the wide layout.
    while (find.text('Easy Mode').evaluate().isEmpty) {
      await tester.tap(find.byTooltip('Back'));
      await tester.pump(settle);
    }
    await tester.tap(find.text('Easy Mode'));
    await _pumpUntil(tester, find.text('Classic'));
    await tester.tap(find.text('Classic'));
    await _pumpUntil(tester, find.byTooltip('Send next wave'));
    expect(find.textContaining('Mod: My mod, signature: '), findsOneWidget);
    final game = tester
        .widget<GameWidget<OnslaughtFlameGame>>(find.byType(GameWidget<OnslaughtFlameGame>))
        .game!;
    final vm = game.viewModel as SessionGameViewModel;
    expect(vm.session.data.turrets['blue']!.stats.damage, 99);

    // A Blue dragged in from the tray fires 99-damage shells.
    final target = game.rig.worldToScreen(const Offset(366, 228));
    final from = tester.getCenter(find.text(r'$10'));
    final drag = await tester.startGesture(from);
    for (var i = 1; i <= 20; i++) {
      await drag.moveTo(Offset.lerp(from, target, i / 20)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await _letGoOfBuildDrag(tester, drag, vm);
    await tester.tap(find.byTooltip('Send next wave'));
    final end = DateTime.now().add(const Duration(seconds: 30));
    while (vm.session.projectiles.isEmpty && DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(vm.session.projectiles.first.damage, 99);
    await tester.tap(find.byTooltip('Back to menu'));
    await _pumpUntil(tester, find.text('ONSLAUGHT 3'));
  });
}

const String _noStartText = 'There is no start point on the map';

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('timed out waiting for $finder');
}

/// Ends a drag from the tray and waits for the turret. Phones default to drop
/// and lock, where the dropped ghost waits for Place.
Future<void> _letGoOfBuildDrag(
  WidgetTester tester,
  TestGesture drag,
  SessionGameViewModel vm,
) async {
  await drag.up();
  await tester.pump(const Duration(milliseconds: 200));
  if (find.text('Place').evaluate().isNotEmpty) await tester.tap(find.text('Place'));
  final end = DateTime.now().add(const Duration(seconds: 30));
  while (vm.session.turrets.isEmpty && DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Taps an action that a wide layout labels with text and a narrow one with
/// an icon and tooltip.
Future<void> _tapAction(WidgetTester tester, String label) async {
  final end = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    for (final action in [find.text(label), find.byTooltip(label)]) {
      if (action.evaluate().isNotEmpty) return tester.tap(action);
    }
  }
  throw TestFailure('timed out waiting for "$label"');
}

Future<void> _pumpUntilGone(WidgetTester tester, Finder finder) async {
  final end = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isEmpty) return;
  }
  throw TestFailure('timed out waiting for $finder to go');
}

/// Runs [check] after every frame the binding draws, including the ones
/// between pumps, until it returns true.
void _afterEveryFrame(bool Function() check) {
  void onFrame(Duration _) {
    if (!check()) WidgetsBinding.instance.addPostFrameCallback(onFrame);
  }

  WidgetsBinding.instance.addPostFrameCallback(onFrame);
}

/// The app on a fresh in-memory profile ([profile] when given).
Widget _app({Profile? profile}) {
  final store = MemoryDocumentStore();
  if (profile != null) unawaited(store.write(Profile.key, profile.toJson()));
  return ProviderScope(
    overrides: [
      audioSinkProvider.overrideWithValue(SilentAudioSink()),
      documentStoreProvider.overrideWithValue(store),
      // No debug-only challenge preset in the list.
      featureFlagsProvider.overrideWithValue(
        FeatureFlags.fromEnvironment().copyWith(debugMenu: false),
      ),
    ],
    child: const OnslaughtApp(),
  );
}

/// Main menu → Play → Easy Mode → Classic.
Future<void> _playClassic(WidgetTester tester) async {
  await _pumpUntil(tester, find.text('Play'));
  await tester.tap(find.text('Play'));
  await _pumpUntil(tester, find.text('Easy Mode'));
  await tester.tap(find.text('Easy Mode'));
  await _pumpUntil(tester, find.text('Classic'));
  await tester.tap(find.text('Classic'));
  await _pumpUntil(tester, find.byTooltip('Send next wave'));
}

SessionGameViewModel _viewModel(WidgetTester tester) =>
    tester
            .widget<GameWidget<OnslaughtFlameGame>>(find.byType(GameWidget<OnslaughtFlameGame>))
            .game!
            .viewModel
        as SessionGameViewModel;
