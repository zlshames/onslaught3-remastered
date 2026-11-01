import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:onslaught3_remastered/app/app.dart';
import 'package:onslaught3_remastered/app/providers.dart';
import 'package:onslaught3_remastered/features/game/flame/onslaught_flame_game.dart';
import 'package:onslaught3_remastered/features/game/game_view_model.dart';
import 'package:onslaught3_remastered/services/persistence/document_store.dart';
import 'package:onslaught3_remastered/services/persistence/profile.dart';
import 'package:onslaught_core/onslaught_core.dart';
import 'package:onslaught_core/testing.dart';

import 'quiet_sinks.dart';

/// Wave the game is fast-forwarded to before the window opens.
const int _startWave = int.fromEnvironment('PERF_START_WAVE', defaultValue: 70);

/// Length of the measured window, in seconds.
const int _seconds = int.fromEnvironment('PERF_SECONDS', defaultValue: 20);

/// Length of the tray-drag window after it, in seconds.
const int _dragSeconds = int.fromEnvironment('PERF_DRAG_SECONDS', defaultValue: 6);

/// The performance scenario of the 2026-10-19 per-frame audit: a Super Sandbox game on
/// map 1 at 3× with about 20 turrets (two colour clusters so combos fire,
/// plus one of every other type, the Targeter among them), fast-forwarded
/// headless to wave [_startWave] with every damage track maxed, then a
/// Green turret selected and [_seconds] of live frames recorded with no
/// builds or upgrades (lives and cash topped up, the next wave sent when
/// the field is quiet), then [_dragSeconds] of a tray drag (a build ghost
/// moved every frame). Prints frame build and raster times and how often
/// the tray, selection and placement notified (`PERF_RESULT`,
/// `DRAG_RESULT`); a host-side VM service client (described in the report)
/// attaches on the `PERF_WINDOW_START` line for the CPU profile and the
/// allocation rate. Run in profile mode:
///
///     fvm flutter drive --profile -d emulator-5554 \
///       --driver=test_driver/integration_test.dart \
///       --target=integration_test/perf_scenario_test.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'perf scenario: sandbox at 3×, wave $_startWave+, turret selected',
    (tester) async {
      final store = MemoryDocumentStore();
      await store.write(Profile.key, const Profile(unlockAll: true).toJson());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            audioSinkProvider.overrideWithValue(SilentAudioSink()),
            hapticSinkProvider.overrideWithValue(NoHaptics()),
            documentStoreProvider.overrideWithValue(store),
          ],
          child: const OnslaughtApp(initialLocation: '/game/map1?mode=sandbox2&difficulty=hard'),
        ),
      );
      final game = find.byType(GameWidget<OnslaughtFlameGame>);
      for (var i = 0; i < 300 && game.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final vm =
          tester.widget<GameWidget<OnslaughtFlameGame>>(game).game!.viewModel
              as SessionGameViewModel;
      final s = vm.session;
      final soak = SoakDriver(s, coloursPerKind: 2, churnEvery: 1 << 30)..setUp();

      // Lives and cash topped up, the next wave sent when the field is quiet
      // (the soak's pacing, without its builds and upgrades).
      void keepUp() {
        s
          ..debugLives = 1 << 30
          ..debugCash = 1e15;
        if (s.waves.spawners.isEmpty && s.creeps.length < soak.quietCreeps) {
          s.enqueue(const SendNextWave());
        }
      }

      bool damageMaxed() => s.turrets.every(
        (t) => t.def.upgrades.damage.isEmpty || t.damageLevel >= t.def.upgrades.damage.length,
      );

      // Fast-forward headless (no frames drawn) to the start wave: build the
      // plan and max every damage track (the soak buys damage first), which
      // makes the colours combo-capable; the other tracks stay at their base
      // so creeps still reach the road at this wave.
      final ff = Stopwatch()..start();
      var rounds = 0;
      while (s.waves.wave < _startWave) {
        if (soak.stats.built < 20 || !damageMaxed()) {
          soak.decide();
        } else {
          keepUp();
        }
        for (var i = 0; i < 30; i++) {
          s.step();
        }
        if (++rounds % 50 == 0) await tester.pump(const Duration(milliseconds: 16));
      }
      // Let the views catch up with the fast-forwarded world.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final green = s.turrets.firstWhere((t) => t.def.id == 'green');
      vm.select(green.uid);
      debugPrint(
        'perf: fast-forward to wave ${s.waves.wave} in ${ff.elapsed.inSeconds} s; '
        '${s.turrets.length} turrets (${{for (final t in s.turrets) t.def.id}.join(',')}); '
        'selected ${green.uid}; ${soak.stats}',
      );

      // Live frames from here: the engine drives every frame, as in the app.
      binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
      final pacer = Timer.periodic(const Duration(milliseconds: 250), (_) => keepUp());
      final waveStart = s.waves.wave;
      debugPrint('PERF_WINDOW_START');
      await Future<void>.delayed(const Duration(seconds: 1));
      final timings = <FrameTiming>[];
      void collect(List<FrameTiming> t) => timings.addAll(t);
      SchedulerBinding.instance.addTimingsCallback(collect);
      var creeps = 0, projectiles = 0, samples = 0;
      final sampler = Timer.periodic(const Duration(milliseconds: 500), (_) {
        creeps += s.creeps.length;
        projectiles += s.projectiles.length;
        samples++;
      });
      var trayNotes = 0, selectionNotes = 0, combos = 0, shots = 0;
      void onTray() => trayNotes++;
      void onSelection() => selectionNotes++;
      vm.tray.addListener(onTray);
      vm.selection.addListener(onSelection);
      final events = vm.events.listen((e) {
        if (e is ComboFired) combos++;
        if (e is TurretFired) shots++;
      });
      final window = Stopwatch()..start();
      await Future<void>.delayed(const Duration(seconds: _seconds));
      window.stop();
      sampler.cancel();
      vm.tray.removeListener(onTray);
      vm.selection.removeListener(onSelection);
      await events.cancel();
      SchedulerBinding.instance.removeTimingsCallback(collect);
      pacer.cancel();

      final build = [for (final t in timings) t.buildDuration.inMicroseconds]..sort();
      final raster = [for (final t in timings) t.rasterDuration.inMicroseconds]..sort();
      int pct(List<int> l, double p) => l.isEmpty ? 0 : l[((l.length - 1) * p).round()];
      double avg(List<int> l) => l.isEmpty ? 0 : l.reduce((a, b) => a + b) / l.length;
      final slow = timings.where((t) => t.totalSpan > const Duration(milliseconds: 17)).length;
      debugPrint(
        'PERF_RESULT frames=${timings.length} seconds=${window.elapsedMilliseconds / 1000} '
        'fps=${(timings.length * 1000 / window.elapsedMilliseconds).toStringAsFixed(1)} '
        'build_avg=${avg(build).round()} build_p50=${pct(build, .5)} build_p95=${pct(build, .95)} '
        'build_p99=${pct(build, .99)} raster_avg=${avg(raster).round()} '
        'raster_p50=${pct(raster, .5)} raster_p95=${pct(raster, .95)} raster_p99=${pct(raster, .99)} '
        'over17ms=${timings.isEmpty ? 0 : (100 * slow / timings.length).toStringAsFixed(1)}% '
        'waves=$waveStart-${s.waves.wave} turrets=${s.turrets.length} '
        'avg_creeps=${samples == 0 ? 0 : creeps ~/ samples} '
        'avg_projectiles=${samples == 0 ? 0 : projectiles ~/ samples} '
        'combos=$combos shots=$shots tray_notifies=$trayNotes selection_notifies=$selectionNotes',
      );

      // A tray drag: the ghost of a Blue follows the finger across the map,
      // a new position every frame (what the game screen's dragTo does).
      await Future<void>.delayed(const Duration(seconds: 2));
      final dragTimings = <FrameTiming>[];
      void collectDrag(List<FrameTiming> t) => dragTimings.addAll(t);
      SchedulerBinding.instance.addTimingsCallback(collectDrag);
      var trayDuringDrag = 0, placementTicks = 0;
      void onPlacement() => placementTicks++;
      vm.tray.addListener(onTray);
      vm.placement.addListener(onPlacement);
      trayNotes = 0;
      var x = 0.0;
      final drag = Timer.periodic(const Duration(milliseconds: 16), (_) {
        vm
          ..select(null)
          ..previewPlacement('blue', Vec2(60 + x % 600, 60 + (x * 0.6) % 360));
        x += 7;
      });
      await Future<void>.delayed(const Duration(seconds: _dragSeconds));
      drag.cancel();
      vm.cancelPlacement();
      trayDuringDrag = trayNotes;
      vm.tray.removeListener(onTray);
      vm.placement.removeListener(onPlacement);
      SchedulerBinding.instance.removeTimingsCallback(collectDrag);
      final dBuild = [for (final t in dragTimings) t.buildDuration.inMicroseconds]..sort();
      debugPrint(
        'DRAG_RESULT frames=${dragTimings.length} build_avg=${avg(dBuild).round()} '
        'build_p95=${pct(dBuild, .95)} build_p99=${pct(dBuild, .99)} '
        'placement_ticks=$placementTicks tray_notifies=$trayDuringDrag',
      );
      expect(tester.takeException(), isNull);
      expect(s.gameOver, isFalse);
      binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fadePointers;
      await tester.pumpWidget(const SizedBox());
    },
    // Semantics off, as in the app on a phone with no accessibility service
    // (on, the testWidgets default, it was a sixth of the frame).
    semanticsEnabled: false,
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
