part of 'game_session.dart';

/// The command processor: [GameSession.step] applies every queued
/// [GameCommand] here, in order, before the systems run. Each handler checks
/// the command (game over, pause, the turret, the cash) and either changes
/// the world and emits its event or emits [CommandRejected] with the reason.
extension _SessionCommands on GameSession {
  void _apply(GameCommand c) {
    switch (c) {
      case SetPaused(:final paused):
        if (clock.paused != paused) {
          clock.paused = paused;
          emit(PausedChanged(stepIndex, paused: paused));
        }
      case SetSpeed(:final speed):
        final s = speed.clamp(data.rules.speedFactorMin, data.rules.speedFactorMax);
        if (s != clock.speed) {
          clock.speed = s;
          emit(SpeedChanged(stepIndex, speed: s));
        }
      case BuildTurret():
        _build(c);
      case UpgradeTurret():
        _upgrade(c);
      case UpgradeTurretMax():
        _upgradeMax(c);
      case SellTurret():
        _sell(c);
      case MoveTurret():
        _move(c);
      case SetTargetMode():
        _targetMode(c);
      case SetTargetLock():
        _targetLock(c);
      case SendNextWave():
        // `AttackerManager.waveSend` refuses while paused or after game over,
        // and once the waves have ended.
        if (_allowed(c) && !waveSend(early: true)) _reject(c, 'noMoreWaves');
      case BuyFreakout():
        _buyFreakout(c);
      case JoinTurret():
        _join(c);
      case ChooseCombonly():
        _chooseCombonly(c);
      case SetWaveSettings():
        _waveSettings(c);
      case TutorialShow():
        _tutorialShow(c);
      case ContinuePlaying():
        _continuePlaying(c);
    }
  }

  void _reject(GameCommand c, String reason) =>
      emit(CommandRejected(stepIndex, command: c.type, reason: reason));

  /// Game over and pause block every world command (the original checks
  /// `game_over` and `game_paused` in build, upgrade, sell, move, target
  /// mode and wave send alike).
  bool _allowed(GameCommand c) {
    if (clock.stopped) {
      _reject(c, 'gameOver');
      return false;
    }
    if (clock.paused) {
      _reject(c, 'paused');
      return false;
    }
    return true;
  }

  /// The turret a command is for; null (rejected) when there is none or it
  /// is inactive (being consumed or taking on a weapon: it cannot be
  /// clicked, `Turret.onPress`).
  Turret? _turretFor(GameCommand c, int uid) {
    final t = turretByUid(uid);
    if (t == null) {
      _reject(c, 'noSuchTurret');
    } else if (!t.active) {
      _reject(c, 'inactive');
      return null;
    }
    return t;
  }

  /// `BuildShape.buildHere`: pay, then place a fresh turret.
  void _build(BuildTurret c) {
    if (!_allowed(c)) return;
    final def = data.turrets[c.turret];
    if (def == null) return _reject(c, 'unknownTurret');
    if (!isBuildable(def)) return _reject(c, 'notImplemented');
    if (!isAvailable(def)) return _reject(c, 'locked');
    if (cash < def.cost) return _reject(c, 'cannotAfford');
    final at = Vec2(c.x, c.y);
    final issue = placementIssueAt(at);
    if (issue != null) return _reject(c, issue.name);
    _cash -= def.cost;
    _totalSpent += def.cost;
    _placeTurret(def, at, cost: def.cost);
  }

  /// The attract demo's turrets, placed on the menu's timeline in the
  /// original: plain level-1 turrets, free, in depth order.
  void _placeAttractTurrets() {
    for (final t in attract?.turrets ?? const <AttractTurret>[]) {
      final def = data.turrets[t.turret];
      if (def != null) _placeTurret(def, Vec2(t.x, t.y), cost: 0);
    }
  }

  /// Adds a fresh turret of [def] at [at] worth [cost].
  void _placeTurret(TurretDef def, Vec2 at, {required double cost}) {
    final names = def.displayNames;
    final turret =
        Turret(
            uid: _nextUid++,
            def: def,
            position: at,
            displayName: names.isEmpty ? def.name : names[random.nextInt(names.length)],
            cashValue: cost,
            targetModeIndex: 0,
            lockOff: def.lockOff,
            builtAtMs: clock.nowMs,
          )
          ..targetMode = def.defaultTargetMode
          ..rotation = normalizeRotation(def.weaponRotation);
    _turrets.add(turret);
    refreshRelations();
    emit(
      TurretBuilt(
        stepIndex,
        uid: turret.uid,
        turret: def.id,
        x: at.x,
        y: at.y,
        cost: cost,
        cash: cash,
      ),
    );
    for (final sp in specialsOf(turret)) {
      sp.onBuilt(this, turret);
    }
    _notifyAdded(turret);
  }

