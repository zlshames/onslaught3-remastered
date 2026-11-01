import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:onslaught3_remastered/features/game/game_view_model.dart';
import 'package:onslaught_core/onslaught_core.dart';

/// A scripted [GameViewModel] for widget and golden tests: set the
/// `…Value` setters, inspect [dispatched] and the UI calls. No simulation
/// runs (docs/REMASTER_PLAN.md §5.3).
class FakeGameViewModel implements GameViewModel {
  FakeGameViewModel({
    required this.data,
    String mapId = 'map1',
    this.profile = RulesProfile.classicFixed,
    HudState hud = const HudState(
      cash: 30,
      lives: 10,
      kills: 0,
      wave: 0,
      paused: false,
      speed: 1,
      nextWaveSeconds: 20,
    ),
    List<TrayItem>? tray,
    TurretPanel? selection,
    GameOverSummary? gameOver,
    this.world = const EmptyWorldView(),
  }) : map = data.maps[mapId]!,
       _hud = ValueNotifier(hud),
       _tray = ValueNotifier(tray ?? defaultTray(data)),
       _selection = ValueNotifier(selection),
       _gameOver = ValueNotifier(gameOver);

  /// The tray of a fresh game: Blue only, affordable.
  static List<TrayItem> defaultTray(GameData data) {
    final blue = data.turrets['blue']!;
    return [
      TrayItem(
        id: blue.id,
        name: blue.name,
        cost: blue.cost,
        icon: blue.art.icon,
        affordable: true,
      ),
    ];
  }

  @override
  final GameData data;

  @override
  final MapDefinition map;

  @override
  final RulesProfile profile;

  @override
  final WorldView world;

  final ValueNotifier<HudState> _hud;
  final ValueNotifier<List<TrayItem>> _tray;
  final ValueNotifier<TurretPanel?> _selection;
  final ValueNotifier<PlacementPreview?> _placement = ValueNotifier(null);
  final ValueNotifier<GameOverSummary?> _gameOver;
  final ValueNotifier<List<GameMessage>> _messages = ValueNotifier(const []);
  final ValueNotifier<List<ObjectiveBadge>> _objectives = ValueNotifier(const []);
  final ValueNotifier<int?> _joining = ValueNotifier(null);
  final StreamController<GameEvent> _events = StreamController.broadcast();

  /// Every command the UI sent, in order.
  final List<GameCommand> dispatched = [];

  /// Every [select] call, in order.
  final List<int?> selections = [];

  /// What [turretAt] answers.
  int? turretAtResult;

  /// The `minRadius` of the last [turretAt] call.
  double? lastTurretAtRadius;

  /// Whether a previewed ghost is valid.
  bool placementValid = true;

  @override
  ValueListenable<HudState> get hud => _hud;
  set hudValue(HudState value) => _hud.value = value;

  @override
  ValueListenable<List<TrayItem>> get tray => _tray;
  set trayValue(List<TrayItem> value) => _tray.value = value;

  @override
  ValueListenable<TurretPanel?> get selection => _selection;
  set selectionValue(TurretPanel? value) => _selection.value = value;

  @override
  ValueListenable<PlacementPreview?> get placement => _placement;

  @override
  ValueListenable<GameOverSummary?> get gameOver => _gameOver;
  set gameOverValue(GameOverSummary? value) => _gameOver.value = value;

  @override
  ValueListenable<List<GameMessage>> get messages => _messages;
  set messagesValue(List<GameMessage> value) => _messages.value = value;

  @override
  ValueListenable<List<ObjectiveBadge>> get objectives => _objectives;
  set objectivesValue(List<ObjectiveBadge> value) => _objectives.value = value;

  @override
  ValueListenable<int?> get joining => _joining;

  /// Every [joinFrom] call, in order.
  final List<int?> joinCalls = [];

  @override
  void joinFrom(int? uid) {
    joinCalls.add(uid);
    _joining.value = uid;
  }

  @override
  Stream<GameEvent> get events => _events.stream;

  void emit(GameEvent e) => _events.add(e);

  @override
  void dispatch(GameCommand command) => dispatched.add(command);

