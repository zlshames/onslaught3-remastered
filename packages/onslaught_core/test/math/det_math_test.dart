import 'dart:math' as math;
import 'dart:typed_data';

import 'package:onslaught_core/src/math/det_math.dart';
import 'package:test/test.dart';

/// The bits of a double as 16 hex digits (two 32-bit words, so this also
/// runs on the web, where `int` cannot hold 64 bits).
String _hex(double d) {
  final b = ByteData(8)..setFloat64(0, d);
  String w(int v) => v.toRadixString(16).toUpperCase().padLeft(8, '0');
  return w(b.getUint32(0)) + w(b.getUint32(4));
}

double _fromHex(String h) =>
    (ByteData(8)
          ..setUint32(0, int.parse(h.substring(0, 8), radix: 16))
          ..setUint32(4, int.parse(h.substring(8), radix: 16)))
        .getFloat64(0);

/// The neighbouring double of finite [d] towards +∞ ([up]) or −∞.
double _next(double d, {required bool up}) {
  if (d == 0) return up ? _fromHex('0000000000000001') : _fromHex('8000000000000001');
  final b = ByteData(8)..setFloat64(0, d);
  final away = up == d > 0; // magnitude grows
  var hi = b.getUint32(0);
  var lo = b.getUint32(4);
  if (away) {
    lo = (lo + 1) & 0xFFFFFFFF;
    if (lo == 0) hi += 1;
  } else {
    if (lo == 0) hi -= 1;
    lo = (lo - 1) & 0xFFFFFFFF;
  }
  return (b
        ..setUint32(0, hi)
        ..setUint32(4, lo))
      .getFloat64(0);
}

/// Whether [a] is [b] or one of its neighbours (within 1 ulp).
bool _within1Ulp(double a, double b) =>
    a == b || a == _next(b, up: true) || a == _next(b, up: false) || (a.isNaN && b.isNaN);

/// (x, sin x, cos x) as bits, from Java's `StrictMath` (fdlibm 5.3 by
/// specification), so the port is checked against the reference exactly.
const _sinCos = [
  ('0000000000000000', '0000000000000000', '3FF0000000000000'),
  ('8000000000000000', '8000000000000000', '3FF0000000000000'),
  ('01A56E1FC2F8F359', '01A56E1FC2F8F359', '3FF0000000000000'),
  ('3E112E0BE826D695', '3E112E0BE826D695', '3FF0000000000000'),
  ('3FE0000000000000', '3FDEAEE8744B05F0', '3FEC1528065B7D50'),
  ('3FE921FB54442D18', '3FE6A09E667F3BCC', '3FE6A09E667F3BCD'),
  ('3FF0000000000000', '3FEAED548F090CEE', '3FE14A280FB5068C'),
  ('3FF921FB54442D18', '3FF0000000000000', '3C91A62633145C07'),
  ('4000000000000000', '3FED18F6EAD1B446', 'BFDAA22657537205'),
  ('4002D97C7F3321D2', '3FE6A09E667F3BCD', 'BFE6A09E667F3BCC'),
  ('4008000000000000', '3FC210386DB6D55B', 'BFEFAE04BE85E5D2'),
  ('400921FB54442D18', '3CA1A62633145C07', 'BFF0000000000000'),
  ('4010000000000000', 'BFE837B9DDDC1EAE', 'BFE4EAA606DB24C1'),
  ('401921FB54442D18', 'BCB1A62633145C07', '3FF0000000000000'),
  ('4024000000000000', 'BFE1689EF5F34F52', 'BFEAD9AC890C6B1F'),
  ('4059000000000000', 'BFE03425B78C4DB8', '3FEB981DBF665FDF'),
  ('BFE0000000000000', 'BFDEAEE8744B05F0', '3FEC1528065B7D50'),
  ('BFF0000000000000', 'BFEAED548F090CEE', '3FE14A280FB5068C'),
  ('BFFD524FE24F89F2', 'BFEEE8DD4748BF15', 'BFD0907DC1930692'),
  ('C004000000000000', 'BFE326AF0DCFCAB0', 'BFE9A2F7EF858B7D'),
  ('C00921FB54442D18', 'BCA1A62633145C07', 'BFF0000000000000'),
  ('C059000000000000', '3FE03425B78C4DB8', '3FEB981DBF665FDF'),
  ('412E848000000000', 'BFD6664B2568D867', '3FEDF9DF9906D32C'),
  ('412921FC00000000', '3FD51102EFAD6266', '3FEE377C09C4CCE7'),
  ('41CDCD6500000000', '3FE1778CAE83C69B', '3FEACFF8C7364234'),
  ('4480F0CF064DD592', 'BFEB453AB76BF397', '3FE0BE2CEF01C8F4'),
  ('FE37E43C8800759C', '3FEA2C16B010E385', 'BFE2699022ADC4C1'),
  ('7FEFFFFFFFFFFFFF', '3F7452FC98B34E97', 'BFEFFFE62ECFAB75'),
  ('3FE0C152382D7365', '3FDFFFFFFFFFFFFF', '3FEBB67AE8584CAB'),
  ('3FF0C152382D7365', '3FEBB67AE8584CAA', '3FE0000000000001'),
  ('3F91DF46A2529D39', '3F91DF0B2B89DD1E', '3FEFFEC097F5AF8A'),
  ('BFF921FB54442D18', 'BFF0000000000000', '3C91A62633145C07'),
  ('4000C152382D7365', '3FEBB67AE8584CAB', 'BFDFFFFFFFFFFFFC'),
  ('4012D97C7F3321D2', 'BFF0000000000000', 'BCAA79394C9E8A0A'),
  ('4015FDBBE9BBA775', 'BFE6A09E667F3BCE', '3FE6A09E667F3BCB'),
];