  /// `Turret.upgradeDamage/Range/Rate`: the stat becomes the next step's
  /// value; its cost is added to the turret's cash value.
  void _upgrade(UpgradeTurret c) {
    final target = _upgradeTarget(c, c.uid, c.stat);
    if (target == null) return;
    final issue = _buyUpgradeStep(target.turret, target.stat);
    if (issue != null) _reject(c, issue);
  }

  /// `Turret.upgradeDamageMax` (and Range, Rate): upgrade steps are bought
  /// until one cannot be (maxed or unaffordable). Rejected like a single
  /// upgrade when not even the first step can be bought.
  void _upgradeMax(UpgradeTurretMax c) {
    final target = _upgradeTarget(c, c.uid, c.stat);
    if (target == null) return;
    final issue = _buyUpgradeStep(target.turret, target.stat);
    if (issue != null) return _reject(c, issue);
    while (_buyUpgradeStep(target.turret, target.stat) == null) {}
  }

  /// The turret and stat an upgrade command is for; null (rejected) when
  /// the world is locked, there is no such active turret or no such stat.
  ({Turret turret, StatKind stat})? _upgradeTarget(GameCommand c, int uid, String statName) {
    if (!_allowed(c)) return null;
    final t = _turretFor(c, uid);
    if (t == null) return null;
    final stat = StatKind.values.where((s) => s.name == statName).firstOrNull;
    if (stat == null) {
      _reject(c, 'unknownStat');
      return null;
    }
    return (turret: t, stat: stat);
  }

  /// Buys the next step of [stat] on [t]; returns why it cannot (`maxed`,
  /// `cannotAfford`), or null once bought.
  String? _buyUpgradeStep(Turret t, StatKind stat) {
    final level = t.level(stat);
    final cost = nextUpgradeCost(t.def.upgrades.track(stat), level);
    if (cost == null) return 'maxed';
    if (cash < cost) return 'cannotAfford';
    _cash -= cost;
    _totalSpent += cost;
    t
      ..setLevel(stat, level + 1)
      ..cashValue += cost;
    for (final sp in specialsOf(t)) {
      sp.onUpgraded(this, t);
    }
    refreshRelations();
    emit(
      TurretUpgraded(
        stepIndex,
        uid: t.uid,
        stat: stat.name,
        level: level + 1,
        cost: cost,
        cash: cash,
      ),
    );
    return null;
  }

  /// `TurretManager.turretSell`: refund `ceil(cash value × refund)`, which
  /// also comes off the total spent (`cashUnspend`).
  void _sell(SellTurret c) {
    if (!_allowed(c)) return;
    final t = _turretFor(c, c.uid);
    if (t == null) return;
    for (final sp in specialsOf(t)) {
      sp.onSold(this, t);
    }
    final refund = sellRefund(t.cashValue, data.rules.sellRefund);
    _cash += refund;
    _totalSpent -= refund;
    _turrets.remove(t);
    refreshRelations();
    emit(TurretSold(stepIndex, uid: t.uid, refund: refund, cash: cash));
    _notifyGone(t);
  }

  /// `MoveShape.buildHere`: same placement rules (ignoring the turret
  /// itself) for the move cost, which counts as spent but not as turret
  /// value. The original also hides the turret for two 130 ms fades; here
  /// the move is instant.
  void _move(MoveTurret c) {
    if (!_allowed(c)) return;
    final t = _turretFor(c, c.uid);
    if (t == null) return;
    final cost = data.world.placement.moveCost;
    if (cash < cost) return _reject(c, 'cannotAfford');
    final at = Vec2(c.x, c.y);
    final issue = placementIssueAt(at, moving: t);
    if (issue != null) return _reject(c, issue.name);
    _cash -= cost;
    _totalSpent += cost;
    // `MoveShape` deactivates the turret and reactivates it in place: a new
    // update timer starts (its `time_last` is kept).
    t
      ..position = at
      ..sinceTickMs = 0;
    refreshRelations();
    emit(TurretMoved(stepIndex, uid: t.uid, x: at.x, y: at.y, cost: cost, cash: cash));
    // `notifyMove`: every other turret sees it leave and arrive.
    _notifyGone(t);
    _notifyAdded(t);
    for (final sp in specialsOf(t)) {
      sp.onMoved(this, t);
    }
  }

  /// `Turret.turretTargetModeCycle`, generalised to choosing any mode.
  void _targetMode(SetTargetMode c) {
    if (!_allowed(c)) return;
    final t = _turretFor(c, c.uid);
    if (t == null) return;
    final index = data.targeting.modes.indexOf(c.mode);
    if (index < 0 || !isTargetMode(c.mode) || t.def.defaultTargetMode == null) {
      return _reject(c, 'unknownMode');
    }
    t
      ..targetMode = c.mode
      ..targetModeIndex = index;
    emit(TargetModeChanged(stepIndex, uid: t.uid, mode: c.mode, lockOff: t.lockOff));
  }

