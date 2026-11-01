import 'dart:convert';

/// 32-bit FNV-1a over the UTF-8 bytes of [text], computed with 16-bit split
/// multiplies so the result is identical on the VM and the web. Used for
/// fixture state hashes; not cryptographic.
int fnv1a32(String text) {
  var h = 0x811C9DC5;
  for (final b in utf8.encode(text)) {
    h ^= b;
    // h * 16777619 (0x01000193) mod 2^32.
    h = ((h * 0x0193) + (((h * 0x0100) & 0xFFFF) << 16)) & 0xFFFFFFFF;
  }
  return h;
}

/// [fnv1a32] of [text] as 8 lowercase hex digits (zero-padded).
String fnv1a32Hex(String text) =>
    fnv1a32(text).toRadixString(16).padLeft(0xFFFFFFFF.toRadixString(16).length, '0');

/// Canonical JSON (keys sorted, numbers to 9 significant digits) so equal
/// states always hash equally on every platform.
///
/// Written by hand rather than with `jsonEncode`, which prints numbers with
/// the platform's `toString`: a whole double is `10.0` on the VM but `10` on
/// the web, where `int` and `double` are one type. Numbers are therefore
/// written by value alone, never by type, in the form the VM's `jsonEncode`
/// gave the recorded fixture hashes: a whole number below 1e15 as an integer
/// (`3`, also for `3.0` and `-0.0`); anything else rounded to 9 significant
/// digits and printed as a VM double, so a value that rounds to a whole
/// number keeps its `.0` (`9.99999999999998` → `10.0`). Integers of 1e15 or
/// more are treated as doubles too (the web cannot tell them apart); none
/// occurs in simulation state.
///
/// Accepts maps with string keys, lists, strings, numbers, booleans and null.
String canonicalJson(Object? value) => (StringBuffer().._write(value)).toString();

extension on StringBuffer {
  void _write(Object? v) {
    switch (v) {
      case null || bool():
        write(v);
      case String():
        write(jsonEncode(v));
      case num():
        write(_number(v));
      case Map():
        final keys = v.keys.map((k) => k as String).toList()..sort();
        write('{');
        for (var i = 0; i < keys.length; i++) {
          if (i > 0) write(',');
          write(jsonEncode(keys[i]));
          write(':');
          _write(v[keys[i]]);
        }
        write('}');
      case List():
        write('[');
        for (var i = 0; i < v.length; i++) {
          if (i > 0) write(',');
          _write(v[i]);
        }
        write(']');
      default:
        throw ArgumentError.value(v, 'value', 'not canonical JSON (${v.runtimeType})');
    }
  }
}

/// [v] as written by [canonicalJson].
String _number(num v) {
  if (!v.isFinite) throw ArgumentError.value(v, 'value', 'not a finite number');
  final d = v.toDouble();
  if (d == d.roundToDouble() && d.abs() < 1e15) {
    // −0.0 is whole; the web would print it as `-0.0`.
    return d == 0 ? '0' : d.toInt().toString();
  }
  // 9 significant decimals: enough to catch drift, stable across platforms.
  final r = double.parse(d.toStringAsPrecision(9));
  // A whole double below 1e21 prints with `.0` on the VM (`toStringAsFixed`
  // gives its digits exactly on every platform); `toString` of anything else
  // is the same shortest form everywhere.
  if (r == r.roundToDouble() && r.abs() < 1e21) return '${r.toStringAsFixed(0)}.0';
  return r.toString();
}
