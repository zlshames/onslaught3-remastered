import 'package:onslaught_core/onslaught_core.dart';
import 'package:test/test.dart';

/// [pickRandom] draws through [SimRandom.nextInt] (audit D10). The draw
/// sequence must be exactly the one the hand-written
/// `floor(nextDouble() × length)` gave, including the draw the original
/// spends on an empty list, or every seeded game would change.
void main() {
  /// The implementation before the change, kept as the reference.
  List<T> reference<T>(SimRandom random, List<T> list, int n) {
    if (n <= 0) return [];
    if (list.length == n) return List.of(list);
    int draw() => (random.nextDouble() * list.length).floor();
    if (n == 1) {
      final i = draw();
      return list.isEmpty ? [] : [list[i]];
    }
    if (list.length < n) return List.of(list);
    if (n == 2) {
      var i = 0;
      var j = 0;
      while (i == j) {
        i = draw();
        j = draw();
      }
      return [list[i], list[j]];
    }
    final rest = List.of(list);
    return [for (var k = 0; k < n; k++) rest.removeAt((random.nextDouble() * rest.length).floor())];
  }

  test('same picks, same draws and same generator state as before', () {
    for (var seed = 0; seed < 200; seed++) {
      for (var length = 0; length <= 7; length++) {
        for (var n = 0; n <= 4; n++) {
          final list = [for (var i = 0; i < length; i++) i];
          final a = SimRandom(seed);
          final b = SimRandom(seed);
          // Several picks in a row, so a drift in draws would show.
          for (var round = 0; round < 3; round++) {
            expect(
              pickRandom(a, list, n),
              reference(b, list, n),
              reason: 'seed $seed, length $length, n $n, round $round',
            );
          }
          expect(a.draws, b.draws, reason: 'seed $seed, length $length, n $n');
          expect(a.state, b.state, reason: 'seed $seed, length $length, n $n');
        }
      }
    }
  });

  test('one from an empty list spends a draw and picks nothing', () {
    final r = SimRandom(1);
    expect(pickRandom(r, const <int>[], 1), isEmpty);
    expect(r.draws, 1);
  });
}
