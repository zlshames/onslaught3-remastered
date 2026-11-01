// Deterministic sin, cos, atan and atan2 for the simulation.
//
// `dart:math` hands these to the host: the Dart VM calls the platform C
// library (glibc, Apple libm, MSVC), while dart2js and dart2wasm call the
// JavaScript engine's `Math` functions (fdlibm in some engines, other code in
// current V8). Results may differ in the last bit, and the simulation branches
// on them (snap tolerances, range checks), so a replay could diverge between
// platforms.
//
// These are ports of fdlibm 5.3 (Sun Microsystems, 1993), the library Java's
// `StrictMath` specifies, and match it bit for bit (test/math/det_math_test.dart):
// `__kernel_sin`, `__kernel_cos`, `__ieee754_rem_pio2`, `__kernel_rem_pio2`,
// `atan` and `__ieee754_atan2`. They use only IEEE 754 add, subtract, multiply
// and divide on doubles (each correctly rounded, so identical everywhere),
// comparisons, and integer bit operations on 32-bit words read through
// `ByteData`; no shift is applied to a negative int, which dart2js treats as
// unsigned 32-bit (masking with `&` is safe: its low bits are the same). Every
// `toInt()` truncates a finite value below 2^31, which every Dart target does
// identically. Accuracy: under 1 ulp.
//
// ====================================================
// Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.
//
// Developed at SunSoft, a Sun Microsystems, Inc. business.
// Permission to use, copy, modify, and distribute this
// software is freely granted, provided that this notice
// is preserved.
// ====================================================

import 'dart:typed_data';

final ByteData _bits = ByteData(8);

/// The high 32 bits of [x] (sign, exponent, top of the mantissa), signed.
int _hi(double x) {
  _bits.setFloat64(0, x, Endian.little);
  return _bits.getInt32(4, Endian.little);
}

/// The low 32 bits of [x]'s mantissa, unsigned.
int _lo(double x) {
  _bits.setFloat64(0, x, Endian.little);
  return _bits.getUint32(0, Endian.little);
}

/// The double whose high and low words are [hi] and [lo].
double _fromWords(int hi, int lo) {
  _bits.setUint32(4, hi & 0xFFFFFFFF, Endian.little);
  _bits.setUint32(0, lo & 0xFFFFFFFF, Endian.little);
  return _bits.getFloat64(0, Endian.little);
}

/// 2^[e] for a normal exponent (−1022 ≤ e ≤ 1023), built from its bits.
double _pow2(int e) => _fromWords((e + 1023) << 20, 0);

/// [x] × 2^[n], exact while the result stays normal (the only case
/// `__kernel_rem_pio2` needs).
double _scalbn(double x, int n) {
  var r = x;
  var k = n;
  while (k > 1023) {
    r *= _pow2(1023);
    k -= 1023;
  }
  while (k < -1022) {
    r *= _pow2(-1022);
    k += 1022;
  }
  return r * _pow2(k);
}

// ---------------------------------------------------------------------------
// Kernels on [−π/4, π/4]; [y] is the tail of the reduced argument x + y.

const double _s1 = -1.66666666666666324348e-01; // 0xBFC55555 55555549
const double _s2 = 8.33333333332248946124e-03; // 0x3F811111 1110F8A6
const double _s3 = -1.98412698298579493134e-04; // 0xBF2A01A0 19C161D5
const double _s4 = 2.75573137070700676789e-06; // 0x3EC71DE3 57B1FE7D
const double _s5 = -2.50507602534068634195e-08; // 0xBE5AE5E6 8A2B9CEB
const double _s6 = 1.58969099521155010221e-10; // 0x3DE5D93A 5ACFD57C

