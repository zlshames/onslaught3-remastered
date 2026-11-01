import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../../app/strings.dart';
import '../../../app/theme.dart';
import '../../../services/assets/asset_pack.dart';
import '../../../services/assets/pack_sprite.dart';
import '../colour_badges.dart';
import '../effect_settings.dart';
import '../game_view_model.dart';
import '../layout/hud_layout.dart';
import 'colour_badge_icon.dart';
import 'format.dart';

/// Bottom sheet for the selected turret (`docs/REMASTER_PLAN.md` §3.3):
/// name and stats, the three upgrade buttons (cost, level pips, value
/// preview; long-press buys as many steps as cash allows, like Shift-click),
/// target mode chip (tap cycles, long-press picks), lock toggle, move and
/// sell, plus a card per special (combos, freakout countdown and "buy now",
/// charge, holding pattern, link, modifier aura, the Targeter's joins, the
/// Fusion cannon's store, the Combonly plate's options and "lock in"). Every
/// action is a [GameCommand] (editing joins is UI state that sends them);
/// while paused the original refuses them all, so the buttons are disabled.
///
/// At least [HudMetrics.compactBelow] wide it is one row, [height] tall (v1);
/// narrower (portrait phones, the Enhanced side panel) it stacks into a
/// compact column as tall as it needs. [edge] is the screen edge it opens
/// against; only its rounded corners follow it.
class TurretSheet extends StatelessWidget {
  const TurretSheet({
    super.key,
    required this.viewModel,
    this.pack,
    this.effects,
    this.edge = SheetEdge.bottom,
    this.inset = EdgeInsets.zero,
  });

  final GameViewModel viewModel;
  final AssetPack? pack;

  /// The screen edge the sheet opens against.
  final SheetEdge edge;

  /// What the controls keep clear of (a notch); the background covers it.
  final EdgeInsets inset;

  /// Display settings: the colour badge beside a colour turret's icon.
  final ValueListenable<EffectSettings>? effects;

  /// Height of the sheet in logical px.
  static const double height = 112;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<TurretPanel?>(
    valueListenable: viewModel.selection,
    // The panel appears at once, as the original's info panel does on the
    // click that selects; only a dismissed panel fades out.
    builder: (context, panel, _) => AnimatedSwitcher(
      duration: Duration.zero,
      reverseDuration: const Duration(milliseconds: 150),
      child: panel == null
          ? const SizedBox.shrink()
          : ValueListenableBuilder<EffectSettings>(
              key: ValueKey(panel.uid),
              valueListenable: effects ?? FixedEffects(EffectSettings.of(viewModel.data)),
              builder: (context, display, _) => _Sheet(
                panel: panel,
                viewModel: viewModel,
                pack: pack,
                badges: display.colourBadges,
                edge: edge,
                inset: inset,
              ),
            ),
    ),
  );
}

class _Sheet extends StatelessWidget {
  const _Sheet({
    required this.panel,
    required this.viewModel,
    required this.pack,
    required this.badges,
    required this.edge,
    required this.inset,
  });

  final TurretPanel panel;
  final GameViewModel viewModel;
  final AssetPack? pack;
  final bool badges;
  final SheetEdge edge;
  final EdgeInsets inset;

  void _send(GameCommand c) => viewModel.dispatch(c);

  bool get _enabled => !panel.locked;

