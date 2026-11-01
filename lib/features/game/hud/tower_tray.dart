import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../../app/strings.dart';
import '../../../services/assets/asset_pack.dart';
import '../../../services/assets/pack_sprite.dart';
import '../effect_settings.dart';
import '../game_view_model.dart';
import '../layout/hud_layout.dart';
import 'colour_badge_icon.dart';

/// Where a tray drag goes: the game screen turns screen positions into
/// world positions and moves the ghost (no Flame types here, rule R2).
abstract interface class PlacementInput {
  /// The finger dragging [turretId] is at [globalPosition]; [touch] when
  /// it is a finger (not a mouse or stylus), [start] on a drag's first call.
  void dragTo(String turretId, Offset globalPosition, {bool touch = false, bool start = false});

  /// The finger lifted: build if the ghost is valid.
  void dragEnd();
}

/// The tower tray (`docs/REMASTER_PLAN.md` §3.3): a rail down the right
/// side in landscape ([Axis.vertical]), a strip along the bottom in portrait
/// ([Axis.horizontal]); one cell per buildable turret with its icon and
/// cost. Drag a cell onto the map to
/// build (ghost + range circle follow the finger, release to place; with
/// drop and lock, release drops it for Place), or tap a cell to arm it and
/// then tap the map; tapping another cell while a ghost is locked swaps the
/// turret in place. Unaffordable cells are dimmed but
/// can still be armed to preview a spot. Turrets not unlocked yet show a
/// lock and the kills still needed, and cannot be armed.
class TowerTray extends StatefulWidget {
  const TowerTray({
    super.key,
    required this.viewModel,
    required this.input,
    this.pack,
    this.effects,
    this.axis = Axis.vertical,
    this.inset = EdgeInsets.zero,
  });

  final GameViewModel viewModel;
  final PlacementInput input;

  /// The direction the cells run and scroll in.
  final Axis axis;

  /// What the cells keep clear of (a notch); the background covers it.
  final EdgeInsets inset;
  final AssetPack? pack;

  /// Display settings: colour badges on the colour turrets' cells.
  final ValueListenable<EffectSettings>? effects;

  /// Width of the rail in logical px.
  static const double width = HudMetrics.trayRailWidth;

  /// Height of the strip in logical px.
  static const double stripHeight = HudMetrics.trayStripHeight;

  @override
  State<TowerTray> createState() => _TowerTrayState();
}

class _TowerTrayState extends State<TowerTray> {
  /// The turret armed for building (the ghost of a build, not a move), so
  /// each cell rebuilds when that changes rather than on every move of the
  /// ghost during a drag.
  late _ArmedTurret _armed = _ArmedTurret(widget.viewModel.placement);

  @override
  void didUpdateWidget(TowerTray old) {
    super.didUpdateWidget(old);
    if (old.viewModel.placement != widget.viewModel.placement) {
      _armed.dispose();
      _armed = _ArmedTurret(widget.viewModel.placement);
    }
  }