double _kernelSin(double x, double y, int iy) {
  final ix = _hi(x) & 0x7fffffff;
  if (ix < 0x3e400000) {
    // |x| < 2^-27: sin(x) rounds to x.
    if (x.truncateToDouble() == 0) return x;
  }
  final z = x * x;
  final v = z * x;
  final r = _s2 + z * (_s3 + z * (_s4 + z * (_s5 + z * _s6)));
  if (iy == 0) return x + v * (_s1 + z * r);
  return x - ((z * (0.5 * y - v * r) - y) - v * _s1);
}

const double _c1 = 4.16666666666666019037e-02; // 0x3FA55555 5555554C
const double _c2 = -1.38888888888741095749e-03; // 0xBF56C16C 16C15177
const double _c3 = 2.48015872894767294178e-05; // 0x3EFA01A0 19CB1590
const double _c4 = -2.75573143513906633035e-07; // 0xBE927E4F 809C52AD
const double _c5 = 2.08757232129817482790e-09; // 0x3E21EE9E BDB4B1C4
const double _c6 = -1.13596475577881948265e-11; // 0xBDA8FAE9 BE8838D4

double _kernelCos(double x, double y) {
  final ix = _hi(x) & 0x7fffffff;
  if (ix < 0x3e400000) {
    // |x| < 2^-27: cos(x) rounds to 1.
    if (x.truncateToDouble() == 0) return 1;
  }
  final z = x * x;
  final r = z * (_c1 + z * (_c2 + z * (_c3 + z * (_c4 + z * (_c5 + z * _c6)))));
  if (ix < 0x3FD33333) {
    // |x| < 0.3
    return 1 - (0.5 * z - (z * r - x * y));
  }
  final qx = ix > 0x3fe90000 ? 0.28125 : _fromWords(ix - 0x00200000, 0); // x/4
  final hz = 0.5 * z - qx;
  final a = 1 - qx;
  return a - (hz - (z * r - x * y));
}

// ---------------------------------------------------------------------------
// Argument reduction: x = n·π/2 + (y0 + y1), |y0 + y1| ≤ π/4.

const double _two24 = 1.67772160000000000000e+07; // 0x41700000 00000000
const double _twon24 = 5.96046447753906250000e-08; // 0x3E700000 00000000
const double _invpio2 = 6.36619772367581382433e-01; // 0x3FE45F30 6DC9C883
const double _pio2_1 = 1.57079632673412561417e+00; // 0x3FF921FB 54400000
const double _pio2_1t = 6.07710050650619224932e-11; // 0x3DD0B461 1A626331
const double _pio2_2 = 6.07710050630396597660e-11; // 0x3DD0B461 1A600000
const double _pio2_2t = 2.02226624879595063154e-21; // 0x3BA3198A 2E037073
const double _pio2_3 = 2.02226624871116645580e-21; // 0x3BA3198A 2E000000
const double _pio2_3t = 8.47842766036889956997e-32; // 0x397B839A 252049C1

/// High words of n·π/2 for n = 1..32, to spot cancellation.
const List<int> _npio2hw = [
  0x3FF921FB, 0x400921FB, 0x4012D97C, 0x401921FB, 0x401F6A7A, 0x4022D97C, //
  0x4025FDBB, 0x402921FB, 0x402C463A, 0x402F6A7A, 0x4031475C, 0x4032D97C,
  0x40346B9C, 0x4035FDBB, 0x40378FDB, 0x403921FB, 0x403AB41B, 0x403C463A,
  0x403DD85A, 0x403F6A7A, 0x40407E4C, 0x4041475C, 0x4042106C, 0x4042D97C,
  0x4043A28C, 0x40446B9C, 0x404534AC, 0x4045FDBB, 0x4046C6CB, 0x40478FDB,
  0x404858EB, 0x404921FB,
];

/// The reduced argument of [_remPio2]: x = n·π/2 + (y0 + y1).
typedef _Reduced = ({int n, double y0, double y1});

