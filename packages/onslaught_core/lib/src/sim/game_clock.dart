/// Game time (`GameClock`): advances by each fixed step × the speed factor,
/// and is frozen while paused or after game over. All sim timers read this,
/// never wall-clock time.
class GameClock {
  GameClock({required this.tickHz});

  /// Fixed steps per real second.
  final int tickHz;

  /// Real milliseconds per fixed simulation step.
  double get stepMs => 1000 / tickHz;

  /// Sum of the speed factors of every running step. Time is derived from
  /// it rather than summed in ms so that whole seconds stay exact (1200
  /// steps at 60 Hz are exactly 20 000 ms, not 20 000.000…1).
  double _scaledSteps = 0;

  /// Game milliseconds elapsed.
  double get nowMs => _scaledSteps * 1000 / tickHz;

  /// Fixed steps taken (including paused ones).
  int ticks = 0;

  /// Game-speed factor (1 = 100 %).
  double speed = 1;
  bool paused = false;
  bool stopped = false;

  bool get running => !paused && !stopped;

  /// Advances one fixed step; returns the game-time delta in ms (0 when frozen).
  double tick() {
    ticks++;
    if (!running) return 0;
    final before = nowMs;
    _scaledSteps += speed;
    return nowMs - before;
  }
}
