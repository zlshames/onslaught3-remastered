import 'dart:async';

import 'package:onslaught_core/onslaught_core.dart';

import '../../services/haptics/haptics.dart';
import '../../services/logging/logging.dart';
import 'game_view_model.dart';

const Logger _log = Logger('haptics');

/// Vibrates for a running game's events ([hapticCueFor]) while [enabled]
/// (the haptics setting). A device without haptics never stops the game; a
/// failed vibration is logged in debug output.
class GameHaptics {
  GameHaptics({required this.viewModel, required this.sink, this.enabled = true}) {
    _sub = viewModel.events.listen(_onEvent);
  }

  final GameViewModel viewModel;
  final HapticSink sink;
  bool enabled;
  late final StreamSubscription<GameEvent> _sub;

  void _onEvent(GameEvent e) {
    if (!enabled) return;
    final cue = hapticCueFor(e);
    if (cue != null) {
      unawaited(
        sink
            .play(cue)
            .catchError(
              (Object e, StackTrace st) => _log.warning(
                'a vibration failed',
                error: e,
                stackTrace: st,
                fields: {'cue': cue},
              ),
            ),
      );
    }
  }

  Future<void> dispose() => _sub.cancel();
}