/// (y, x, atan2(y, x)) as bits, from `StrictMath.atan2`.
const _atan2 = [
  ('0000000000000000', '3FF0000000000000', '0000000000000000'),
  ('3FF0000000000000', '0000000000000000', '3FF921FB54442D18'),
  ('0000000000000000', 'BFF0000000000000', '400921FB54442D18'),
  ('BFF0000000000000', '0000000000000000', 'BFF921FB54442D18'),
  ('3FF0000000000000', '3FF0000000000000', '3FE921FB54442D18'),
  ('BFF0000000000000', 'BFF0000000000000', 'C002D97C7F3321D2'),
  ('3FF0000000000000', 'BFF0000000000000', '4002D97C7F3321D2'),
  ('BFF0000000000000', '3FF0000000000000', 'BFE921FB54442D18'),
  ('8000000000000000', '3FF0000000000000', '8000000000000000'),
  ('0000000000000000', 'BFF0000000000000', '400921FB54442D18'),
  ('8000000000000000', 'BFF0000000000000', 'C00921FB54442D18'),
  ('0000000000000000', '0000000000000000', '0000000000000000'),
  ('8000000000000000', '0000000000000000', '8000000000000000'),
  ('0000000000000000', '8000000000000000', '400921FB54442D18'),
  ('8000000000000000', '8000000000000000', 'C00921FB54442D18'),
  ('C043B0A3D70A3D70', 'C04C547AE147AE19', 'C00446126A426BB7'),
  ('4043B0A3D70A3D71', '404C547AE147AE14', '3FE36FA3A807058A'),
  ('4008000000000000', '4010000000000000', '3FE4978FA3269EE1'),
  ('C010000000000000', '4008000000000000', 'BFEDAC670561BB4F'),
  ('01A56E1FC2F8F359', '7E37E43C8800759C', '0000000000000000'),
  ('7E37E43C8800759C', '01A56E1FC2F8F359', '3FF921FB54442D18'),
  ('FE37E43C8800759C', '81A56E1FC2F8F359', 'BFF921FB54442D19'),
  ('01A56E1FC2F8F359', 'FE37E43C8800759C', '400921FB54442D18'),
  ('3FE0000000000000', '3FE6666666666666', '3FE3D91573350661'),
  ('4003333333333333', '3FF0000000000000', '3FF2D0EAD6066396'),
  ('3FF0000000000000', '4003800000000000', '3FD8EA90AF03CB11'),
  ('3FF0000000000000', '4415AF1D78B58C40', '3BC79CA10C924223'),
  ('7FF0000000000000', '3FF0000000000000', '3FF921FB54442D18'),
  ('3FF0000000000000', '7FF0000000000000', '0000000000000000'),
  ('3FF0000000000000', 'FFF0000000000000', '400921FB54442D18'),
  ('7FF0000000000000', 'FFF0000000000000', '4002D97C7F3321D2'),
  ('FFF0000000000000', '7FF0000000000000', 'BFE921FB54442D18'),
  ('C06A8C28F5C28F5C', 'C04C30A3D70A3D71', 'BFFD48D2831DA129'),
  ('405E200000000000', 'BFD0000000000000', '3FF92A7ACB801DBB'),
  ('BF50624DD2F1A9FC', 'C086800000000000', 'C00921FA99DA513B'),
];

