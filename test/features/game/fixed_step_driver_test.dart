import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/features/game/fixed_step_driver.dart';

void main() {
  FixedStepDriver driver() => FixedStepDriver(stepSeconds: 0.25, maxStepsPerFrame: 3);

  test('runs one step per whole step of frame time and carries the rest', () {
    final d = driver();
    var steps = 0;
    void step() => steps++;
    expect(d.advance(0.2, step), 0);
    expect(d.advance(0.1, step), 1); // 0.3: one step, 0.05 left
    expect(d.advance(0.45, step), 2); // 0.5: two steps
    expect(steps, 3);
  });

  test('a stall runs at most the cap, then drops the backlog', () {
    final d = driver();
    var steps = 0;
    expect(d.advance(10, () => steps++), 3);
    expect(d.advance(0, () => steps++), 0);
    expect(d.advance(0.25, () => steps++), 1);
    expect(steps, 4);
  });
}
