/// Tolerance for comparing summed 1/60 s steps with interval lengths: a
/// timer of `n` ms is due once `elapsed >= n - epsilonMs`, so rounding in
/// the summed step lengths never delays it by a step.
const double epsilonMs = 1e-6;