  /// `Turret.turretTargetModeLockToggle`.
  void _targetLock(SetTargetLock c) {
    if (!_allowed(c)) return;
    final t = _turretFor(c, c.uid);
    if (t == null) return;
    t.lockOff = c.lockOff;
    emit(TargetModeChanged(stepIndex, uid: t.uid, mode: t.targetMode ?? '', lockOff: t.lockOff));
  }

  /// The freakout info-panel button (`TurretInfoBlue`): pay
  /// `floor(seconds until the next freakout) × buyCostPerSecond` to freak
  /// out now. Refused when no freakout is scheduled, which in the classic
  /// rules is always (the cost is NaN there).
  void _buyFreakout(BuyFreakout c) {
    if (!_allowed(c)) return;
    final t = _turretFor(c, c.uid);
    if (t == null) return;
    final sp = registry.turretSpecial(FreakoutSpecial.specialId);
    if (sp is! FreakoutSpecial || !t.def.specials.contains(FreakoutSpecial.specialId)) {
      return _reject(c, 'unavailable');
    }
    final cost = sp.buyCost(this, t);
    if (cost == null) return _reject(c, 'unavailable');
    if (cash < cost) return _reject(c, 'cannotAfford');
    _cash -= cost;
    _totalSpent += cost;
    sp.freakoutNow(this, t, cost: cost);
  }

  /// The joiner (`TurretJoiner.onRelease`): Targeter [JoinTurret.uid] joins
  /// [JoinTurret.target], or lets it go when it is already joined.
  void _join(JoinTurret c) {
    if (!_allowed(c)) return;
    final t = _turretFor(c, c.uid);
    if (t == null) return;
    final other = _turretFor(c, c.target);
    if (other == null) return;
    final sp = registry.turretSpecial(TargeterSpecial.specialId);
    if (sp is! TargeterSpecial || !t.def.specials.contains(TargeterSpecial.specialId)) {
      return _reject(c, 'notTargeter');
    }
    final reason = sp.toggleJoin(this, t, other);
    if (reason != null) _reject(c, reason);
  }

  /// A click on Combonly plate [ChooseCombonly.uid] (`TurretCombonly.onPress`).
  void _chooseCombonly(ChooseCombonly c) {
    if (!_allowed(c)) return;
    final t = _turretFor(c, c.uid);
    if (t == null) return;
    final sp = registry.turretSpecial(CombonlySpecial.specialId);
    if (sp is! CombonlySpecial || !t.def.specials.contains(CombonlySpecial.specialId)) {
      return _reject(c, 'notCombonly');
    }
    final reason = sp.choose(this, t);
    if (reason != null) _reject(c, reason);
  }

  /// `GameManager.settingsApply`: the wave spacing (within the settings'
  /// bounds) and wave follow. Applies while paused.
  void _waveSettings(SetWaveSettings c) {
    final w = data.waves;
    _waveSpacingMs = c.spacingMs
        .clamp(w.spacingPrefMinS * 1000, w.spacingPrefMaxS * 1000)
        .toDouble();
    _waveFollow = c.follow;
    emit(WaveSettingsChanged(stepIndex, spacingMs: waveSpacingMs, follow: waveFollow));
  }

  /// "Continue playing" after a win (`RulesProfile.continueAfterWin`): the
  /// clock runs again, the objectives are done with and the wave clock
  /// starts a fresh spacing. The win itself stands.
  void _continuePlaying(ContinuePlaying c) {
    if (!config.profile.continueAfterWin) return _reject(c, 'notAllowed');
    if (!won || freeplay) return _reject(c, 'notWon');
    _freeplay = true;
    clock.stopped = false;
    _objectiveSystem.onFreeplay();
    waves.lastWaveMs = clock.nowMs;
    emit(FreeplayStarted(stepIndex, wave: waves.wave, nextWaveMs: waveSpacingMs));
  }

  /// The tutorial's "Show me": a page with `setCash` sets the cash, once.
  void _tutorialShow(TutorialShow c) {
    if (config.mode != GameConfig.tutorialMode) return _reject(c, 'notTutorial');
    final pages = data.tutorial.pages;
    if (c.page < 0 || c.page >= pages.length) return _reject(c, 'noSuchPage');
    final setCash = pages[c.page].setCash;
    if (setCash == null || _tutorialCashGiven) return;
    _tutorialCashGiven = true;
    _cash = setCash;
    emit(TutorialCashSet(stepIndex, page: c.page, cash: cash));
  }
}