_Reduced _remPio2(double x) {
  final hx = _hi(x);
  final ix = hx & 0x7fffffff;
  if (ix <= 0x3fe921fb) return (n: 0, y0: x, y1: 0); // |x| ≤ π/4
  if (ix < 0x4002d97c) {
    // |x| < 3π/4: n = ±1.
    if (hx > 0) {
      var z = x - _pio2_1;
      if (ix != 0x3ff921fb) {
        final y0 = z - _pio2_1t;
        return (n: 1, y0: y0, y1: (z - y0) - _pio2_1t);
      }
      z -= _pio2_2; // near π/2: 33 more bits of π/2
      final y0 = z - _pio2_2t;
      return (n: 1, y0: y0, y1: (z - y0) - _pio2_2t);
    }
    var z = x + _pio2_1;
    if (ix != 0x3ff921fb) {
      final y0 = z + _pio2_1t;
      return (n: -1, y0: y0, y1: (z - y0) + _pio2_1t);
    }
    z += _pio2_2;
    final y0 = z + _pio2_2t;
    return (n: -1, y0: y0, y1: (z - y0) + _pio2_2t);
  }
  if (ix <= 0x413921fb) {
    // |x| ≤ 2^19·(π/2): medium size, Cody–Waite with up to three parts.
    final t = x.abs();
    final n = (t * _invpio2 + 0.5).toInt(); // truncation of a value below 2^20
    final fn = n.toDouble();
    var r = t - fn * _pio2_1;
    var w = fn * _pio2_1t; // first round, good to 85 bits
    double y0;
    if (n < 32 && ix != _npio2hw[n - 1]) {
      y0 = r - w; // quick check: no cancellation
    } else {
      final j = ix >> 20;
      y0 = r - w;
      var i = j - (((_hi(y0) & 0x7fffffff) >> 20) & 0x7ff);
      if (i > 16) {
        // second round, good to 118 bits
        var tt = r;
        w = fn * _pio2_2;
        r = tt - w;
        w = fn * _pio2_2t - ((tt - r) - w);
        y0 = r - w;
        i = j - (((_hi(y0) & 0x7fffffff) >> 20) & 0x7ff);
        if (i > 49) {
          // third round, good to 151 bits
          tt = r;
          w = fn * _pio2_3;
          r = tt - w;
          w = fn * _pio2_3t - ((tt - r) - w);
          y0 = r - w;
        }
      }
    }
    final y1 = (r - y0) - w;
    return hx < 0 ? (n: -n, y0: -y0, y1: -y1) : (n: n, y0: y0, y1: y1);
  }
  if (ix >= 0x7ff00000) return (n: 0, y0: x - x, y1: x - x); // inf or NaN
  // Large |x|: split |x| into three 24-bit pieces scaled by 2^-e0 and reduce
  // them against 2/π to as many bits as needed.
  final e0 = (ix >> 20) - 1046; // e0 = ilogb(|x|) − 23
  // fdlibm's `ix - (e0 << 20)`, as a product: e0 is −3…−1 for
  // 2^19·(π/2) < |x| < 2^23, and a negative int is never shifted.
  var z = _fromWords(ix - e0 * 0x100000, _lo(x));
  final tx = List<double>.filled(3, 0);
  for (var i = 0; i < 2; i++) {
    tx[i] = z.truncateToDouble();
    z = (z - tx[i]) * _two24;
  }
  tx[2] = z;
  var nx = 3;
  while (tx[nx - 1] == 0) {
    nx--;
  }
  final y = List<double>.filled(2, 0);
  final n = _kernelRemPio2(tx, y, e0, nx);
  return hx < 0 ? (n: -n, y0: -y[0], y1: -y[1]) : (n: n, y0: y[0], y1: y[1]);
}

