import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../app/providers.dart';
import '../../services/assets/asset_pack.dart';
import 'flame/onslaught_flame_game.dart';
import 'game_view_model.dart';

/// The attract-mode demo behind the main menu (`GameManagerIntro`): its own
/// road over the whole stage, the menu's preset turrets and a tough creep
/// every 6 s, played forever without losing lives. Silent and untouchable;
/// nothing when the data has no demo or is still loading. On a tall screen
/// the demo covers it, upright, like a portrait game's map.
class AttractView extends ConsumerWidget {
  const AttractView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(gameDataProvider).value;
    final pack = ref.watch(assetPackProvider).value;
    if (data?.attract == null || pack == null) return const SizedBox.expand();
    return _AttractGame(data: data!, pack: pack, registry: ref.watch(rulesRegistryProvider));
  }
}

class _AttractGame extends StatefulWidget {
  const _AttractGame({required this.data, required this.pack, required this.registry});

  final GameData data;
  final AssetPack pack;
  final RulesRegistry registry;

  @override
  State<_AttractGame> createState() => _AttractGameState();
}

class _AttractGameState extends State<_AttractGame> {
  late final SessionGameViewModel _viewModel = SessionGameViewModel(
    GameSession(
      data: widget.data,
      config: const GameConfig.attractDemo(),
      registry: widget.registry,
    ),
  );
  late final OnslaughtFlameGame _game = OnslaughtFlameGame(
    viewModel: _viewModel,
    pack: widget.pack,
    drawBase: false,
    worldSize: Size(widget.data.attract!.stageWidth, widget.data.attract!.stageHeight),
    groundArt: widget.data.attract!.groundArt,
  );

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A tall screen is covered by the demo, like a portrait game's map.
    final size = MediaQuery.sizeOf(context);
    _game.setFrame(EdgeInsets.zero, fill: size.height > size.width);
    return IgnorePointer(
      child: ExcludeSemantics(child: GameWidget<OnslaughtFlameGame>(game: _game)),
    );
  }
}
