import 'dart:convert';
import 'dart:ui';

import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/features/game/flame/onslaught_flame_game.dart';
import 'package:onslaught3_remastered/features/game/game_view_model.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../support/fakes.dart';
import '../../support/test_data.dart';

typedef _Frame = ({Size size, EdgeInsets insets, bool fill});

/// The screen shape is presentation only: the same game played through
/// screen taps in landscape, in portrait (the filled view), and turning
/// between them sends the same commands and produces the same event log.
void main() {
  late GameData data;
  setUpAll(() => data = loadTestGameData());

  const landscape = (
    size: Size(923, 411),
    insets: EdgeInsets.only(top: 48, right: 76),
    fill: false,
  );
  const portrait = (size: Size(411, 923), insets: EdgeInsets.only(top: 48, bottom: 88), fill: true);

  /// Plays a scripted game; [frameAt] gives the screen shape for each step
  /// of the script (0-based).
  Future<List<String>> play(_Frame Function(int step) frameAt) async {
    final vm = SessionGameViewModel(
      GameSession(
        data: data,
        config: const GameConfig(mapId: 'map1', seed: 7),
      ),
    );
    final log = <String>[];
    final sub = vm.events.listen((e) => log.add(canonicalJson(e.toJson())));
    final game = OnslaughtFlameGame(viewModel: vm, pack: EmptyAssetPack(), driveSimulation: false);
    var step = 0;
    void frame() {
      final f = frameAt(step++);
      game.rig.resize(f.size);
      game.setFrame(f.insets, fill: f.fill);
    }

    void tapWorld(double x, double y) {
      frame();
      // Pan a filled view so the spot is on screen, as a player would.
      game.rig.panToShow(Offset(x, y));
      game.tapAt(game.rig.worldToScreen(Offset(x, y)));
    }

    void run(double seconds) {
      for (var t = 0.0; t < seconds; t += 1 / 60) {
        vm.advance(1 / 60);
      }
    }

    // Build two turrets with tap-to-build, let the waves come, select one
    // with a tap, upgrade it, sell the other.
    run(0.1);
    // Two buildable spots away from each other.
    final spots = [
      for (var x = 40.0; x < 700; x += 40)
        for (var y = 40.0; y < 460; y += 40)
          if (vm.session.placementIssueAt(Vec2(x, y)) == null) Vec2(x, y),
    ];
    final a = spots.first;
    final b = spots.lastWhere((p) => p.distanceTo(a) > 200);
    vm.previewPlacement('blue', null);
    tapWorld(a.x, a.y);
    run(0.5);
    vm.previewPlacement('blue', null);
    tapWorld(b.x, b.y);
    run(25);
    tapWorld(a.x, a.y);
    final selected = vm.selection.value!.uid;
    vm.dispatch(UpgradeTurret(selected, 'damage'));
    run(5);
    tapWorld(b.x, b.y);
    vm.dispatch(SellTurret(vm.selection.value!.uid));
    run(10);
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    vm.dispose();
    return log;
  }

  /// The logs match event for event; numbers may differ only by the float
  /// noise of turning a tap into a world point (a finger is never that
  /// precise either).
  void expectSameGame(List<String> actual, List<String> expected) {
    expect(actual, hasLength(expected.length));
    void same(Object? a, Object? b, String at) {
      if (a is num && b is num) {
        expect(a.toDouble(), closeTo(b.toDouble(), 1e-6), reason: at);
      } else if (a is Map && b is Map) {
        expect(a.keys.toSet(), b.keys.toSet(), reason: at);
        for (final k in a.keys) {
          same(a[k], b[k], '$at.$k');
        }
      } else if (a is List && b is List) {
        expect(a, hasLength(b.length), reason: at);
        for (var i = 0; i < a.length; i++) {
          same(a[i], b[i], '$at[$i]');
        }
      } else {
        expect(a, b, reason: at);
      }
    }

    for (var i = 0; i < expected.length; i++) {
      same(jsonDecode(actual[i]), jsonDecode(expected[i]), 'event $i');
    }
  }

  test('landscape, portrait and turning mid-game play the same game', () async {
    final upright = await play((_) => landscape);
    final turned = await play((_) => portrait);
    final switching = await play((step) => step.isEven ? landscape : portrait);
    expect(upright.where((e) => e.toLowerCase().contains('turretbuilt')), hasLength(2));
    expect(upright.where((e) => e.toLowerCase().contains('turretsold')), hasLength(1));
    expectSameGame(turned, upright);
    expectSameGame(switching, upright);
  });
}
