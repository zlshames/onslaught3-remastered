import 'package:meta/meta.dart';

import '../data/challenge_defs.dart';
import 'game_event.dart';
import 'game_session.dart';
import 'sim_constants.dart';

/// What a game must reach to be won, and how far it has got
/// (`GameManager`: `wave_limit`, `kill_target`, `time_limit` and their
/// `_hit` flags; `AttackerManager.no_more_waves`). Challenges set these from
/// their objective and time limit; the tutorial has a wave limit. Games
/// without any (normal, sandbox) never win: they end when the lives run out.
///
/// Read-only outside this library: only [ObjectiveSystem] moves the flags.
class Objectives {
  Objectives({this.waveLimit, this.killTarget, this.timeLimitMs});

  /// Waves to beat (`wave_limit`): once the next wave after it is due, no
  /// more are sent and the game is won when the field is clear.
  final int? waveLimit;

  /// Kills to make (`kill_target`): no more waves once reached; won when the
  /// field is clear.
  final int? killTarget;

  /// Game ms the game may last (`time_limit`, from the game's start). When it
  /// runs out no more waves are sent: won (once the field is clear) if every
  /// objective was reached, else lost.
  final double? timeLimitMs;

  /// `wave_limit_hit`: set by the wave limit, and also by the kill target
  /// and by a time limit with no wave objective, since all of them end the
  /// waves; the win check then waits for a clear field.
  bool get wavesDone => _wavesDone;
  bool _wavesDone = false;

  bool get waveLimitHit => _waveLimitHit;
  bool _waveLimitHit = false;

  bool get killTargetHit => _killTargetHit;
  bool _killTargetHit = false;

  bool get timeLimitHit => _timeLimitHit;
  bool _timeLimitHit = false;

  /// `no_more_waves`: the wave clock has stopped for good.
  bool get noMoreWaves => _noMoreWaves;
  bool _noMoreWaves = false;

  /// The once-a-second win check (`interval_gamewin`) is running, and the
  /// real ms since it last ran.
  bool get winCheckArmed => _winCheckArmed;
  bool _winCheckArmed = false;

  double get sinceWinCheckMs => _sinceWinCheckMs;
  double _sinceWinCheckMs = 0;

  /// The step the win check was started in; its interval counts from the
  /// end of that step.
  int get winCheckArmedStep => _winCheckArmedStep;
  int _winCheckArmedStep = 0;

  bool get any => waveLimit != null || killTarget != null || timeLimitMs != null;

  Map<String, Object?> toJson() => {
    'waveLimit': ?waveLimit,
    'killTarget': ?killTarget,
    'timeLimitMs': ?timeLimitMs,
    'wavesDone': wavesDone,
    'waveLimitHit': waveLimitHit,
    'killTargetHit': killTargetHit,
    'timeLimitHit': timeLimitHit,
    'noMoreWaves': noMoreWaves,
    'winCheckArmed': winCheckArmed,
    'sinceWinCheckMs': sinceWinCheckMs,
    'winCheckArmedStep': winCheckArmedStep,
  };
}

/// The objectives step (`GameManager`'s wave limit, kill target, time limit
/// and win check). It owns the [Objectives] state. The session holds one and
/// runs its real-time part itself, after every other system's real-time
/// timers and before the cleanup; it is not one of [classicSystems]. The
/// other hooks are called where the original calls them: [allowsWave] from
/// the wave send, [onKill] after a kill, [checkTimeLimit] on the wave
/// manager's check.
class ObjectiveSystem implements SimSystem, RealTimeSystem {
  ObjectiveSystem(this.objectives);

  final Objectives objectives;

  @override
  String get name => 'objectives';

  /// The objectives have no game-time work: the time limit is checked on
  /// the wave manager's interval ([checkTimeLimit]).
  @override
  void step(GameSession session, double dtMs) {}