/// 2/π in 24-bit chunks (enough for any double's exponent).
const List<int> _ipio2 = [
  0xA2F983, 0x6E4E44, 0x1529FC, 0x2757D1, 0xF534DD, 0xC0DB62, 0x95993C, 0x439041, //
  0xFE5163, 0xABDEBB, 0xC561B7, 0x246E3A, 0x424DD2, 0xE00649, 0x2EEA09, 0xD1921C,
  0xFE1DEB, 0x1CB129, 0xA73EE8, 0x8235F5, 0x2EBB44, 0x84E99C, 0x7026B4, 0x5F7E41,
  0x3991D6, 0x398353, 0x39F49C, 0x845F8B, 0xBDF928, 0x3B1FF8, 0x97FFDE, 0x05980F,
  0xEF2F11, 0x8B5A0A, 0x6D1F6D, 0x367ECF, 0x27CB09, 0xB74F46, 0x3F669E, 0x5FEA2D,
  0x7527BA, 0xC7EBE5, 0xF17B3D, 0x0739F7, 0x8A5292, 0xEA6BFB, 0x5FB11F, 0x8D5D08,
  0x560330, 0x46FC7B, 0x6BABF0, 0xCFBC20, 0x9AF436, 0x1DA9E3, 0x91615E, 0xE61B08,
  0x659985, 0x5F14A0, 0x68408D, 0xFFD880, 0x4D7327, 0x310606, 0x1556CA, 0x73A8C9,
  0x60E27B, 0xC08C6B,
];

/// π/2 in 24-bit pieces.
const List<double> _pio2 = [
  1.57079625129699707031e+00, // 0x3FF921FB 40000000
  7.54978941586159635335e-08, // 0x3E74442D 00000000
  5.39030252995776476554e-15, // 0x3CF84698 80000000
  3.28200341580791294123e-22, // 0x3B78CC51 60000000
  1.27065575308067607349e-29, // 0x39F01B83 80000000
  1.22933308981111328932e-36, // 0x387A2520 40000000
  2.73370053816464559624e-44, // 0x36E38222 80000000
  2.16741683877804819444e-51, // 0x3569F31D 00000000
];

