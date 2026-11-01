import 'dart:async';

import 'package:onslaught_core/onslaught_core.dart';

import '../../services/audio/audio_cues.dart';
import '../../services/audio/audio_service.dart';
import '../../services/logging/logging.dart';
import 'game_view_model.dart';

const Logger _log = Logger('audio');

/// Plays the original's sounds for a running game: listens to the view
/// model's events and turns each into its cues ([audioCuesFor]). A failing
/// audio backend never stops the game; it is reported once in debug logs.
class GameAudio {
  GameAudio({required this.viewModel, required this.audio}) {
    _sub = viewModel.events.listen(_onEvent);
  }

  final GameViewModel viewModel;
  final AudioService audio;
  late final StreamSubscription<GameEvent> _sub;
  bool _reported = false;

  ({TurretDef def, Vec2 position})? _turret(int uid) {
    for (final t in viewModel.world.turrets) {
      if (t.uid == uid) return (def: t.def, position: t.position);
    }
    return null;
  }

  void _onEvent(GameEvent e) {
    for (final cue in audioCuesFor(e, _turret)) {
      unawaited(
        audio
            .play(cue.event, x: cue.x)
            .then<void>(
              (_) {},
              onError: (Object error, StackTrace stack) {
                if (_reported) return;
                _reported = true;
                _log.warning(
                  'audio unavailable; later failures in this game are not logged',
                  error: error,
                  stackTrace: stack,
                  fields: {'cue': cue.event},
                );
              },
            ),
      );
    }
  }

  Future<void> dispose() => _sub.cancel();
}