  BoxDecoration get _decoration => BoxDecoration(
    color: HudColours.panel,
    borderRadius: switch (edge) {
      SheetEdge.bottom => const BorderRadius.vertical(top: Radius.circular(14)),
      SheetEdge.top => const BorderRadius.vertical(bottom: Radius.circular(14)),
      SheetEdge.left => const BorderRadius.horizontal(right: Radius.circular(14)),
      SheetEdge.right => const BorderRadius.horizontal(left: Radius.circular(14)),
    },
    border: Border.all(color: Colors.white24),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final width = box.maxWidth - inset.horizontal;
      return width < HudMetrics.compactBelow ? _compact(context, width) : _wide(context);
    },
  );

  Widget _upgrade(StatRow row) => _UpgradeButton(
    data: viewModel.data,
    row: row,
    enabled: _enabled,
    onUpgrade: () => _send(UpgradeTurret(panel.uid, row.stat.name)),
    // `Turret.upgradeDamageMax`, Shift-click in the original: the game
    // buys as many steps as the cash allows.
    onUpgradeMax: () => _send(UpgradeTurretMax(panel.uid, row.stat.name)),
  );

  Widget? _target(BuildContext context) => panel.targetMode == null
      ? null
      : _TargetChip(panel: panel, data: viewModel.data, enabled: _enabled, send: _send);

  Widget? _lock(BuildContext context) {
    if (panel.targetMode == null) return null;
    final data = viewModel.data;
    return _SmallButton(
      label: data.tr(context, panel.lockOff ? 'ui.sheet.lockOff' : 'ui.sheet.lockOn'),
      semantics: data.tr(context, panel.lockOff ? 'ui.sheet.lockOffInfo' : 'ui.sheet.lockOnInfo'),
      icon: panel.lockOff ? Icons.lock_open : Icons.lock,
      onTap: _enabled ? () => _send(SetTargetLock(panel.uid, lockOff: !panel.lockOff)) : null,
    );
  }

  Widget _move(BuildContext context) {
    final data = viewModel.data;
    return _SmallButton(
      label: data.tr(context, 'ui.sheet.move', {'cost': '\$${panel.moveCost.toStringAsFixed(0)}'}),
      semantics: data.tr(context, 'ui.sheet.moveInfo', {'cost': panel.moveCost.toStringAsFixed(0)}),
      icon: Icons.open_with,
      onTap: _enabled && panel.canAffordMove
          ? () => viewModel.previewPlacement(panel.turretId, null, moving: panel.uid)
          : null,
    );
  }

  Widget _sell(BuildContext context) {
    final data = viewModel.data;
    return _SmallButton(
      label: data.tr(context, 'ui.sheet.sell', {'refund': '\$${panel.refund}'}),
      semantics: data.tr(context, 'ui.sheet.sellInfo', {'refund': panel.refund}),
      icon: Icons.sell,
      onTap: _enabled ? () => _send(SellTurret(panel.uid)) : null,
    );
  }

  Widget _close(BuildContext context) => IconButton(
    tooltip: viewModel.data.tr(context, 'ui.common.close'),
    icon: const Icon(Icons.close, color: Colors.white70),
    onPressed: () => viewModel.select(null),
  );

  Widget _info({bool compact = false}) =>
      _InfoBlock(panel: panel, data: viewModel.data, pack: pack, badges: badges, compact: compact);

  /// Below this content width the four action buttons take two rows.
  static const double _oneActionRowFrom = 340;

  /// The narrowest a special's card is laid out (the landscape panel's
  /// cards are 124 wide); as many sit side by side as fit.
  static const double _minCardWidth = 116;

  /// Portrait phones and side panels: the icon, name, type and record with
  /// the close button; the three upgrade buttons; the target / lock / move /
  /// sell buttons (one row when there is room, else two); and the special
  /// cards side by side, as many to a row as fit. The same contents as the
  /// landscape row, packed so the panel covers as little of the map as it
  /// can.
  Widget _compact(BuildContext context, double width) {
    final actions = [?_target(context), ?_lock(context), _move(context), _sell(context)];
    const gap = 6.0;
    Widget row(List<Widget> children) => Row(
      children: [
        for (final (i, c) in children.indexed) ...[
          if (i > 0) const SizedBox(width: gap),
          Expanded(child: c),
        ],
      ],
    );
    // Padding: 10 left, 4 + 6 right.
    final content = width - 20;
    final split = content < _oneActionRowFrom && actions.length > 2;
    final cards = [
      for (final card in panel.cards)
        _SpecialCardView(
          card: card,
          action: _actionFor(context, card, _enabled),
          data: viewModel.data,
        ),
    ];
    final perRow = ((content + gap) / (_minCardWidth + gap)).floor().clamp(1, 3);
    return Container(
      decoration: _decoration,
      padding: inset + const EdgeInsets.fromLTRB(10, 4, 4, 8),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: _info(compact: true)),
                _close(context),
              ],
            ),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: SizedBox(
                height: 76,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [for (final r in panel.stats) Expanded(child: _upgrade(r))],
                ),
              ),
            ),
            const SizedBox(height: gap),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: split
                  ? Column(
                      children: [
                        row(actions.sublist(0, 2)),
                        const SizedBox(height: gap),
                        row(actions.sublist(2)),
                      ],
                    )
                  : row(actions),
            ),
            for (var i = 0; i < cards.length; i += perRow)
              Padding(
                padding: const EdgeInsets.only(top: gap, right: 6),
                child: SizedBox(
                  height: 52,
                  child: row([
                    ...cards.sublist(i, (i + perRow).clamp(0, cards.length)),
                    // An unfilled last row keeps the cards' width.
                    for (var k = cards.length; k < i + perRow && cards.length > perRow; k++)
                      const SizedBox.shrink(),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Landscape: one row, as v1.
  Widget _wide(BuildContext context) {
    final enabled = _enabled;
    return Container(
      height: TurretSheet.height + inset.vertical,
      decoration: _decoration,
      padding: inset + const EdgeInsets.fromLTRB(10, 6, 4, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 120,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: SizedBox(width: 120, child: _info()),
            ),
          ),
          for (final row in panel.stats) Expanded(child: _upgrade(row)),
          if (panel.cards.isNotEmpty) ...[
            const SizedBox(width: 6),
            SizedBox(
              width: 124,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final card in panel.cards)
                    Expanded(
                      child: _SpecialCardView(
                        card: card,
                        action: _actionFor(context, card, enabled),
                        data: viewModel.data,
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (panel.targetMode != null) ...[
            const SizedBox(width: 6),
            SizedBox(
              width: 116,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [_target(context)!, _lock(context)!],
              ),
            ),
          ],
          const SizedBox(width: 6),
          SizedBox(
            width: 96,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [_move(context), _sell(context)],
            ),
          ),
          _close(context),
        ],
      ),
    );
  }

  /// The button on [card], if it has one.
  _CardAction? _actionFor(BuildContext context, SpecialCard card, bool enabled) {
    final data = viewModel.data;
    return switch (card) {
      FreakoutCard(:final available, :final stage, :final buyCost?, :final affordable)
          when available && stage == FreakoutCard.stageIdle =>
        (
          label: data.tr(context, 'ui.sheet.freakoutNow', {'cost': '\$${plainNumber(buyCost)}'}),
          semantics: data.tr(context, 'ui.sheet.freakoutNowInfo', {'cost': plainNumber(buyCost)}),
          onPressed: enabled && affordable ? () => _send(BuyFreakout(panel.uid)) : null,
        ),
      TargeterCard(:final joining) => (
        label: data.tr(context, joining ? 'ui.sheet.joinDone' : 'ui.sheet.join'),
        semantics: data.tr(context, joining ? 'ui.sheet.joinDoneInfo' : 'ui.sheet.joinInfo'),
        onPressed: enabled ? () => viewModel.joinFrom(joining ? null : panel.uid) : null,
      ),
      CombonlyCard(:final chosen, :final shown?) when chosen == null => (
        label: data.tr(context, 'ui.sheet.lockIn'),
        semantics: data.tr(context, 'ui.sheet.lockInInfo', {'name': shown.name}),
        onPressed: enabled ? () => _send(ChooseCombonly(panel.uid)) : null,
      ),
      _ => null,
    };
  }
}

/// The selected turret's icon (and colour badge), name, type and record.
class _InfoBlock extends StatelessWidget {
  const _InfoBlock({
    required this.panel,
    required this.data,
    required this.pack,
    required this.badges,
    this.compact = false,
  });

  final TurretPanel panel;
  final GameData data;
  final AssetPack? pack;
  final bool badges;

  /// Two lines beside the icon (name; type and record) instead of three.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final record = data.tr(context, 'ui.sheet.record', {
      'kills': panel.kills,
      'shots': panel.shots,
    });
    final small = theme.textTheme.bodySmall?.copyWith(
      color: Colors.white70,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final icon = Stack(
      clipBehavior: Clip.none,
      children: [
        PackSprite(pack: pack, id: panel.icon, size: 36, anchored: true),
        if (badges)
          Positioned(
            left: -4,
            top: -4,
            child: ColourBadgeIcon(data: data, turretId: panel.turretId),
          ),
      ],
    );
    if (compact) {
      return Row(
        children: [
          icon,
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  panel.displayName,
                  style: theme.textTheme.titleSmall?.copyWith(color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
                Text('${panel.typeName} · $record', style: small, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      );
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            icon,
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                panel.displayName,
                style: theme.textTheme.titleSmall?.copyWith(color: Colors.white),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        Text(
          panel.typeName,
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
          overflow: TextOverflow.ellipsis,
        ),
        Text(record, style: small),
      ],
    );
  }
}

/// The `strings` key of each upgrade button's name.
const _statNames = {
  StatKind.damage: 'ui.sheet.damage',
  StatKind.range: 'ui.sheet.range',
  StatKind.rate: 'ui.sheet.rate',
};

/// A button on a special's card: [label], its semantics, and what it does
/// (null = disabled).
typedef _CardAction = ({String label, String semantics, VoidCallback? onPressed});

class _UpgradeButton extends StatelessWidget {
  const _UpgradeButton({
    required this.data,
    required this.row,
    required this.enabled,
    required this.onUpgrade,
    required this.onUpgradeMax,
  });

  final GameData data;
  final StatRow row;
  final bool enabled;
  final VoidCallback onUpgrade;
  final VoidCallback onUpgradeMax;

  @override
  Widget build(BuildContext context) {
    final name = data.tr(context, _statNames[row.stat]!);
    final active = enabled && !row.maxed && row.affordable;
    final price = row.maxed ? data.tr(context, 'ui.sheet.max') : '\$${plainNumber(row.nextCost!)}';
    final preview = row.maxed
        ? plainNumber(row.value)
        : '${plainNumber(row.value)} → ${plainNumber(row.nextValue!)}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Semantics(
        button: true,
        enabled: active,
        label: data.tr(context, 'ui.sheet.upgrade', {
          'name': name,
          'level': row.level,
          'max': row.maxLevel,
          'price': row.maxed
              ? data.tr(context, 'ui.sheet.maxed')
              : data.tr(context, 'ui.sheet.costs', {'cost': plainNumber(row.nextCost!)}),
          'preview': preview,
        }),
        child: Material(
          color: active ? HudColours.toggleOn : Colors.white10,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: active ? onUpgrade : null,
            onLongPress: active ? onUpgradeMax : null,
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      _Pips(level: row.level, max: row.maxLevel),
                      const SizedBox(height: 2),
                      FittedBox(
                        child: Text(
                          preview,
                          style: TextStyle(
                            // Raised or lowered by auras or a freakout.
                            color: row.modified ? Colors.cyanAccent : Colors.white70,
                            fontSize: 12,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      Text(
                        price,
                        style: TextStyle(
                          color: active || row.maxed ? Colors.amberAccent : Colors.white38,
                          fontWeight: FontWeight.bold,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pips extends StatelessWidget {
  const _Pips({required this.level, required this.max});
  final int level;
  final int max;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (var i = 0; i < max; i++)
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: i < level ? Colors.amberAccent : Colors.white24,
          ),
        ),
    ],
  );
}

/// Target mode chip: tap cycles to the next mode, long-press opens the
/// picker with all eight.
class _TargetChip extends StatelessWidget {
  const _TargetChip({
    required this.panel,
    required this.data,
    required this.enabled,
    required this.send,
  });

  final TurretPanel panel;
  final GameData data;
  final bool enabled;
  final void Function(GameCommand) send;

  @override
  Widget build(BuildContext context) {
    String name(String mode) => data.tr(context, 'targetMode.$mode');
    return _SmallButton(
      label: name(panel.targetMode!),
      semantics: data.tr(context, 'ui.sheet.targetMode', {
        'mode': name(panel.targetMode!),
        'next': name(panel.nextTargetMode),
      }),
      icon: Icons.gps_fixed,
      onTap: enabled ? () => send(SetTargetMode(panel.uid, panel.nextTargetMode)) : null,
      onLongPress: enabled
          ? () async {
              final picked = await showModalBottomSheet<String>(
                context: context,
                builder: (context) => SafeArea(
                  child: Wrap(
                    children: [
                      for (final m in panel.targetModes)
                        ListTile(
                          title: Text(name(m)),
                          selected: m == panel.targetMode,
                          onTap: () => Navigator.pop(context, m),
                        ),
                    ],
                  ),
                ),
              );
              if (picked != null) send(SetTargetMode(panel.uid, picked));
            }
          : null,
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.label,
    required this.semantics,
    required this.icon,
    required this.onTap,
    this.onLongPress,
  });

  final String label;
  final String semantics;
  final IconData icon;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onTap != null,
    label: semantics,
    child: Material(
      color: onTap == null ? Colors.white10 : Colors.white24,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        onLongPress: onLongPress,
        child: ExcludeSemantics(
          child: SizedBox(
            height: 48,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: onTap == null ? Colors.white38 : Colors.white),
                const SizedBox(width: 4),
                // Shrinks to fit rather than cutting a price off.
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(color: onTap == null ? Colors.white38 : Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// One special's card: a title line and one or two value lines, with its
/// button if it has one (the freakout's "buy now", the Targeter's "Join",
/// the Combonly plate's "Lock in").
class _SpecialCardView extends StatelessWidget {
  const _SpecialCardView({required this.card, required this.action, required this.data});

  final SpecialCard card;
  final _CardAction? action;
  final GameData data;

  @override
  Widget build(BuildContext context) {
    String t(String key, [Map<String, Object?> args = const {}]) => data.tr(context, key, args);
    final (title, lines, semantics) = switch (card) {
      ComboCard(:final capable, :final damageLevelsToGo) when !capable => (
        t('ui.card.combo'),
        [
          t('ui.card.comboNeedsDamage'),
          t('ui.card.toGo', {'count': damageLevelsToGo}),
        ],
        t('ui.card.comboLockedInfo', {'count': damageLevelsToGo}),
      ),
      ComboCard(:final nextSeconds, :final partners, :final recipe, :final led, :final assisted) =>
        (
          nextSeconds == null
              ? t('ui.card.comboReady')
              : t('ui.card.comboIn', {'seconds': nextSeconds}),
          [
            if (partners.isEmpty)
              t('ui.card.noPartners')
            else
              t('ui.card.recipe', {
                'recipe': recipe ?? t('ui.card.noRecipe'),
                'partners': _partnersText(partners, uiLocale(context)),
              }),
            if (led + assisted > 0) t('ui.card.led', {'led': led, 'assisted': assisted}),
          ],
          t('ui.card.comboInfo', {
            'next': nextSeconds == null
                ? t('ui.card.comboReady')
                : t('ui.card.nextComboInfo', {'seconds': nextSeconds}),
            'recipe': recipe == null
                ? t('ui.card.noRecipeInfo')
                : t('ui.card.firesInfo', {'recipe': recipe}),
            'led': led,
            'assisted': assisted,
          }),
        ),
      FreakoutCard(:final available, :final stage, :final nextSeconds) => (
        t('ui.card.freakout'),
        [
          switch (stage) {
            'warning' => t('ui.card.warming'),
            'active' => t('ui.card.freakingOut'),
            _ when !available => t('ui.card.freakoutNeeds'),
            _ when nextSeconds == null => t('ui.card.notScheduled'),
            _ => t('ui.card.nextIn', {'seconds': nextSeconds}),
          },
        ],
        t('ui.card.freakout'),
      ),
      ChargeCard(:final charge, :final max, :final shotPoison) => (
        t('ui.card.charge'),
        [
          '${plainNumber(charge.floorToDouble())} / ${plainNumber(max)}',
          t('ui.card.slow', {'slow': shotPoison.toStringAsFixed(1)}),
        ],
        t('ui.card.chargeInfo', {
          'charge': charge.floor(),
          'max': plainNumber(max),
          'slow': shotPoison.toStringAsFixed(1),
        }),
      ),
      HoldingCard(:final unlocked, :final held, :final max, :final levelRange, :final levelRate) =>
        (
          t('ui.card.holding'),
          [
            unlocked
                ? t('ui.card.held', {'held': held, 'max': max})
                : t('ui.card.holdingNeeds', {'range': levelRange, 'rate': levelRate}),
          ],
          unlocked
              ? t('ui.card.holdingInfo', {'held': held, 'max': max})
              : t('ui.card.holdingLockedInfo', {'range': levelRange, 'rate': levelRate}),
        ),
      LinkCard(:final links, :final lastDamage) => (
        t('ui.card.link'),
        [
          t('ui.card.linked', {'links': links}),
          if (lastDamage > 0)
            t('ui.card.lastDamage', {'damage': plainNumber(lastDamage.roundToDouble())}),
        ],
        t('ui.card.linkInfo', {'links': links}),
      ),
      AuraCard(:final terms, :final radius, :final covered) => (
        t('ui.card.aura', {'radius': plainNumber(radius)}),
        [
          _auraText(context, terms),
          t('ui.card.auraCovered', {'count': covered}),
        ],
        t('ui.card.auraInfo', {
          'radius': plainNumber(radius),
          'terms': _auraText(context, terms),
          'count': covered,
        }),
      ),
      TargeterCard(:final joins, :final max, :final joining) => (
        t('ui.card.joined', {'joins': joins, 'max': max}),
        [joining ? t('ui.card.tapTurrets') : t('ui.card.paintsFastest')],
        joining
            ? t('ui.card.joiningInfo', {'joins': joins, 'max': max})
            : t('ui.card.joinedInfo', {'joins': joins, 'max': max}),
      ),
      FusionCard(:final storeDamage, :final storePoison, :final tier, :final feeders) => (
        t('ui.card.stored', {'damage': shortNumber(storeDamage)}),
        [
          t('ui.card.fusionSlow', {'slow': shortNumber(storePoison), 'tier': tier}),
          t('ui.card.feeding', {'count': feeders}),
        ],
        t('ui.card.fusionInfo', {
          'damage': shortNumber(storeDamage),
          'slow': shortNumber(storePoison),
          'count': feeders,
        }),
      ),
      CombonlyCard(:final chosen?, :final armed) => (
        chosen.name,
        [if (armed) t('ui.card.ready') else t('ui.card.takingShape')],
        t(armed ? 'ui.card.combonlyArmedInfo' : 'ui.card.combonlyArmingInfo', {
          'name': chosen.name,
        }),
      ),
      CombonlyCard(:final shown?, :final options) => (
        shown.name,
        [
          t(options.length == 1 ? 'ui.card.optionOne' : 'ui.card.optionMany', {
            'count': options.length,
          }),
        ],
        t('ui.card.combonlyShowingInfo', {'name': shown.name, 'count': options.length}),
      ),
      CombonlyCard(:final options) => (
        options.isEmpty ? t('ui.card.noCombo') : t('ui.card.scanning'),
        [
          if (options.isEmpty)
            t('ui.card.maxColour')
          else
            t('ui.card.optionMany', {'count': options.length}),
        ],
        options.isEmpty
            ? t('ui.card.combonlyNoneInfo')
            : t('ui.card.combonlyScanningInfo', {'count': options.length}),
      ),
    };
    final action = this.action;
    return Semantics(
      container: true,
      label: semantics,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
        child: Row(
          children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: ExcludeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      for (final l in lines)
                        Text(
                          l,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (action != null)
              Semantics(
                container: true,
                button: true,
                enabled: action.onPressed != null,
                label: action.semantics,
                child: ExcludeSemantics(
                  child: SizedBox(
                    height: 44,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        foregroundColor: Colors.amberAccent,
                      ),
                      onPressed: action.onPressed,
                      child: FittedBox(child: Text(action.label, textAlign: TextAlign.center)),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// `R2 B1`: partner counts by the first letter of each turret's name.
  String _partnersText(Map<String, int> partners, String locale) =>
      [for (final e in partners.entries) '${colourLetter(data, e.key, locale: locale)}${e.value}']
          .join(' ');

  /// `+100 range, dmg ×1.4` style summary of an aura's terms.
  String _auraText(BuildContext context, StatTerms t) {
    String mult(double m) {
      final text = (1 + m).toStringAsFixed(2);
      return '×${text.replaceFirst(RegExp(r'\.?0+$'), '')}';
    }

    final parts = [
      for (final (stat, name) in [
        (StatKind.damage, data.tr(context, 'ui.card.auraDamage')),
        (StatKind.range, data.tr(context, 'ui.card.auraRange')),
        (StatKind.rate, data.tr(context, 'ui.card.auraRate')),
      ]) ...[
        if (t.added(stat) != 0)
          '${t.added(stat) > 0 ? '+' : ''}${plainNumber(t.added(stat))} $name',
        if (t.mult(stat) != 1) '$name ${mult(t.mult(stat) - 1)}',
      ],
    ];
    return parts.join(', ');
  }
}