/// `__kernel_rem_pio2` for double precision (`prec` = 2, 53 bits): writes the
/// reduced argument to [y] and returns n mod 8.
int _kernelRemPio2(List<double> x, List<double> y, int e0, int nx) {
  const jk = 4; // init_jk[2]
  const jp = jk;
  final iq = List<int>.filled(20, 0);
  final f = List<double>.filled(20, 0);
  final fq = List<double>.filled(20, 0);
  final q = List<double>.filled(20, 0);

  final jx = nx - 1;
  var jv = (e0 - 3) ~/ 24;
  if (jv < 0) jv = 0;
  var q0 = e0 - 24 * (jv + 1);

  // f[0..jx+jk] = _ipio2[jv-jx .. jv+jk]
  var j = jv - jx;
  final m = jx + jk;
  for (var i = 0; i <= m; i++, j++) {
    f[i] = j < 0 ? 0 : _ipio2[j].toDouble();
  }
  // q[0..jk] = x[0..jx] · f
  for (var i = 0; i <= jk; i++) {
    var fw = 0.0;
    for (j = 0; j <= jx; j++) {
      fw += x[j] * f[jx + i - j];
    }
    q[i] = fw;
  }

  var jz = jk;
  int n;
  int ih;
  double z;
  for (;;) {
    // distill q[] into iq[] in reverse order
    z = q[jz];
    for (var i = 0, jj = jz; jj > 0; i++, jj--) {
      final fw = (_twon24 * z).truncateToDouble();
      iq[i] = (z - _two24 * fw).toInt();
      z = q[jj - 1] + fw;
    }
    // compute n
    z = _scalbn(z, q0); // actual value of z
    z -= 8.0 * (z * 0.125).floorToDouble(); // trim off integer >= 8
    n = z.toInt();
    z -= n.toDouble();
    ih = 0;
    if (q0 > 0) {
      // need iq[jz-1] to determine n
      final i = iq[jz - 1] >> (24 - q0);
      n += i;
      iq[jz - 1] -= i << (24 - q0);
      ih = iq[jz - 1] >> (23 - q0);
    } else if (q0 == 0) {
      ih = iq[jz - 1] >> 23;
    } else if (z >= 0.5) {
      ih = 2;
    }

    if (ih > 0) {
      // q > 0.5
      n += 1;
      var carry = 0;
      for (var i = 0; i < jz; i++) {
        final jj = iq[i];
        if (carry == 0) {
          if (jj != 0) {
            carry = 1;
            iq[i] = 0x1000000 - jj;
          }
        } else {
          iq[i] = 0xffffff - jj;
        }
      }
      if (q0 > 0) {
        // rare case: chance is 1 in 12
        switch (q0) {
          case 1:
            iq[jz - 1] &= 0x7fffff;
          case 2:
            iq[jz - 1] &= 0x3fffff;
        }
      }
      if (ih == 2) {
        z = 1 - z;
        if (carry != 0) z -= _scalbn(1, q0);
      }
    }

    // check if recomputation is needed
    if (z == 0) {
      var jj = 0;
      for (var i = jz - 1; i >= jk; i--) {
        jj |= iq[i];
      }
      if (jj == 0) {
        // need recomputation
        var k = 1;
        while (iq[jk - k] == 0) {
          k++; // k = number of terms needed
        }
        for (var i = jz + 1; i <= jz + k; i++) {
          // add q[jz+1] to q[jz+k]
          f[jx + i] = _ipio2[jv + i].toDouble();
          var fw = 0.0;
          for (j = 0; j <= jx; j++) {
            fw += x[j] * f[jx + i - j];
          }
          q[i] = fw;
        }
        jz += k;
        continue;
      }
    }
    break;
  }

  // chop off zero terms
  if (z == 0) {
    jz -= 1;
    q0 -= 24;
    while (iq[jz] == 0) {
      jz--;
      q0 -= 24;
    }
  } else {
    // break z into 24-bit if necessary
    z = _scalbn(z, -q0);
    if (z >= _two24) {
      final fw = (_twon24 * z).truncateToDouble();
      iq[jz] = (z - _two24 * fw).toInt();
      jz += 1;
      q0 += 24;
      iq[jz] = fw.toInt();
    } else {
      iq[jz] = z.toInt();
    }
  }

  // convert integer "bit" chunk to floating-point value
  var fw = _scalbn(1, q0);
  for (var i = jz; i >= 0; i--) {
    q[i] = fw * iq[i].toDouble();
    fw *= _twon24;
  }

  // compute PIo2[0..jp] · q[jz..0]
  for (var i = jz; i >= 0; i--) {
    fw = 0.0;
    for (var k = 0; k <= jp && k <= jz - i; k++) {
      fw += _pio2[k] * q[i + k];
    }
    fq[jz - i] = fw;
  }

  // compress fq[] into y[]
  fw = 0.0;
  for (var i = jz; i >= 0; i--) {
    fw += fq[i];
  }
  y[0] = ih == 0 ? fw : -fw;
  fw = fq[0] - fw;
  for (var i = 1; i <= jz; i++) {
    fw += fq[i];
  }
  y[1] = ih == 0 ? fw : -fw;
  return n & 7;
}

// ---------------------------------------------------------------------------
// Public functions.

/// sin([x]) (radians), identical on every Dart platform.
double detSin(double x) {
  final ix = _hi(x) & 0x7fffffff;
  if (ix <= 0x3fe921fb) return _kernelSin(x, 0, 0); // |x| ~< π/4
  if (ix >= 0x7ff00000) return x - x; // NaN for inf or NaN
  final r = _remPio2(x);
  return switch (r.n & 3) {
    0 => _kernelSin(r.y0, r.y1, 1),
    1 => _kernelCos(r.y0, r.y1),
    2 => -_kernelSin(r.y0, r.y1, 1),
    _ => -_kernelCos(r.y0, r.y1),
  };
}