  /// Runs the win check on its real-time interval (`gameWinCheck`): won when
  /// the kill target (if any) is reached and, once the waves have ended,
  /// the field is clear.
  @override
  void stepRealTime(GameSession session, double realMs) {
    final s = session;
    final o = objectives;
    if (!o.winCheckArmed || s.clock.stopped || o.winCheckArmedStep == s.stepIndex) return;
    o._sinceWinCheckMs += realMs;
    final interval = s.data.rules.winCheckIntervalMs;
    while (o.sinceWinCheckMs >= interval - epsilonMs) {
      o._sinceWinCheckMs -= interval;
      final target = o.killTarget;
      if (target != null && s.kills < target) continue;
      if (o.wavesDone && !s.fieldClear) continue;
      o._winCheckArmed = false;
      s.winGame();
      return;
    }
  }

  /// `AttackerManager.waveSend`'s objective checks: no wave once the waves
  /// have ended (wave limit, kill target, time limit); the first attempt
  /// past the wave limit reaches it.
  @internal
  bool allowsWave(GameSession s) {
    final o = objectives;
    if (o.noMoreWaves || o.wavesDone || o.killTargetHit) return false;
    final limit = o.waveLimit;
    if (limit != null && s.waves.wave >= limit) {
      _waveLimitReached(s);
      return false;
    }
    return true;
  }

  /// `GameManager.attackerKilled`: the kill target, then the win check once
  /// the waves have ended.
  @internal
  void onKill(GameSession s) {
    final o = objectives;
    final target = o.killTarget;
    if (target != null && s.kills >= target) _killTargetReached(s);
    if (o.wavesDone || o.killTargetHit) _armWinCheck(s);
  }

  /// `GameManager.timeLimitUpdate`, on the wave manager's check: once the
  /// rounded seconds left reach 0 the time is up (`timeLimitHit`). No more
  /// waves; passed (once the field is clear) if every objective was reached,
  /// else lost.
  @internal
  void checkTimeLimit(GameSession s) {
    if (s.freeplay) return;
    final o = objectives;
    final left = s.timeLimitSecondsLeft;
    if (left == null || left > 0 || o.timeLimitHit) return;
    o._noMoreWaves = true;
    var ok = true;
    if (o.killTarget != null && !o.killTargetHit) {
      ok = false;
      s.emit(ObjectiveMissed(s.stepIndex, kind: ChallengeObjective.kills));
    }
    if (o.waveLimit != null) {
      if (!o.waveLimitHit) {
        ok = false;
        s.emit(ObjectiveMissed(s.stepIndex, kind: ChallengeObjective.waves));
      }
    } else {
      o._wavesDone = true;
    }
    o._timeLimitHit = true;
    if (ok) {
      s.emit(ObjectiveReached(s.stepIndex, kind: ChallengeObjective.time));
      _armWinCheck(s);
    } else {
      s.emit(ObjectiveMissed(s.stepIndex, kind: ChallengeObjective.time));
      s.endGame(GameOver.timeLimitReason);
    }
  }

  /// The won game goes on in freeplay: the wave clock may run again and the
  /// win check stops.
  @internal
  void onFreeplay() {
    objectives
      .._noMoreWaves = false
      .._winCheckArmed = false;
  }

  /// `GameManager.waveLimitHit`: the last wave has been sent.
  void _waveLimitReached(GameSession s) {
    final o = objectives;
    if (!o.waveLimitHit) {
      s.emit(ObjectiveReached(s.stepIndex, kind: ChallengeObjective.waves));
      o._noMoreWaves = true;
      _armWinCheck(s);
    }
    o
      .._waveLimitHit = true
      .._wavesDone = true;
  }

  /// `GameManager.killTargetHit`: enough kills; no more waves.
  void _killTargetReached(GameSession s) {
    final o = objectives;
    if (!o.killTargetHit) {
      s.emit(ObjectiveReached(s.stepIndex, kind: ChallengeObjective.kills));
      o._noMoreWaves = true;
      _armWinCheck(s);
    }
    o
      .._wavesDone = true
      .._killTargetHit = true;
  }

  /// `gameWinCheckSetup`: start the once-a-second win check (real time, so
  /// it also runs while paused).
  void _armWinCheck(GameSession s) {
    final o = objectives;
    if (o.winCheckArmed) return;
    o
      .._winCheckArmed = true
      .._sinceWinCheckMs = 0
      .._winCheckArmedStep = s.stepIndex;
  }
}