  @override
  void select(int? uid) {
    selections.add(uid);
    if (uid == null) _selection.value = null;
  }

  @override
  int? turretAt(Vec2 at, {double minRadius = 0}) {
    lastTurretAtRadius = minRadius;
    return turretAtResult;
  }

  @override
  void previewPlacement(String turretId, Vec2? at, {int? moving, bool locked = false}) =>
      _placement.value = PlacementPreview(
        turretId: turretId,
        at: at,
        valid: at != null && placementValid,
        range: data.turrets[turretId]!.stats.range,
        moving: moving,
        locked: locked && at != null,
      );

  @override
  bool commitPlacement() {
    final p = _placement.value;
    _placement.value = null;
    if (p == null || !p.valid) return false;
    dispatch(
      p.moving == null
          ? BuildTurret(p.turretId, p.at!.x, p.at!.y)
          : MoveTurret(p.moving!, p.at!.x, p.at!.y),
    );
    return true;
  }

  @override
  void cancelPlacement() => _placement.value = null;
}

/// A selected-turret panel for a Blue at [level] on every track.
TurretPanel bluePanel(
  GameData data, {
  int uid = 1,
  int damage = 0,
  int range = 0,
  int rate = 0,
  double cash = 30,
  bool locked = false,
  bool lockOff = false,
  String mode = 'near',
}) => turretPanel(
  data,
  'blue',
  uid: uid,
  damage: damage,
  range: range,
  rate: rate,
  cash: cash,
  locked: locked,
  lockOff: lockOff,
  mode: mode,
  displayName: 'Kapow',
);

/// A sheet panel for a [turretId] at the given levels, unmodified unless
/// [terms] are given, with [cards] for its specials.
TurretPanel turretPanel(
  GameData data,
  String turretId, {
  int uid = 1,
  int damage = 0,
  int range = 0,
  int rate = 0,
  double cash = 30,
  bool locked = false,
  bool? lockOff,
  String? mode,
  String displayName = 'Sample',
  StatTerms terms = StatTerms.identity,
  List<SpecialCard> cards = const [],
}) {
  final def = data.turrets[turretId]!;
  double eff(double base, StatKind k) => effectiveStat(
    base: base,
    added: terms.added(k),
    mult: terms.mult(k),
    multFloor: data.rules.modifierMultFloor,
  );
  StatRow row(StatKind stat, int level) {
    final track = def.upgrades.track(stat);
    final cost = level < track.length ? track[level].cost : null;
    final base = statAtLevel(def.stats.stat(stat), track, level);
    return StatRow(
      stat: stat,
      level: level,
      maxLevel: track.length,
      value: eff(base, stat),
      baseValue: base,
      nextValue: cost == null ? null : eff(track[level].value, stat),
      nextCost: cost,
      affordable: cost != null && cash >= cost,
    );
  }

  final levels = {StatKind.damage: damage, StatKind.range: range, StatKind.rate: rate};
  final spent = [
    for (final e in levels.entries)
      for (var i = 0; i < e.value; i++) def.upgrades.track(e.key)[i].cost,
  ].fold<double>(def.cost, (a, b) => a + b);
  final targetMode = def.defaultTargetMode == null ? null : (mode ?? def.defaultTargetMode);
  return TurretPanel(
    uid: uid,
    turretId: turretId,
    typeName: def.name,
    displayName: displayName,
    icon: def.art.icon,
    kills: 12,
    shots: 40,
    stats: [
      for (final e in levels.entries)
        if (def.upgrades.track(e.key).isNotEmpty) row(e.key, e.value),
    ],
    refund: sellRefund(spent, data.rules.sellRefund),
    moveCost: data.world.placement.moveCost,
    canAffordMove: cash >= data.world.placement.moveCost,
    targetMode: targetMode,
    targetModeIndex: mode == null || targetMode == null
        ? 0
        : data.targeting.modes.indexOf(targetMode),
    targetModes: data.targeting.modes,
    lockOff: lockOff ?? def.lockOff,
    locked: locked,
    cards: cards,
    auraRadius: def.modifierAura == null
        ? null
        : statAtLevel(def.stats.range, def.upgrades.range, range),
  );
}