/// cos([x]) (radians), identical on every Dart platform.
double detCos(double x) {
  final ix = _hi(x) & 0x7fffffff;
  if (ix <= 0x3fe921fb) return _kernelCos(x, 0); // |x| ~< π/4
  if (ix >= 0x7ff00000) return x - x; // NaN for inf or NaN
  final r = _remPio2(x);
  return switch (r.n & 3) {
    0 => _kernelCos(r.y0, r.y1),
    1 => -_kernelSin(r.y0, r.y1, 1),
    2 => -_kernelCos(r.y0, r.y1),
    _ => _kernelSin(r.y0, r.y1, 1),
  };
}

const List<double> _atanhi = [
  4.63647609000806093515e-01, // atan(0.5)hi 0x3FDDAC67 0561BB4F
  7.85398163397448278999e-01, // atan(1.0)hi 0x3FE921FB 54442D18
  9.82793723247329054082e-01, // atan(1.5)hi 0x3FEF730B D281F69B
  1.57079632679489655800e+00, // atan(inf)hi 0x3FF921FB 54442D18
];

const List<double> _atanlo = [
  2.26987774529616870924e-17, // atan(0.5)lo 0x3C7A2B7F 222F65E2
  3.06161699786838301793e-17, // atan(1.0)lo 0x3C81A626 33145C07
  1.39033110312309984516e-17, // atan(1.5)lo 0x3C700788 7AF0CBBD
  6.12323399573676603587e-17, // atan(inf)lo 0x3C91A626 33145C07
];

const List<double> _aT = [
  3.33333333333329318027e-01, // 0x3FD55555 5555550D
  -1.99999999998764832476e-01, // 0xBFC99999 9998EBC4
  1.42857142725034663711e-01, // 0x3FC24924 920083FF
  -1.11111104054623557880e-01, // 0xBFBC71C6 FE231671
  9.09088713343650656196e-02, // 0x3FB745CD C54C206E
  -7.69187620504482999495e-02, // 0xBFB3B0F2 AF749A6D
  6.66107313738753120669e-02, // 0x3FB10D66 A0D03D51
  -5.83357013379057348645e-02, // 0xBFADDE2D 52DEFD9A
  4.97687799461593236017e-02, // 0x3FA97B4B 24760DEB
  -3.65315727442169155270e-02, // 0xBFA2B444 2C6A6C2F
  1.62858201153657823623e-02, // 0x3F90AD3A E322DA11
];

/// atan([x]) in [−π/2, π/2], identical on every Dart platform.
double detAtan(double x) {
  final hx = _hi(x);
  final ix = hx & 0x7fffffff;
  if (ix >= 0x44100000) {
    // |x| ≥ 2^66
    if (x.isNaN) return x + x;
    return hx > 0 ? _atanhi[3] + _atanlo[3] : -_atanhi[3] - _atanlo[3];
  }
  int id;
  var t = x;
  if (ix < 0x3fdc0000) {
    // |x| < 0.4375
    if (ix < 0x3e400000) return x; // |x| < 2^-27
    id = -1;
  } else {
    t = x.abs();
    if (ix < 0x3ff30000) {
      // |x| < 1.1875
      if (ix < 0x3fe60000) {
        // 7/16 ≤ |x| < 11/16
        id = 0;
        t = (2.0 * t - 1) / (2.0 + t);
      } else {
        // 11/16 ≤ |x| < 19/16
        id = 1;
        t = (t - 1) / (t + 1);
      }
    } else if (ix < 0x40038000) {
      // |x| < 2.4375
      id = 2;
      t = (t - 1.5) / (1 + 1.5 * t);
    } else {
      // 2.4375 ≤ |x| < 2^66
      id = 3;
      t = -1.0 / t;
    }
  }
  // end of argument reduction
  final z = t * t;
  final w = z * z;
  // break sum from i=0 to 10 aT[i]z^(i+1) into odd and even poly
  final s1 = z * (_aT[0] + w * (_aT[2] + w * (_aT[4] + w * (_aT[6] + w * (_aT[8] + w * _aT[10])))));
  final s2 = w * (_aT[1] + w * (_aT[3] + w * (_aT[5] + w * (_aT[7] + w * _aT[9]))));
  if (id < 0) return t - t * (s1 + s2);
  final r = _atanhi[id] - ((t * (s1 + s2) - _atanlo[id]) - t);
  return hx < 0 ? -r : r;
}

