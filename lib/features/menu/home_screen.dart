import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../app/camera_rig.dart';
import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../app/theme.dart';
import 'resume_game_dialog.dart';

/// Where the credit line sits on a landscape [screen], in screen px: the
/// middle of the longest level straight of the demo's road in the stage's
/// lower half, clear of the stage's edges, [roadWidth] world px tall. Null on
/// a tall screen, where the demo covers the screen and no road runs under the
/// menu, and when the road has no such straight.
@visibleForTesting
Rect? creditRoad(AttractDef attract, double roadWidth, Size screen) {
  if (screen.height > screen.width) return null;
  final stage = Size(attract.stageWidth, attract.stageHeight);
  Rect? best;
  for (var i = 1; i < attract.road.length; i++) {
    final a = attract.road[i - 1];
    final b = attract.road[i];
    final left = math.min(a.x, b.x);
    final right = math.max(a.x, b.x);
    final level = (a.y - b.y).abs() < 1;
    final clear = left > 0 && right < stage.width && a.y > stage.height / 2;
    if (!level || !clear || right - left <= (best?.width ?? 0)) continue;
    best = Rect.fromCenter(
      center: Offset((left + right) / 2, (a.y + b.y) / 2),
      width: right - left,
      height: roadWidth,
    );
  }
  if (best == null) return null;
  final zoom = CameraRig.fitZoomFor(screen, EdgeInsets.zero, stage);
  final middle = stage.center(Offset.zero);
  final screenMiddle = screen.center(Offset.zero);
  return Rect.fromCenter(
    center: screenMiddle + (best.center - middle) * zoom,
    width: best.width * zoom,
    height: best.height * zoom,
  );
}

/// The main menu: the title over the attract demo ([background], the
/// original's `GameManagerIntro` game running behind the menu), Play and
/// Settings, the custom games' Records, and the original credits.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, this.background});

  /// What runs behind the menu (the attract demo); plain backdrop if null.
  final Widget? background;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // One notice per run when a saved document could not be read and was
    // reset (the provider resolves once).
    ref.listen(recoveredDocumentsProvider, (_, next) {
      if (next case AsyncData(value: final keys) when keys.isNotEmpty) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(ref.tr(context, 'ui.menu.recovered'))));
      }
    });
    return Scaffold(
      backgroundColor: AppColours.backdrop,
      body: Stack(
        fit: StackFit.expand,
        children: [
          ?background,
          // The gradient's radius is a share of the shortest side; on a tall
          // screen it stretches to cover as much as in landscape.
          LayoutBuilder(
            builder: (context, box) => DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: box.maxHeight > box.maxWidth ? 0.9 * box.maxHeight / box.maxWidth : 0.9,
                  colors: const [Color(0x99000000), Color(0x33000000)],
                ),
              ),
            ),
          ),
          LayoutBuilder(
            builder: (context, box) {
              final data = ref.watch(gameDataProvider).value;
              final attract = data?.attract;
              final road = background == null || attract == null
                  ? null
                  : creditRoad(attract, data!.world.road.innerWidth, box.biggest);
              final credits = Text(
                ref.tr(context, 'ui.menu.credits'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
              );
              final menu = Align(
                // Above the road, it hangs low enough to clear the demo's top row of turrets.
                alignment: road == null ? Alignment.center : const Alignment(0, 0.6),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        ref.tr(context, 'ui.menu.title'),
                        style: theme.textTheme.displaySmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          shadows: const [Shadow(blurRadius: 12)],
                        ),
                      ),
                      Text(
                        ref.tr(context, 'ui.menu.subtitle'),
                        style: theme.textTheme.titleLarge?.copyWith(color: Colors.white70),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: 220,
                        child: FilledButton.icon(
                          icon: const Icon(Icons.play_arrow),
                          label: Text(ref.tr(context, 'ui.menu.play')),
                          onPressed: () => _play(context, ref),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: 220,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                          icon: const Icon(Icons.settings),
                          label: Text(ref.tr(context, 'ui.menu.settings')),
                          onPressed: () => context.go('/settings'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: 220,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                          icon: const Icon(Icons.emoji_events_outlined),
                          label: Text(ref.tr(context, 'ui.records.menu')),
                          onPressed: () => context.go('/records'),
                        ),
                      ),
                      if (road == null) ...[const SizedBox(height: 20), credits],
                    ],
                  ),
                ),
              );
              if (road == null) return SafeArea(child: menu);
              // On the demo's road, with the menu centred above it. The menu
              // is narrow, so it stays centred over the road past a side inset.
              return Stack(
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: road.top,
                    child: SafeArea(left: false, right: false, bottom: false, child: menu),
                  ),
                  Positioned.fromRect(
                    rect: road,
                    child: Center(
                      child: FittedBox(fit: BoxFit.scaleDown, child: credits),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// Play: with a game in progress, asks whether to resume it or discard it
  /// (then a new game is chosen as usual); without, chooses a new game.
  Future<void> _play(BuildContext context, WidgetRef ref) async {
    final game = await ref.read(gameInProgressProvider.future);
    if (!context.mounted) return;
    if (game == null) {
      context.go('/mode');
      return;
    }
    final data = await ref.read(gameDataProvider.future);
    if (!context.mounted) return;
    final choice = await askResumeGame(context, data: data, game: game);
    if (!context.mounted) return;
    switch (choice) {
      case ResumeChoice.resume:
        context.go('/resume');
      case ResumeChoice.discard:
        await ref.read(gameInProgressProvider.notifier).clear();
        if (context.mounted) context.go('/mode');
      case null:
        break;
    }
  }
}
