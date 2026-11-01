import 'package:onslaught_core/onslaught_core.dart';
import 'package:test/test.dart';

void main() {
  test('FNV-1a 32 known vectors', () {
    expect(fnv1a32(''), 0x811C9DC5);
    expect(fnv1a32('a'), 0xE40C292C);
    expect(fnv1a32('foobar'), 0xBF9CF968);
  });

  test('canonical JSON sorts keys and normalises numbers', () {
    expect(
      canonicalJson({
        'b': 1.0,
        'a': [2.5, 3],
      }),
      '{"a":[2.5,3],"b":1}',
    );
    expect(canonicalJson({'x': 0.1 + 0.2}), '{"x":0.3}');
  });

  // These also run in the browser (tool/web_regression.dart), where int and
  // double are one type and `jsonEncode` would print 10.0 as 10.
  test('canonical JSON prints numbers the same on every platform', () {
    // Whole and below 1e15 before rounding: an integer, however it is typed.
    expect(canonicalJson([3, 3.0, -0.0, 1e14]), '[3,3,0,100000000000000]');
    // Whole only after the 9-digit rounding: the VM's `.0` form, which the
    // recorded fixture hashes contain.
    expect(canonicalJson([9.99999999999998, -107.99999999999994]), '[10.0,-108.0]');
    expect(canonicalJson(123456789012.5), '123456789000.0');
    expect(
      // From 1e15 on, whole numbers are written as doubles, ints included.
      canonicalJson([1e15, 1000000000000000, 2.5e21, 1.5e-7, -0.000123456789123]),
      '[1000000000000000.0,1000000000000000.0,2.5e+21,1.5e-7,-0.000123456789]',
    );
    expect(canonicalJson({'s': 'a"b', 'b': true, 'n': null}), r'{"b":true,"n":null,"s":"a\"b"}');
  });

  test('canonical JSON rejects what it cannot write identically', () {
    expect(() => canonicalJson(double.nan), throwsArgumentError);
    expect(() => canonicalJson(double.infinity), throwsArgumentError);
    expect(() => canonicalJson(Object()), throwsArgumentError);
  });
}