  @override
  void dispose() {
    _armed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TowerTray(:viewModel, :input, :axis, :inset, :pack, :effects) = widget;
    return Container(
      width: axis == Axis.vertical ? TowerTray.width + inset.horizontal : null,
      height: axis == Axis.horizontal ? TowerTray.stripHeight + inset.vertical : null,
      padding: inset,
      color: Colors.black.withValues(alpha: 0.45),
      child: ValueListenableBuilder<List<TrayItem>>(
        valueListenable: viewModel.tray,
        builder: (context, items, _) => ValueListenableBuilder<EffectSettings>(
          valueListenable: effects ?? FixedEffects(EffectSettings.of(viewModel.data)),
          builder: (context, display, _) => ListView(
            scrollDirection: axis,
            padding: axis == Axis.vertical
                ? const EdgeInsets.symmetric(vertical: 6)
                : const EdgeInsets.symmetric(horizontal: 6),
            children: [
              for (final item in items)
                _TrayCell(
                  axis: axis,
                  data: viewModel.data,
                  item: item,
                  pack: pack,
                  badge: display.colourBadges
                      ? ColourBadgeIcon(data: viewModel.data, turretId: item.id)
                      : null,
                  armed: _armed,
                  onTap: item.locked
                      ? null
                      : () {
                          final placement = viewModel.placement.value;
                          if (_armed.value == item.id) {
                            viewModel.cancelPlacement();
                          } else if (placement != null &&
                              placement.locked &&
                              placement.moving == null) {
                            viewModel.previewPlacement(item.id, placement.at, locked: true);
                          } else {
                            viewModel.select(null);
                            viewModel.previewPlacement(item.id, null);
                          }
                        },
                  onDrag: item.locked
                      ? null
                      : (p, {touch = false, start = false}) =>
                            input.dragTo(item.id, p, touch: touch, start: start),
                  onDragEnd: input.dragEnd,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The id of the turret whose build ghost is up (null while none is, or
/// while a turret is being moved), from [placement]; notifies only when
/// that id changes.
class _ArmedTurret extends ValueNotifier<String?> {
  _ArmedTurret(this.placement) : super(_of(placement.value)) {
    placement.addListener(_update);
  }

  final ValueListenable<PlacementPreview?> placement;

  static String? _of(PlacementPreview? p) => p != null && p.moving == null ? p.turretId : null;

  void _update() => value = _of(placement.value);

  @override
  void dispose() {
    placement.removeListener(_update);
    super.dispose();
  }
}

/// Where a cell's drag is: the global position, and whether a finger.
typedef _DragTo = void Function(Offset globalPosition, {bool touch, bool start});

class _TrayCell extends StatefulWidget {
  const _TrayCell({
    required this.axis,
    required this.data,
    required this.item,
    required this.pack,
    required this.badge,
    required this.armed,
    required this.onTap,
    required this.onDrag,
    required this.onDragEnd,
  });

  final Axis axis;
  final GameData data;
  final TrayItem item;
  final AssetPack? pack;

  /// The colour badge, when shown.
  final Widget? badge;

  /// The armed turret's id; this cell is armed when it is [item]'s.
  final ValueListenable<String?> armed;
  final VoidCallback? onTap;
  final _DragTo? onDrag;
  final VoidCallback onDragEnd;

  @override
  State<_TrayCell> createState() => _TrayCellState();
}

class _TrayCellState extends State<_TrayCell> {
  /// The drag in progress is a finger's.
  bool _touch = false;

  @override
  Widget build(BuildContext context) {
    final _TrayCell(:data, :item, :pack, :badge, :armed, :onTap, :onDragEnd, :axis) = widget;
    final cost = '\$${item.cost.toStringAsFixed(0)}';
    final drag = widget.onDrag;
    final bright = item.affordable && !item.locked;
    final rail = axis == Axis.vertical;
    void start(DragStartDetails d) {
      _touch = d.kind == null || d.kind == PointerDeviceKind.touch;
      drag!(d.globalPosition, touch: _touch, start: true);
    }

    void update(DragUpdateDetails d) => drag!(d.globalPosition, touch: _touch);
    // The icon and price do not depend on the armed state: built once here
    // and kept when only the armed turret changes.
    final content = ExcludeSemantics(
      child: SizedBox(
        width: rail ? null : 64,
        height: rail ? 64 : 72,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                alignment: Alignment.center,
                // The badge sits over the icon's corner, partly
                // outside the icon.
                clipBehavior: Clip.none,
                children: [
                  PackSprite(
                    pack: pack,
                    id: item.icon,
                    size: 40,
                    opacity: bright ? 1 : 0.4,
                    anchored: true,
                  ),
                  if (item.locked) const Icon(Icons.lock, color: Colors.white, size: 20),
                  if (badge case final b?) Positioned(left: -8, top: 0, child: b),
                ],
              ),
              Text(
                item.locked
                    ? data.tr(context, 'ui.tray.unlockKills', {'kills': item.unlockKills})
                    : cost,
                style: TextStyle(
                  color: bright ? Colors.white : Colors.white38,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return ValueListenableBuilder<String?>(
      valueListenable: armed,
      child: content,
      builder: (context, armedId, content) {
        final armed = armedId == item.id;
        return Semantics(
          button: true,
          enabled: !item.locked,
          selected: armed,
          label: data.tr(
            context,
            item.locked
                ? 'ui.tray.locked'
                : (item.affordable ? 'ui.tray.item' : 'ui.tray.cannotAfford'),
            {
              'name': item.name,
              'cost': cost,
              'kills': item.unlockKills,
              'toGo': item.killsToUnlock,
            },
          ),
          child: Padding(
            padding: rail
                ? const EdgeInsets.symmetric(horizontal: 6, vertical: 4)
                : const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Material(
              color: armed ? Colors.amber.withValues(alpha: 0.35) : Colors.white10,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: armed ? Colors.amber : Colors.white24),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onTap,
                child: GestureDetector(
                  // Across the tray first (horizontal on the rail, vertical on
                  // the strip) so the tray can still scroll along itself; after
                  // the slop the drag follows the finger anywhere.
                  onHorizontalDragStart: !rail || drag == null ? null : start,
                  onHorizontalDragUpdate: !rail || drag == null ? null : update,
                  onHorizontalDragEnd: !rail || drag == null ? null : (_) => onDragEnd(),
                  onHorizontalDragCancel: !rail || drag == null ? null : onDragEnd,
                  onVerticalDragStart: rail || drag == null ? null : start,
                  onVerticalDragUpdate: rail || drag == null ? null : update,
                  onVerticalDragEnd: rail || drag == null ? null : (_) => onDragEnd(),
                  onVerticalDragCancel: rail || drag == null ? null : onDragEnd,
                  child: content,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
