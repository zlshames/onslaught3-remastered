import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/features/game/game_audio.dart';
import 'package:onslaught3_remastered/services/assets/asset_pack.dart';
import 'package:onslaught3_remastered/services/audio/audio_cues.dart';
import 'package:onslaught3_remastered/services/audio/audio_service.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../support/fake_game_view_model.dart';
import '../support/test_data.dart';

class _Sink implements AudioSink {
  final played = <String>[];
  @override
  Future<void> play(String bundlePath, {required double volume, required double pan}) async =>
      played.add(bundlePath);
}

class _FailingSink implements AudioSink {
  @override
  Future<void> play(String bundlePath, {required double volume, required double pan}) =>
      Future.error(StateError('no audio plugin'));
}

class _Pack implements AssetPack {
  @override
  String get id => 'p';
  @override
  Future<void> load() async {}
  @override
  Set<String> get spriteIds => const {};
  @override
  Set<String> get soundIds => const {};
  @override
  SpriteAsset? sprite(String id) => null;
  @override
  List<String>? sound(String id) => [id];
  @override
  PackTheme? get theme => null;
  @override
  GroundSource? ground(String id) => null;
}

void main() {
  late GameData data;
  setUpAll(() => data = loadTestGameData());

  ({TurretDef def, Vec2 position})? blueAt(int uid) =>
      uid == 7 ? (def: data.turrets['blue']!, position: const Vec2(360, 100)) : null;

  List<String> cues(GameEvent e) => [for (final c in audioCuesFor(e, blueAt)) c.event];

  /// One of every event type (the mapping's switch is exhaustive over the
  /// sealed class; this list keeps the data check complete).
  List<GameEvent> everyEvent() => [
    const SessionStarted(
      0,
      map: 'map1',
      mode: 'normal',
      difficulty: 'easy',
      profile: 'classic',
      seed: 1,
      cash: 30,
      lives: 10,
    ),
    const PausedChanged(0, paused: true),
    const PausedChanged(0, paused: false),
    const SpeedChanged(0, speed: 2),
    const CommandRejected(0, command: 'upgrade', reason: 'cannotAfford'),
    const WaveStarted(
      0,
      wave: 1,
      size: 10,
      creepType: 0,
      hp: 13,
      bounty: 1,
      speed: 60,
      early: false,
    ),
    const CreepSpawned(0, uid: 1, wave: 1, x: 0, y: 0),
    const CreepKilled(0, uid: 1, turret: 7, bounty: 1, cash: 31, kills: 1, x: 10, y: 10),
    for (var lives = 0; lives <= 5; lives++) BaseHit(0, uid: 1, lives: lives),
    const GameOver(0, wave: 1, kills: 0, shots: 0, spent: 0, score: 0),
    const TurretBuilt(0, uid: 7, turret: 'blue', x: 360, y: 100, cost: 10, cash: 20),
    for (final stat in StatKind.values)
      TurretUpgraded(0, uid: 7, stat: stat.name, level: 1, cost: 20, cash: 0),
    const TurretSold(0, uid: 7, refund: 7, cash: 7),
    const TurretMoved(0, uid: 7, x: 1, y: 1, cost: 500, cash: 0),
    const TargetModeChanged(0, uid: 7, mode: 'far', lockOff: false),
    const TurretFired(0, uid: 7, projectile: 'shell-1', target: 1),
    for (final stage in ['warning', 'active', 'ended']) FreakoutChanged(0, uid: 7, stage: stage),
    const WeaponUnlocked(0, turret: 'range-up', kills: 300),
    const ComboFired(0, uid: 7, combo: 'clusterbomb', helpers: [8], projectile: 'cluster-bomb'),
    const ComboFired(
      0,
      uid: 7,
      combo: 'blackhole',
      helpers: [8],
      projectile: 'black-hole',
      sound: 'black-hole',
    ),
    for (final c in data.combos.values)
      if (c.sound != null)
        BlastStarted(0, uid: 9, blast: c.blast ?? 'x', x: 1, y: 1, damage: 1, sound: c.sound),
    const BlastStarted(0, uid: 9, blast: 'cluster-sparks', x: 1, y: 1, damage: 1, sound: 'tazer'),
    const BlackHoleOpened(0, uid: 9, x: 1, y: 1),
    const CreepSwallowed(0, uid: 1, hole: 9),
    for (final sound in ['fusion-low', 'fusion-med', 'fusion-high', 'fusion-max'])
      TurretFired(0, uid: 7, projectile: 'spark', target: 1, sound: sound),
    const TurretJoined(0, uid: 7, target: 8, joined: true, joins: [8]),
    const CombonlyChanged(0, uid: 7, stage: 'chosen', colour: 'red', recipe: 'nuke'),
    const TurretConsumed(0, uid: 8, into: 7),
  ];

  test('every cue names an audio.json event that has clips', () {
    for (final e in everyEvent()) {
      for (final c in audioCuesFor(e, blueAt)) {
        expect(data.audio.events.containsKey(c.event), isTrue, reason: '${e.type} → ${c.event}');
        expect(data.audio.events[c.event], isNotEmpty, reason: c.event);
      }
    }
  });

  test('shots play the turret fire sound at its x; pooling helpers are silent', () {
    final shot = audioCuesFor(
      const TurretFired(0, uid: 7, projectile: 'shell-1', target: 1),
      blueAt,
    );
    expect(shot, [(event: 'cannon', x: 360.0)]);
    expect(
      cues(const TurretFired(0, uid: 7, projectile: 'x', target: null, silent: true)),
      isEmpty,
    );
    expect(cues(const TurretFired(0, uid: 99, projectile: 'x', target: 1)), isEmpty);
    for (final (id, sound) in [('green', 'laser'), ('red', 'rocket'), ('yellow', 'tazer')]) {
      expect(data.turrets[id]!.fireSound, sound);
    }
  });

  test('a Fusion discharge sounds by its tier; joins and Combonly changes are silent', () {
    expect(
      audioCuesFor(
        const TurretFired(0, uid: 7, projectile: 'spark', target: 1, sound: 'fusion-max'),
        blueAt,
      ),
      [(event: 'fusion-max', x: 360.0)],
    );
    expect(cues(const TurretJoined(0, uid: 7, target: 8, joined: true, joins: [8])), isEmpty);
    expect(cues(const TurretConsumed(0, uid: 8, into: 7)), isEmpty);
    expect(data.turrets['sniper']!.fireSound, 'sniper');
    expect(data.turrets['railgun']!.fireSound, 'tazer');
    expect(data.turrets['fusion']!.fireSound, 'fusion-low');
  });

  test('base hits: BaseHit, plus BaseWarn3/2/1 and BaseDead (PlayerBase.lifeLost)', () {
    List<String> hit(int lives) => cues(BaseHit(0, uid: 1, lives: lives));
    expect(hit(9), ['base-hit']);
    expect(hit(4), ['base-hit']);
    expect(hit(3), ['base-warn-3', 'base-hit']);
    expect(hit(2), ['base-warn-2', 'base-hit']);
    expect(hit(1), ['base-warn-1', 'base-hit']);
    expect(hit(0), ['base-dead', 'base-hit']);
  });

  test('turret commands, waves, pause, freakouts and unlocks', () {
    expect(cues(const TurretBuilt(0, uid: 7, turret: 'blue', x: 1, y: 1, cost: 10, cash: 0)), [
      'build',
    ]);
    expect(cues(const TurretMoved(0, uid: 7, x: 1, y: 1, cost: 500, cash: 0)), ['build']);
    expect(cues(const TurretSold(0, uid: 7, refund: 7, cash: 7)), ['sell']);
    expect(cues(const TurretUpgraded(0, uid: 7, stat: 'rate', level: 1, cost: 1, cash: 0)), [
      'upgrade-rate',
    ]);
    expect(cues(const CommandRejected(0, command: 'upgrade', reason: 'maxed')), ['upgrade-no']);
    expect(cues(const CommandRejected(0, command: 'upgrade', reason: 'paused')), isEmpty);
    expect(cues(const CommandRejected(0, command: 'upgradeMax', reason: 'cannotAfford')), [
      'upgrade-no',
    ]);
    expect(cues(const CommandRejected(0, command: 'upgradeMax', reason: 'paused')), isEmpty);
    expect(cues(const CommandRejected(0, command: 'build', reason: 'cannotAfford')), isEmpty);
    expect(
      cues(
        const WaveStarted(
          0,
          wave: 2,
          size: 10,
          creepType: 1,
          hp: 1,
          bounty: 2,
          speed: 60,
          early: true,
        ),
      ),
      ['next-wave'],
    );
    expect(cues(const PausedChanged(0, paused: true)), ['pause']);
    expect(cues(const PausedChanged(0, paused: false)), ['un-pause']);
    expect(
      [
        for (final s in ['warning', 'active', 'ended'])
          ...cues(FreakoutChanged(0, uid: 7, stage: s)),
      ],
      ['freakout-warn', 'freakout-start', 'freakout-end'],
    );
    expect(cues(const WeaponUnlocked(0, turret: 'range-up', kills: 300)), ['weapon']);
    expect(
      cues(const CreepKilled(0, uid: 1, turret: null, bounty: 1, cash: 1, kills: 1, x: 3, y: 4)),
      ['attacker-dead'],
    );
    expect(cues(const CreepSpawned(0, uid: 1, wave: 1, x: 0, y: 0)), isEmpty);
  });

  test('combos: "Combo" at the leader, blast sounds where they go off, the black hole twice', () {
    expect(
      audioCuesFor(
        const ComboFired(0, uid: 7, combo: 'nuke', helpers: [8, 9], projectile: 'rocket-nuke'),
        blueAt,
      ),
      [(event: 'combo', x: 360.0)],
    );
    expect(
      cues(
        const ComboFired(
          0,
          uid: 7,
          combo: 'blackhole',
          helpers: [8],
          projectile: 'black-hole',
          sound: 'black-hole',
        ),
      ),
      ['combo', 'black-hole'],
    );
    expect(cues(const BlackHoleOpened(0, uid: 9, x: 1, y: 1)), ['black-hole']);
    expect(
      audioCuesFor(
        const BlastStarted(
          0,
          uid: 9,
          blast: 'blast-huge',
          x: 50,
          y: 1,
          damage: 1,
          sound: 'blast-large',
        ),
        blueAt,
      ),
      [(event: 'blast-large', x: 50.0)],
    );
    expect(
      cues(const BlastStarted(0, uid: 9, blast: 'blast-napalm', x: 1, y: 1, damage: 1)),
      isEmpty,
    );
    expect(cues(const CreepSwallowed(0, uid: 1, hole: 9)), isEmpty);
    expect(data.blasts['cluster-sparks']!.params.string('sound'), 'tazer');
  });

  test('GameAudio plays the cues of view-model events and survives a failing backend', () async {
    final vm = FakeGameViewModel(data: data);
    final sink = _Sink();
    final audio = GameAudio(
      viewModel: vm,
      audio: AudioService(data: data, pack: _Pack(), sink: sink, random: math.Random(1)),
    );
    vm.emit(
      const WaveStarted(
        0,
        wave: 1,
        size: 10,
        creepType: 0,
        hp: 13,
        bounty: 1,
        speed: 60,
        early: false,
      ),
    );
    vm.emit(const PausedChanged(0, paused: true));
    await pumpEventQueue();
    expect(sink.played, ['sfx.ons2-nextwave-02', 'sfx.pause-03']);
    await audio.dispose();

    final failing = GameAudio(
      viewModel: vm,
      audio: AudioService(data: data, pack: _Pack(), sink: _FailingSink()),
    );
    vm.emit(const PausedChanged(0, paused: false));
    await pumpEventQueue();
    unawaited(failing.dispose());
  });
}
