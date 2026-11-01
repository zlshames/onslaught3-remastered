/// The simulation's only source of randomness: a seeded xorshift128 generator
/// using 32-bit shifts and xors only, so it produces the same sequence on the
/// Dart VM, AOT and the web (where `int` is a JS double). `dart:math` Random
/// is not used because its sequence is not guaranteed across platforms.
class SimRandom {
  SimRandom(int seed) {
    // SplitMix-style scrambling of the seed into four non-zero words.
    var s = seed & _mask;
    int next() {
      s = (s + 0x9E3779B9) & _mask;
      var z = s;
      z = _mul32(z ^ (z >>> 16), 0x85EBCA6B);
      z = _mul32(z ^ (z >>> 13), 0xC2B2AE35);
      return (z ^ (z >>> 16)) & _mask;
    }

    _x = next();
    _y = next();
    _z = next();
    _w = next();
    if ((_x | _y | _z | _w) == 0) _w = 1;
  }

  static const int _mask = 0xFFFFFFFF;

  late int _x;
  late int _y;
  late int _z;
  late int _w;

  /// Number of values drawn so far (part of the state hash).
  int draws = 0;

  /// Next unsigned 32-bit value.
  int nextUint32() {
    draws++;
    var t = _x ^ ((_x << 11) & _mask);
    _x = _y;
    _y = _z;
    _z = _w;
    t = t ^ (t >>> 8);
    _w = (_w ^ (_w >>> 19) ^ t) & _mask;
    return _w;
  }

  /// Uniform double in [0, 1).
  double nextDouble() => nextUint32() / 4294967296.0;

  /// Uniform int in [0, max).
  int nextInt(int max) {
    if (max <= 0) throw ArgumentError.value(max, 'max', 'must be positive');
    return (nextDouble() * max).floor();
  }

  /// Uniform double in [-range, range].
  double jitter(double range) => (nextDouble() * 2 - 1) * range;

  /// The internal state, for snapshots and hashing.
  List<int> get state => [_x, _y, _z, _w];
}

/// 32-bit multiply that stays exact on the web by splitting into 16-bit halves.
int _mul32(int a, int b) {
  final aHi = (a >>> 16) & 0xFFFF;
  final aLo = a & 0xFFFF;
  final lo = aLo * b;
  final hi = (aHi * b) & 0xFFFF;
  return (lo + ((hi << 16) & 0xFFFFFFFF)) & 0xFFFFFFFF;
}
