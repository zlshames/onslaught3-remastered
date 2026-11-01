/// Turns real frame time into whole fixed simulation steps, so the
/// simulation stays deterministic whatever the frame rate: frame time
/// accumulates and each full [stepSeconds] of it runs one step. At most
/// [maxStepsPerFrame] run per frame; after a frame that hits the cap the
/// rest of the backlog is dropped, so a long stall cannot freeze the UI.
class FixedStepDriver {
  FixedStepDriver({required this.stepSeconds, required this.maxStepsPerFrame});

  /// Real seconds per simulation step (1 / tick rate).
  final double stepSeconds;
  final int maxStepsPerFrame;

  double _accumulator = 0;

  /// Adds [dtSeconds] of frame time and calls [step] once per whole step
  /// due; returns how many ran.
  int advance(double dtSeconds, void Function() step) {
    _accumulator += dtSeconds;
    var steps = 0;
    while (_accumulator >= stepSeconds && steps < maxStepsPerFrame) {
      _accumulator -= stepSeconds;
      steps++;
      step();
    }
    if (steps == maxStepsPerFrame) _accumulator = 0;
    return steps;
  }
}
