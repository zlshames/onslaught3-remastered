import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/features/game/game_event_log.dart';
import 'package:onslaught3_remastered/services/logging/log_level.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../support/log_capture.dart';

/// The game's notable events reach the log; the many-per-second ones do not.
void main() {
  test('builds, upgrades, sales, moves and waves are logged at debug with the step', () async {
    final log = LogCapture.install();
    logGameEvent(
      const TurretBuilt(10, uid: 1, turret: 'blue', x: 120.4, y: 80, cost: 50, cash: 50),
    );
    logGameEvent(const TurretBuilt(11, uid: 2, turret: 'red', x: 200, y: 90, cost: 60, cash: 0));
    logGameEvent(const TurretUpgraded(20, uid: 1, stat: 'damage', level: 2, cost: 30, cash: 20));
    logGameEvent(const TurretSold(30, uid: 2, refund: 45, cash: 65));
    logGameEvent(const TurretMoved(35, uid: 1, x: 300, y: 100, cost: 10, cash: 55));
    logGameEvent(
      const WaveStarted(
        40,
        wave: 3,
        size: 12,
        creepType: 2,
        hp: 140,
        bounty: 4,
        speed: 1,
        early: false,
      ),
    );
    logGameEvent(const BaseHit(50, uid: 9, lives: 19));
    expect(
      await log.records(),
      [
        'DEBUG [game] turret built tick=10 uid=1 turret=blue x=120 y=80 cost=50.0',
        'DEBUG [game] turret built tick=11 uid=2 turret=red x=200 y=90 cost=60.0',
        'DEBUG [game] turret upgraded tick=20 uid=1 stat=damage level=2 cost=30.0 cash=20.0',
        'DEBUG [game] turret sold tick=30 uid=2 refund=45 cash=65.0',
        'DEBUG [game] turret moved tick=35 uid=1 x=300 y=100 cost=10.0 cash=55.0',
        'DEBUG [game] wave started tick=40 wave=3 size=12 creepType=2 hp=140.0',
        'DEBUG [game] base hit tick=50 lives=19',
      ].map(endsWith).toList(),
    );
  });

  test('results and unlocks are logged at info', () async {
    final log = LogCapture.install();
    logGameEvent(const WeaponUnlocked(5, turret: 'green', kills: 100));
    logGameEvent(const GameWon(9, wave: 20, kills: 300, shots: 900, spent: 4000, score: 7000));
    logGameEvent(const FreeplayStarted(9, wave: 20, nextWaveMs: 5000));
    logGameEvent(const GameOver(99, wave: 31, kills: 500, shots: 1500, spent: 9000, score: 9900));
    final records = await log.records();
    expect(records, hasLength(4));
    expect(records, everyElement(contains('INFO  [game]')));
    expect(records[0], endsWith('weapon unlocked tick=5 turret=green kills=100'));
    expect(records[3], contains('game over tick=99 wave=31 kills=500 score=9900.0 reason='));
  });

  test('shots, kills and spawns are not logged; below the level nothing is', () async {
    final log = LogCapture.install();
    logGameEvent(
      const CreepKilled(1, uid: 1, turret: null, bounty: 1, cash: 0, kills: 1, x: 0, y: 0),
    );
    logGameEvent(const TurretFired(1, uid: 1, projectile: 'shell', target: 2));
    expect(await log.records(), isEmpty);
    log.level = LogLevel.info;
    logGameEvent(const TurretSold(2, uid: 1, refund: 5, cash: 5));
    expect(await log.records(), isEmpty);
  });
}
