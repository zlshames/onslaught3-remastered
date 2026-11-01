import '../math/geometry.dart';
import '../sim/sim_random.dart';

/// One waypoint jitter offset: `round(random × jitter − jitter / 2)`
/// (`AttackerEngine` ctor and `updateMove`). With the original jitter of 19
/// this is a whole number in −9 … +9.
double jitterOffset(SimRandom random, double jitter) =>
    roundHalfUp(random.nextDouble() * jitter - jitter / 2);

/// Sprite scale in percent for a creep whose wave size scale is [scaleBump]
/// (`AttackerEngine.onLoad`: `100 + (scale_bump − 1) × 6`).
double creepScalePercent(double scaleBump, double bumpPercent) =>
    100 + (scaleBump - 1) * bumpPercent;

/// Seconds shown on the next-wave clock: `ceil(ms / 100) / 10`, i.e. rounded
/// up to a tenth (`AttackerManager.update`).
double waveClockSeconds(double msUntilWave) => (msUntilWave / 100).ceil() * 100 / 1000;