const double _tiny = 1.0e-300;
const double _piO4 = 7.8539816339744827900e-01; // 0x3FE921FB 54442D18
const double _piO2 = 1.5707963267948965580e+00; // 0x3FF921FB 54442D18
const double _pi = 3.1415926535897931160e+00; // 0x400921FB 54442D18
const double _piLo = 1.2246467991473531772e-16; // 0x3CA1A626 33145C07

/// atan2([y], [x]) in [−π, π], identical on every Dart platform. Argument
/// order as `dart:math`: the angle of the point (x, y).
double detAtan2(double y, double x) {
  if (x.isNaN || y.isNaN) return x + y;
  if (x == 1.0) return detAtan(y);
  final hx = _hi(x);
  final ix = hx & 0x7fffffff;
  final lx = _lo(x);
  final hy = _hi(y);
  final iy = hy & 0x7fffffff;
  final ly = _lo(y);
  final m = (hy < 0 ? 1 : 0) | (hx < 0 ? 2 : 0); // 2·sign(x) + sign(y)

  // when y = 0
  if ((iy | ly) == 0) {
    return switch (m) {
      0 || 1 => y, // atan(±0, +anything) = ±0
      2 => _pi + _tiny, // atan(+0, −anything) = π
      _ => -_pi - _tiny, // atan(−0, −anything) = −π
    };
  }
  // when x = 0
  if ((ix | lx) == 0) return hy < 0 ? -_piO2 - _tiny : _piO2 + _tiny;

  // when x is inf
  if (ix == 0x7ff00000) {
    if (iy == 0x7ff00000) {
      return switch (m) {
        0 => _piO4 + _tiny, // atan(+inf, +inf)
        1 => -_piO4 - _tiny, // atan(−inf, +inf)
        2 => 3.0 * _piO4 + _tiny, // atan(+inf, −inf)
        _ => -3.0 * _piO4 - _tiny, // atan(−inf, −inf)
      };
    }
    return switch (m) {
      0 => 0.0, // atan(+…, +inf)
      1 => -0.0, // atan(−…, +inf)
      2 => _pi + _tiny, // atan(+…, −inf)
      _ => -_pi - _tiny, // atan(−…, −inf)
    };
  }
  // when y is inf
  if (iy == 0x7ff00000) return hy < 0 ? -_piO2 - _tiny : _piO2 + _tiny;

  // compute y/x
  // fdlibm's `(iy - ix) >> 20`, as a division: the difference can be
  // negative, and dart2js shifts a negative int as an unsigned 32-bit value.
  // Dividing by 2^20 is exact and floor() is the arithmetic shift.
  final k = ((iy - ix) / 0x100000).floorToDouble();
  double z;
  if (k > 60) {
    // |y/x| > 2^60
    z = _piO2 + 0.5 * _piLo;
  } else if (hx < 0 && k < -60) {
    z = 0.0; // 0 > |y|/x > −2^-60
  } else {
    z = detAtan((y / x).abs()); // safe to do y/x
  }
  return switch (m) {
    0 => z, // atan(+, +)
    1 => -z, // atan(−, +)
    2 => _pi - (z - _piLo), // atan(+, −)
    _ => (z - _piLo) - _pi, // atan(−, −)
  };
}
