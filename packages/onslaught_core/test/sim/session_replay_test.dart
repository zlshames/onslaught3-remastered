import 'dart:convert';
import 'dart:math';

import 'package:onslaught_core/onslaught_core.dart';
import 'package:test/test.dart';

import '../support/repo_data.dart';

/// A game in progress is saved as its config and command log and rebuilt by
/// re-simulating the log ([SessionReplay]); these tests pin that the rebuilt
/// game is the same game.
void main() {
  late GameData data;
  setUpAll(() => data = loadClassicData());

  const config = GameConfig(mapId: 'map1', mode: 'sandbox', difficulty: 'medium', seed: 7);

  /// Sends one scripted command (a mix of everything a player does) chosen
  /// by [rng]; rejected ones are part of the test too.
  void act(GameSession s, Random rng) {
    final colours = ['blue', 'green', 'red', 'yellow'];
    final turrets = s.turrets.toList();
    switch (rng.nextInt(9)) {
      case 0 || 1 || 2:
        s.enqueue(
          BuildTurret(
            colours[rng.nextInt(4)],
            40.0 + rng.nextInt(16) * 40,
            40.0 + rng.nextInt(10) * 40,
          ),
        );
      case 3 || 4 when turrets.isNotEmpty:
        final t = turrets[rng.nextInt(turrets.length)];
        s.enqueue(UpgradeTurret(t.uid, StatKind.values[rng.nextInt(3)].name));
      case 5:
        s.enqueue(const SendNextWave());
      case 6:
        s.enqueue(SetSpeed(rng.nextBool() ? 2 : 1));
      case 7 when turrets.isNotEmpty:
        final t = turrets[rng.nextInt(turrets.length)];
        s.enqueue(MoveTurret(t.uid, 40.0 + rng.nextInt(16) * 40, 40.0 + rng.nextInt(10) * 40));
      case 8 when turrets.length > 3:
        s.enqueue(SellTurret(turrets[rng.nextInt(turrets.length)].uid));
      default:
        s.enqueue(SetPaused(rng.nextBool()));
    }
  }

  /// Plays [ticks] steps from [s]'s current step, acting every 37 steps.
  void play(GameSession s, Random rng, int ticks) {
    final end = s.tick + ticks;
    while (s.tick < end && !s.gameOver) {
      if (s.tick % 37 == 0) act(s, rng);
      s.step();
    }
  }

  GameSession rebuild(GameSession from) {
    final copy = GameSession(data: data, config: from.config);
    SessionReplay(copy, from.commandLog.toList(), from.tick).runToEnd();
    return copy;
  }

  test('the session logs every command against the step it applies at', () {
    final s = GameSession(data: data, config: config);
    s.step();
    s.enqueue(const SendNextWave());
    s.enqueue(const SetSpeed(2));
    expect(s.commandLog.map((c) => (c.tick, c.command.type)), [(1, 'sendWave'), (1, 'speed')]);
    expect(() => (s.commandLog as List).add(s.commandLog.first), throwsUnsupportedError);
  });

  test('a game rebuilt from its log is the same game, and carries on the same', () {
    final live = GameSession(data: data, config: config);
    play(live, Random(1), 6000);
    expect(live.turrets, isNotEmpty, reason: 'the script built something');
    expect(live.commandLog.length, greaterThan(100));

    final copy = rebuild(live);
    expect(copy.tick, live.tick);
    expect(copy.stateHash(), live.stateHash());
    expect(
      jsonEncode([for (final c in copy.commandLog) c.toJson()]),
      jsonEncode([for (final c in live.commandLog) c.toJson()]),
      reason: 'the rebuilt session re-logs the commands, so it can be saved again',
    );

    // Both go on with the same further play and stay identical.
    play(live, Random(2), 1500);
    play(copy, Random(2), 1500);
    expect(copy.stateHash(), live.stateHash());
  });

  test('reading a special\'s state does not create it, so the live hash is the replayed one', () {
    // A Red's holding state hashes as soon as it exists; the rules create
    // it on the turret's first tick, which has not come in the step it was
    // built in.
    final live = GameSession(data: data, config: config);
    live.enqueue(const BuildTurret('red', 40, 40));
    live.step();
    final red = live.turrets.single;
    final before = live.stateHash();
    expect(red.stateOrNull<HoldingState>(HoldingSpecial.specialId), isNull);
    expect(red.specialState, isEmpty);
    expect(live.stateHash(), before);
    expect(rebuild(live).stateHash(), before);
    // The map readers see cannot be written to.
    expect(
      () => red.specialState[HoldingSpecial.specialId] = HoldingState(),
      throwsUnsupportedError,
    );
    expect(live.stateHash(), before);
    // Once the rules created it, the state is there to read and the hash
    // moved on in the replay too.
    for (var i = 0; i < 60 && red.specialState.isEmpty; i++) {
      live.step();
    }
    expect(red.stateOrNull<HoldingState>(HoldingSpecial.specialId), isNotNull);
    expect(live.stateHash(), isNot(before));
    expect(rebuild(live).stateHash(), live.stateHash());
  });

  test('commands sent after the last step stay pending in the rebuilt game', () {
    final live = GameSession(data: data, config: config);
    play(live, Random(3), 900);
    live.enqueue(const SetPaused(true));
    final copy = rebuild(live);
    live.step();
    copy.step();
    expect(live.clock.paused, isTrue);
    expect(copy.stateHash(), live.stateHash());
  });

  test('replay runs in slices and reports progress', () {
    final live = GameSession(data: data, config: config);
    play(live, Random(4), 2000);
    final copy = GameSession(data: data, config: config);
    final replay = SessionReplay(copy, live.commandLog.toList(), live.tick);
    var slices = 0;
    while (!replay.advance(500)) {
      slices++;
      expect(replay.done, slices * 500);
    }
    expect(slices, 3);
    expect(copy.stateHash(), live.stateHash());
  });

  test(
    'a different data set or seed does not rebuild the same game (the save checks the hash)',
    () {
      final live = GameSession(data: data, config: config);
      play(live, Random(5), 3000);
      final other = GameSession(
        data: data,
        config: const GameConfig(mapId: 'map1', mode: 'sandbox', difficulty: 'medium', seed: 8),
      );
      SessionReplay(other, live.commandLog.toList(), live.tick).runToEnd();
      expect(other.stateHash(), isNot(live.stateHash()));
    },
  );
}
