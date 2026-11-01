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
import 'package:onslaught_core/testing.dart';

import 'quiet_sinks.dart';

/// Waves to play (`--dart-define=SOAK_WAVES=40` for a quick run).
const int _waves = int.fromEnvironment('SOAK_WAVES', defaultValue: 300);

/// Wall-clock limit for the whole run, in minutes.
const int _minutes = int.fromEnvironment('SOAK_MINUTES', defaultValue: 45);

/// The Phase 8 device soak (`docs/REMASTER_PLAN.md` §7): the real app, with
/// Flame drawing every frame, plays a Super Sandbox game on Classic at 3×
/// to wave [_waves] under the same [SoakDriver] as the headless soak (every
/// turret type, colour clusters firing combos, maxed upgrades, sales,
/// overlapping waves, smoke on). It must finish without a Flutter error or
/// a game over; frame times are reported. Release gate and nightly job:
///
///     fvm flutter test integration_test/soak_test.dart -d emulator-5554
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Super Sandbox at 3× to wave $_waves', (tester) async {
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
        tester.widget<GameWidget<OnslaughtFlameGame>>(game).game!.viewModel as SessionGameViewModel;
    final soak = SoakDriver(vm.session)..setUp();

    final timings = <FrameTiming>[];
    void collect(List<FrameTiming> t) => timings.addAll(t);
    SchedulerBinding.instance.addTimingsCallback(collect);
    final start = DateTime.now();
    final deadline = start.add(const Duration(minutes: _minutes));
    var frames = 0;
    var lastWave = 0;
    while (!soak.done && DateTime.now().isBefore(deadline)) {
      if (frames % 4 == 0) soak.decide();
      await tester.pump(const Duration(milliseconds: 16));
      frames++;
      expect(tester.takeException(), isNull, reason: 'frame $frames');
      final wave = vm.session.waves.wave;
      if (wave ~/ 25 != lastWave ~/ 25) {
        debugPrint('soak: wave $wave after ${DateTime.now().difference(start).inSeconds} s');
      }
      lastWave = wave;
    }
    SchedulerBinding.instance.removeTimingsCallback(collect);

    final build = [for (final t in timings) t.buildDuration.inMicroseconds]..sort();
    final raster = [for (final t in timings) t.rasterDuration.inMicroseconds]..sort();
    int pct(List<int> l, double p) => l.isEmpty ? 0 : l[((l.length - 1) * p).round()];
    final slow = timings.where((t) => t.totalSpan > const Duration(milliseconds: 17)).length;
    debugPrint(
      'soak: wave ${vm.session.waves.wave} in ${DateTime.now().difference(start).inSeconds} s, '
      '${timings.length} frames; build p50 ${pct(build, .5)} p90 ${pct(build, .9)} '
      'p99 ${pct(build, .99)} µs; raster p50 ${pct(raster, .5)} p90 ${pct(raster, .9)} '
      'p99 ${pct(raster, .99)} µs; ${timings.isEmpty ? 0 : (100 * slow / timings.length).toStringAsFixed(1)} % '
      'over 17 ms; ${soak.stats}',
    );
    expect(soak.done, isTrue, reason: 'reached wave ${vm.session.waves.wave} in $_minutes min');
    expect(vm.session.gameOver, isFalse);
    expect(vm.session.kills, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
  }, timeout: const Timeout(Duration(minutes: _minutes + 5)));
}