void main() {
  group('det_math matches fdlibm bit for bit', () {
    for (final (x, s, c) in _sinCos) {
      test('sin and cos of ${_fromHex(x)}', () {
        expect(_hex(detSin(_fromHex(x))), s);
        expect(_hex(detCos(_fromHex(x))), c);
      });
    }
    for (final (y, x, r) in _atan2) {
      test('atan2(${_fromHex(y)}, ${_fromHex(x)})', () {
        expect(_hex(detAtan2(_fromHex(y), _fromHex(x))), r);
      });
    }
  });

  // Large arguments with a negative exponent offset (e0 = ilogb(|x|) − 23
  // is −3…−1 for 2^19·(π/2) < |x| < 2^23); recorded from the VM before
  // det_math stopped shifting e0, and equal to the host libm's.
  group('large arguments below 2^23', () {
    const cases = [
      ('4130000000000000', '3FD526CCB2FC8656', '3FEE33ADA92FE2AE'), // 2^20
      ('C130000000000000', 'BFD526CCB2FC8656', '3FEE33ADA92FE2AE'), // -2^20
      ('4132D687E4189375', 'BFDFAFCC6A382E25', 'BFEBCD7B4E942040'), // 1234567.891
      ('414B333333333333', 'BFDFA0A012918500', 'BFEBD1CCAEF6A67E'), // 3565158.4
      ('4158CBA810000000', '3FEC07E084EFF4C7', '3FDEDF54427EE1D6'), // 6500000.25
      ('415FFFFFE0000000', '3FE9F919943E1642', 'BFE2B1386C2356F5'), // 8388607.5
    ];
    for (final (x, s, c) in cases) {
      test('sin and cos of ${_fromHex(x)}', () {
        expect(_hex(detSin(_fromHex(x))), s);
        expect(_hex(detCos(_fromHex(x))), c);
      });
    }
  });

  test('special values', () {
    for (final f in [detSin, detCos]) {
      expect(f(double.nan).isNaN, isTrue);
      expect(f(double.infinity).isNaN, isTrue);
      expect(f(double.negativeInfinity).isNaN, isTrue);
    }
    expect(detAtan2(double.nan, 1).isNaN, isTrue);
    expect(detAtan2(1, double.nan).isNaN, isTrue);
    expect(detAtan(double.nan).isNaN, isTrue);
    expect(detAtan(double.infinity), math.pi / 2);
    expect(detAtan(double.negativeInfinity), -math.pi / 2);
  });

  // dart:math is the host's libm on the VM and the JavaScript engine on the
  // web; neither is fdlibm, but every good libm is within 1 ulp of the truth.
  test('within 1 ulp of dart:math on a sweep of angles and points', () {
    final misses = <String>[];
    final rnd = math.Random(7);
    final xs = [
      for (var i = -2880; i <= 2880; i++) i * math.pi / 720,
      for (var i = -720; i <= 720; i++) i * math.pi / 180,
      for (var i = 0; i < 4000; i++) (rnd.nextDouble() * 2 - 1) * 1000,
      for (var i = 0; i < 500; i++) (rnd.nextDouble() * 2 - 1) * 1e12,
    ];
    for (final x in xs) {
      if (!_within1Ulp(detSin(x), math.sin(x))) misses.add('sin($x)');
      if (!_within1Ulp(detCos(x), math.cos(x))) misses.add('cos($x)');
    }
    for (var i = 0; i < 4000; i++) {
      final y = (rnd.nextDouble() * 2 - 1) * 720;
      final x = (rnd.nextDouble() * 2 - 1) * 720;
      if (!_within1Ulp(detAtan2(y, x), math.atan2(y, x))) misses.add('atan2($y, $x)');
    }
    for (var y = -720; y <= 720; y += 9) {
      for (var x = -720; x <= 720; x += 13) {
        final r = detAtan2(y.toDouble(), x.toDouble());
        if (!_within1Ulp(r, math.atan2(y, x))) misses.add('atan2($y, $x)');
      }
    }
    expect(misses, isEmpty);
  });
}
